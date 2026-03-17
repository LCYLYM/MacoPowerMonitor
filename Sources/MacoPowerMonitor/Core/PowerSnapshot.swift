import Foundation

enum PowerSourceKind: String, Codable, Sendable {
    case acPower
    case battery
    case unknown
}

struct PowerSnapshot: Codable, Equatable, Sendable {
    let timestamp: Date
    let source: PowerSourceKind
    let batteryName: String?
    let batteryLevel: Double
    let currentChargePercent: Double?
    let nominalCapacity: Int?
    let designCapacity: Int?
    let fullChargeCapacity: Int?
    let designCycleCount: Int?
    let cycleCount: Int?
    let maximumCapacityPercent: Double?
    let hardwareSerialNumber: String?
    let isCharging: Bool
    let isCharged: Bool
    let timeToEmptyMinutes: Int?
    let timeToFullChargeMinutes: Int?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
    let temperatureCelsius: Double?
    let batteryHealthCondition: String?
    let batteryHealthState: String?
    let adapterWatts: Int?
    let adapterVoltageMillivolts: Int?
    let adapterCurrentMilliamps: Int?
    let systemPowerWatts: Double?
    let batteryPowerWatts: Double?
    let cpuPowerWatts: Double?
    let gpuPowerWatts: Double?
    let anePowerWatts: Double?
    let subsystemPowerUnavailableReason: String?

    var preferredPowerWatts: Double? {
        systemPowerWatts ?? batteryPowerWatts.map(abs)
    }

    var batteryFlowWatts: Double? {
        if let batteryPowerWatts {
            return batteryPowerWatts
        }

        guard let voltageMillivolts, let amperageMilliamps else {
            return nil
        }

        return Double(voltageMillivolts * amperageMilliamps) / 1_000_000.0
    }

    var batteryHealthRatio: Double? {
        if let maximumCapacityPercent {
            return maximumCapacityPercent / 100.0
        }

        if let designCapacity, let fullChargeCapacity, designCapacity > 0 {
            return Double(fullChargeCapacity) / Double(designCapacity)
        }

        guard let designCapacity, let nominalCapacity, designCapacity > 0 else {
            return nil
        }

        return Double(nominalCapacity) / Double(designCapacity)
    }

    var displayStatusText: String {
        switch source {
        case .acPower where isCharged:
            return "已充满"
        case .acPower where isCharging:
            return "正在充电"
        case .acPower:
            return "外接电源"
        case .battery:
            return "电池供电"
        case .unknown:
            return "状态未知"
        }
    }
}

struct SessionSummary: Equatable, Sendable {
    let title: String
    let startedAt: Date
    let elapsed: TimeInterval
    let batteryPercentDelta: Double
    let capacityDeltaMah: Int?
}

enum ChartMetric: String, CaseIterable, Identifiable {
    case power
    case batteryLevel
    case chargeRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power:
            return "功耗"
        case .batteryLevel:
            return "电量"
        case .chargeRate:
            return "电流"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .power:
            return "等待更多功耗样本"
        case .batteryLevel:
            return "等待更多电量样本"
        case .chargeRate:
            return "等待更多电流样本"
        }
    }

    var unitLabel: String {
        switch self {
        case .power:
            return "W"
        case .batteryLevel:
            return "%"
        case .chargeRate:
            return "A"
        }
    }
}

enum ChartTimeRange: String, CaseIterable, Identifiable {
    case oneHour
    case twentyFourHours
    case tenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour:
            return "1小时"
        case .twentyFourHours:
            return "24小时"
        case .tenDays:
            return "10天"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .oneHour:
            return 60 * 60
        case .twentyFourHours:
            return 60 * 60 * 24
        case .tenDays:
            return 60 * 60 * 24 * 10
        }
    }

    var bucketCount: Int {
        switch self {
        case .oneHour:
            return 24
        case .twentyFourHours:
            return 48
        case .tenDays:
            return 20
        }
    }
}

struct PowerChartPoint: Identifiable, Sendable {
    let timestamp: Date
    let value: Double
    let isCharging: Bool

    var id: TimeInterval { timestamp.timeIntervalSinceReferenceDate }
}
