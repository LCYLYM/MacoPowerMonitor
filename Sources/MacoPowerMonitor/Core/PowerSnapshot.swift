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
    let chargeHoldReason: ChargeHoldReason?
    let chargeLimitPercent: Int?
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
    let adapterInputVoltageMillivolts: Int?
    let adapterInputCurrentMilliamps: Int?
    let adapterInputPowerWatts: Double?
    let adapterProtocol: PowerAdapterProtocol?
    let adapterProtocolDetail: String?
    let adapterVendorID: Int?
    let adapterProductID: Int?
    let adapterPDRevisionCode: Int?
    let systemPowerWatts: Double?
    let batteryPowerWatts: Double?
    let cpuPowerWatts: Double?
    let gpuPowerWatts: Double?
    let anePowerWatts: Double?
    let subsystemPowerUnavailableReason: String?

    private enum CodingKeys: String, CodingKey {
        case timestamp, source, batteryName, batteryLevel, currentChargePercent
        case nominalCapacity, designCapacity, fullChargeCapacity, designCycleCount, cycleCount
        case maximumCapacityPercent, hardwareSerialNumber, isCharging, isCharged
        case chargeHoldReason, chargeLimitPercent
        case timeToEmptyMinutes, timeToFullChargeMinutes, voltageMillivolts, amperageMilliamps
        case temperatureCelsius, batteryHealthCondition, batteryHealthState
        case adapterWatts, adapterVoltageMillivolts, adapterCurrentMilliamps
        case adapterInputVoltageMillivolts, adapterInputCurrentMilliamps, adapterInputPowerWatts
        case adapterProtocol, adapterProtocolDetail, adapterVendorID, adapterProductID, adapterPDRevisionCode
        case systemPowerWatts, batteryPowerWatts, cpuPowerWatts, gpuPowerWatts, anePowerWatts
        case subsystemPowerUnavailableReason
    }

    init(
        timestamp: Date,
        source: PowerSourceKind,
        batteryName: String?,
        batteryLevel: Double,
        currentChargePercent: Double?,
        nominalCapacity: Int?,
        designCapacity: Int?,
        fullChargeCapacity: Int?,
        designCycleCount: Int?,
        cycleCount: Int?,
        maximumCapacityPercent: Double?,
        hardwareSerialNumber: String?,
        isCharging: Bool,
        isCharged: Bool,
        chargeHoldReason: ChargeHoldReason? = nil,
        chargeLimitPercent: Int? = nil,
        timeToEmptyMinutes: Int?,
        timeToFullChargeMinutes: Int?,
        voltageMillivolts: Int?,
        amperageMilliamps: Int?,
        temperatureCelsius: Double?,
        batteryHealthCondition: String?,
        batteryHealthState: String?,
        adapterWatts: Int?,
        adapterVoltageMillivolts: Int?,
        adapterCurrentMilliamps: Int?,
        adapterInputVoltageMillivolts: Int?,
        adapterInputCurrentMilliamps: Int?,
        adapterInputPowerWatts: Double?,
        adapterProtocol: PowerAdapterProtocol?,
        adapterProtocolDetail: String?,
        adapterVendorID: Int?,
        adapterProductID: Int?,
        adapterPDRevisionCode: Int?,
        systemPowerWatts: Double?,
        batteryPowerWatts: Double?,
        cpuPowerWatts: Double?,
        gpuPowerWatts: Double?,
        anePowerWatts: Double?,
        subsystemPowerUnavailableReason: String?
    ) {
        self.timestamp = timestamp
        self.source = source
        self.batteryName = batteryName
        self.batteryLevel = batteryLevel
        self.currentChargePercent = currentChargePercent
        self.nominalCapacity = nominalCapacity
        self.designCapacity = designCapacity
        self.fullChargeCapacity = fullChargeCapacity
        self.designCycleCount = designCycleCount
        self.cycleCount = cycleCount
        self.maximumCapacityPercent = maximumCapacityPercent
        self.hardwareSerialNumber = hardwareSerialNumber
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.chargeHoldReason = chargeHoldReason
        self.chargeLimitPercent = chargeLimitPercent
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamps = amperageMilliamps
        self.temperatureCelsius = temperatureCelsius
        self.batteryHealthCondition = batteryHealthCondition
        self.batteryHealthState = batteryHealthState
        self.adapterWatts = adapterWatts
        self.adapterVoltageMillivolts = adapterVoltageMillivolts
        self.adapterCurrentMilliamps = adapterCurrentMilliamps
        self.adapterInputVoltageMillivolts = adapterInputVoltageMillivolts
        self.adapterInputCurrentMilliamps = adapterInputCurrentMilliamps
        self.adapterInputPowerWatts = adapterInputPowerWatts
        self.adapterProtocol = adapterProtocol
        self.adapterProtocolDetail = adapterProtocolDetail
        self.adapterVendorID = adapterVendorID
        self.adapterProductID = adapterProductID
        self.adapterPDRevisionCode = adapterPDRevisionCode
        self.systemPowerWatts = systemPowerWatts
        self.batteryPowerWatts = batteryPowerWatts
        self.cpuPowerWatts = cpuPowerWatts
        self.gpuPowerWatts = gpuPowerWatts
        self.anePowerWatts = anePowerWatts
        self.subsystemPowerUnavailableReason = subsystemPowerUnavailableReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decode(PowerSourceKind.self, forKey: .source)
        batteryName = try container.decodeIfPresent(String.self, forKey: .batteryName)
        batteryLevel = try container.decode(Double.self, forKey: .batteryLevel)
        currentChargePercent = try container.decodeIfPresent(Double.self, forKey: .currentChargePercent)
        nominalCapacity = try container.decodeIfPresent(Int.self, forKey: .nominalCapacity)
        designCapacity = try container.decodeIfPresent(Int.self, forKey: .designCapacity)
        fullChargeCapacity = try container.decodeIfPresent(Int.self, forKey: .fullChargeCapacity)
        designCycleCount = try container.decodeIfPresent(Int.self, forKey: .designCycleCount)
        cycleCount = try container.decodeIfPresent(Int.self, forKey: .cycleCount)
        maximumCapacityPercent = try container.decodeIfPresent(Double.self, forKey: .maximumCapacityPercent)
        hardwareSerialNumber = try container.decodeIfPresent(String.self, forKey: .hardwareSerialNumber)
        isCharging = try container.decode(Bool.self, forKey: .isCharging)
        isCharged = try container.decode(Bool.self, forKey: .isCharged)
        chargeHoldReason = try container.decodeIfPresent(ChargeHoldReason.self, forKey: .chargeHoldReason)
        chargeLimitPercent = try container.decodeIfPresent(Int.self, forKey: .chargeLimitPercent)
        timeToEmptyMinutes = try container.decodeIfPresent(Int.self, forKey: .timeToEmptyMinutes)
        timeToFullChargeMinutes = try container.decodeIfPresent(Int.self, forKey: .timeToFullChargeMinutes)
        voltageMillivolts = try container.decodeIfPresent(Int.self, forKey: .voltageMillivolts)
        amperageMilliamps = try container.decodeIfPresent(Int.self, forKey: .amperageMilliamps)
        temperatureCelsius = try container.decodeIfPresent(Double.self, forKey: .temperatureCelsius)
        batteryHealthCondition = try container.decodeIfPresent(String.self, forKey: .batteryHealthCondition)
        batteryHealthState = try container.decodeIfPresent(String.self, forKey: .batteryHealthState)
        adapterWatts = try container.decodeIfPresent(Int.self, forKey: .adapterWatts)
        adapterVoltageMillivolts = try container.decodeIfPresent(Int.self, forKey: .adapterVoltageMillivolts)
        adapterCurrentMilliamps = try container.decodeIfPresent(Int.self, forKey: .adapterCurrentMilliamps)
        adapterInputVoltageMillivolts = try container.decodeIfPresent(Int.self, forKey: .adapterInputVoltageMillivolts)
        adapterInputCurrentMilliamps = try container.decodeIfPresent(Int.self, forKey: .adapterInputCurrentMilliamps)
        adapterInputPowerWatts = try container.decodeIfPresent(Double.self, forKey: .adapterInputPowerWatts)
            ?? (source == .acPower ? try container.decodeIfPresent(Double.self, forKey: .systemPowerWatts) : nil)
        adapterProtocol = try container.decodeIfPresent(PowerAdapterProtocol.self, forKey: .adapterProtocol)
        adapterProtocolDetail = try container.decodeIfPresent(String.self, forKey: .adapterProtocolDetail)
        adapterVendorID = try container.decodeIfPresent(Int.self, forKey: .adapterVendorID)
        adapterProductID = try container.decodeIfPresent(Int.self, forKey: .adapterProductID)
        adapterPDRevisionCode = try container.decodeIfPresent(Int.self, forKey: .adapterPDRevisionCode)
        systemPowerWatts = try container.decodeIfPresent(Double.self, forKey: .systemPowerWatts)
        batteryPowerWatts = try container.decodeIfPresent(Double.self, forKey: .batteryPowerWatts)
        cpuPowerWatts = try container.decodeIfPresent(Double.self, forKey: .cpuPowerWatts)
        gpuPowerWatts = try container.decodeIfPresent(Double.self, forKey: .gpuPowerWatts)
        anePowerWatts = try container.decodeIfPresent(Double.self, forKey: .anePowerWatts)
        subsystemPowerUnavailableReason = try container.decodeIfPresent(String.self, forKey: .subsystemPowerUnavailableReason)
    }

    var preferredPowerWatts: Double? {
        adapterRealtimePowerWatts ?? systemPowerWatts ?? batteryPowerWatts.map(abs)
    }

    var adapterRealtimePowerWatts: Double? {
        adapterInputPowerWatts ?? (source == .acPower ? systemPowerWatts : nil)
    }

    var adapterRealtimeCurrentMilliamps: Int? {
        guard source == .acPower else { return nil }
        return adapterInputCurrentMilliamps
    }

    var adapterRealtimeVoltageMillivolts: Int? {
        guard source == .acPower else { return nil }
        return adapterInputVoltageMillivolts
    }

    var adapterProtocolDisplayName: String {
        guard source == .acPower else {
            return "未连接"
        }

        return (adapterProtocol ?? .unknown).displayName
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
        if source == .acPower, let chargeHoldReason {
            return chargeHoldReason.displayText
        }

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

enum ChartMetric: String, CaseIterable, Identifiable, Sendable {
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

    var subtitle: String {
        switch self {
        case .power:
            return "适配器实时输入 + 电池输出/回充"
        case .batteryLevel:
            return "电池百分比走势"
        case .chargeRate:
            return "电池充电/放电电流"
        }
    }

    func formatValue(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        switch self {
        case .power:
            return String(format: "%.1fW", value)
        case .batteryLevel:
            return String(format: "%.0f%%", value)
        case .chargeRate:
            return String(format: "%.2fA", value)
        }
    }
}

enum ChartTimeRange: String, CaseIterable, Identifiable, Sendable {
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
            return 120
        case .twentyFourHours:
            return 144
        case .tenDays:
            return 120
        }
    }
}

struct PowerChartPoint: Identifiable, Sendable {
    let timestamp: Date
    let value: Double

    var id: TimeInterval { timestamp.timeIntervalSinceReferenceDate }
}

enum PowerChartSeriesKind: String, CaseIterable, Identifiable, Sendable {
    case adapterInputPower
    case batteryDischargePower
    case batteryChargePower
    case batteryDischargeCurrent
    case batteryChargeCurrent
    case batteryLevel

    var id: String { rawValue }

    var metric: ChartMetric {
        switch self {
        case .adapterInputPower, .batteryDischargePower, .batteryChargePower:
            return .power
        case .batteryDischargeCurrent, .batteryChargeCurrent:
            return .chargeRate
        case .batteryLevel:
            return .batteryLevel
        }
    }

    var title: String {
        switch self {
        case .adapterInputPower:
            return "适配器实时"
        case .batteryDischargePower:
            return "电池输出"
        case .batteryChargePower:
            return "电池回充"
        case .batteryDischargeCurrent:
            return "放电电流"
        case .batteryChargeCurrent:
            return "充电电流"
        case .batteryLevel:
            return "电量"
        }
    }
}

struct PowerChartSeries: Identifiable, Sendable {
    let id: PowerChartSeriesKind
    let points: [PowerChartPoint]

    var title: String { id.title }
    var metric: ChartMetric { id.metric }
    var latestValue: Double? { points.last?.value }
    var hasData: Bool { !points.isEmpty }
}
