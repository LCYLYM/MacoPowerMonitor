import Foundation
import OSLog

@MainActor
final class PowerMonitorStore: ObservableObject {
    @Published private(set) var latestSnapshot: PowerSnapshot?
    @Published private(set) var history: [PowerSnapshot]
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var topProcesses: [ProcessEnergyStat] = []

    private let collector: PowerSnapshotCollecting
    private let historyStore: PowerHistoryStore
    private let scheduler: RepeatingTaskScheduler
    private let processStatsProvider = ProcessEnergyStatsProvider.shared
    private let subsystemPowerProvider = PowermetricsSubsystemPowerProvider.shared
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "store")

    private static let maxHistoryAge: TimeInterval = 60 * 60 * 24 * 10
    private static let maxHistoryCount = 30_000

    static let shared = PowerMonitorStore.live()

    static func live() -> PowerMonitorStore {
        PowerMonitorStore(
            collector: SystemPowerSnapshotCollector(),
            historyStore: PowerHistoryStore(),
            scheduler: RepeatingTaskScheduler(
                interval: AppConstants.refreshInterval,
                tolerance: AppConstants.refreshTolerance
            )
        )
    }

    init(
        collector: PowerSnapshotCollecting,
        historyStore: PowerHistoryStore,
        scheduler: RepeatingTaskScheduler
    ) {
        self.collector = collector
        self.historyStore = historyStore
        self.scheduler = scheduler
        self.history = historyStore.load().sorted { $0.timestamp < $1.timestamp }
        self.latestSnapshot = self.history.last

        scheduler.start { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }

        Task {
            await refresh()
        }
    }

    deinit {
        scheduler.stop()
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func requestPrivilegedSubsystemSample() {
        Task {
            do {
                let provider = subsystemPowerProvider
                _ = try await Task.detached(priority: .userInitiated) {
                    try provider.refreshInteractively()
                }.value
                await refresh()
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func chartSeries(for metric: ChartMetric, range: ChartTimeRange) -> [PowerChartSeries] {
        let buckets = chartBuckets(for: range)
        guard !buckets.isEmpty else {
            return []
        }

        switch metric {
        case .power:
            return [
                buildSeries(kind: .systemInputPower, buckets: buckets) { bucket in
                    average(bucket.compactMap(\.systemPowerWatts).filter { $0 > 0.05 })
                },
                buildSeries(kind: .batteryDischargePower, buckets: buckets) { bucket in
                    average(bucket.compactMap(\.batteryFlowWatts).filter { $0 < -0.05 }.map(abs))
                },
                buildSeries(kind: .batteryChargePower, buckets: buckets) { bucket in
                    average(bucket.compactMap(\.batteryFlowWatts).filter { $0 > 0.05 })
                },
            ]
        case .batteryLevel:
            return [
                buildSeries(kind: .batteryLevel, buckets: buckets) { bucket in
                    average(bucket.map { $0.batteryLevel * 100.0 })
                },
            ]
        case .chargeRate:
            return [
                buildSeries(kind: .batteryDischargeCurrent, buckets: buckets) { bucket in
                    average(bucket.compactMap(\.amperageMilliamps).filter { $0 < 0 }.map { abs(Double($0)) / 1_000.0 })
                },
                buildSeries(kind: .batteryChargeCurrent, buckets: buckets) { bucket in
                    average(bucket.compactMap(\.amperageMilliamps).filter { $0 > 0 }.map { Double($0) / 1_000.0 })
                },
            ]
        }
    }

    private func chartBuckets(for range: ChartTimeRange) -> [(timestamp: Date, snapshots: [PowerSnapshot])] {
        let lowerBound = Date().addingTimeInterval(-range.interval)
        let samples = history.filter { $0.timestamp >= lowerBound }

        guard !samples.isEmpty else {
            return []
        }

        let bucketWidth = range.interval / Double(range.bucketCount)
        var buckets: [[PowerSnapshot]] = Array(repeating: [], count: range.bucketCount)

        for sample in samples {
            let elapsed = sample.timestamp.timeIntervalSince(lowerBound)
            let index = min(max(Int(elapsed / bucketWidth), 0), range.bucketCount - 1)
            buckets[index].append(sample)
        }

        return buckets.enumerated().compactMap { index, bucket in
            guard !bucket.isEmpty else { return nil }

            let timestamp = lowerBound.addingTimeInterval((Double(index) + 0.5) * bucketWidth)
            return (
                timestamp: timestamp,
                snapshots: bucket
            )
        }
    }

    private func buildSeries(
        kind: PowerChartSeriesKind,
        buckets: [(timestamp: Date, snapshots: [PowerSnapshot])],
        valueForBucket: ([PowerSnapshot]) -> Double?
    ) -> PowerChartSeries {
        let points = buckets.compactMap { bucket -> PowerChartPoint? in
            guard let value = valueForBucket(bucket.snapshots) else {
                return nil
            }

            return PowerChartPoint(timestamp: bucket.timestamp, value: value)
        }

        return PowerChartSeries(id: kind, points: points)
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }

    func recentSnapshots(limit: Int) -> [PowerSnapshot] {
        Array(history.suffix(limit))
    }

    var lastUpdatedText: String {
        guard let latestSnapshot else {
            return "尚未完成首次采样"
        }

        return PowerFormatting.relativeUpdateTime(from: latestSnapshot.timestamp)
    }

    var sessionSummary: SessionSummary? {
        guard let latestSnapshot else {
            return nil
        }

        let contiguousSession = history.reversed().reduce(into: [PowerSnapshot]()) { partialResult, snapshot in
            if partialResult.isEmpty {
                partialResult.append(snapshot)
                return
            }

            guard let last = partialResult.last else {
                return
            }

            let sameSource = snapshot.source == last.source
            let gapIsSmall = last.timestamp.timeIntervalSince(snapshot.timestamp) <= AppConstants.refreshInterval * 3

            if sameSource && gapIsSmall {
                partialResult.append(snapshot)
            }
        }

        guard let earliest = contiguousSession.last else {
            return nil
        }

        let deltaPercent = (latestSnapshot.batteryLevel - earliest.batteryLevel) * 100.0
        let title: String
        switch latestSnapshot.source {
        case .battery:
            title = "自断开电源起"
        case .acPower where latestSnapshot.isCharging:
            title = "自接通电源起"
        case .acPower:
            title = "当前外接电源会话"
        case .unknown:
            title = "当前采样会话"
        }

        return SessionSummary(
            title: title,
            startedAt: earliest.timestamp,
            elapsed: latestSnapshot.timestamp.timeIntervalSince(earliest.timestamp),
            batteryPercentDelta: deltaPercent,
            capacityDeltaMah: nil
        )
    }

    private func refresh() async {
        do {
            let collector = self.collector
            async let snapshotTask: PowerSnapshot = Task.detached(priority: .utility) {
                try collector.readSnapshot()
            }.value
            async let processStatsTask: [ProcessEnergyStat] = Task.detached(priority: .utility) { [processStatsProvider] in
                processStatsProvider.currentStats()
            }.value

            let snapshot = try await snapshotTask
            let processStats = await processStatsTask

            apply(snapshot)
            topProcesses = processStats
        } catch {
            lastErrorMessage = error.localizedDescription
            logger.error("Power refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ snapshot: PowerSnapshot) {
        lastErrorMessage = nil
        latestSnapshot = snapshot
        history = prunedHistory(afterAppending: snapshot)

        let historyToPersist = history
        historyStore.save(historyToPersist)
    }

    private func prunedHistory(afterAppending snapshot: PowerSnapshot) -> [PowerSnapshot] {
        let merged = (history + [snapshot]).sorted { $0.timestamp < $1.timestamp }
        let lowerBound = snapshot.timestamp.addingTimeInterval(-Self.maxHistoryAge)
        let ageFiltered = merged.filter { $0.timestamp >= lowerBound }

        if ageFiltered.count > Self.maxHistoryCount {
            return Array(ageFiltered.suffix(Self.maxHistoryCount))
        }

        return ageFiltered
    }
}
