import Darwin
import Foundation
import ObjectiveC
import OSLog

/// Reads macOS smart-charging state without linking against the private
/// PowerUI framework. All selectors are checked at runtime and every failure
/// degrades to `ChargeLimitStatus.unavailable`.
final class ChargeLimitStatusProvider: @unchecked Sendable {
    static let shared = ChargeLimitStatusProvider()

    private typealias AllocMessage = @convention(c) (AnyClass, Selector) -> AnyObject
    private typealias InitMessage = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
    private typealias BoolMessage = @convention(c) (AnyObject, Selector) -> Bool
    private typealias ByteErrorMessage = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutablePointer<AnyObject?>?
    ) -> UInt8
    private typealias UIntErrorMessage = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutablePointer<AnyObject?>?
    ) -> UInt64
    private typealias OptimizedStatusMessage = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutablePointer<Bool>?,
        UnsafeMutablePointer<UInt64>?,
        UnsafeMutablePointer<Bool>?,
        UnsafeMutablePointer<AnyObject?>?
    ) -> Bool

    private let logger = Logger(subsystem: AppConstants.subsystem, category: "charge-limit")
    private let queue = DispatchQueue(label: "com.codex.MacoPowerMonitor.charge-limit")
    private let refreshInterval: TimeInterval = 5
    private let powerUIPath = "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI"

    private var cachedStatus = ChargeLimitStatus.unavailable
    private var lastRefreshDate: Date?
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var processHandle: UnsafeMutableRawPointer?
    private var clientClass: AnyClass?
    private var client: AnyObject?
    private var messageSendSymbol: UnsafeMutableRawPointer?
    private var didAttemptInitialization = false
    private var refreshScheduled = false
    private var reportedErrors = Set<String>()

    func currentStatus() -> ChargeLimitStatus {
        // PowerUISmartChargeClient is not safe to invoke from a Swift
        // cooperative worker thread. Background snapshot tasks must only read
        // the plain Swift cache and never move PowerUI objects across threads.
        guard Thread.isMainThread else {
            return cachedStatusOnly()
        }

        let now = Date()
        if let cached = queue.sync(execute: { () -> ChargeLimitStatus? in
            guard let lastRefreshDate,
                  now.timeIntervalSince(lastRefreshDate) < refreshInterval else {
                return nil
            }
            return cachedStatus
        }) {
            return cached
        }

        let status = readStatus()
        queue.sync {
            cachedStatus = status
            lastRefreshDate = now
        }
        return status
    }

    func cachedStatusOnly() -> ChargeLimitStatus {
        queue.sync { cachedStatus }
    }

    func prewarm() {
        let now = Date()
        let shouldSchedule = queue.sync { () -> Bool in
            let isStale = lastRefreshDate.map { now.timeIntervalSince($0) >= refreshInterval } ?? true
            guard isStale, !refreshScheduled else { return false }
            refreshScheduled = true
            return true
        }
        guard shouldSchedule else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            _ = self.currentStatus()
            self.queue.sync {
                self.refreshScheduled = false
            }
        }
    }

    private func readStatus() -> ChargeLimitStatus {
        precondition(Thread.isMainThread)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        ) else {
            return .unavailable
        }

        guard initializeClientIfNeeded(),
              let client,
              let messageSendSymbol else {
            return .unavailable
        }

        var manualLimit: Int?
        var manualEnabled: Bool?
        var optimizedLimit: Int?
        var optimizedEngaged: Bool?

        let supportsMCLSelector = NSSelectorFromString("isMCLSupported")
        if responds(to: supportsMCLSelector) {
            let supportsMCL = unsafeBitCast(
                messageSendSymbol,
                to: BoolMessage.self
            )(client, supportsMCLSelector)

            if supportsMCL {
                var enabledError: AnyObject?
                let enabledSelector = NSSelectorFromString("isMCLCurrentlyEnabled:")
                if responds(to: enabledSelector) {
                    let rawEnabled = unsafeBitCast(
                        messageSendSymbol,
                        to: UIntErrorMessage.self
                    )(client, enabledSelector, &enabledError)
                    if enabledError == nil {
                        manualEnabled = rawEnabled != 0
                    } else {
                        report(error: enabledError, operation: "读取手动充电上限启用状态")
                    }
                }

                var limitError: AnyObject?
                let limitSelector = NSSelectorFromString("getMCLLimitWithError:")
                if responds(to: limitSelector) {
                    let rawLimit = unsafeBitCast(
                        messageSendSymbol,
                        to: ByteErrorMessage.self
                    )(client, limitSelector, &limitError)
                    if limitError == nil, (80...100).contains(Int(rawLimit)) {
                        manualLimit = Int(rawLimit)
                    } else if limitError != nil {
                        report(error: limitError, operation: "读取手动充电上限")
                    }
                }
            }
        }

        let optimizedSelector = NSSelectorFromString(
            "isOBCEngaged:chargeLimit:chargingOverrideAllowed:withError:"
        )
        if responds(to: optimizedSelector) {
            var engaged = false
            var rawLimit: UInt64 = 0
            var chargingOverrideAllowed = false
            var optimizedError: AnyObject?
            let succeeded = unsafeBitCast(
                messageSendSymbol,
                to: OptimizedStatusMessage.self
            )(
                client,
                optimizedSelector,
                &engaged,
                &rawLimit,
                &chargingOverrideAllowed,
                &optimizedError
            )

            if succeeded, optimizedError == nil {
                optimizedEngaged = engaged
                if (80...100).contains(Int(rawLimit)) {
                    optimizedLimit = Int(rawLimit)
                }
            } else if optimizedError != nil {
                report(error: optimizedError, operation: "读取优化电池充电状态")
            }
        }

        return ChargeLimitStatus(
            manualLimitPercent: manualLimit,
            isManualLimitEnabled: manualEnabled,
            optimizedLimitPercent: optimizedLimit,
            isOptimizedChargingEngaged: optimizedEngaged
        )
    }

    private func initializeClientIfNeeded() -> Bool {
        if didAttemptInitialization {
            return client != nil && messageSendSymbol != nil
        }
        didAttemptInitialization = true

        frameworkHandle = dlopen(powerUIPath, RTLD_NOW | RTLD_LOCAL)
        guard frameworkHandle != nil else {
            report(message: "无法动态加载 PowerUI：\(lastDynamicLoaderError())")
            return false
        }

        processHandle = dlopen(nil, RTLD_NOW)
        guard let processHandle,
              let messageSendSymbol = dlsym(processHandle, "objc_msgSend") else {
            report(message: "无法解析 Objective-C 消息发送入口")
            return false
        }
        self.messageSendSymbol = messageSendSymbol

        guard let clientClass = NSClassFromString("PowerUISmartChargeClient") else {
            report(message: "PowerUISmartChargeClient 在当前系统不可用")
            return false
        }
        self.clientClass = clientClass

        let initSelector = NSSelectorFromString("initWithClientName:")
        guard class_getInstanceMethod(clientClass, initSelector) != nil else {
            report(message: "PowerUI 客户端初始化接口在当前系统不可用")
            return false
        }

        let allocated = unsafeBitCast(
            messageSendSymbol,
            to: AllocMessage.self
        )(clientClass, NSSelectorFromString("alloc"))
        client = unsafeBitCast(
            messageSendSymbol,
            to: InitMessage.self
        )(allocated, initSelector, "MacoPowerMonitor")

        return client != nil
    }

    private func responds(to selector: Selector) -> Bool {
        guard let clientClass else {
            return false
        }
        return class_getInstanceMethod(clientClass, selector) != nil
    }

    private func report(error: AnyObject?, operation: String) {
        if let error = error as? NSError {
            report(message: "\(operation)失败：\(error.localizedDescription)")
        }
    }

    private func report(message: String) {
        guard reportedErrors.insert(message).inserted else {
            return
        }
        logger.debug("\(message, privacy: .public)")
    }

    private func lastDynamicLoaderError() -> String {
        guard let error = dlerror() else {
            return "未知错误"
        }
        return String(cString: error)
    }
}
