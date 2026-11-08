import Foundation

enum ChargeHoldReason: String, Codable, Equatable, Sendable {
    case manualLimit
    case optimizedCharging
    case fullyCharged
    case inferredPolicyLimit

    var displayText: String {
        switch self {
        case .manualLimit:
            return "达到上限"
        case .optimizedCharging:
            return "优化充电"
        case .fullyCharged:
            return "已充满"
        case .inferredPolicyLimit:
            return "达到目标"
        }
    }
}

struct ChargeLimitStatus: Equatable, Sendable {
    let manualLimitPercent: Int?
    let isManualLimitEnabled: Bool?
    let optimizedLimitPercent: Int?
    let isOptimizedChargingEngaged: Bool?

    static let unavailable = ChargeLimitStatus(
        manualLimitPercent: nil,
        isManualLimitEnabled: nil,
        optimizedLimitPercent: nil,
        isOptimizedChargingEngaged: nil
    )
}

struct ChargeHoldResolution: Equatable, Sendable {
    let reason: ChargeHoldReason?
    let limitPercent: Int?

    static let none = ChargeHoldResolution(reason: nil, limitPercent: nil)
}

enum ChargeHoldResolver {
    // Observed on macOS 26.5 when the battery is held at a fixed manual limit.
    // It is intentionally a fallback only; PowerUI remains the authoritative
    // source whenever its read-only client is available.
    static let policyLimitNotChargingMask: UInt64 = 1 << 24

    static func resolve(
        source: PowerSourceKind,
        batteryLevel: Double,
        isCharging: Bool,
        isCharged: Bool,
        chargeStatus: String?,
        notChargingReason: UInt64?,
        limitStatus: ChargeLimitStatus
    ) -> ChargeHoldResolution {
        guard source == .acPower else {
            return .none
        }

        if isCharged {
            return ChargeHoldResolution(reason: .fullyCharged, limitPercent: 100)
        }

        // Active current flow always wins over a configured target. This
        // prevents the plug from appearing during the final top-off phase.
        if isCharging {
            return .none
        }

        let currentPercent = Int((min(max(batteryLevel, 0), 1) * 100).rounded())

        if limitStatus.isManualLimitEnabled == true,
           let limit = validatedLimit(limitStatus.manualLimitPercent),
           hasReached(currentPercent: currentPercent, targetPercent: limit) {
            return ChargeHoldResolution(reason: .manualLimit, limitPercent: limit)
        }

        if limitStatus.isOptimizedChargingEngaged == true {
            if let limit = validatedLimit(limitStatus.optimizedLimitPercent) {
                if hasReached(currentPercent: currentPercent, targetPercent: limit) {
                    return ChargeHoldResolution(reason: .optimizedCharging, limitPercent: limit)
                }
            } else {
                return ChargeHoldResolution(
                    reason: .optimizedCharging,
                    limitPercent: currentPercent
                )
            }
        }

        // A published ChargeStatus describes a thermal or other explicit
        // interruption. Do not reinterpret it as a charge ceiling.
        if let chargeStatus, !chargeStatus.isEmpty {
            return .none
        }

        if let notChargingReason,
           notChargingReason & policyLimitNotChargingMask != 0 {
            return ChargeHoldResolution(
                reason: .inferredPolicyLimit,
                limitPercent: currentPercent
            )
        }

        return .none
    }

    private static func validatedLimit(_ limit: Int?) -> Int? {
        guard let limit, (80...100).contains(limit) else {
            return nil
        }
        return limit
    }

    private static func hasReached(
        currentPercent: Int,
        targetPercent: Int
    ) -> Bool {
        currentPercent >= targetPercent - 1
    }
}
