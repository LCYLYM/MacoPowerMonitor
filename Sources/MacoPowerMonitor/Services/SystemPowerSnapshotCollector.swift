import Foundation
import IOKit
import IOKit.ps
import OSLog

struct SystemPowerSnapshotCollector: PowerSnapshotCollecting {
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "collector")

    func readSnapshot() throws -> PowerSnapshot {
        let sourceDescription = try readPrimaryPowerSource()
        let registry = try readBatteryRegistry()
        let adapter = readAdapterDetails()
        let batteryHealthCondition = sourceDescription.stringValue(forCKey: kIOPSBatteryHealthConditionKey)
        let batteryHealthState = sourceDescription.stringValue(forCKey: kIOPSBatteryHealthKey)

        let sourceState = sourceDescription.stringValue(forCKey: kIOPSPowerSourceStateKey)
        let source: PowerSourceKind

        switch sourceState {
        case cString(kIOPSACPowerValue):
            source = .acPower
        case cString(kIOPSBatteryPowerValue):
            source = .battery
        default:
            source = .unknown
        }

        let iopsVoltage = sourceDescription.intValue(forCKey: kIOPSVoltageKey)
        let iopsCurrent = sourceDescription.intValue(forCKey: kIOPSCurrentKey)
        let rawTemperature = sourceDescription.intValue(forCKey: kIOPSTemperatureKey) ?? registry.int("Temperature")

        let telemetrySystemPower = registry.double(path: ["PowerTelemetryData", "SystemPowerIn"]).map { $0 / 1_000.0 }
        let batteryDataSystemPower = registry.double(path: ["BatteryData", "SystemPower"])
        let derivedSystemPower = telemetrySystemPower ?? batteryDataSystemPower

        let telemetryBatteryPower = registry.double(path: ["PowerTelemetryData", "BatteryPower"]).map { $0 / 1_000.0 }
        let amperage = registry.int("Amperage") ?? iopsCurrent
        let voltage = registry.int("Voltage") ?? iopsVoltage
        let derivedBatteryPower = telemetryBatteryPower ?? SystemPowerSnapshotCollector.powerFrom(voltageMillivolts: voltage, amperageMilliamps: amperage)

        let currentCapacityPercent = sourceDescription.doubleValue(forCKey: kIOPSCurrentCapacityKey)
        let maxPercentCapacity = sourceDescription.doubleValue(forCKey: kIOPSMaxCapacityKey)
        let batteryLevel = {
            guard let currentCapacityPercent, let maxPercentCapacity, maxPercentCapacity > 0 else {
                return 0.0
            }

            return min(max(currentCapacityPercent / maxPercentCapacity, 0.0), 1.0)
        }()

        let snapshot = PowerSnapshot(
            timestamp: Date(),
            source: source,
            batteryName: sourceDescription.stringValue(forCKey: kIOPSNameKey),
            batteryLevel: batteryLevel,
            currentChargePercent: currentCapacityPercent,
            currentCapacityMah: registry.int("AppleRawCurrentCapacity"),
            maxCapacityMah: registry.int("AppleRawMaxCapacity") ?? registry.int("MaxCapacity"),
            designCapacityMah: registry.int("DesignCapacity"),
            cycleCount: registry.int("CycleCount"),
            isCharging: sourceDescription.boolValue(forCKey: kIOPSIsChargingKey),
            isCharged: sourceDescription.boolValue(forCKey: kIOPSIsChargedKey),
            timeToEmptyMinutes: normalized(minutes: sourceDescription.intValue(forCKey: kIOPSTimeToEmptyKey) ?? timeRemainingEstimate(for: source)),
            timeToFullChargeMinutes: normalized(minutes: sourceDescription.intValue(forCKey: kIOPSTimeToFullChargeKey)),
            voltageMillivolts: voltage,
            amperageMilliamps: amperage,
            temperatureCelsius: normalizeTemperature(rawTemperature),
            batteryHealthCondition: batteryHealthCondition,
            batteryHealthState: batteryHealthState,
            adapterWatts: adapter.intValue(forCKey: kIOPSPowerAdapterWattsKey),
            adapterVoltageMillivolts: adapter.intValue(forCKey: kIOPSPowerAdapterCurrentKey) == nil ? nil : registry.int(path: ["AdapterDetails", "AdapterVoltage"]) ?? adapter.intValue(forKey: "AdapterVoltage"),
            adapterCurrentMilliamps: adapter.intValue(forCKey: kIOPSPowerAdapterCurrentKey),
            systemPowerWatts: derivedSystemPower,
            batteryPowerWatts: derivedBatteryPower
        )

        logger.debug("Captured power snapshot at \(snapshot.timestamp, privacy: .public)")
        return snapshot
    }

    private func readPrimaryPowerSource() throws -> [String: Any] {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as Array

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source).takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let type = description.stringValue(forCKey: kIOPSTypeKey)
            let transportType = description.stringValue(forCKey: kIOPSTransportTypeKey)
            let isInternalBattery = type == cString(kIOPSInternalBatteryType)
                || transportType == cString(kIOPSInternalType)

            if isInternalBattery {
                return description
            }
        }

        guard let fallback = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, fallback).takeUnretainedValue() as? [String: Any] else {
            throw PowerSnapshotCollectorError.noPowerSourceFound
        }

        return description
    }

    private func readAdapterDetails() -> [String: Any] {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }

        return details
    }

    private func readBatteryRegistry() throws -> RegistrySnapshot {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return RegistrySnapshot(properties: [:])
        }

        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanagedProperties, kCFAllocatorDefault, 0)

        guard result == KERN_SUCCESS,
              let dictionary = unmanagedProperties?.takeRetainedValue() as? [String: Any] else {
            throw PowerSnapshotCollectorError.unableToReadRegistryProperties
        }

        return RegistrySnapshot(properties: dictionary)
    }

    private func timeRemainingEstimate(for source: PowerSourceKind) -> Int? {
        guard source == .battery else {
            return nil
        }

        let estimate = IOPSGetTimeRemainingEstimate()
        guard estimate > 0 else {
            return nil
        }

        return Int(estimate / 60.0)
    }

    private func normalized(minutes: Int?) -> Int? {
        guard let minutes, minutes != 65_535, minutes >= 0 else {
            return nil
        }

        return minutes
    }

    private func normalizeTemperature(_ rawValue: Int?) -> Double? {
        guard let rawValue else {
            return nil
        }

        if rawValue > 120 {
            return Double(rawValue) / 100.0
        }

        return Double(rawValue)
    }

    private static func powerFrom(voltageMillivolts: Int?, amperageMilliamps: Int?) -> Double? {
        guard let voltageMillivolts, let amperageMilliamps else {
            return nil
        }

        return Double(voltageMillivolts * amperageMilliamps) / 1_000_000.0
    }
}

private struct RegistrySnapshot {
    let properties: [String: Any]

    func int(_ key: String) -> Int? {
        properties[key] as? Int
    }

    func int(path: [String]) -> Int? {
        value(path: path) as? Int
    }

    func double(path: [String]) -> Double? {
        if let value = value(path: path) as? Double {
            return value
        }

        if let value = value(path: path) as? Int {
            return Double(value)
        }

        return nil
    }

    private func value(path: [String]) -> Any? {
        guard let first = path.first else {
            return nil
        }

        var current: Any? = properties[first]

        for key in path.dropFirst() {
            guard let dictionary = current as? [String: Any] else {
                return nil
            }

            current = dictionary[key]
        }

        return current
    }
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(forKey key: String) -> String? {
        self[key] as? String
    }

    func intValue(forKey key: String) -> Int? {
        self[key] as? Int
    }

    func stringValue(forCKey key: UnsafePointer<CChar>) -> String? {
        self[cString(key)] as? String
    }

    func intValue(forCKey key: UnsafePointer<CChar>) -> Int? {
        self[cString(key)] as? Int
    }

    func doubleValue(forCKey key: UnsafePointer<CChar>) -> Double? {
        if let value = self[cString(key)] as? Double {
            return value
        }

        if let value = self[cString(key)] as? Int {
            return Double(value)
        }

        return nil
    }

    func boolValue(forCKey key: UnsafePointer<CChar>) -> Bool {
        self[cString(key)] as? Bool ?? false
    }
}

private func cString(_ key: UnsafePointer<CChar>) -> String {
    String(validatingCString: key) ?? ""
}
