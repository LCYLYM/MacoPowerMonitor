import Foundation
import IOKit.ps
import OSLog

struct SystemPowerSnapshotCollector: PowerSnapshotCollecting {
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "collector")

    func readSnapshot() throws -> PowerSnapshot {
        let sourceDescription = try readPrimaryPowerSource()
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

        let voltage = sourceDescription.intValue(forCKey: kIOPSVoltageKey)
        let current = sourceDescription.intValue(forCKey: kIOPSCurrentKey)
        let temperature = normalizeTemperature(sourceDescription.intValue(forCKey: kIOPSTemperatureKey))

        let currentCapacityPercent = sourceDescription.doubleValue(forCKey: kIOPSCurrentCapacityKey)
        let maxPercentCapacity = sourceDescription.doubleValue(forCKey: kIOPSMaxCapacityKey)
        let batteryLevel = {
            guard let currentCapacityPercent, let maxPercentCapacity, maxPercentCapacity > 0 else {
                return 0.0
            }

            return min(max(currentCapacityPercent / maxPercentCapacity, 0.0), 1.0)
        }()

        let adapterWatts = adapter.intValue(forCKey: kIOPSPowerAdapterWattsKey)
        let adapterCurrent = adapter.intValue(forCKey: kIOPSPowerAdapterCurrentKey)
        let adapterVoltage = adapter.intValue(forKey: "AdapterVoltage")
        let batteryPower = Self.powerFrom(voltageMillivolts: voltage, amperageMilliamps: current)

        let systemPower: Double?
        if let adapterWatts, source == .acPower {
            systemPower = Double(adapterWatts)
        } else {
            systemPower = batteryPower.map(abs)
        }

        let snapshot = PowerSnapshot(
            timestamp: Date(),
            source: source,
            batteryName: sourceDescription.stringValue(forCKey: kIOPSNameKey),
            batteryLevel: batteryLevel,
            currentChargePercent: currentCapacityPercent,
            nominalCapacity: sourceDescription.intValue(forCKey: kIOPSNominalCapacityKey),
            designCapacity: sourceDescription.intValue(forCKey: kIOPSDesignCapacityKey),
            designCycleCount: sourceDescription.intValue(forKey: "DesignCycleCount"),
            hardwareSerialNumber: sourceDescription.stringValue(forCKey: kIOPSHardwareSerialNumberKey),
            isCharging: sourceDescription.boolValue(forCKey: kIOPSIsChargingKey),
            isCharged: sourceDescription.boolValue(forCKey: kIOPSIsChargedKey),
            timeToEmptyMinutes: normalized(minutes: sourceDescription.intValue(forCKey: kIOPSTimeToEmptyKey) ?? timeRemainingEstimate(for: source)),
            timeToFullChargeMinutes: normalized(minutes: sourceDescription.intValue(forCKey: kIOPSTimeToFullChargeKey)),
            voltageMillivolts: voltage,
            amperageMilliamps: current,
            temperatureCelsius: temperature,
            batteryHealthCondition: batteryHealthCondition,
            batteryHealthState: batteryHealthState,
            adapterWatts: adapterWatts,
            adapterVoltageMillivolts: adapterVoltage,
            adapterCurrentMilliamps: adapterCurrent,
            systemPowerWatts: systemPower,
            batteryPowerWatts: batteryPower
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
