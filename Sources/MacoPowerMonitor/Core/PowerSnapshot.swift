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
    let currentCapacityMah: Int?
    let maxCapacityMah: Int?
    let designCapacityMah: Int?
    let cycleCount: Int?
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
        guard let designCapacityMah, let maxCapacityMah, designCapacityMah > 0 else {
            return nil
        }

        return Double(maxCapacityMah) / Double(designCapacityMah)
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power:
            return "实时功耗"
        case .batteryLevel:
            return "电池电量"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .power:
            return "等待更多功耗样本"
        case .batteryLevel:
            return "等待更多电量样本"
        }
    }
}
