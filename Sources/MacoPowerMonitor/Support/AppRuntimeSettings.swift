import Combine
import Foundation
import OSLog
import ServiceManagement

@MainActor
final class AppRuntimeSettings: ObservableObject {
    static let shared = AppRuntimeSettings()

    static let backgroundKeepAliveDefaultsKey = "maco.runtime.backgroundKeepAlive"
    private static let keepAliveReason = "Maco Power Monitor background keepalive"

    @Published private(set) var backgroundKeepAliveEnabled: Bool
    @Published private(set) var backgroundKeepAliveActive = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatusText = "未启用"
    @Published private(set) var launchAtLoginDetailText = "登录当前用户后不自动启动。"
    @Published private(set) var launchAtLoginErrorMessage: String?

    private let defaults: UserDefaults
    private let processInfo: ProcessInfo
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "runtime-settings")
    private let isBundledApp: Bool
    private var loginItemStatus: SMAppService.Status = .notFound

    private init(
        defaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.defaults = defaults
        self.processInfo = processInfo
        self.isBundledApp = Bundle.main.bundleURL.pathExtension == "app"
        self.backgroundKeepAliveEnabled = defaults.object(forKey: Self.backgroundKeepAliveDefaultsKey) as? Bool ?? true
    }

    func configureOnLaunch() {
        applyBackgroundKeepAlivePreference()
        refreshLaunchAtLoginStatus()
    }

    func setBackgroundKeepAlive(enabled: Bool) {
        defaults.set(enabled, forKey: Self.backgroundKeepAliveDefaultsKey)
        backgroundKeepAliveEnabled = enabled
        applyBackgroundKeepAlivePreference()
    }

    func setLaunchAtLogin(enabled: Bool) {
        guard isBundledApp else {
            launchAtLoginErrorMessage = "开机自启只在打包后的 .app 里可用。"
            refreshLaunchAtLoginStatus()
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginErrorMessage = nil
            refreshLaunchAtLoginStatus()
        } catch {
            launchAtLoginErrorMessage = launchAtLoginErrorDescription(for: error, enabling: enabled)
            logger.error("Failed to update launch at login setting: \(error.localizedDescription, privacy: .public)")
            refreshLaunchAtLoginStatus()
        }
    }

    func refreshLaunchAtLoginStatus() {
        guard isBundledApp else {
            launchAtLoginEnabled = false
            loginItemStatus = .notFound
            launchAtLoginStatusText = "仅打包版可用"
            launchAtLoginDetailText = "请使用打包后的 .app 才能注册开机自启。"
            return
        }

        let status = SMAppService.mainApp.status
        loginItemStatus = status
        launchAtLoginEnabled = status == .enabled

        switch status {
        case .enabled:
            launchAtLoginStatusText = "已启用"
            launchAtLoginDetailText = "登录当前用户后会自动启动。"
        case .requiresApproval:
            launchAtLoginStatusText = "待系统批准"
            launchAtLoginDetailText = "系统需要用户批准登录项。可在“系统设置 > 通用 > 登录项”里确认。"
        case .notRegistered:
            launchAtLoginStatusText = "未启用"
            launchAtLoginDetailText = "登录当前用户后不自动启动。"
        case .notFound:
            launchAtLoginStatusText = "尚未注册"
            launchAtLoginDetailText = "当前还未向系统注册登录项，可直接打开开机自启开关进行注册。若失败，建议把应用放进 Applications 后重试。"
        @unknown default:
            launchAtLoginStatusText = "状态未知"
            launchAtLoginDetailText = "系统返回了未知登录项状态。"
        }
    }

    func runSelfTest(named command: String) -> String {
        switch command {
        case "background-keepalive":
            return runBackgroundKeepAliveSelfTest()
        case "launch-at-login-roundtrip":
            return runLaunchAtLoginRoundTripSelfTest()
        default:
            return "UNKNOWN_SELF_TEST=\(command)"
        }
    }

    private func applyBackgroundKeepAlivePreference() {
        processInfo.automaticTerminationSupportEnabled = true

        if backgroundKeepAliveEnabled && !backgroundKeepAliveActive {
            processInfo.disableAutomaticTermination(Self.keepAliveReason)
            processInfo.disableSuddenTermination()
            backgroundKeepAliveActive = true
            logger.notice("Background keepalive enabled")
        } else if !backgroundKeepAliveEnabled && backgroundKeepAliveActive {
            processInfo.enableAutomaticTermination(Self.keepAliveReason)
            processInfo.enableSuddenTermination()
            backgroundKeepAliveActive = false
            logger.notice("Background keepalive disabled")
        }
    }

    private func launchAtLoginErrorDescription(for error: Error, enabling: Bool) -> String {
        let nsError = error as NSError

        if !isBundledApp {
            return "开机自启只在打包后的 .app 中可用。"
        }

        let actionText = enabling ? "开启" : "关闭"

        switch loginItemStatus {
        case .requiresApproval:
            return "\(actionText)失败：系统需要你先在“系统设置 > 通用 > 登录项”里批准该应用。"
        case .notFound:
            return "\(actionText)失败：系统还未识别到主应用登录项。请确认正在运行打包后的 .app，并尽量将它放在 Applications 后再试。"
        case .enabled, .notRegistered:
            return "\(actionText)失败：\(nsError.localizedDescription)"
        @unknown default:
            return "\(actionText)失败：系统返回了未知错误。"
        }
    }

    private func runBackgroundKeepAliveSelfTest() -> String {
        let originalValue = backgroundKeepAliveEnabled
        let originalActive = backgroundKeepAliveActive

        setBackgroundKeepAlive(enabled: false)
        let disabledState = backgroundKeepAliveActive
        setBackgroundKeepAlive(enabled: true)
        let enabledState = backgroundKeepAliveActive
        setBackgroundKeepAlive(enabled: originalValue)

        return [
            "SELF_TEST=background-keepalive",
            "ORIGINAL_ENABLED=\(originalValue)",
            "ORIGINAL_ACTIVE=\(originalActive)",
            "AFTER_DISABLE_ACTIVE=\(disabledState)",
            "AFTER_ENABLE_ACTIVE=\(enabledState)",
            "RESTORED_ENABLED=\(backgroundKeepAliveEnabled)",
            "RESTORED_ACTIVE=\(backgroundKeepAliveActive)",
        ].joined(separator: "\n")
    }

    private func runLaunchAtLoginRoundTripSelfTest() -> String {
        guard isBundledApp else {
            return [
                "SELF_TEST=launch-at-login-roundtrip",
                "RESULT=SKIPPED",
                "DETAIL=Current process is not running from a bundled .app",
            ].joined(separator: "\n")
        }

        refreshLaunchAtLoginStatus()

        let originalEnabled = launchAtLoginEnabled
        let originalStatus = loginItemStatus
        var lines = [
            "SELF_TEST=launch-at-login-roundtrip",
            "ORIGINAL_ENABLED=\(originalEnabled)",
            "ORIGINAL_STATUS=\(statusDescription(originalStatus))",
        ]

        do {
            if originalEnabled {
                try SMAppService.mainApp.unregister()
                refreshLaunchAtLoginStatus()
                lines.append("AFTER_UNREGISTER=\(statusDescription(loginItemStatus))")

                try SMAppService.mainApp.register()
                refreshLaunchAtLoginStatus()
                lines.append("AFTER_RESTORE=\(statusDescription(loginItemStatus))")
            } else {
                try SMAppService.mainApp.register()
                refreshLaunchAtLoginStatus()
                lines.append("AFTER_REGISTER=\(statusDescription(loginItemStatus))")

                try SMAppService.mainApp.unregister()
                refreshLaunchAtLoginStatus()
                lines.append("AFTER_UNREGISTER=\(statusDescription(loginItemStatus))")
            }

            return lines.joined(separator: "\n")
        } catch {
            lines.append("RESULT=FAILED")
            lines.append("ERROR=\(error.localizedDescription)")

            if originalEnabled {
                do {
                    try SMAppService.mainApp.register()
                    refreshLaunchAtLoginStatus()
                } catch {
                    lines.append("RESTORE_ERROR=\(error.localizedDescription)")
                }
            } else {
                do {
                    try SMAppService.mainApp.unregister()
                    refreshLaunchAtLoginStatus()
                } catch {
                    lines.append("RESTORE_ERROR=\(error.localizedDescription)")
                }
            }

            return lines.joined(separator: "\n")
        }
    }

    private func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "enabled"
        case .notRegistered:
            return "notRegistered"
        case .requiresApproval:
            return "requiresApproval"
        case .notFound:
            return "notFound"
        @unknown default:
            return "unknown"
        }
    }
}
