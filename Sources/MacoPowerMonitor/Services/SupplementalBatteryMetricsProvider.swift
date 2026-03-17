import Foundation
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
}

final class SupplementalBatteryMetricsProvider: @unchecked Sendable {
    static let shared = SupplementalBatteryMetricsProvider()

    private let logger = Logger(subsystem: AppConstants.subsystem, category: "supplemental-battery")
    private let queue = DispatchQueue(label: "com.codex.MacoPowerMonitor.supplemental-battery")
    private var cachedMetrics: SupplementalBatteryMetrics?
    private var lastRefreshDate: Date?

    private let refreshInterval: TimeInterval = 60

    func currentMetrics() -> SupplementalBatteryMetrics? {
        queue.sync {
            let now = Date()
            if let cachedMetrics,
               let lastRefreshDate,
               now.timeIntervalSince(lastRefreshDate) < refreshInterval {
                return cachedMetrics
            }

            do {
                let metrics = try fetchMetrics()
                cachedMetrics = metrics
                lastRefreshDate = now
                return metrics
            } catch {
                logger.error("Failed to fetch supplemental battery metrics: \(error.localizedDescription, privacy: .public)")
                return cachedMetrics
            }
        }
    }

    private func fetchMetrics() throws -> SupplementalBatteryMetrics {
        let ioreg = try readIoregMetrics()
        let systemProfiler = try readSystemProfilerMetrics()

        return SupplementalBatteryMetrics(
            designCapacityMah: ioreg.designCapacityMah,
            fullChargeCapacityMah: ioreg.fullChargeCapacityMah,
            cycleCount: systemProfiler.cycleCount ?? ioreg.cycleCount,
            maximumCapacityPercent: systemProfiler.maximumCapacityPercent,
            temperatureCelsius: ioreg.temperatureCelsius,
            voltageMillivolts: ioreg.voltageMillivolts,
            amperageMilliamps: ioreg.amperageMilliamps,
            timeRemainingMinutes: ioreg.timeRemainingMinutes,
            systemInputWatts: ioreg.systemInputWatts,
            batteryPowerWatts: ioreg.batteryPowerWatts,
            adapterWatts: ioreg.adapterWatts,
            adapterVoltageMillivolts: ioreg.adapterVoltageMillivolts,
            adapterCurrentMilliamps: ioreg.adapterCurrentMilliamps
        )
    }

    private func readIoregMetrics() throws -> IoregMetrics {
        let data = try CommandRunner.run(executable: "/usr/sbin/ioreg", arguments: ["-r", "-c", "AppleSmartBattery", "-a"])
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]],
              let item = plist.first else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let batteryData = item["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = item["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapterDetails = item["AdapterDetails"] as? [String: Any] ?? [:]

        return IoregMetrics(
            designCapacityMah: item.int("DesignCapacity") ?? batteryData.int("DesignCapacity"),
            fullChargeCapacityMah: item.int("AppleRawMaxCapacity") ?? batteryData.int("FccComp1"),
            cycleCount: item.int("CycleCount") ?? batteryData.int("CycleCount"),
            temperatureCelsius: item.int("Temperature").map { Double($0) / 100.0 },
            voltageMillivolts: item.int("Voltage"),
            amperageMilliamps: item.int("Amperage"),
            timeRemainingMinutes: item.int("TimeRemaining"),
            systemInputWatts: telemetry.int("SystemPowerIn").map { Double($0) / 1_000.0 } ?? batteryData.double("AdapterPower"),
            batteryPowerWatts: telemetry.int("BatteryPower").map { Double($0) / 1_000.0 } ?? batteryData.double("SystemPower"),
            adapterWatts: adapterDetails.int("Watts"),
            adapterVoltageMillivolts: adapterDetails.int("AdapterVoltage"),
            adapterCurrentMilliamps: adapterDetails.int("Current")
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
            cycleCount: health["sppower_battery_cycle_count"] as? Int,
            maximumCapacityPercent: maximumCapacityPercent
        )
    }
}

private struct IoregMetrics {
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
}

private struct SystemProfilerMetrics {
    let cycleCount: Int?
    let maximumCapacityPercent: Double?
}

private extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        self[key] as? Int
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double {
            return value
        }

        if let value = self[key] as? Int {
            return Double(value)
        }

        return nil
    }
}
