import Foundation
import IOKit
import OSLog

struct SupplementalBatteryMetrics: Sendable {
    let designCapacityMah: Int?
    let fullChargeCapacityMah: Int?
    let cycleCount: Int?
    let maximumCapacityPercent: Double?
    let temperatureCelsius: Double?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
    let timeRemainingMinutes: Int?
    let systemInputWatts: Double?
    let batteryPowerWatts: Double?
    let adapterWatts: Int?
    let adapterVoltageMillivolts: Int?
    let adapterCurrentMilliamps: Int?
    let adapterInputVoltageMillivolts: Int?
    let adapterInputCurrentMilliamps: Int?
    let adapterProtocol: PowerAdapterProtocol?
    let adapterProtocolDetail: String?
    let adapterVendorID: Int?
    let adapterProductID: Int?
    let adapterPDRevisionCode: Int?
    let chargeStatus: String?
    let notChargingReason: UInt64?
    let chargeLimitStatus: ChargeLimitStatus
}

final class SupplementalBatteryMetricsProvider: @unchecked Sendable {
    static let shared = SupplementalBatteryMetricsProvider()

    private let logger = Logger(subsystem: AppConstants.subsystem, category: "supplemental-battery")
    private let stateQueue = DispatchQueue(label: "com.codex.MacoPowerMonitor.supplemental-battery.state")
    private let profilerQueue = DispatchQueue(label: "com.codex.MacoPowerMonitor.supplemental-battery.profiler", qos: .utility)
    private let chargeLimitStatusProvider = ChargeLimitStatusProvider.shared
    private var cachedSystemProfilerMetrics: SystemProfilerMetrics?
    private var lastSystemProfilerRefreshDate: Date?
    private var isSystemProfilerRefreshInFlight = false

    private let systemProfilerRefreshInterval: TimeInterval = 5 * 60

    func currentMetrics() -> SupplementalBatteryMetrics? {
        let ioRegistryMetrics: IORegistryMetrics
        do {
            ioRegistryMetrics = try readIORegistryMetrics()
        } catch {
            logger.error("Failed to fetch IORegistry battery metrics: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let profilerMetrics = stateQueue.sync { cachedSystemProfilerMetrics }

        return SupplementalBatteryMetrics(
            designCapacityMah: ioRegistryMetrics.designCapacityMah,
            fullChargeCapacityMah: ioRegistryMetrics.fullChargeCapacityMah,
            cycleCount: profilerMetrics?.cycleCount ?? ioRegistryMetrics.cycleCount,
            maximumCapacityPercent: profilerMetrics?.maximumCapacityPercent,
            temperatureCelsius: ioRegistryMetrics.temperatureCelsius,
            voltageMillivolts: ioRegistryMetrics.voltageMillivolts,
            amperageMilliamps: ioRegistryMetrics.amperageMilliamps,
            timeRemainingMinutes: ioRegistryMetrics.timeRemainingMinutes,
            systemInputWatts: ioRegistryMetrics.systemInputWatts,
            batteryPowerWatts: ioRegistryMetrics.batteryPowerWatts,
            adapterWatts: ioRegistryMetrics.adapterWatts,
            adapterVoltageMillivolts: ioRegistryMetrics.adapterVoltageMillivolts,
            adapterCurrentMilliamps: ioRegistryMetrics.adapterCurrentMilliamps,
            adapterInputVoltageMillivolts: ioRegistryMetrics.adapterInputVoltageMillivolts,
            adapterInputCurrentMilliamps: ioRegistryMetrics.adapterInputCurrentMilliamps,
            adapterProtocol: ioRegistryMetrics.protocolDetection.protocol,
            adapterProtocolDetail: ioRegistryMetrics.protocolDetection.detail,
            adapterVendorID: ioRegistryMetrics.protocolDetection.vendorID,
            adapterProductID: ioRegistryMetrics.protocolDetection.productID,
            adapterPDRevisionCode: ioRegistryMetrics.protocolDetection.pdRevisionCode,
            chargeStatus: ioRegistryMetrics.chargeStatus,
            notChargingReason: ioRegistryMetrics.notChargingReason,
            chargeLimitStatus: chargeLimitStatusProvider.cachedStatusOnly()
        )
    }

    func prewarmSlowMetricsIfNeeded() {
        chargeLimitStatusProvider.prewarm()
        let now = Date()
        let shouldRefresh = stateQueue.sync { () -> Bool in
            let isStale = cachedSystemProfilerMetrics == nil
                || lastSystemProfilerRefreshDate.map({ now.timeIntervalSince($0) >= systemProfilerRefreshInterval }) != false
            guard isStale, !isSystemProfilerRefreshInFlight else { return false }
            isSystemProfilerRefreshInFlight = true
            return true
        }
        guard shouldRefresh else { return }

        profilerQueue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.readSystemProfilerMetrics() }
            self.stateQueue.async {
                self.isSystemProfilerRefreshInFlight = false
                switch result {
                case let .success(metrics):
                    self.cachedSystemProfilerMetrics = metrics
                    self.lastSystemProfilerRefreshDate = Date()
                case let .failure(error):
                    self.logger.error("Failed to fetch system_profiler battery metrics: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func readIORegistryMetrics() throws -> IORegistryMetrics {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else {
            throw SupplementalMetricsError.appleSmartBatteryNotFound
        }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            IOOptionBits(0)
        )

        guard result == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any] else {
            throw SupplementalMetricsError.ioRegistryReadFailed(result)
        }

        let batteryData = properties["BatteryData"] as? [String: Any] ?? [:]
        let chargerData = properties["ChargerData"] as? [String: Any] ?? [:]
        let telemetry = properties["PowerTelemetryData"] as? [String: Any] ?? [:]
        let rawAdapterDetails = (properties["AppleRawAdapterDetails"] as? [[String: Any]])?.first ?? [:]
        let adapterDetails = properties["AdapterDetails"] as? [String: Any] ?? rawAdapterDetails
        let fedDetails = (properties["FedDetails"] as? [[String: Any]])?
            .first(where: { $0.boolish("FedExternalConnected") })
        let protocolDetection = PowerAdapterProtocolDetector.detect(
            adapterDetails: adapterDetails,
            fedDetails: fedDetails
        )

        return IORegistryMetrics(
            designCapacityMah: properties.int("DesignCapacity") ?? batteryData.int("DesignCapacity"),
            fullChargeCapacityMah: properties.int("AppleRawMaxCapacity") ?? batteryData.int("FccComp1"),
            cycleCount: properties.int("CycleCount") ?? batteryData.int("CycleCount"),
            temperatureCelsius: properties.int("Temperature").map { Double($0) / 100.0 },
            voltageMillivolts: properties.int("Voltage") ?? properties.int("AppleRawBatteryVoltage"),
            amperageMilliamps: properties.int("Amperage"),
            timeRemainingMinutes: properties.int("TimeRemaining"),
            systemInputWatts: telemetry.powerWatts("SystemPowerIn") ?? batteryData.double("AdapterPower"),
            batteryPowerWatts: telemetry.powerWatts("BatteryPower") ?? batteryData.double("SystemPower"),
            adapterWatts: adapterDetails.int("Watts"),
            adapterVoltageMillivolts: adapterDetails.int("AdapterVoltage"),
            adapterCurrentMilliamps: adapterDetails.int("Current"),
            adapterInputVoltageMillivolts: telemetry.int("SystemVoltageIn"),
            adapterInputCurrentMilliamps: telemetry.int("SystemCurrentIn"),
            chargeStatus: properties["ChargeStatus"] as? String,
            notChargingReason: chargerData.uint64("NotChargingReason"),
            protocolDetection: protocolDetection
        )
    }

    private func readSystemProfilerMetrics() throws -> SystemProfilerMetrics {
        let data = try CommandRunner.run(executable: "/usr/sbin/system_profiler", arguments: ["SPPowerDataType", "-json"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]],
              let batteryInformation = items.first(where: { ($0["_name"] as? String) == "spbattery_information" }) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let health = batteryInformation["sppower_battery_health_info"] as? [String: Any] ?? [:]
        let maximumCapacityPercent = (health["sppower_battery_health_maximum_capacity"] as? String)
            .map { $0.replacingOccurrences(of: "%", with: "") }
            .flatMap { Double($0) }

        return SystemProfilerMetrics(
            cycleCount: health.int("sppower_battery_cycle_count"),
            maximumCapacityPercent: maximumCapacityPercent
        )
    }
}

private enum SupplementalMetricsError: LocalizedError {
    case appleSmartBatteryNotFound
    case ioRegistryReadFailed(kern_return_t)

    var errorDescription: String? {
        switch self {
        case .appleSmartBatteryNotFound:
            return "未找到 AppleSmartBattery IORegistry 服务。"
        case let .ioRegistryReadFailed(code):
            return "读取 AppleSmartBattery IORegistry 属性失败（\(code)）。"
        }
    }
}

private struct IORegistryMetrics {
    let designCapacityMah: Int?
    let fullChargeCapacityMah: Int?
    let cycleCount: Int?
    let temperatureCelsius: Double?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
    let timeRemainingMinutes: Int?
    let systemInputWatts: Double?
    let batteryPowerWatts: Double?
    let adapterWatts: Int?
    let adapterVoltageMillivolts: Int?
    let adapterCurrentMilliamps: Int?
    let adapterInputVoltageMillivolts: Int?
    let adapterInputCurrentMilliamps: Int?
    let chargeStatus: String?
    let notChargingReason: UInt64?
    let protocolDetection: PowerAdapterProtocolDetection
}

private struct SystemProfilerMetrics {
    let cycleCount: Int?
    let maximumCapacityPercent: Double?
}

private extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double {
            return value
        }
        if let value = self[key] as? Int {
            return Double(value)
        }
        if let value = self[key] as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    func uint64(_ key: String) -> UInt64? {
        if let value = self[key] as? UInt64 {
            return value
        }
        if let value = self[key] as? Int, value >= 0 {
            return UInt64(value)
        }
        if let value = self[key] as? NSNumber {
            return value.uint64Value
        }
        return nil
    }

    func powerWatts(_ key: String) -> Double? {
        guard let raw = double(key) else {
            return nil
        }
        return raw / 1_000.0
    }

    func boolish(_ key: String) -> Bool {
        if let value = self[key] as? Bool {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.boolValue
        }
        return false
    }
}
