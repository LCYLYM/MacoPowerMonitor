import Foundation
import OSLog

@MainActor
final class PowerMonitorStore: ObservableObject {
    @Published private(set) var latestSnapshot: PowerSnapshot?
    @Published private(set) var history: [PowerSnapshot]
    @Published private(set) var lastErrorMessage: String?

    private let collector: PowerSnapshotCollecting
    private let historyStore: PowerHistoryStore
    private let scheduler: RepeatingTaskScheduler
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "store")

    private static let maxHistoryAge: TimeInterval = 60 * 60 * 24
    private static let maxHistoryCount = 2_880

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

    func chartPoints(for metric: ChartMetric, window: TimeInterval = 60 * 60) -> [Double] {
        let lowerBound = Date().addingTimeInterval(-window)
        let samples = history.filter { $0.timestamp >= lowerBound }

        switch metric {
        case .power:
            return samples.compactMap(\.preferredPowerWatts)
        case .batteryLevel:
            return samples.map { $0.batteryLevel * 100.0 }
        }
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
        let deltaMah: Int?

        if let latestCapacity = latestSnapshot.currentCapacityMah,
           let earliestCapacity = earliest.currentCapacityMah {
            deltaMah = latestCapacity - earliestCapacity
        } else {
            deltaMah = nil
        }

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
            capacityDeltaMah: deltaMah
        )
    }

    private func refresh() async {
        do {
            let collector = self.collector
            let snapshot = try await Task.detached(priority: .utility) {
                try collector.readSnapshot()
            }.value

            apply(snapshot)
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
