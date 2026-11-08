import Foundation
import XCTest
@testable import MacoPowerMonitor

final class PowerAdapterProtocolTests: XCTestCase {
    func testWirelessFlagProducesWirelessProtocol() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["IsWireless": true, "VendorID": 1_452]
        )

        XCTAssertEqual(result.protocol, .wireless)
        XCTAssertEqual(result.detail, "系统报告为无线电源")
        XCTAssertEqual(result.vendorID, 1_452)
    }

    func testMagSafeBatteryTextProducesWirelessProtocol() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["Description": "MagSafe Battery Pack"]
        )

        XCTAssertEqual(result.protocol, .wireless)
        XCTAssertEqual(result.detail, "系统报告为无线电源")
    }

    func testExternalConnectionWithPDRevisionProducesPowerDelivery() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: [:],
            fedDetails: [
                "FedExternalConnected": true,
                "FedPdSpecRevision": 3,
                "FedVendorID": 1_452,
                "FedProductID": 4_127
            ]
        )

        XCTAssertEqual(result.protocol, .usbPowerDelivery)
        XCTAssertEqual(result.detail, "PD 修订码 3 · VID 0x05AC · PID 0x101F")
        XCTAssertEqual(result.vendorID, 1_452)
        XCTAssertEqual(result.productID, 4_127)
        XCTAssertEqual(result.pdRevisionCode, 3)
    }

    func testPowerDeliveryTextProducesPowerDeliveryWithoutIDs() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["Description": "USB Power Delivery Adapter"]
        )

        XCTAssertEqual(result.protocol, .usbPowerDelivery)
        XCTAssertEqual(result.detail, "检测到 USB PD 协商")
        XCTAssertNil(result.vendorID)
        XCTAssertNil(result.pdRevisionCode)
    }

    func testExternalConnectionWithoutPDRevisionFallsThrough() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: [:],
            fedDetails: [
                "FedExternalConnected": true,
                "FedPdSpecRevision": 0
            ]
        )

        XCTAssertEqual(result.protocol, .unknown)
        XCTAssertNil(result.detail)
        XCTAssertEqual(result.pdRevisionCode, 0)
    }

    func testPDRevisionWithoutExternalConnectionFallsThrough() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: [:],
            fedDetails: ["FedPdSpecRevision": 3]
        )

        XCTAssertEqual(result.protocol, .unknown)
        XCTAssertNil(result.detail)
        XCTAssertEqual(result.pdRevisionCode, 3)
    }

    func testZeroVendorIDIsOmittedFromPowerDeliveryDetail() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["VendorID": 0],
            fedDetails: [
                "FedExternalConnected": true,
                "FedPdSpecRevision": 2
            ]
        )

        XCTAssertEqual(result.protocol, .usbPowerDelivery)
        XCTAssertEqual(result.detail, "PD 修订码 2")
        XCTAssertEqual(result.vendorID, 0)
    }

    func testFedVendorIDTakesPrecedenceOverAdapterVendorID() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["VendorID": 111],
            fedDetails: [
                "FedExternalConnected": true,
                "FedPdSpecRevision": 2,
                "FedVendorID": 222
            ]
        )

        XCTAssertEqual(result.protocol, .usbPowerDelivery)
        XCTAssertEqual(result.detail, "PD 修订码 2 · VID 0x00DE")
        XCTAssertEqual(result.vendorID, 222)
    }

    func testAdapterVendorIDUsedWhenFedVendorIDMissing() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["VendorID": 4_662],
            fedDetails: [
                "FedExternalConnected": true,
                "FedPdSpecRevision": 1
            ]
        )

        XCTAssertEqual(result.protocol, .usbPowerDelivery)
        XCTAssertEqual(result.detail, "PD 修订码 1 · VID 0x1236")
        XCTAssertEqual(result.vendorID, 4_662)
    }

    func testQuickChargeTextProducesQuickChargeProtocol() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["Description": "Qualcomm Quick Charge 3.0"]
        )

        XCTAssertEqual(result.protocol, .quickCharge)
        XCTAssertEqual(result.detail, "系统注册表包含 Quick Charge 标识")
    }

    func testApplePrivateTextProducesApplePrivateProtocol() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["Description": "Apple 2.4A charging"]
        )

        XCTAssertEqual(result.protocol, .applePrivate)
        XCTAssertEqual(result.detail, "系统仅报告 Apple 充电器标识，未报告 USB PD 协商")
    }

    func testUsbHvcMenuKeyProducesTypeCProtocol() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["UsbHvcMenu": [["Index": 0]]]
        )

        XCTAssertEqual(result.protocol, .usbTypeC)
        XCTAssertEqual(result.detail, "检测到 USB-C 高压档位，但系统未公开具体协议")
    }

    func testTypeCTextProducesTypeCProtocol() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["Description": "USB-C adapter"]
        )

        XCTAssertEqual(result.protocol, .usbTypeC)
        XCTAssertEqual(result.detail, "检测到 USB-C 高压档位，但系统未公开具体协议")
    }

    func testAdapterVoltageAloneProducesUnknownWithDetail() {
        let result = PowerAdapterProtocolDetector.detect(
            adapterDetails: ["AdapterVoltage": 20_000]
        )

        XCTAssertEqual(result.protocol, .unknown)
        XCTAssertEqual(result.detail, "已检测到外接电源，macOS 未公开协议标识")
    }

    func testEmptyDetailsProduceUnknownWithoutDetail() {
        let result = PowerAdapterProtocolDetector.detect(adapterDetails: [:])

        XCTAssertEqual(result.protocol, .unknown)
        XCTAssertNil(result.detail)
        XCTAssertNil(result.vendorID)
        XCTAssertNil(result.productID)
        XCTAssertNil(result.pdRevisionCode)
    }
}
