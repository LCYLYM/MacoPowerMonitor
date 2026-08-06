import Foundation
import XCTest
@testable import MacoPowerMonitor

@MainActor
final class PowerHistoryEngineTests: XCTestCase {
    func testAggregationSeparatesFlowsAndIgnoresMissingValues() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        try await engine.prepare()

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await engine.record(snapshot(
            at: start,
            source: .acPower,
            batteryLevel: 0.5,
            amperageMilliamps: -1_000,
            adapterInputPowerWatts: 10,
            batteryPowerWatts: -4
        ))
        try await engine.record(snapshot(
            at: start.addingTimeInterval(1),
            source: .acPower,
            batteryLevel: 0.7,
            amperageMilliamps: 2_000,
            adapterInputPowerWatts: 20,
            batteryPowerWatts: 6
        ))
        try await engine.record(snapshot(
            at: start.addingTimeInterval(2),
            source: .acPower,
            batteryLevel: .nan,
            amperageMilliamps: nil,
            adapterInputPowerWatts: .infinity,
            batteryPowerWatts: nil
        ))

        let projection = try await engine.projection(
            metrics: Set(ChartMetric.allCases),
            range: .oneHour,
            now: start.addingTimeInterval(5)
        )

        XCTAssertEqual(latestValue(.adapterInputPower, in: projection), 15, accuracy: 0.000_1)
        XCTAssertEqual(latestValue(.batteryDischargePower, in: projection), 4, accuracy: 0.000_1)
        XCTAssertEqual(latestValue(.batteryChargePower, in: projection), 6, accuracy: 0.000_1)
        XCTAssertEqual(latestValue(.batteryLevel, in: projection), 60, accuracy: 0.000_1)
        XCTAssertEqual(latestValue(.batteryDischargeCurrent, in: projection), 1, accuracy: 0.000_1)
        XCTAssertEqual(latestValue(.batteryChargeCurrent, in: projection), 2, accuracy: 0.000_1)
    }

    func testMinuteAggregatesRemainWeightedWhenProjected() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        try await engine.prepare()

        let nowSeconds = floor(Date().timeIntervalSince1970 / 600) * 600 + 590
        let now = Date(timeIntervalSince1970: nowSeconds)
        let minuteStart = floor(nowSeconds / 60) * 60 - 180
        try await engine.record(snapshot(
            at: Date(timeIntervalSince1970: minuteStart),
            batteryLevel: 0.1
        ))
        for offset in 0...2 {
            try await engine.record(snapshot(
                at: Date(timeIntervalSince1970: minuteStart + 60 + Double(offset)),
                batteryLevel: 0.2
            ))
        }
        try await engine.record(snapshot(
            at: Date(timeIntervalSince1970: minuteStart + 120),
            batteryLevel: .nan
        ))

        let projection = try await engine.projection(
            metrics: [.batteryLevel],
            range: .twentyFourHours,
            now: now
        )
        XCTAssertEqual(latestValue(.batteryLevel, in: projection), 17.5, accuracy: 0.000_1)
    }

    func testRetentionAndProjectionBucketLimitsAcrossAllRanges() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        try await engine.prepare()

        let now = Date()
        let oldTimestamp = now.addingTimeInterval(-(11 * 24 * 60 * 60))
        try await engine.record(snapshot(at: oldTimestamp, batteryLevel: 0.1))
        try await engine.record(snapshot(
            at: now.addingTimeInterval(-(9 * 24 * 60 * 60)),
            batteryLevel: 0.2
        ))
        try await engine.record(snapshot(
            at: now.addingTimeInterval(-(23 * 60 * 60)),
            batteryLevel: 0.3
        ))
        try await engine.record(snapshot(
            at: now.addingTimeInterval(-(5 * 60 * 60)),
            batteryLevel: 0.35
        ))

        for index in 0..<500 {
            let timestamp = now.addingTimeInterval(-3_000 + Double(index * 6))
            try await engine.record(snapshot(
                at: timestamp,
                batteryLevel: 0.4 + Double(index) / 10_000,
                batteryPowerWatts: -5
            ))
        }
        try await engine.flush()

        for range in ChartTimeRange.allCases {
            let projection = try await engine.projection(
                metrics: [.batteryLevel],
                range: range,
                now: now
            )
            let points = try XCTUnwrap(
                projection.seriesByMetric[.batteryLevel]?.first(where: { $0.id == .batteryLevel })?.points
            )
            XCTAssertLessThanOrEqual(points.count, range.bucketCount)
            XCTAssertTrue(points.allSatisfy {
                $0.timestamp >= now.addingTimeInterval(-range.interval) && $0.timestamp <= now
            })
            XCTAssertFalse(points.contains { abs($0.value - 10) < 0.000_1 })
        }

        let oneHour = try await engine.projection(metrics: [.batteryLevel], range: .oneHour, now: now)
        let twentyFourHours = try await engine.projection(
            metrics: [.batteryLevel],
            range: .twentyFourHours,
            now: now
        )
        let tenDays = try await engine.projection(metrics: [.batteryLevel], range: .tenDays, now: now)
        XCTAssertFalse(values(in: oneHour).contains { abs($0 - 35) < 0.000_1 })
        XCTAssertTrue(values(in: twentyFourHours).contains { abs($0 - 30) < 0.000_1 })
        XCTAssertTrue(values(in: tenDays).contains { abs($0 - 20) < 0.000_1 })
    }

    func testLegacyMigrationExcludesSerialNumberAndDeletesLegacyFile() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let serialNumber = "PRIVATE-SERIAL-123"
        let timestamp = Date().addingTimeInterval(-120)
        let firstSnapshot = snapshot(
            at: timestamp,
            source: .acPower,
            batteryLevel: 0.75,
            amperageMilliamps: 1_500,
            adapterInputPowerWatts: 30,
            batteryPowerWatts: 8,
            hardwareSerialNumber: serialNumber
        )
        let secondSnapshot = snapshot(
            at: timestamp.addingTimeInterval(1),
            source: .battery,
            batteryLevel: 0.74,
            amperageMilliamps: -1_000,
            batteryPowerWatts: -5,
            hardwareSerialNumber: serialNumber
        )
        let legacySnapshots = [
            secondSnapshot,
            firstSnapshot,
            firstSnapshot,
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacySnapshots).write(to: fixture.legacyURL, options: .atomic)

        let engine = fixture.engine()
        try await engine.prepare()

        let loadState = await engine.loadState
        XCTAssertEqual(loadState, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.legacyURL.path))

        let persistedText = try historyFiles(in: fixture.directoryURL)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertFalse(persistedText.contains(serialNumber))
        XCTAssertFalse(persistedText.contains("hardwareSerialNumber"))
        let rawLineCount = try historyFiles(in: fixture.directoryURL, tier: "raw")
            .map { try Data(contentsOf: $0).filter { $0 == 0x0A }.count }
            .reduce(0, +)
        XCTAssertEqual(rawLineCount, 2)

        let projection = try await engine.projection(
            metrics: [.power, .batteryLevel, .chargeRate],
            range: .oneHour,
            now: Date()
        )
        XCTAssertFalse(projection.seriesByMetric[.batteryLevel, default: []].isEmpty)
    }

    func testFailedMigrationPreservesLegacyFileAndEngineRemainsUsable() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let invalidLegacyData = Data("not valid JSON".utf8)
        try invalidLegacyData.write(to: fixture.legacyURL, options: .atomic)

        let engine = fixture.engine()
        try await engine.prepare()

        let loadState = await engine.loadState
        guard case .failed = loadState else {
            XCTFail("A malformed legacy file must be reported as a migration failure")
            return
        }
        XCTAssertEqual(try Data(contentsOf: fixture.legacyURL), invalidLegacyData)

        let timestamp = Date()
        try await engine.record(snapshot(at: timestamp, batteryLevel: 0.61))
        let projection = try await engine.projection(
            metrics: [.batteryLevel],
            range: .oneHour,
            now: timestamp
        )
        XCTAssertEqual(latestValue(.batteryLevel, in: projection), 61, accuracy: 0.000_1)
    }

    func testPrepareTrimsIncompleteJSONLTailAndKeepsValidRecords() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let timestamp = Date().addingTimeInterval(-30)
        let writer = fixture.engine()
        try await writer.prepare()
        try await writer.record(snapshot(at: timestamp, batteryLevel: 0.66))
        try await writer.flush()

        let rawFile = try XCTUnwrap(historyFiles(in: fixture.directoryURL, tier: "raw").first)
        let handle = try FileHandle(forWritingTo: rawFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"t\":".utf8))
        try handle.close()

        let reader = fixture.engine()
        try await reader.prepare()

        let recoveredData = try Data(contentsOf: rawFile)
        XCTAssertEqual(recoveredData.last, 0x0A)
        XCTAssertEqual(recoveredData.filter { $0 == 0x0A }.count, 1)

        let projection = try await reader.projection(
            metrics: [.batteryLevel],
            range: .oneHour,
            now: Date()
        )
        XCTAssertEqual(latestValue(.batteryLevel, in: projection), 66, accuracy: 0.000_1)
    }

    func testFlushReportsStorageFailure() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        try await engine.prepare()

        let rawDirectory = fixture.directoryURL.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.removeItem(at: rawDirectory)
        XCTAssertTrue(FileManager.default.createFile(atPath: rawDirectory.path, contents: Data()))

        try await engine.record(snapshot(at: Date(), batteryLevel: 0.5))
        do {
            try await engine.flush()
            XCTFail("Flush must report a storage error when the raw tier is not a directory")
        } catch let error as PowerHistoryEngineError {
            guard case .storageFailed = error else {
                XCTFail("Expected storageFailed, got \(error)")
                return
            }
        }
    }

    func testPrepareQuarantinesMalformedInteriorLineAndReportsWarning() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let timestamp = Date().addingTimeInterval(-30)
        let writer = fixture.engine()
        try await writer.prepare()
        try await writer.record(snapshot(at: timestamp, batteryLevel: 0.60))
        try await writer.record(snapshot(at: timestamp.addingTimeInterval(1), batteryLevel: 0.62))
        try await writer.flush()

        let rawFile = try XCTUnwrap(historyFiles(in: fixture.directoryURL, tier: "raw").first)
        let validLines = try String(contentsOf: rawFile, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(validLines.count, 2)
        let corrupted = "\(validLines[0])\nnot-json\n\(validLines[1])\n"
        try Data(corrupted.utf8).write(to: rawFile, options: .atomic)

        let reader = fixture.engine()
        try await reader.prepare()

        guard case .failed = await reader.loadState else {
            XCTFail("An isolated interior record must be surfaced as a recoverable warning")
            return
        }
        let projection = try await reader.projection(
            metrics: [.batteryLevel],
            range: .oneHour,
            now: Date()
        )
        XCTAssertEqual(latestValue(.batteryLevel, in: projection), 61, accuracy: 0.000_1)
        let rawDirectory = fixture.directoryURL.appendingPathComponent("raw", isDirectory: true)
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: rawDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(quarantined.count, 1)
    }

    func testPrepareReconcilesMissingCompletedAggregateTailsFromRaw() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let baseSeconds = floor(Date().addingTimeInterval(-(7 * 60 * 60)).timeIntervalSince1970 / 300) * 300
        let start = Date(timeIntervalSince1970: baseSeconds)
        let writer = fixture.engine()
        try await writer.prepare()
        try await writer.record(snapshot(at: start, batteryLevel: 0.40))
        try await writer.record(snapshot(at: start.addingTimeInterval(1), batteryLevel: 0.60))
        try await writer.record(snapshot(at: start.addingTimeInterval(300), batteryLevel: 0.70))
        try await writer.flush()

        for tier in ["minute", "five-minute"] {
            for file in try historyFiles(in: fixture.directoryURL, tier: tier) {
                try FileManager.default.removeItem(at: file)
            }
        }

        let reader = fixture.engine()
        try await reader.prepare()

        let verifier = fixture.engine()
        try await verifier.prepare()

        for tier in ["minute", "five-minute"] {
            let records = try aggregateRecords(in: fixture.directoryURL, tier: tier)
            let first = try XCTUnwrap(records.first { $0.bucketStart == start })
            let firstBatteryLevel = try XCTUnwrap(first.batteryLevel)
            XCTAssertEqual(firstBatteryLevel.sum, 100, accuracy: 0.000_1)
            XCTAssertEqual(firstBatteryLevel.count, 2)

            let secondStart = start.addingTimeInterval(300)
            let second = try XCTUnwrap(records.first { $0.bucketStart == secondStart })
            let secondBatteryLevel = try XCTUnwrap(second.batteryLevel)
            XCTAssertEqual(secondBatteryLevel.sum, 70, accuracy: 0.000_1)
            XCTAssertEqual(secondBatteryLevel.count, 1)
        }
    }

    func testMissingManifestDoesNotSilentlySkipLegacyMigration() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.directoryURL.appendingPathComponent("raw", isDirectory: true),
            withIntermediateDirectories: true
        )
        let timestamp = Date().addingTimeInterval(-30)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([snapshot(at: timestamp, batteryLevel: 0.73)])
            .write(to: fixture.legacyURL, options: .atomic)

        let engine = fixture.engine()
        try await engine.prepare()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.legacyURL.path))
        let projection = try await engine.projection(
            metrics: [.batteryLevel],
            range: .oneHour,
            now: Date()
        )
        XCTAssertEqual(latestValue(.batteryLevel, in: projection), 73, accuracy: 0.000_1)
    }

    func testStoragePermissionsAndLogicalWriteBudget() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        try await engine.prepare()
        let sample = snapshot(
            at: Date(),
            source: .acPower,
            batteryLevel: 0.731_234_567_89,
            amperageMilliamps: 1_987,
            adapterInputPowerWatts: 123.456_789,
            batteryPowerWatts: 45.678_912,
            isCharging: true
        )
        try await engine.record(sample)
        try await engine.flush()

        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: fixture.directoryURL.path)[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        let rawFile = try XCTUnwrap(historyFiles(in: fixture.directoryURL, tier: "raw").first)
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: rawFile.path)[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(fileMode & 0o777, 0o600)

        let raw = try XCTUnwrap(HistoricalRawRecord(snapshot: sample))
        let metric = HistoricalMetricAggregate(sum: 123.456_789, count: 60)
        let aggregate = HistoricalAggregateRecord(
            bucketStart: sample.timestamp,
            resolutionSeconds: 60,
            adapterInputPower: metric,
            batteryDischargePower: metric,
            batteryChargePower: metric,
            batteryLevel: metric,
            batteryDischargeCurrent: metric,
            batteryChargeCurrent: metric
        )
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .secondsSince1970
        jsonEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let rawLineBytes = try jsonEncoder.encode(raw).count + 1
        let aggregateLineBytes = try jsonEncoder.encode(aggregate).count + 1
        let logicalBytesPerDay = rawLineBytes * 86_400
            + aggregateLineBytes * 1_440
            + aggregateLineBytes * 288
        XCTAssertLessThan(logicalBytesPerDay, 50 * 1_024 * 1_024)
    }

    func testSessionResetsAfterGapAndPowerSourceChange() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        try await engine.prepare()

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await engine.record(snapshot(at: start, source: .battery, batteryLevel: 0.8))
        try await engine.record(snapshot(at: start.addingTimeInterval(1), source: .battery, batteryLevel: 0.79))

        var projection = try await engine.projection(
            metrics: [],
            range: .oneHour,
            now: start.addingTimeInterval(1)
        )
        XCTAssertEqual(projection.sessionSummary?.startedAt, start)
        XCTAssertEqual(projection.sessionSummary?.batteryPercentDelta ?? 0, -1, accuracy: 0.000_1)

        let afterGap = start.addingTimeInterval(AppConstants.refreshInterval * 3 + 2)
        try await engine.record(snapshot(at: afterGap, source: .battery, batteryLevel: 0.77))
        projection = try await engine.projection(metrics: [], range: .oneHour, now: afterGap)
        XCTAssertEqual(projection.sessionSummary?.startedAt, afterGap)
        XCTAssertEqual(projection.sessionSummary?.elapsed, 0)
        XCTAssertEqual(projection.sessionSummary?.batteryPercentDelta, 0)

        let onAC = afterGap.addingTimeInterval(1)
        try await engine.record(snapshot(
            at: onAC,
            source: .acPower,
            batteryLevel: 0.77,
            isCharging: true
        ))
        projection = try await engine.projection(metrics: [], range: .oneHour, now: onAC)
        XCTAssertEqual(projection.sessionSummary?.startedAt, onAC)
        XCTAssertEqual(projection.sessionSummary?.title, "自接通电源起")
    }

    func testPendingBuffersStayBoundedAndProjectionSurvivesRestart() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        try await engine.prepare()

        let now = Date()
        for index in 0..<95 {
            try await engine.record(snapshot(
                at: now.addingTimeInterval(Double(index - 95)),
                batteryLevel: 0.5 + Double(index) / 10_000
            ))
        }

        let diagnostics = await engine.memoryDiagnostics()
        XCTAssertLessThanOrEqual(diagnostics.pendingRawRecordCount, 30)
        XCTAssertLessThanOrEqual(diagnostics.pendingMinuteRecordCount, 2)
        XCTAssertLessThanOrEqual(diagnostics.pendingFiveMinuteRecordCount, 2)
        try await engine.flush()

        let restarted = fixture.engine()
        try await restarted.prepare()
        let projection = try await restarted.projection(
            metrics: [.batteryLevel],
            range: .oneHour,
            now: now
        )
        XCTAssertFalse(values(in: projection).isEmpty)
        let restartedDiagnostics = await restarted.memoryDiagnostics()
        XCTAssertEqual(restartedDiagnostics.pendingRawRecordCount, 0)
        XCTAssertEqual(restartedDiagnostics.pendingMinuteRecordCount, 0)
        XCTAssertEqual(restartedDiagnostics.pendingFiveMinuteRecordCount, 0)
    }

    func testSparseSamplesFlushAggregateBuffersBeforeTheyGrow() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let engine = fixture.engine()
        try await engine.prepare()

        let start = Date().addingTimeInterval(-3_600)
        for index in 0..<20 {
            try await engine.record(snapshot(
                at: start.addingTimeInterval(Double(index * 300)),
                batteryLevel: 0.5
            ))
            let diagnostics = await engine.memoryDiagnostics()
            XCTAssertLessThanOrEqual(diagnostics.pendingMinuteRecordCount, 2)
            XCTAssertLessThanOrEqual(diagnostics.pendingFiveMinuteRecordCount, 2)
        }
    }

    func testFullDensityDiskProjectionsCompleteWithinFourHundredMilliseconds() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let bootstrap = fixture.engine()
        try await bootstrap.prepare()

        let nowSeconds = floor(Date().timeIntervalSince1970)
        let now = Date(timeIntervalSince1970: nowSeconds)
        try writePerformanceFixture(to: fixture.directoryURL, now: now)

        let engine = fixture.engine()
        try await engine.prepare()

        let clock = ContinuousClock()
        for range in ChartTimeRange.allCases {
            let startedAt = clock.now
            let projection = try await engine.projection(
                metrics: Set(ChartMetric.allCases),
                range: range,
                now: now
            )
            let elapsed = startedAt.duration(to: clock.now)

            XCTAssertFalse(projection.seriesByMetric.isEmpty)
            XCTAssertLessThan(elapsed, .milliseconds(400))
            let points = try XCTUnwrap(
                projection.seriesByMetric[.batteryLevel]?
                    .first(where: { $0.id == .batteryLevel })?.points
            )
            let bucketWidth = range.interval / Double(range.bucketCount)
            let hasVisibleGap = zip(points, points.dropFirst()).contains { previous, next in
                next.timestamp.timeIntervalSince(previous.timestamp) > bucketWidth * 1.5
            }
            XCTAssertTrue(hasVisibleGap)
        }
    }

    private func latestValue(
        _ kind: PowerChartSeriesKind,
        in projection: HistoryProjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Double {
        guard let value = projection.seriesByMetric[kind.metric]?
            .first(where: { $0.id == kind })?
            .latestValue else {
            XCTFail("Missing series value for \(kind)", file: file, line: line)
            return .nan
        }
        return value
    }

    private func values(in projection: HistoryProjection) -> [Double] {
        projection.seriesByMetric[.batteryLevel]?
            .first(where: { $0.id == .batteryLevel })?
            .points
            .map(\.value) ?? []
    }

    private func makeFixture() throws -> HistoryFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacoPowerMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return HistoryFixture(rootURL: rootURL)
    }

    private func historyFiles(in directoryURL: URL, tier: String? = nil) throws -> [URL] {
        let root = tier.map { directoryURL.appendingPathComponent($0, isDirectory: true) } ?? directoryURL
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.path < $1.path }
    }

    private func aggregateRecords(in directoryURL: URL, tier: String) throws -> [HistoricalAggregateRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try historyFiles(in: directoryURL, tier: tier).flatMap { file in
            try Data(contentsOf: file)
                .split(separator: 0x0A, omittingEmptySubsequences: true)
                .map { try decoder.decode(HistoricalAggregateRecord.self, from: Data($0)) }
        }
    }

    private func writePerformanceFixture(to directoryURL: URL, now: Date) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var payloads: [URL: Data] = [:]

        let rawStart = now.addingTimeInterval(-3_600)
        for index in 1...3_600 {
            let timestamp = rawStart.addingTimeInterval(Double(index))
            let isGap = (1_800...1_859).contains(index)
            let sample = snapshot(
                at: timestamp,
                batteryLevel: isGap ? .nan : 0.5 + Double(index % 100) / 1_000,
                amperageMilliamps: isGap ? nil : -1_000,
                adapterInputPowerWatts: isGap ? nil : 20,
                batteryPowerWatts: isGap ? nil : -5
            )
            let record = try XCTUnwrap(HistoricalRawRecord(snapshot: sample))
            let url = directoryURL
                .appendingPathComponent("raw", isDirectory: true)
                .appendingPathComponent(sliceName(for: timestamp, includesHour: true) + ".jsonl")
            try appendJSONLine(record, to: url, encoder: encoder, payloads: &payloads)
        }

        let minuteStart = now.addingTimeInterval(-24 * 60 * 60)
        for index in 1...1_440 where !(700...709).contains(index) {
            let timestamp = minuteStart.addingTimeInterval(Double(index * 60))
            let record = aggregateRecord(at: timestamp, resolutionSeconds: 60, value: 40 + Double(index % 50))
            let url = directoryURL
                .appendingPathComponent("minute", isDirectory: true)
                .appendingPathComponent(sliceName(for: timestamp, includesHour: true) + ".jsonl")
            try appendJSONLine(record, to: url, encoder: encoder, payloads: &payloads)
        }

        let fiveMinuteStart = now.addingTimeInterval(-10 * 24 * 60 * 60)
        for index in 1...2_880 where !(1_400...1_435).contains(index) {
            let timestamp = fiveMinuteStart.addingTimeInterval(Double(index * 300))
            let record = aggregateRecord(at: timestamp, resolutionSeconds: 300, value: 50 + Double(index % 40))
            let url = directoryURL
                .appendingPathComponent("five-minute", isDirectory: true)
                .appendingPathComponent(sliceName(for: timestamp, includesHour: false) + ".jsonl")
            try appendJSONLine(record, to: url, encoder: encoder, payloads: &payloads)
        }

        for (url, data) in payloads {
            try data.write(to: url, options: .atomic)
        }
    }

    private func aggregateRecord(
        at timestamp: Date,
        resolutionSeconds: Int,
        value: Double
    ) -> HistoricalAggregateRecord {
        let aggregate = HistoricalMetricAggregate(sum: value * 3, count: 3)
        return HistoricalAggregateRecord(
            bucketStart: timestamp,
            resolutionSeconds: resolutionSeconds,
            adapterInputPower: aggregate,
            batteryDischargePower: aggregate,
            batteryChargePower: aggregate,
            batteryLevel: aggregate,
            batteryDischargeCurrent: aggregate,
            batteryChargeCurrent: aggregate
        )
    }

    private func appendJSONLine<T: Encodable>(
        _ record: T,
        to url: URL,
        encoder: JSONEncoder,
        payloads: inout [URL: Data]
    ) throws {
        payloads[url, default: Data()].append(try encoder.encode(record))
        payloads[url, default: Data()].append(0x0A)
    }

    private func sliceName(for date: Date, includesHour: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = includesHour ? "yyyy-MM-dd'T'HH" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func snapshot(
        at timestamp: Date,
        source: PowerSourceKind = .battery,
        batteryLevel: Double,
        amperageMilliamps: Int? = nil,
        adapterInputPowerWatts: Double? = nil,
        batteryPowerWatts: Double? = nil,
        hardwareSerialNumber: String? = nil,
        isCharging: Bool = false
    ) -> PowerSnapshot {
        PowerSnapshot(
            timestamp: timestamp,
            source: source,
            batteryName: "Test Battery",
            batteryLevel: batteryLevel,
            currentChargePercent: batteryLevel.isFinite ? batteryLevel * 100 : nil,
            nominalCapacity: nil,
            designCapacity: nil,
            fullChargeCapacity: nil,
            designCycleCount: nil,
            cycleCount: nil,
            maximumCapacityPercent: nil,
            hardwareSerialNumber: hardwareSerialNumber,
            isCharging: isCharging,
            isCharged: false,
            timeToEmptyMinutes: nil,
            timeToFullChargeMinutes: nil,
            voltageMillivolts: nil,
            amperageMilliamps: amperageMilliamps,
            temperatureCelsius: nil,
            batteryHealthCondition: nil,
            batteryHealthState: nil,
            adapterWatts: nil,
            adapterVoltageMillivolts: nil,
            adapterCurrentMilliamps: nil,
            adapterInputVoltageMillivolts: nil,
            adapterInputCurrentMilliamps: nil,
            adapterInputPowerWatts: adapterInputPowerWatts,
            adapterProtocol: nil,
            adapterProtocolDetail: nil,
            adapterVendorID: nil,
            adapterProductID: nil,
            adapterPDRevisionCode: nil,
            systemPowerWatts: nil,
            batteryPowerWatts: batteryPowerWatts,
            cpuPowerWatts: nil,
            gpuPowerWatts: nil,
            anePowerWatts: nil,
            subsystemPowerUnavailableReason: nil
        )
    }
}

// Deterministic disk fixtures live only in the test target and are never a runtime data fallback.
private struct HistoryFixture {
    let rootURL: URL

    var directoryURL: URL {
        rootURL.appendingPathComponent("power-history", isDirectory: true)
    }

    var legacyURL: URL {
        rootURL.appendingPathComponent("power-history.json")
    }

    func engine() -> PowerHistoryEngine {
        PowerHistoryEngine(
            directoryURL: directoryURL,
            legacyFileURL: legacyURL,
            flushInterval: .greatestFiniteMagnitude
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
