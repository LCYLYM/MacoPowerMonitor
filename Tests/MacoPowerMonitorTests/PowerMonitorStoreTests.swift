import Foundation
import XCTest
@testable import MacoPowerMonitor

@MainActor
final class PowerMonitorStoreTests: XCTestCase {
    func testPanelRefreshPublishesAllOrdinaryDataAndClearsPresentationCaches() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacoPowerMonitorStoreTests-\(UUID().uuidString)", isDirectory: true)
        let historyURL = rootURL.appendingPathComponent("power-history", isDirectory: true)
        let legacyURL = rootURL.appendingPathComponent("power-history.json")
        let engine = PowerHistoryEngine(
            directoryURL: historyURL,
            legacyFileURL: legacyURL,
            flushInterval: .greatestFiniteMagnitude
        )
        try await engine.prepare()
        try await engine.record(makeSnapshot(at: Date().addingTimeInterval(-1)))
        try await engine.flush()

        let processProvider = ImmediateProcessStatsProvider()
        let store = PowerMonitorStore(
            collector: ImmediatePowerSnapshotCollector(),
            historyEngine: engine,
            scheduler: RepeatingTaskScheduler(interval: 3_600, tolerance: 1),
            processStatsProvider: processProvider,
            startsScheduler: false
        )

        for _ in 0..<100 where store.historyLoadState == .loading || store.historyLoadState == .idle {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(store.historyLoadState, .ready)

        store.beginPanelPresentation(openedAt: ContinuousClock.now)
        for _ in 0..<100 where store.lastPanelRefreshDurationMilliseconds == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertNotNil(store.latestSnapshot)
        XCTAssertFalse(store.chartSeriesByMetric.isEmpty)
        XCTAssertEqual(store.topProcesses.first?.command, "TestProcess")
        XCTAssertEqual(processProvider.refreshCount, 1)
        XCTAssertLessThan(store.lastPanelRefreshDurationMilliseconds ?? .infinity, 400)

        store.endPanelPresentation()
        XCTAssertTrue(store.chartSeriesByMetric.isEmpty)
        XCTAssertTrue(store.topProcesses.isEmpty)

        await store.shutdown()
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testClosingPanelCancelsChildrenAndRejectsLateProcessResults() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacoPowerMonitorStoreCancellationTests-\(UUID().uuidString)", isDirectory: true)
        let engine = PowerHistoryEngine(
            directoryURL: rootURL.appendingPathComponent("power-history", isDirectory: true),
            legacyFileURL: rootURL.appendingPathComponent("power-history.json"),
            flushInterval: .greatestFiniteMagnitude
        )
        try await engine.prepare()

        let processProvider = CancellableDelayedProcessStatsProvider()
        let store = PowerMonitorStore(
            collector: ImmediatePowerSnapshotCollector(),
            historyEngine: engine,
            scheduler: RepeatingTaskScheduler(interval: 3_600, tolerance: 1),
            processStatsProvider: processProvider,
            startsScheduler: false
        )

        for _ in 0..<100 where store.historyLoadState == .loading || store.historyLoadState == .idle {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(store.historyLoadState, .ready)

        store.beginPanelPresentation(openedAt: ContinuousClock.now)
        for _ in 0..<100 where processProvider.refreshCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        store.endPanelPresentation()

        for _ in 0..<100 where !processProvider.observedCancellation {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(processProvider.observedCancellation)
        XCTAssertTrue(store.topProcesses.isEmpty)
        XCTAssertTrue(store.chartSeriesByMetric.isEmpty)

        await store.shutdown()
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testColdHistoryPreparationIsIncludedInPanelDeadline() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacoPowerMonitorColdHistoryTests-\(UUID().uuidString)", isDirectory: true)
        let store = PowerMonitorStore(
            collector: ImmediatePowerSnapshotCollector(),
            historyEngine: PowerHistoryEngine(
                directoryURL: rootURL.appendingPathComponent("power-history", isDirectory: true),
                legacyFileURL: rootURL.appendingPathComponent("power-history.json")
            ),
            scheduler: RepeatingTaskScheduler(interval: 3_600, tolerance: 1),
            processStatsProvider: ImmediateProcessStatsProvider(),
            startsScheduler: false
        )

        store.beginPanelPresentation(openedAt: ContinuousClock.now)
        for _ in 0..<100 where store.lastPanelRefreshDurationMilliseconds == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertLessThan(store.lastPanelRefreshDurationMilliseconds ?? .infinity, 400)
        XCTAssertFalse(store.chartSeriesByMetric.isEmpty)

        await store.shutdown()
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testLateProcessResultIsNotPublishedAfterDeadline() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacoPowerMonitorDeadlineTests-\(UUID().uuidString)", isDirectory: true)
        let engine = PowerHistoryEngine(
            directoryURL: rootURL.appendingPathComponent("power-history", isDirectory: true),
            legacyFileURL: rootURL.appendingPathComponent("power-history.json")
        )
        try await engine.prepare()
        let store = PowerMonitorStore(
            collector: ImmediatePowerSnapshotCollector(),
            historyEngine: engine,
            scheduler: RepeatingTaskScheduler(interval: 3_600, tolerance: 1),
            processStatsProvider: NonCooperativeDelayedProcessStatsProvider(),
            startsScheduler: false
        )

        store.beginPanelPresentation(openedAt: ContinuousClock.now)
        for _ in 0..<120 where store.lastPanelRefreshDurationMilliseconds == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue((store.lastPanelRefreshDurationMilliseconds ?? 0) >= 400)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(store.topProcesses.isEmpty)

        store.endPanelPresentation()
        await store.shutdown()
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testCommandRunnerCancellationTerminatesChildProcess() async throws {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task.detached { () -> Bool in
            do {
                _ = try CommandRunner.run(executable: "/bin/sleep", arguments: ["5"])
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        try await Task.sleep(for: .milliseconds(25))
        task.cancel()
        let observedCancellation = await task.value
        XCTAssertTrue(observedCancellation)
        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(1))
    }

    private func makeSnapshot(at timestamp: Date) -> PowerSnapshot {
        PowerSnapshot(
            timestamp: timestamp,
            source: .battery,
            batteryName: "Test Battery",
            batteryLevel: 0.75,
            currentChargePercent: 75,
            nominalCapacity: 4_000,
            designCapacity: 5_000,
            fullChargeCapacity: 4_500,
            designCycleCount: nil,
            cycleCount: 100,
            maximumCapacityPercent: 90,
            hardwareSerialNumber: nil,
            isCharging: false,
            isCharged: false,
            timeToEmptyMinutes: 300,
            timeToFullChargeMinutes: nil,
            voltageMillivolts: 12_000,
            amperageMilliamps: -1_000,
            temperatureCelsius: 32,
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
            systemPowerWatts: 12,
            batteryPowerWatts: -12,
            cpuPowerWatts: nil,
            gpuPowerWatts: nil,
            anePowerWatts: nil,
            subsystemPowerUnavailableReason: nil
        )
    }
}

private final class ImmediatePowerSnapshotCollector: PowerSnapshotCollecting, @unchecked Sendable {
    func readSnapshot() throws -> PowerSnapshot {
        PowerSnapshot(
            timestamp: Date(),
            source: .battery,
            batteryName: "Test Battery",
            batteryLevel: 0.75,
            currentChargePercent: 75,
            nominalCapacity: 4_000,
            designCapacity: 5_000,
            fullChargeCapacity: 4_500,
            designCycleCount: nil,
            cycleCount: 100,
            maximumCapacityPercent: 90,
            hardwareSerialNumber: nil,
            isCharging: false,
            isCharged: false,
            timeToEmptyMinutes: 300,
            timeToFullChargeMinutes: nil,
            voltageMillivolts: 12_000,
            amperageMilliamps: -1_000,
            temperatureCelsius: 32,
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
            systemPowerWatts: 12,
            batteryPowerWatts: -12,
            cpuPowerWatts: nil,
            gpuPowerWatts: nil,
            anePowerWatts: nil,
            subsystemPowerUnavailableReason: nil
        )
    }
}

private final class ImmediateProcessStatsProvider: ProcessEnergyStatsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var refreshCount: Int {
        lock.withLock { count }
    }

    func currentStats(limit: Int, forceRefresh: Bool) -> [ProcessEnergyStat] {
        lock.withLock { count += 1 }
        return [ProcessEnergyStat(
            pid: 42,
            command: "TestProcess",
            cpuPercent: 12,
            powerScore: 0,
            memoryText: "10M"
        )]
    }
}

private final class CancellableDelayedProcessStatsProvider: ProcessEnergyStatsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var cancellationObserved = false

    var refreshCount: Int {
        lock.withLock { count }
    }

    var observedCancellation: Bool {
        lock.withLock { cancellationObserved }
    }

    func currentStats(limit: Int, forceRefresh: Bool) -> [ProcessEnergyStat] {
        lock.withLock { count += 1 }
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if Task.isCancelled {
                lock.withLock { cancellationObserved = true }
                return []
            }
            Thread.sleep(forTimeInterval: 0.005)
        }

        return [ProcessEnergyStat(
            pid: 99,
            command: "LateProcess",
            cpuPercent: 99,
            powerScore: 0,
            memoryText: "99M"
        )]
    }
}

private final class NonCooperativeDelayedProcessStatsProvider: ProcessEnergyStatsProviding, @unchecked Sendable {
    func currentStats(limit: Int, forceRefresh: Bool) -> [ProcessEnergyStat] {
        Thread.sleep(forTimeInterval: 0.5)
        return [ProcessEnergyStat(
            pid: 100,
            command: "TooLate",
            cpuPercent: 100,
            powerScore: 0,
            memoryText: "100M"
        )]
    }
}
