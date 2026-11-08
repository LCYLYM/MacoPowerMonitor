import Foundation
import XCTest
@testable import MacoPowerMonitor

final class DisplayStatusTextTests: XCTestCase {
    func testManualLimitHoldUsesLimitText() {
        let snapshot = makeSnapshot(chargeHoldReason: .manualLimit)

        XCTAssertEqual(snapshot.displayStatusText, "已达到充电上限")
    }

    func testOptimizedChargingHoldUsesOptimizedText() {
        let snapshot = makeSnapshot(chargeHoldReason: .optimizedCharging)

        XCTAssertEqual(snapshot.displayStatusText, "优化充电暂停")
    }

    func testFullyChargedHoldUsesChargedText() {
        let snapshot = makeSnapshot(chargeHoldReason: .fullyCharged, isCharged: true)

        XCTAssertEqual(snapshot.displayStatusText, "已充满")
    }

    func testInferredPolicyLimitHoldUsesTargetText() {
        let snapshot = makeSnapshot(chargeHoldReason: .inferredPolicyLimit)

        XCTAssertEqual(snapshot.displayStatusText, "已达到充电目标")
    }

    func testChargeHoldReasonWinsOverChargingFlags() {
        let snapshot = makeSnapshot(
            isCharging: true,
            isCharged: true,
            chargeHoldReason: .manualLimit
        )

        XCTAssertEqual(snapshot.displayStatusText, "已达到充电上限")
    }

    func testBatterySourceIgnoresChargeHoldReason() {
        let snapshot = makeSnapshot(
            source: .battery,
            chargeHoldReason: .manualLimit
        )

        XCTAssertEqual(snapshot.displayStatusText, "电池供电")
    }

    func testChargedAdapterUsesChargedText() {
        let snapshot = makeSnapshot(isCharged: true)

        XCTAssertEqual(snapshot.displayStatusText, "已充满")
    }

    func testChargingAdapterUsesChargingText() {
        let snapshot = makeSnapshot(isCharging: true)

        XCTAssertEqual(snapshot.displayStatusText, "正在充电")
    }

    func testIdleAdapterUsesExternalPowerText() {
        let snapshot = makeSnapshot()

        XCTAssertEqual(snapshot.displayStatusText, "外接电源")
    }

    func testBatterySourceUsesBatteryText() {
        let snapshot = makeSnapshot(source: .battery)

        XCTAssertEqual(snapshot.displayStatusText, "电池供电")
    }

    func testUnknownSourceUsesUnknownText() {
        let snapshot = makeSnapshot(source: .unknown)

        XCTAssertEqual(snapshot.displayStatusText, "状态未知")
    }

    private func makeSnapshot(
        source: PowerSourceKind = .acPower,
        isCharging: Bool = false,
        isCharged: Bool = false,
        chargeHoldReason: ChargeHoldReason? = nil
    ) -> PowerSnapshot {
        PowerSnapshot(
            timestamp: Date(),
            source: source,
            batteryName: nil,
            batteryLevel: 0.85,
            currentChargePercent: nil,
            nominalCapacity: nil,
            designCapacity: nil,
            fullChargeCapacity: nil,
            designCycleCount: nil,
            cycleCount: nil,
            maximumCapacityPercent: nil,
            hardwareSerialNumber: nil,
            isCharging: isCharging,
            isCharged: isCharged,
            chargeHoldReason: chargeHoldReason,
            chargeLimitPercent: nil,
            timeToEmptyMinutes: nil,
            timeToFullChargeMinutes: nil,
            voltageMillivolts: nil,
            amperageMilliamps: nil,
            temperatureCelsius: nil,
            batteryHealthCondition: nil,
            batteryHealthState: nil,
            adapterWatts: nil,
            adapterVoltageMillivolts: nil,
            adapterCurrentMilliamps: nil,
            adapterInputVoltageMillivolts: nil,
            adapterInputCurrentMilliamps: nil,
            adapterInputPowerWatts: nil,
            adapterProtocol: nil,
            adapterProtocolDetail: nil,
            adapterVendorID: nil,
            adapterProductID: nil,
            adapterPDRevisionCode: nil,
            systemPowerWatts: nil,
            batteryPowerWatts: nil,
            cpuPowerWatts: nil,
            gpuPowerWatts: nil,
            anePowerWatts: nil,
            subsystemPowerUnavailableReason: nil
        )
    }
}
