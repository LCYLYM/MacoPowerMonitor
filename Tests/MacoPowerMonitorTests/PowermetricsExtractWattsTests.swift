import Foundation
import XCTest
@testable import MacoPowerMonitor

final class PowermetricsExtractWattsTests: XCTestCase {
    private let provider = PowermetricsSubsystemPowerProvider()

    func testMilliwattsAreConvertedToWatts() {
        let plist: [String: Any] = [
            "processor": [
                "CPU Power": 1_500
            ]
        ]

        let result = provider.extractWatts(from: plist, matching: ["cpu"])

        XCTAssertEqual(result, 1.5)
    }

    func testCombinedPowerKeyDoesNotMatchSubsystemKeywords() {
        let plist: [String: Any] = [
            "processor": [
                "Combined Power (CPU+GPU+ANE)": 9_000,
                "GPU Power": 2_000
            ]
        ]

        let result = provider.extractWatts(from: plist, matching: ["gpu"])

        XCTAssertEqual(result, 2.0)
    }

    func testCombinedPowerIsTheOnlyCandidateReturnsNil() {
        let plist: [String: Any] = [
            "processor": [
                "Combined Power (CPU+GPU+ANE)": 9_000
            ]
        ]

        let result = provider.extractWatts(from: plist, matching: ["ane"])

        XCTAssertNil(result)
    }
}
