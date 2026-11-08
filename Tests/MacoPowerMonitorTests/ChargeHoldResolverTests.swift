import Foundation
import XCTest
@testable import MacoPowerMonitor

final class ChargeHoldResolverTests: XCTestCase {
    func testBatteryPowerNeverProducesChargeHold() {
        let result = resolve(
            source: .battery,
            level: 0.85,
            notChargingReason: ChargeHoldResolver.policyLimitNotChargingMask,
            limitStatus: manualLimit(85)
        )

        XCTAssertEqual(result, .none)
    }

    func testActiveChargingWinsOverConfiguredLimit() {
        let result = resolve(
            level: 0.85,
            isCharging: true,
            limitStatus: manualLimit(85)
        )

        XCTAssertEqual(result, .none)
    }

    func testBelowManualLimitKeepsChargingPresentation() {
        let result = resolve(
            level: 0.82,
            limitStatus: manualLimit(85)
        )

        XCTAssertEqual(result, .none)
    }

    func testManualLimitAllowsOnePercentTolerance() {
        let result = resolve(
            level: 0.84,
            limitStatus: manualLimit(85)
        )

        XCTAssertEqual(result, ChargeHoldResolution(reason: .manualLimit, limitPercent: 85))
    }

    func testOptimizedChargingHoldUsesPlugPresentation() {
        let result = resolve(
            level: 0.8,
            limitStatus: ChargeLimitStatus(
                manualLimitPercent: nil,
                isManualLimitEnabled: false,
                optimizedLimitPercent: 80,
                isOptimizedChargingEngaged: true
            )
        )

        XCTAssertEqual(result, ChargeHoldResolution(reason: .optimizedCharging, limitPercent: 80))
    }

    func testFullyChargedUsesPlugPresentation() {
        let result = resolve(level: 1, isCharged: true)

        XCTAssertEqual(result, ChargeHoldResolution(reason: .fullyCharged, limitPercent: 100))
    }

    func testThermalChargeStatusSuppressesPolicyFallback() {
        let result = resolve(
            level: 0.85,
            chargeStatus: "HighTemperature",
            notChargingReason: ChargeHoldResolver.policyLimitNotChargingMask
        )

        XCTAssertEqual(result, .none)
    }

    func testPolicyReasonFallbackInfersChargeTarget() {
        let result = resolve(
            level: 0.85,
            notChargingReason: ChargeHoldResolver.policyLimitNotChargingMask
        )

        XCTAssertEqual(result, ChargeHoldResolution(reason: .inferredPolicyLimit, limitPercent: 85))
    }

    func testLegacySnapshotWithoutChargeHoldFieldsStillDecodes() throws {
        let json = """
        {
          "timestamp": "2026-07-18T00:00:00Z",
          "source": "acPower",
          "batteryLevel": 0.85,
          "isCharging": false,
          "isCharged": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(PowerSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(snapshot.chargeHoldReason)
        XCTAssertNil(snapshot.chargeLimitPercent)
        XCTAssertEqual(snapshot.displayStatusText, "外接电源")
    }

    func testBackgroundChargeLimitReadUsesPlainSwiftCache() async {
        let expected = ChargeLimitStatusProvider.shared.cachedStatusOnly()
        let actual = await Task.detached {
            ChargeLimitStatusProvider.shared.currentStatus()
        }.value

        XCTAssertEqual(actual, expected)
    }

    private func resolve(
        source: PowerSourceKind = .acPower,
        level: Double,
        isCharging: Bool = false,
        isCharged: Bool = false,
        chargeStatus: String? = nil,
        notChargingReason: UInt64? = nil,
        limitStatus: ChargeLimitStatus = .unavailable
    ) -> ChargeHoldResolution {
        ChargeHoldResolver.resolve(
            source: source,
            batteryLevel: level,
            isCharging: isCharging,
            isCharged: isCharged,
            chargeStatus: chargeStatus,
            notChargingReason: notChargingReason,
            limitStatus: limitStatus
        )
    }

    private func manualLimit(_ percent: Int) -> ChargeLimitStatus {
        ChargeLimitStatus(
            manualLimitPercent: percent,
            isManualLimitEnabled: true,
            optimizedLimitPercent: nil,
            isOptimizedChargingEngaged: false
        )
    }
}
