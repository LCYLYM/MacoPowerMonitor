import Foundation
import OSLog

enum HistoryLoadState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct HistorySelection: Equatable, Sendable {
    let metrics: Set<ChartMetric>
    let range: ChartTimeRange
}

struct HistoryProjection: Sendable {
    let seriesByMetric: [ChartMetric: [PowerChartSeries]]
    let sessionSummary: SessionSummary?
    let generatedAt: Date
}

struct HistoryMemoryDiagnostics: Equatable, Sendable {
    let pendingRawRecordCount: Int
    let pendingMinuteRecordCount: Int
    let pendingFiveMinuteRecordCount: Int
    let hasActiveMinuteBucket: Bool
    let hasActiveFiveMinuteBucket: Bool
}

enum PowerHistoryEngineError: LocalizedError, Sendable {
    case notPrepared
    case migrationFailed(String)
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "历史记录引擎尚未准备完成"
        case let .migrationFailed(message):
            return "历史记录迁移失败：\(message)"
        case let .storageFailed(message):
            return "历史记录存储失败：\(message)"
        }
    }
}

private enum HistoricalRecordIdentity: Hashable, Sendable {
    case raw(Date)
    case aggregate(Date, Int)
}

private protocol HistoricalRecord: Codable, Sendable {
    var historyIdentity: HistoricalRecordIdentity { get }
    var storageTimestamp: Date { get }
}

struct HistoricalMetricAggregate: Codable, Equatable, Sendable {
    var sum: Double
    var count: Int

    private enum CodingKeys: String, CodingKey {
        case sum = "s"
        case count = "n"
    }

    var average: Double? {
        guard count > 0 else { return nil }
        return sum / Double(count)
    }

    mutating func merge(_ other: HistoricalMetricAggregate) {
        sum += other.sum
        count += other.count
    }
}

struct HistoricalRawRecord: Codable, Equatable, Sendable {
    let timestamp: Date
    let source: PowerSourceKind
    let adapterInputPower: Double?
    let batteryDischargePower: Double?
    let batteryChargePower: Double?
    let batteryLevel: Double?
    let batteryDischargeCurrent: Double?
    let batteryChargeCurrent: Double?

    private enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case source = "o"
        case adapterInputPower = "ap"
        case batteryDischargePower = "bd"
        case batteryChargePower = "bc"
        case batteryLevel = "l"
        case batteryDischargeCurrent = "id"
        case batteryChargeCurrent = "ic"
    }

    init?(snapshot: PowerSnapshot) {
        guard snapshot.timestamp.timeIntervalSince1970.isFinite else { return nil }

        timestamp = snapshot.timestamp
        source = snapshot.source
        adapterInputPower = Self.finitePositive(snapshot.adapterRealtimePowerWatts, threshold: 0.05)

        if let flow = snapshot.batteryFlowWatts, flow.isFinite, flow < -0.05 {
            batteryDischargePower = abs(flow)
        } else {
            batteryDischargePower = nil
        }

        if let flow = snapshot.batteryFlowWatts, flow.isFinite, flow > 0.05 {
            batteryChargePower = flow
        } else {
            batteryChargePower = nil
        }

        let level = snapshot.batteryLevel * 100
        batteryLevel = level.isFinite ? level : nil

        if let current = snapshot.amperageMilliamps, current < 0 {
            batteryDischargeCurrent = abs(Double(current)) / 1_000
        } else {
            batteryDischargeCurrent = nil
        }

        if let current = snapshot.amperageMilliamps, current > 0 {
            batteryChargeCurrent = Double(current) / 1_000
        } else {
            batteryChargeCurrent = nil
        }
    }

    private static func finitePositive(_ value: Double?, threshold: Double) -> Double? {
        guard let value, value.isFinite, value > threshold else { return nil }
        return value
    }
}

extension HistoricalRawRecord: HistoricalRecord {
    fileprivate var historyIdentity: HistoricalRecordIdentity { .raw(timestamp) }
    fileprivate var storageTimestamp: Date { timestamp }
}

struct HistoricalAggregateRecord: Codable, Equatable, Sendable {
    let bucketStart: Date
    let resolutionSeconds: Int
    let adapterInputPower: HistoricalMetricAggregate?
    let batteryDischargePower: HistoricalMetricAggregate?
    let batteryChargePower: HistoricalMetricAggregate?
    let batteryLevel: HistoricalMetricAggregate?
    let batteryDischargeCurrent: HistoricalMetricAggregate?
    let batteryChargeCurrent: HistoricalMetricAggregate?

    private enum CodingKeys: String, CodingKey {
        case bucketStart = "t"
        case resolutionSeconds = "r"
        case adapterInputPower = "ap"
        case batteryDischargePower = "bd"
        case batteryChargePower = "bc"
        case batteryLevel = "l"
        case batteryDischargeCurrent = "id"
        case batteryChargeCurrent = "ic"
    }
}

extension HistoricalAggregateRecord: HistoricalRecord {
    fileprivate var historyIdentity: HistoricalRecordIdentity {
        .aggregate(bucketStart, resolutionSeconds)
    }

    fileprivate var storageTimestamp: Date { bucketStart }
}

private struct MutableAggregateBucket: Sendable {
    let bucketStart: Date
    let resolutionSeconds: Int
    var adapterInputPower = HistoricalMetricAggregate(sum: 0, count: 0)
    var batteryDischargePower = HistoricalMetricAggregate(sum: 0, count: 0)
    var batteryChargePower = HistoricalMetricAggregate(sum: 0, count: 0)
    var batteryLevel = HistoricalMetricAggregate(sum: 0, count: 0)
    var batteryDischargeCurrent = HistoricalMetricAggregate(sum: 0, count: 0)
    var batteryChargeCurrent = HistoricalMetricAggregate(sum: 0, count: 0)

    init(timestamp: Date, resolutionSeconds: Int) {
        self.resolutionSeconds = resolutionSeconds
        bucketStart = Self.bucketStart(for: timestamp, resolutionSeconds: resolutionSeconds)
    }

    mutating func add(_ record: HistoricalRawRecord) {
        Self.add(record.adapterInputPower, to: &adapterInputPower)
        Self.add(record.batteryDischargePower, to: &batteryDischargePower)
        Self.add(record.batteryChargePower, to: &batteryChargePower)
        Self.add(record.batteryLevel, to: &batteryLevel)
        Self.add(record.batteryDischargeCurrent, to: &batteryDischargeCurrent)
        Self.add(record.batteryChargeCurrent, to: &batteryChargeCurrent)
    }

    var record: HistoricalAggregateRecord {
        HistoricalAggregateRecord(
            bucketStart: bucketStart,
            resolutionSeconds: resolutionSeconds,
            adapterInputPower: nonEmpty(adapterInputPower),
            batteryDischargePower: nonEmpty(batteryDischargePower),
            batteryChargePower: nonEmpty(batteryChargePower),
            batteryLevel: nonEmpty(batteryLevel),
            batteryDischargeCurrent: nonEmpty(batteryDischargeCurrent),
            batteryChargeCurrent: nonEmpty(batteryChargeCurrent)
        )
    }

    func contains(_ timestamp: Date) -> Bool {
        Self.bucketStart(for: timestamp, resolutionSeconds: resolutionSeconds) == bucketStart
    }

    private static func add(_ value: Double?, to aggregate: inout HistoricalMetricAggregate) {
        guard let value, value.isFinite else { return }
        aggregate.sum += value
        aggregate.count += 1
    }

    private func nonEmpty(_ aggregate: HistoricalMetricAggregate) -> HistoricalMetricAggregate? {
        aggregate.count > 0 ? aggregate : nil
    }

    private static func bucketStart(for timestamp: Date, resolutionSeconds: Int) -> Date {
        let seconds = timestamp.timeIntervalSince1970
        let bucket = floor(seconds / Double(resolutionSeconds)) * Double(resolutionSeconds)
        return Date(timeIntervalSince1970: bucket)
    }
}

private struct HistoryManifest: Codable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    var legacyMigrationComplete: Bool
    var legacyCleanupPending: Bool
}

private enum HistoryTier: Hashable, Sendable {
    case raw
    case minute
    case fiveMinute

    var directoryName: String {
        switch self {
        case .raw: return "raw"
        case .minute: return "minute"
        case .fiveMinute: return "five-minute"
        }
    }

    var retention: TimeInterval {
        switch self {
        case .raw: return 6 * 60 * 60
        case .minute: return 24 * 60 * 60
        case .fiveMinute: return 10 * 24 * 60 * 60
        }
    }
}

actor PowerHistoryEngine {
    private static let minuteResolution = 60
    private static let fiveMinuteResolution = 5 * 60
    private static let flushFailureBackoff: TimeInterval = 30
    private static let maximumPendingRawRecordCount = 30
    private static let maximumPendingAggregateRecordCount = 2

    private let logger = Logger(subsystem: AppConstants.subsystem, category: "history-engine")
    private let directoryURL: URL
    private let legacyFileURL: URL
    private let flushInterval: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var pendingRawRecords: [HistoricalRawRecord] = []
    private var pendingMinuteRecords: [HistoricalAggregateRecord] = []
    private var pendingFiveMinuteRecords: [HistoricalAggregateRecord] = []
    private var activeMinuteBucket: MutableAggregateBucket?
    private var activeFiveMinuteBucket: MutableAggregateBucket?
    private var lastRecordedAt: Date?
    private var lastFlushAt = Date()
    private var nextFlushAttemptAt: Date?
    private var sessionAccumulator: SessionAccumulator?
    private var isPrepared = false
    private var persistentWarnings: [String] = []
    private var uncertainSliceTiers: Set<HistoryTier> = []

    private(set) var loadState: HistoryLoadState = .idle
    private(set) var sessionSummary: SessionSummary?

    init(
        directoryURL: URL = AppPaths.historyDirectoryURL,
        legacyFileURL: URL = AppPaths.legacyHistoryFileURL,
        flushInterval: TimeInterval = 30
    ) {
        self.directoryURL = directoryURL
        self.legacyFileURL = legacyFileURL
        self.flushInterval = max(flushInterval, 0)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    func prepare() throws {
        guard !isPrepared else { return }

        loadState = .loading
        persistentWarnings.removeAll(keepingCapacity: true)
        pendingRawRecords.removeAll(keepingCapacity: true)
        pendingMinuteRecords.removeAll(keepingCapacity: true)
        pendingFiveMinuteRecords.removeAll(keepingCapacity: true)
        activeMinuteBucket = nil
        activeFiveMinuteBucket = nil
        lastRecordedAt = nil

        do {
            let preparationDate = Date()
            try prepareBaseDirectory()
            if let migrationWarning = try prepareStorageAndMigrateIfNeeded() {
                addWarning(migrationWarning)
            }
            try ensureTierDirectories(at: directoryURL)

            let rawCutoff = preparationDate.addingTimeInterval(-HistoryTier.raw.retention)
            let minuteCutoff = preparationDate.addingTimeInterval(-HistoryTier.minute.retention)
            let fiveMinuteCutoff = preparationDate.addingTimeInterval(-HistoryTier.fiveMinute.retention)
            let rawRecords = Self.deduplicated(
                try loadRecords(HistoricalRawRecord.self, tier: .raw)
            ).filter {
                $0.timestamp <= preparationDate
            }.sorted { $0.timestamp < $1.timestamp }
            let minuteRecords = Self.deduplicated(
                try loadRecords(HistoricalAggregateRecord.self, tier: .minute)
            ).filter {
                $0.bucketStart >= minuteCutoff && $0.bucketStart <= preparationDate
            }.sorted { $0.bucketStart < $1.bucketStart }
            let fiveMinuteRecords = Self.deduplicated(
                try loadRecords(HistoricalAggregateRecord.self, tier: .fiveMinute)
            ).filter {
                $0.bucketStart >= fiveMinuteCutoff && $0.bucketStart <= preparationDate
            }.sorted { $0.bucketStart < $1.bucketStart }

            reconcileCompletedAggregates(
                rawRecords: rawRecords,
                minuteRecords: minuteRecords,
                fiveMinuteRecords: fiveMinuteRecords,
                now: preparationDate
            )
            try flushAggregateRecords(tier: .minute)
            try flushAggregateRecords(tier: .fiveMinute)
            try removeExpiredSlices(now: preparationDate, root: directoryURL)
            let activeRawRecords = rawRecords.filter { $0.timestamp >= rawCutoff }
            rebuildActiveBuckets(from: activeRawRecords, now: preparationDate)
            rebuildSession(from: activeRawRecords)
            lastRecordedAt = rawRecords.last?.timestamp
            lastFlushAt = preparationDate
            isPrepared = true
        } catch let error as PowerHistoryEngineError {
            loadState = .failed(error.localizedDescription)
            throw error
        } catch {
            let wrapped = PowerHistoryEngineError.storageFailed(error.localizedDescription)
            loadState = .failed(wrapped.localizedDescription)
            throw wrapped
        }

        updateLoadStateForWarnings()
    }

    @discardableResult
    func record(_ snapshot: PowerSnapshot) throws -> SessionSummary? {
        guard isPrepared else { throw PowerHistoryEngineError.notPrepared }
        guard let rawRecord = HistoricalRawRecord(snapshot: snapshot) else {
            logger.error("Ignored history sample with an invalid timestamp")
            return sessionSummary
        }
        guard lastRecordedAt.map({ rawRecord.timestamp > $0 }) ?? true else {
            logger.notice("Ignored duplicate or out-of-order history sample")
            return sessionSummary
        }

        pendingRawRecords.append(rawRecord)
        advanceAggregate(&activeMinuteBucket, with: rawRecord, resolutionSeconds: Self.minuteResolution)
        advanceAggregate(&activeFiveMinuteBucket, with: rawRecord, resolutionSeconds: Self.fiveMinuteResolution)
        updateSession(with: snapshot)
        lastRecordedAt = rawRecord.timestamp

        let currentTime = Date()
        let backoffHasElapsed = nextFlushAttemptAt.map { currentTime >= $0 } ?? true
        let reachedBufferLimit = pendingRawRecords.count >= Self.maximumPendingRawRecordCount
        let reachedAggregateBufferLimit = pendingMinuteRecords.count >= Self.maximumPendingAggregateRecordCount
            || pendingFiveMinuteRecords.count >= Self.maximumPendingAggregateRecordCount
        if backoffHasElapsed,
           reachedBufferLimit
            || reachedAggregateBufferLimit
            || currentTime.timeIntervalSince(lastFlushAt) >= flushInterval {
            try flush()
        } else if !backoffHasElapsed {
            let droppedCount = boundPendingBuffers()
            if droppedCount > 0 {
                logger.error("Dropped \(droppedCount, privacy: .public) buffered history records during storage backoff")
            }
        }
        return sessionSummary
    }

    func projection(
        metrics: Set<ChartMetric>,
        range: ChartTimeRange,
        now: Date = Date()
    ) async throws -> HistoryProjection {
        guard isPrepared else { throw PowerHistoryEngineError.notPrepared }
        try Task.checkCancellation()

        let lowerBound = now.addingTimeInterval(-range.interval)
        let kinds = metrics.reduce(into: Set<PowerChartSeriesKind>()) { result, metric in
            result.formUnion(Self.seriesKinds(for: metric))
        }
        let bucketWidth = range.interval / Double(range.bucketCount)
        var values: [PowerChartSeriesKind: [HistoricalMetricAggregate]] = [:]
        for kind in kinds {
            values[kind] = Array(
                repeating: HistoricalMetricAggregate(sum: 0, count: 0),
                count: range.bucketCount
            )
        }

        func merge(_ record: HistoricalAggregateRecord) {
            guard record.bucketStart >= lowerBound, record.bucketStart <= now else { return }
            let elapsed = record.bucketStart.timeIntervalSince(lowerBound)
            let index = min(max(Int(elapsed / bucketWidth), 0), range.bucketCount - 1)
            for kind in kinds {
                guard let aggregate = Self.aggregate(in: record, for: kind) else { continue }
                values[kind]?[index].merge(aggregate)
            }
        }

        switch range {
        case .oneHour:
            try await forEachPersistedRecord(
                HistoricalRawRecord.self,
                tier: .raw,
                lowerBound: lowerBound,
                upperBound: now
            ) { record in
                merge(Self.aggregateRecord(from: record))
            }
            for record in pendingRawRecords where record.timestamp >= lowerBound && record.timestamp <= now {
                merge(Self.aggregateRecord(from: record))
            }
        case .twentyFourHours:
            try await forEachPersistedRecord(
                HistoricalAggregateRecord.self,
                tier: .minute,
                lowerBound: lowerBound,
                upperBound: now,
                body: merge
            )
            for record in pendingMinuteRecords {
                merge(record)
            }
            activeRecordIfRelevant(activeMinuteBucket, now: now).forEach(merge)
        case .tenDays:
            try await forEachPersistedRecord(
                HistoricalAggregateRecord.self,
                tier: .fiveMinute,
                lowerBound: lowerBound,
                upperBound: now,
                body: merge
            )
            for record in pendingFiveMinuteRecords {
                merge(record)
            }
            activeRecordIfRelevant(activeFiveMinuteBucket, now: now).forEach(merge)
        }

        try Task.checkCancellation()
        var seriesByMetric: [ChartMetric: [PowerChartSeries]] = [:]
        for metric in metrics {
            seriesByMetric[metric] = buildSeries(
                metric: metric,
                values: values,
                lowerBound: lowerBound,
                range: range
            )
        }

        return HistoryProjection(
            seriesByMetric: seriesByMetric,
            sessionSummary: sessionSummary,
            generatedAt: now
        )
    }

    func flush() throws {
        guard isPrepared else { throw PowerHistoryEngineError.notPrepared }

        do {
            try flushRawRecords()
            try flushAggregateRecords(tier: .minute)
            try flushAggregateRecords(tier: .fiveMinute)
            try removeExpiredSlices(now: lastRecordedAt ?? Date(), root: directoryURL)
            lastFlushAt = Date()
            nextFlushAttemptAt = nil
        } catch {
            nextFlushAttemptAt = Date().addingTimeInterval(Self.flushFailureBackoff)
            let droppedCount = pruneAndBoundPending(now: lastRecordedAt ?? Date())
            if droppedCount > 0 {
                logger.error("Dropped \(droppedCount, privacy: .public) expired buffered history records after a flush failure")
            }
            logger.error("Failed to flush history: \(error.localizedDescription, privacy: .public)")
            throw PowerHistoryEngineError.storageFailed(error.localizedDescription)
        }
    }

    private func advanceAggregate(
        _ bucket: inout MutableAggregateBucket?,
        with record: HistoricalRawRecord,
        resolutionSeconds: Int
    ) {
        if var existing = bucket, existing.contains(record.timestamp) {
            existing.add(record)
            bucket = existing
            return
        }

        if let completed = bucket?.record {
            if resolutionSeconds == Self.minuteResolution {
                pendingMinuteRecords.append(completed)
            } else {
                pendingFiveMinuteRecords.append(completed)
            }
        }

        var replacement = MutableAggregateBucket(
            timestamp: record.timestamp,
            resolutionSeconds: resolutionSeconds
        )
        replacement.add(record)
        bucket = replacement
    }

    private func updateSession(with snapshot: PowerSnapshot) {
        let shouldStartNewSession: Bool
        if let sessionAccumulator {
            shouldStartNewSession = sessionAccumulator.source != snapshot.source
                || snapshot.timestamp.timeIntervalSince(sessionAccumulator.lastTimestamp) > AppConstants.refreshInterval * 3
        } else {
            shouldStartNewSession = true
        }

        if shouldStartNewSession {
            sessionAccumulator = SessionAccumulator(snapshot: snapshot)
        } else {
            sessionAccumulator?.update(with: snapshot)
        }
        sessionSummary = sessionAccumulator?.summary
    }

    private func activeRecordIfRelevant(_ bucket: MutableAggregateBucket?, now: Date) -> [HistoricalAggregateRecord] {
        guard let bucket, bucket.bucketStart <= now else { return [] }
        return [bucket.record]
    }

    private func buildSeries(
        metric: ChartMetric,
        values: [PowerChartSeriesKind: [HistoricalMetricAggregate]],
        lowerBound: Date,
        range: ChartTimeRange
    ) -> [PowerChartSeries] {
        let kinds = Self.seriesKinds(for: metric)
        let bucketWidth = range.interval / Double(range.bucketCount)

        return kinds.map { kind in
            let points = (values[kind] ?? []).enumerated().compactMap { index, aggregate -> PowerChartPoint? in
                guard let average = aggregate.average else { return nil }
                return PowerChartPoint(
                    timestamp: lowerBound.addingTimeInterval((Double(index) + 0.5) * bucketWidth),
                    value: average
                )
            }
            return PowerChartSeries(id: kind, points: points)
        }
    }

    private static func seriesKinds(for metric: ChartMetric) -> [PowerChartSeriesKind] {
        switch metric {
        case .power:
            return [.adapterInputPower, .batteryDischargePower, .batteryChargePower]
        case .batteryLevel:
            return [.batteryLevel]
        case .chargeRate:
            return [.batteryDischargeCurrent, .batteryChargeCurrent]
        }
    }

    private static func aggregate(
        in record: HistoricalAggregateRecord,
        for kind: PowerChartSeriesKind
    ) -> HistoricalMetricAggregate? {
        switch kind {
        case .adapterInputPower: return record.adapterInputPower
        case .batteryDischargePower: return record.batteryDischargePower
        case .batteryChargePower: return record.batteryChargePower
        case .batteryLevel: return record.batteryLevel
        case .batteryDischargeCurrent: return record.batteryDischargeCurrent
        case .batteryChargeCurrent: return record.batteryChargeCurrent
        }
    }

    private static func aggregateRecord(from raw: HistoricalRawRecord) -> HistoricalAggregateRecord {
        func aggregate(_ value: Double?) -> HistoricalMetricAggregate? {
            value.map { HistoricalMetricAggregate(sum: $0, count: 1) }
        }

        return HistoricalAggregateRecord(
            bucketStart: raw.timestamp,
            resolutionSeconds: 1,
            adapterInputPower: aggregate(raw.adapterInputPower),
            batteryDischargePower: aggregate(raw.batteryDischargePower),
            batteryChargePower: aggregate(raw.batteryChargePower),
            batteryLevel: aggregate(raw.batteryLevel),
            batteryDischargeCurrent: aggregate(raw.batteryDischargeCurrent),
            batteryChargeCurrent: aggregate(raw.batteryChargeCurrent)
        )
    }

    private func reconcileCompletedAggregates(
        rawRecords: [HistoricalRawRecord],
        minuteRecords: [HistoricalAggregateRecord],
        fiveMinuteRecords: [HistoricalAggregateRecord],
        now: Date
    ) {
        let minuteCutoff = now.addingTimeInterval(-HistoryTier.minute.retention)
        let fiveMinuteCutoff = now.addingTimeInterval(-HistoryTier.fiveMinute.retention)
        let minuteCandidates = Self.aggregate(
            rawRecords.filter { $0.timestamp >= minuteCutoff && $0.timestamp <= now },
            resolutionSeconds: Self.minuteResolution,
            now: now
        ).filter { $0.bucketStart >= minuteCutoff }
        let fiveMinuteCandidates = Self.aggregate(
            rawRecords.filter { $0.timestamp >= fiveMinuteCutoff && $0.timestamp <= now },
            resolutionSeconds: Self.fiveMinuteResolution,
            now: now
        ).filter { $0.bucketStart >= fiveMinuteCutoff }

        let minuteIdentities = Set(minuteRecords.map(\.historyIdentity))
        let missingMinute = minuteCandidates.filter { !minuteIdentities.contains($0.historyIdentity) }
        if !missingMinute.isEmpty {
            pendingMinuteRecords.append(contentsOf: missingMinute)
        }

        let fiveMinuteIdentities = Set(fiveMinuteRecords.map(\.historyIdentity))
        let missingFiveMinute = fiveMinuteCandidates.filter { !fiveMinuteIdentities.contains($0.historyIdentity) }
        if !missingFiveMinute.isEmpty {
            pendingFiveMinuteRecords.append(contentsOf: missingFiveMinute)
        }
    }

    private func rebuildActiveBuckets(from rawRecords: [HistoricalRawRecord], now: Date) {
        guard let latest = rawRecords.last else { return }

        var minute = MutableAggregateBucket(timestamp: latest.timestamp, resolutionSeconds: Self.minuteResolution)
        var fiveMinute = MutableAggregateBucket(timestamp: latest.timestamp, resolutionSeconds: Self.fiveMinuteResolution)
        for record in rawRecords.reversed() {
            let belongsToMinute = minute.contains(record.timestamp)
            let belongsToFiveMinute = fiveMinute.contains(record.timestamp)
            if !belongsToMinute && !belongsToFiveMinute { break }
            if belongsToMinute { minute.add(record) }
            if belongsToFiveMinute { fiveMinute.add(record) }
        }
        activeMinuteBucket = minute.bucketStart.addingTimeInterval(Double(Self.minuteResolution)) > now
            ? minute
            : nil
        activeFiveMinuteBucket = fiveMinute.bucketStart.addingTimeInterval(Double(Self.fiveMinuteResolution)) > now
            ? fiveMinute
            : nil
    }

    private func rebuildSession(from rawRecords: [HistoricalRawRecord]) {
        guard let latest = rawRecords.last else { return }
        var contiguous: [HistoricalRawRecord] = [latest]
        for record in rawRecords.dropLast().reversed() {
            guard let newer = contiguous.last,
                  record.source == newer.source,
                  newer.timestamp.timeIntervalSince(record.timestamp) <= AppConstants.refreshInterval * 3 else {
                break
            }
            contiguous.append(record)
        }

        guard let earliest = contiguous.last else { return }
        sessionAccumulator = SessionAccumulator(
            source: latest.source,
            startedAt: earliest.timestamp,
            startingBatteryLevel: (earliest.batteryLevel ?? 0) / 100,
            lastTimestamp: latest.timestamp,
            latestBatteryLevel: (latest.batteryLevel ?? 0) / 100,
            latestIsCharging: latest.batteryChargePower != nil
        )
        sessionSummary = sessionAccumulator?.summary
    }

    func memoryDiagnostics() -> HistoryMemoryDiagnostics {
        HistoryMemoryDiagnostics(
            pendingRawRecordCount: pendingRawRecords.count,
            pendingMinuteRecordCount: pendingMinuteRecords.count,
            pendingFiveMinuteRecordCount: pendingFiveMinuteRecords.count,
            hasActiveMinuteBucket: activeMinuteBucket != nil,
            hasActiveFiveMinuteBucket: activeFiveMinuteBucket != nil
        )
    }

    private func prepareBaseDirectory() throws {
        let baseURL = directoryURL.deletingLastPathComponent()
        try createDirectory(baseURL)
    }

    private func prepareStorageAndMigrateIfNeeded() throws -> String? {
        var warnings: [String] = []
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: directoryURL.path),
           !FileManager.default.fileExists(atPath: manifestURL.path) {
            let preservedURL = directoryURL.deletingLastPathComponent().appendingPathComponent(
                "\(directoryURL.lastPathComponent).unrecognized-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.moveItem(at: directoryURL, to: preservedURL)
            warnings.append("历史目录缺少 manifest，异常目录已保留并重新初始化")
            logger.error("Preserved a history directory without a manifest as \(preservedURL.lastPathComponent, privacy: .public)")
        }

        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
                try createEmptyStorage(migrationComplete: true)
                return warnings.isEmpty ? nil : warnings.joined(separator: "；")
            }

            do {
                try migrateLegacyHistory()
            } catch {
                logger.error("Legacy history migration failed: \(error.localizedDescription, privacy: .public)")
                try createEmptyStorage(migrationComplete: false)
                warnings.append(error.localizedDescription)
            }
        }

        let legacyFileExists = FileManager.default.fileExists(atPath: legacyFileURL.path)
        var manifest = try readManifest() ?? HistoryManifest(
            schemaVersion: HistoryManifest.currentSchemaVersion,
            legacyMigrationComplete: !legacyFileExists,
            legacyCleanupPending: false
        )
        if manifest.schemaVersion != HistoryManifest.currentSchemaVersion {
            throw PowerHistoryEngineError.storageFailed("不支持的历史记录 schema：\(manifest.schemaVersion)")
        }

        if manifest.legacyCleanupPending || manifest.legacyMigrationComplete {
            if FileManager.default.fileExists(atPath: legacyFileURL.path) {
                do {
                    try FileManager.default.removeItem(at: legacyFileURL)
                    manifest.legacyCleanupPending = false
                    try writeManifest(manifest, root: directoryURL)
                } catch {
                    logger.error("Could not remove migrated legacy history: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        if !manifest.legacyMigrationComplete {
            warnings.append("旧历史文件未能迁移，原文件已保留")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: "；")
    }

    private func createEmptyStorage(migrationComplete: Bool) throws {
        try createDirectory(directoryURL)
        try ensureTierDirectories(at: directoryURL)
        try writeManifest(
            HistoryManifest(
                schemaVersion: HistoryManifest.currentSchemaVersion,
                legacyMigrationComplete: migrationComplete,
                legacyCleanupPending: false
            ),
            root: directoryURL
        )
    }

    private func migrateLegacyHistory() throws {
        let legacyData = try Data(contentsOf: legacyFileURL)
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        let snapshots = try legacyDecoder.decode([PowerSnapshot].self, from: legacyData)
            .sorted { $0.timestamp < $1.timestamp }

        var uniqueRecords: [HistoricalRawRecord] = []
        uniqueRecords.reserveCapacity(snapshots.count)
        var lastTimestamp: Date?
        for snapshot in snapshots {
            guard snapshot.timestamp.timeIntervalSince1970.isFinite else { continue }
            guard snapshot.timestamp != lastTimestamp else { continue }
            if let record = HistoricalRawRecord(snapshot: snapshot) {
                uniqueRecords.append(record)
                lastTimestamp = snapshot.timestamp
            }
        }

        let now = Date()
        let rawCutoff = now.addingTimeInterval(-HistoryTier.raw.retention)
        let minuteCutoff = now.addingTimeInterval(-HistoryTier.minute.retention)
        let fiveMinuteCutoff = now.addingTimeInterval(-HistoryTier.fiveMinute.retention)
        let raw = uniqueRecords.filter { $0.timestamp >= rawCutoff && $0.timestamp <= now }
        let minute = Self.aggregate(
            uniqueRecords.filter { $0.timestamp >= minuteCutoff && $0.timestamp <= now },
            resolutionSeconds: Self.minuteResolution,
            now: now
        )
        let fiveMinute = Self.aggregate(
            uniqueRecords.filter { $0.timestamp >= fiveMinuteCutoff && $0.timestamp <= now },
            resolutionSeconds: Self.fiveMinuteResolution,
            now: now
        )

        let temporaryURL = directoryURL.deletingLastPathComponent()
            .appendingPathComponent("power-history.importing-\(UUID().uuidString)", isDirectory: true)
        do {
            try createDirectory(temporaryURL)
            try ensureTierDirectories(at: temporaryURL)
            try append(raw, tier: .raw, root: temporaryURL)
            try append(minute, tier: .minute, root: temporaryURL)
            try append(fiveMinute, tier: .fiveMinute, root: temporaryURL)
            try writeManifest(
                HistoryManifest(
                    schemaVersion: HistoryManifest.currentSchemaVersion,
                    legacyMigrationComplete: true,
                    legacyCleanupPending: false
                ),
                root: temporaryURL
            )
            try verifyMigratedStorage(
                root: temporaryURL,
                expectedRaw: raw.count,
                expectedMinute: minute.count,
                expectedFiveMinute: fiveMinute.count
            )
            try FileManager.default.moveItem(at: temporaryURL, to: directoryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }

        do {
            try FileManager.default.removeItem(at: legacyFileURL)
        } catch {
            var manifest = try readManifest() ?? HistoryManifest(
                schemaVersion: HistoryManifest.currentSchemaVersion,
                legacyMigrationComplete: true,
                legacyCleanupPending: true
            )
            manifest.legacyCleanupPending = true
            try writeManifest(manifest, root: directoryURL)
        }
    }

    private static func aggregate(
        _ records: [HistoricalRawRecord],
        resolutionSeconds: Int,
        now: Date
    ) -> [HistoricalAggregateRecord] {
        var result: [HistoricalAggregateRecord] = []
        var active: MutableAggregateBucket?

        for record in records {
            if var existing = active, existing.contains(record.timestamp) {
                existing.add(record)
                active = existing
            } else {
                if let completed = active?.record,
                   completed.bucketStart.addingTimeInterval(Double(resolutionSeconds)) <= now {
                    result.append(completed)
                }
                var replacement = MutableAggregateBucket(
                    timestamp: record.timestamp,
                    resolutionSeconds: resolutionSeconds
                )
                replacement.add(record)
                active = replacement
            }
        }

        if let completed = active?.record,
           completed.bucketStart.addingTimeInterval(Double(resolutionSeconds)) <= now {
            result.append(completed)
        }
        return result
    }

    private static func deduplicated<T: HistoricalRecord>(_ records: [T]) -> [T] {
        var identities: Set<HistoricalRecordIdentity> = []
        return records.filter { identities.insert($0.historyIdentity).inserted }
    }

    private func flushRawRecords() throws {
        while !pendingRawRecords.isEmpty {
            pendingRawRecords = try flushingFirstSlice(of: pendingRawRecords, tier: .raw)
        }
    }

    private func flushAggregateRecords(tier: HistoryTier) throws {
        switch tier {
        case .minute:
            while !pendingMinuteRecords.isEmpty {
                pendingMinuteRecords = try flushingFirstSlice(of: pendingMinuteRecords, tier: tier)
            }
        case .fiveMinute:
            while !pendingFiveMinuteRecords.isEmpty {
                pendingFiveMinuteRecords = try flushingFirstSlice(of: pendingFiveMinuteRecords, tier: tier)
            }
        case .raw:
            break
        }
    }

    private func flushingFirstSlice<T: HistoricalRecord>(of records: [T], tier: HistoryTier) throws -> [T] {
        guard let first = records.first else { return [] }
        let targetURL = try fileURL(for: first, tier: tier, root: directoryURL)
        let sliceRecords = records.filter {
            (try? fileURL(for: $0, tier: tier, root: directoryURL)) == targetURL
        }
        try appendLines(sliceRecords, to: targetURL, tier: tier)
        return records.filter {
            (try? fileURL(for: $0, tier: tier, root: directoryURL)) != targetURL
        }
    }

    private func append<T: HistoricalRecord>(_ records: [T], tier: HistoryTier, root: URL) throws {
        let groups = try Dictionary(grouping: records) { record in
            try fileURL(for: record, tier: tier, root: root)
        }
        for (url, values) in groups {
            try appendLines(values, to: url, tier: tier)
        }
    }

    private func appendLines<T: HistoricalRecord>(_ records: [T], to url: URL, tier: HistoryTier) throws {
        guard !records.isEmpty else { return }
        do {
            let fileManager = FileManager.default
            var recordsToAppend = Self.deduplicated(records)
            if uncertainSliceTiers.contains(tier), fileManager.fileExists(atPath: url.path) {
                let existing = try recoverAndDecode(T.self, from: url)
                let knownIdentities = Set(existing.map(\.historyIdentity))
                recordsToAppend.removeAll { knownIdentities.contains($0.historyIdentity) }
            }

            if recordsToAppend.isEmpty {
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                return
            }

            var data = Data()
            for record in recordsToAppend {
                data.append(try encoder.encode(record))
                data.append(0x0A)
            }

            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(
                    atPath: url.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Keep this tier in conservative de-duplication mode until restart.
            // The set is bounded to the three storage tiers.
            uncertainSliceTiers.insert(tier)
            throw error
        }
    }

    private func loadRecords<T: HistoricalRecord>(_ type: T.Type, tier: HistoryTier) throws -> [T] {
        let tierURL = directoryURL.appendingPathComponent(tier.directoryName, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: tierURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var result: [T] = []
        for url in files.filter({ $0.pathExtension == "jsonl" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            result.append(contentsOf: try recoverAndDecode(type, from: url))
        }
        return result
    }

    private func forEachPersistedRecord<T: HistoricalRecord>(
        _ type: T.Type,
        tier: HistoryTier,
        lowerBound: Date,
        upperBound: Date,
        body: (T) throws -> Void
    ) async throws {
        let tierURL = directoryURL.appendingPathComponent(tier.directoryName, isDirectory: true)
        let lowerSlice = Self.sliceName(for: lowerBound, tier: tier) + ".jsonl"
        let upperSlice = Self.sliceName(for: upperBound, tier: tier) + ".jsonl"
        let files = try FileManager.default.contentsOfDirectory(
            at: tierURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter {
            $0.pathExtension == "jsonl"
                && $0.lastPathComponent >= lowerSlice
                && $0.lastPathComponent <= upperSlice
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var seen = Set<HistoricalRecordIdentity>()
        for url in files {
            try Task.checkCancellation()
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            for try await line in handle.bytes.lines {
                try Task.checkCancellation()
                guard !line.isEmpty else { continue }
                let record = try decoder.decode(type, from: Data(line.utf8))
                guard seen.insert(record.historyIdentity).inserted,
                      record.storageTimestamp >= lowerBound,
                      record.storageTimestamp <= upperBound else {
                    continue
                }
                try body(record)
            }
        }
    }

    private func recoverAndDecode<T: HistoricalRecord>(_ type: T.Type, from url: URL) throws -> [T] {
        var data = try Data(contentsOf: url)
        if !data.isEmpty, data.last != 0x0A {
            let validLength = data.lastIndex(of: 0x0A).map { data.distance(from: data.startIndex, to: $0) + 1 } ?? 0
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(validLength))
            try handle.close()
            data = Data(data.prefix(validLength))
            logger.warning("Trimmed an incomplete history line from \(url.lastPathComponent, privacy: .public)")
            addWarning("检测到未完整写入的历史记录，已恢复可用部分")
        }

        var decoded: [T] = []
        var hasMalformedInteriorLine = false
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            do {
                decoded.append(try decoder.decode(type, from: Data(line)))
            } catch {
                hasMalformedInteriorLine = true
                logger.error("Isolated a malformed record in \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if hasMalformedInteriorLine {
            try quarantineAndRewrite(url: url, validRecords: decoded)
            addWarning("检测到损坏的历史记录，原文件已备份并隔离坏行")
        }
        return decoded
    }

    private func quarantineAndRewrite<T: HistoricalRecord>(url: URL, validRecords: [T]) throws {
        let fileManager = FileManager.default
        let suffix = UUID().uuidString
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).repair-\(suffix)"
        )
        let backupName = "\(url.lastPathComponent).corrupt-\(suffix)"
        var repairedData = Data()
        for record in validRecords {
            repairedData.append(try encoder.encode(record))
            repairedData.append(0x0A)
        }

        do {
            try repairedData.write(to: temporaryURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            _ = try fileManager.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: backupName,
                options: [.withoutDeletingBackupItem]
            )
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let backupURL = url.deletingLastPathComponent().appendingPathComponent(backupName)
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            logger.error("Could not rewrite repaired history file: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func verifyMigratedStorage(
        root: URL,
        expectedRaw: Int,
        expectedMinute: Int,
        expectedFiveMinute: Int
    ) throws {
        let rawCount = try strictRecordCount(HistoricalRawRecord.self, tier: .raw, root: root)
        let minuteCount = try strictRecordCount(HistoricalAggregateRecord.self, tier: .minute, root: root)
        let fiveMinuteCount = try strictRecordCount(HistoricalAggregateRecord.self, tier: .fiveMinute, root: root)
        guard rawCount == expectedRaw,
              minuteCount == expectedMinute,
              fiveMinuteCount == expectedFiveMinute else {
            throw PowerHistoryEngineError.migrationFailed("迁移结果验证不一致")
        }
    }

    private func strictRecordCount<T: HistoricalRecord>(_ type: T.Type, tier: HistoryTier, root: URL) throws -> Int {
        let tierURL = root.appendingPathComponent(tier.directoryName, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: tierURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        var count = 0
        for file in files {
            let data = try Data(contentsOf: file)
            guard data.isEmpty || data.last == 0x0A else {
                throw PowerHistoryEngineError.migrationFailed("迁移文件末尾不完整")
            }
            for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                _ = try decoder.decode(type, from: Data(line))
                count += 1
            }
        }
        return count
    }

    private func fileURL<T: HistoricalRecord>(for record: T, tier: HistoryTier, root: URL) throws -> URL {
        let filename = Self.sliceName(for: record.storageTimestamp, tier: tier) + ".jsonl"
        return root.appendingPathComponent(tier.directoryName, isDirectory: true)
            .appendingPathComponent(filename)
    }

    private static func sliceName(for date: Date, tier: HistoryTier) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        switch tier {
        case .raw, .minute:
            return day + String(format: "T%02d", components.hour ?? 0)
        case .fiveMinute:
            return day
        }
    }

    private func removeExpiredSlices(now: Date, root: URL) throws {
        for tier in [HistoryTier.raw, .minute, .fiveMinute] {
            let directory = root.appendingPathComponent(tier.directoryName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            let boundaryName = Self.sliceName(for: now.addingTimeInterval(-tier.retention), tier: tier) + ".jsonl"
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in urls where url.pathExtension == "jsonl" && url.lastPathComponent < boundaryName {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func pruneAndBoundPending(now: Date) -> Int {
        let beforeCount = pendingRawRecords.count
            + pendingMinuteRecords.count
            + pendingFiveMinuteRecords.count
        let rawCutoff = now.addingTimeInterval(-HistoryTier.raw.retention)
        let minuteCutoff = now.addingTimeInterval(-HistoryTier.minute.retention)
        let fiveMinuteCutoff = now.addingTimeInterval(-HistoryTier.fiveMinute.retention)
        pendingRawRecords.removeAll { $0.timestamp < rawCutoff }
        pendingMinuteRecords.removeAll { $0.bucketStart < minuteCutoff }
        pendingFiveMinuteRecords.removeAll { $0.bucketStart < fiveMinuteCutoff }

        _ = boundPendingBuffers()

        let afterCount = pendingRawRecords.count
            + pendingMinuteRecords.count
            + pendingFiveMinuteRecords.count
        return beforeCount - afterCount
    }

    private func boundPendingBuffers() -> Int {
        var droppedCount = 0
        if pendingRawRecords.count > Self.maximumPendingRawRecordCount {
            let overflow = pendingRawRecords.count - Self.maximumPendingRawRecordCount
            pendingRawRecords.removeFirst(overflow)
            droppedCount += overflow
        }
        if pendingMinuteRecords.count > Self.maximumPendingAggregateRecordCount {
            let overflow = pendingMinuteRecords.count - Self.maximumPendingAggregateRecordCount
            pendingMinuteRecords.removeFirst(overflow)
            droppedCount += overflow
        }
        if pendingFiveMinuteRecords.count > Self.maximumPendingAggregateRecordCount {
            let overflow = pendingFiveMinuteRecords.count - Self.maximumPendingAggregateRecordCount
            pendingFiveMinuteRecords.removeFirst(overflow)
            droppedCount += overflow
        }
        return droppedCount
    }

    private func addWarning(_ warning: String) {
        guard !warning.isEmpty, !persistentWarnings.contains(warning) else { return }
        persistentWarnings.append(warning)
        if isPrepared {
            updateLoadStateForWarnings()
        }
    }

    private func updateLoadStateForWarnings() {
        if persistentWarnings.isEmpty {
            loadState = .ready
        } else {
            loadState = .failed(persistentWarnings.joined(separator: "；"))
        }
    }

    private func ensureTierDirectories(at root: URL) throws {
        for tier in [HistoryTier.raw, .minute, .fiveMinute] {
            try createDirectory(root.appendingPathComponent(tier.directoryName, isDirectory: true))
        }
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func readManifest() throws -> HistoryManifest? {
        let url = directoryURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(HistoryManifest.self, from: Data(contentsOf: url))
    }

    private func writeManifest(_ manifest: HistoryManifest, root: URL) throws {
        let url = root.appendingPathComponent("manifest.json")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private struct SessionAccumulator: Sendable {
    let source: PowerSourceKind
    let startedAt: Date
    let startingBatteryLevel: Double
    var lastTimestamp: Date
    var latestBatteryLevel: Double
    var latestIsCharging: Bool

    init(
        source: PowerSourceKind,
        startedAt: Date,
        startingBatteryLevel: Double,
        lastTimestamp: Date,
        latestBatteryLevel: Double,
        latestIsCharging: Bool
    ) {
        self.source = source
        self.startedAt = startedAt
        self.startingBatteryLevel = startingBatteryLevel
        self.lastTimestamp = lastTimestamp
        self.latestBatteryLevel = latestBatteryLevel
        self.latestIsCharging = latestIsCharging
    }

    init(snapshot: PowerSnapshot) {
        source = snapshot.source
        startedAt = snapshot.timestamp
        startingBatteryLevel = snapshot.batteryLevel
        lastTimestamp = snapshot.timestamp
        latestBatteryLevel = snapshot.batteryLevel
        latestIsCharging = snapshot.isCharging
    }

    mutating func update(with snapshot: PowerSnapshot) {
        lastTimestamp = snapshot.timestamp
        latestBatteryLevel = snapshot.batteryLevel
        latestIsCharging = snapshot.isCharging
    }

    var summary: SessionSummary {
        let title: String
        switch source {
        case .battery:
            title = "自断开电源起"
        case .acPower where latestIsCharging:
            title = "自接通电源起"
        case .acPower:
            title = "当前外接电源会话"
        case .unknown:
            title = "当前采样会话"
        }

        return SessionSummary(
            title: title,
            startedAt: startedAt,
            elapsed: max(lastTimestamp.timeIntervalSince(startedAt), 0),
            batteryPercentDelta: (latestBatteryLevel - startingBatteryLevel) * 100,
            capacityDeltaMah: nil
        )
    }
}
