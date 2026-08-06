import Foundation
import OSLog

@MainActor
final class PowerMonitorStore: ObservableObject {
    @Published private(set) var latestSnapshot: PowerSnapshot?
    @Published private(set) var historyLoadState: HistoryLoadState = .idle
    @Published private(set) var chartSeriesByMetric: [ChartMetric: [PowerChartSeries]] = [:]
    @Published private(set) var sessionSummary: SessionSummary?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var topProcesses: [ProcessEnergyStat] = []
    @Published private(set) var lastPanelRefreshDurationMilliseconds: Double?

    private let collector: PowerSnapshotCollecting
    private let historyEngine: PowerHistoryEngine
    private let scheduler: RepeatingTaskScheduler
    private let processStatsProvider: any ProcessEnergyStatsProviding
    private let subsystemPowerProvider = PowermetricsSubsystemPowerProvider.shared
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "store")
    private let panelSignposter = OSSignposter(subsystem: AppConstants.subsystem, category: "panel-refresh")
    private var historyMetrics = Set(ChartMetric.allCases)
    private var historyRange = ChartTimeRange.twentyFourHours
    private var isHistoryPresentationActive = false
    private var isHistoryReady = false
    private var isRefreshing = false
    private var isShuttingDown = false
    private var samplingErrorMessage: String?
    private var historyPreparationErrorMessage: String?
    private var historyOperationErrorMessage: String?
    private var droppedHistorySampleCount = 0
    private var historyContinuation: AsyncStream<PowerSnapshot>.Continuation?
    private var historyConsumerTask: Task<Void, Never>?
    private var projectionTask: Task<Void, Never>?
    private var panelRefreshTask: Task<Void, Never>?
    private var panelRefreshGeneration = 0
    private var projectionTaskGeneration = 0
    private var projectionIsDirty = false

    private static let historyFlushInterval: TimeInterval = 30
    private static let historyQueueCapacity = 120
    private static let panelDataBudgetMilliseconds = 350.0
    private static let panelRefreshDeadlineMilliseconds = 400.0

    static let shared = PowerMonitorStore.live()

    static func live() -> PowerMonitorStore {
        return PowerMonitorStore(
            collector: SystemPowerSnapshotCollector(),
            historyEngine: PowerHistoryEngine(
                directoryURL: AppPaths.historyDirectoryURL,
                legacyFileURL: AppPaths.legacyHistoryFileURL,
                flushInterval: historyFlushInterval
            ),
            scheduler: RepeatingTaskScheduler(
                interval: AppConstants.refreshInterval,
                tolerance: AppConstants.refreshTolerance
            ),
            processStatsProvider: ProcessEnergyStatsProvider.shared
        )
    }

    init(
        collector: PowerSnapshotCollecting,
        historyEngine: PowerHistoryEngine,
        scheduler: RepeatingTaskScheduler,
        processStatsProvider: any ProcessEnergyStatsProviding = ProcessEnergyStatsProvider.shared,
        startsScheduler: Bool = true
    ) {
        self.collector = collector
        self.historyEngine = historyEngine
        self.scheduler = scheduler
        self.processStatsProvider = processStatsProvider

        let (historyStream, continuation) = AsyncStream<PowerSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.historyQueueCapacity)
        )
        historyContinuation = continuation
        historyConsumerTask = Task { [weak self] in
            await self?.consumeHistory(from: historyStream)
        }

        collector.prewarmSlowMetrics()

        if startsScheduler {
            scheduler.start { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
        }

    }

    deinit {
        scheduler.stop()
        historyContinuation?.finish()
        historyConsumerTask?.cancel()
        projectionTask?.cancel()
        panelRefreshTask?.cancel()
    }

    func refreshNow() {
        if isHistoryPresentationActive {
            beginPanelPresentation(openedAt: ContinuousClock.now)
            return
        }

        Task { [weak self] in
            await self?.refresh()
        }
    }

    func requestPrivilegedSubsystemSample() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let provider = subsystemPowerProvider
                _ = try await Task.detached(priority: .userInitiated) {
                    try provider.refreshInteractively()
                }.value
                await refresh()
            } catch {
                samplingErrorMessage = error.localizedDescription
                updateDisplayedError()
            }
        }
    }

    func updateHistorySelection(metrics: Set<ChartMetric>, range: ChartTimeRange) {
        guard metrics != historyMetrics || range != historyRange else {
            return
        }

        historyMetrics = metrics
        historyRange = range
        requestHistoryProjection()
    }

    func beginPanelPresentation(openedAt: ContinuousClock.Instant) {
        guard !isShuttingDown else { return }

        isHistoryPresentationActive = true
        lastPanelRefreshDurationMilliseconds = nil
        panelRefreshGeneration += 1
        let generation = panelRefreshGeneration
        panelRefreshTask?.cancel()
        projectionTaskGeneration += 1
        projectionTask?.cancel()
        projectionTask = nil
        projectionIsDirty = false

        panelRefreshTask = Task { [weak self] in
            await self?.refreshPanelData(openedAt: openedAt, generation: generation)
        }
    }

    func endPanelPresentation() {
        isHistoryPresentationActive = false
        panelRefreshGeneration += 1
        panelRefreshTask?.cancel()
        panelRefreshTask = nil
        projectionTaskGeneration += 1
        projectionTask?.cancel()
        projectionTask = nil
        projectionIsDirty = false
        chartSeriesByMetric = [:]
        topProcesses = []
    }

    func shutdown() async {
        guard !isShuttingDown else {
            if let historyConsumerTask {
                await historyConsumerTask.value
            }
            return
        }

        isShuttingDown = true
        scheduler.stop()
        endPanelPresentation()
        historyContinuation?.finish()
        historyContinuation = nil

        if let historyConsumerTask {
            await historyConsumerTask.value
            self.historyConsumerTask = nil
        }

        do {
            try await historyEngine.flush()
        } catch {
            historyOperationErrorMessage = error.localizedDescription
            updateDisplayedError()
            logger.error("Final history flush failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var lastUpdatedText: String {
        guard let latestSnapshot else {
            return "尚未完成首次采样"
        }

        return PowerFormatting.relativeUpdateTime(from: latestSnapshot.timestamp)
    }

    var selectedHistoryMetrics: Set<ChartMetric> { historyMetrics }
    var selectedHistoryRange: ChartTimeRange { historyRange }

    private func refresh() async {
        guard !isRefreshing, !isShuttingDown else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let collector = self.collector
            collector.prewarmSlowMetrics()
            let snapshot = try await Task.detached(priority: .utility) {
                try collector.readSnapshot()
            }.value

            apply(snapshot)
        } catch {
            samplingErrorMessage = error.localizedDescription
            updateDisplayedError()
            logger.error("Power refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ snapshot: PowerSnapshot) {
        if let latestSnapshot, snapshot.timestamp <= latestSnapshot.timestamp {
            logger.warning("Ignored an out-of-order live snapshot")
            return
        }

        samplingErrorMessage = nil
        latestSnapshot = snapshot
        updateDisplayedError()
        enqueueHistory(snapshot)
    }

    private func refreshPanelData(openedAt: ContinuousClock.Instant, generation: Int) async {
        let signpostID = panelSignposter.makeSignpostID()
        let signpostState = panelSignposter.beginInterval("PanelRefresh", id: signpostID)
        defer {
            panelSignposter.endInterval("PanelRefresh", signpostState)
            if generation == panelRefreshGeneration {
                panelRefreshTask = nil
                if projectionIsDirty {
                    requestHistoryProjection()
                }
            }
        }

        let collector = self.collector
        let processStatsProvider = self.processStatsProvider
        let historyEngine = self.historyEngine
        let metrics = historyMetrics
        let range = historyRange
        let projectionNow = Date()
        let expectedResultCount = 3
        let dataBudgetDeadline = openedAt.advanced(by: .milliseconds(350))
        let refreshDeadline = openedAt.advanced(by: .milliseconds(400))
        let clock = ContinuousClock()
        let stageSignposter = panelSignposter
        var completedResultCount = 0
        var exceededDataBudget = false
        var missedDeadline = false
        var dataCompletionMilliseconds: Double?
        collector.prewarmSlowMetrics()

        await withTaskGroup(of: PanelRefreshEvent.self) { group in
            group.addTask(priority: .userInitiated) {
                let startedAt = clock.now
                let state = stageSignposter.beginInterval("PanelSnapshot")
                defer { stageSignposter.endInterval("PanelSnapshot", state) }
                do {
                    return .snapshot(
                        .success(try collector.readSnapshot()),
                        startedAt.duration(to: clock.now)
                    )
                } catch {
                    return .snapshot(
                        .failure(error.localizedDescription),
                        startedAt.duration(to: clock.now)
                    )
                }
            }
            group.addTask(priority: .userInitiated) {
                let startedAt = clock.now
                let state = stageSignposter.beginInterval("PanelProcesses")
                defer { stageSignposter.endInterval("PanelProcesses", state) }
                return .processes(
                    processStatsProvider.currentStats(limit: 6, forceRefresh: true),
                    startedAt.duration(to: clock.now)
                )
            }
            group.addTask(priority: .userInitiated) {
                let startedAt = clock.now
                let state = stageSignposter.beginInterval("PanelHistory")
                defer { stageSignposter.endInterval("PanelHistory", state) }
                do {
                    try await historyEngine.prepare()
                    return .history(
                        .success(try await historyEngine.projection(
                            metrics: metrics,
                            range: range,
                            now: projectionNow
                        )),
                        startedAt.duration(to: clock.now)
                    )
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return .history(
                        .failure(error.localizedDescription),
                        startedAt.duration(to: clock.now)
                    )
                }
            }
            group.addTask {
                do {
                    try await ContinuousClock().sleep(until: dataBudgetDeadline)
                    return .dataBudgetExpired
                } catch {
                    return .cancelled
                }
            }
            group.addTask {
                do {
                    try await ContinuousClock().sleep(until: refreshDeadline)
                    return .refreshDeadlineExpired
                } catch {
                    return .cancelled
                }
            }

            while let event = await group.next() {
                guard !Task.isCancelled,
                      generation == panelRefreshGeneration,
                      isHistoryPresentationActive else {
                    group.cancelAll()
                    return
                }

                let receivedAt = clock.now
                if receivedAt >= refreshDeadline {
                    missedDeadline = true
                    let elapsed = Self.milliseconds(from: openedAt.duration(to: receivedAt))
                    lastPanelRefreshDurationMilliseconds = elapsed
                    logger.error("Panel refresh missed 400 ms deadline with \(completedResultCount, privacy: .public)/\(expectedResultCount, privacy: .public) results published after \(elapsed, format: .fixed(precision: 1), privacy: .public) ms; retaining the latest values")
                    group.cancelAll()
                    return
                }
                if receivedAt >= dataBudgetDeadline, !exceededDataBudget {
                    exceededDataBudget = true
                    logger.warning("Panel refresh exceeded the 350 ms data budget with \(completedResultCount, privacy: .public)/\(expectedResultCount, privacy: .public) results published")
                }

                switch event {
                case let .snapshot(result, duration):
                    completedResultCount += 1
                    logger.notice("Panel IOKit snapshot finished in \(Self.milliseconds(from: duration), format: .fixed(precision: 1), privacy: .public) ms")
                    switch result {
                    case let .success(snapshot):
                        apply(snapshot)
                    case let .failure(message):
                        samplingErrorMessage = message
                        updateDisplayedError()
                    }

                case let .processes(processes, duration):
                    completedResultCount += 1
                    logger.notice("Panel process ranking finished in \(Self.milliseconds(from: duration), format: .fixed(precision: 1), privacy: .public) ms")
                    topProcesses = processes

                case let .history(result, duration):
                    completedResultCount += 1
                    logger.notice("Panel history projection finished in \(Self.milliseconds(from: duration), format: .fixed(precision: 1), privacy: .public) ms")
                    switch result {
                    case let .success(projection):
                        isHistoryReady = true
                        if metrics == historyMetrics, range == historyRange {
                            chartSeriesByMetric = projection.seriesByMetric
                            sessionSummary = projection.sessionSummary ?? sessionSummary
                            historyOperationErrorMessage = nil
                            updateDisplayedError()
                        } else {
                            projectionIsDirty = true
                        }
                    case let .failure(message):
                        historyOperationErrorMessage = message
                        updateDisplayedError()
                    }

                case .dataBudgetExpired:
                    guard completedResultCount < expectedResultCount else { break }
                    if !exceededDataBudget {
                        exceededDataBudget = true
                        logger.warning("Panel refresh exceeded the 350 ms data budget with \(completedResultCount, privacy: .public)/\(expectedResultCount, privacy: .public) results published")
                    }

                case .refreshDeadlineExpired:
                    break

                case .cancelled:
                    break
                }

                if completedResultCount == expectedResultCount {
                    dataCompletionMilliseconds = Self.milliseconds(from: openedAt.duration(to: clock.now))
                    group.cancelAll()
                    return
                }
            }
        }

        guard !Task.isCancelled,
              generation == panelRefreshGeneration,
              isHistoryPresentationActive,
              !missedDeadline else {
            return
        }

        let elapsedMilliseconds = dataCompletionMilliseconds
            ?? Self.milliseconds(from: openedAt.duration(to: clock.now))
        lastPanelRefreshDurationMilliseconds = elapsedMilliseconds
        if exceededDataBudget || elapsedMilliseconds > Self.panelDataBudgetMilliseconds {
            logger.warning("Panel refresh completed beyond the 350 ms data budget: \(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        } else {
            logger.notice("Panel refresh completed in \(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        }
    }

    private func enqueueHistory(_ snapshot: PowerSnapshot) {
        guard let historyContinuation else {
            return
        }

        switch historyContinuation.yield(snapshot) {
        case .enqueued:
            break
        case .dropped:
            droppedHistorySampleCount += 1
            logger.warning("History queue dropped a sample; total dropped: \(self.droppedHistorySampleCount, privacy: .public)")
        case .terminated:
            logger.debug("History queue is closed; sample was not persisted")
        @unknown default:
            logger.warning("History queue returned an unknown yield result")
        }
    }

    private func consumeHistory(from stream: AsyncStream<PowerSnapshot>) async {
        historyLoadState = .loading

        do {
            try await historyEngine.prepare()
            isHistoryReady = true
            historyLoadState = await historyEngine.loadState
            if case let .failed(message) = historyLoadState {
                historyPreparationErrorMessage = message
                updateDisplayedError()
            }
            requestHistoryProjection()
        } catch let error as PowerHistoryEngineError {
            if case .migrationFailed = error {
                isHistoryReady = true
            }
            historyLoadState = .failed(error.localizedDescription)
            historyPreparationErrorMessage = error.localizedDescription
            updateDisplayedError()
            logger.error("History preparation failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            historyLoadState = .failed(error.localizedDescription)
            historyPreparationErrorMessage = error.localizedDescription
            updateDisplayedError()
            logger.error("History preparation failed: \(error.localizedDescription, privacy: .public)")
        }

        for await snapshot in stream {
            do {
                sessionSummary = try await historyEngine.record(snapshot)
                historyOperationErrorMessage = nil
                updateDisplayedError()
                if isHistoryReady, panelRefreshTask == nil {
                    requestHistoryProjection()
                }
            } catch {
                historyOperationErrorMessage = error.localizedDescription
                updateDisplayedError()
                logger.error("Failed to record history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func requestHistoryProjection() {
        guard isHistoryPresentationActive,
              isHistoryReady,
              !isShuttingDown,
              panelRefreshTask == nil else {
            return
        }

        projectionIsDirty = true
        guard projectionTask == nil else {
            return
        }

        projectionTaskGeneration += 1
        let generation = projectionTaskGeneration
        projectionTask = Task { [weak self] in
            await self?.runProjectionLoop(generation: generation)
        }
    }

    private func runProjectionLoop(generation: Int) async {
        while generation == projectionTaskGeneration,
              isHistoryPresentationActive,
              isHistoryReady,
              !isShuttingDown,
              projectionIsDirty {
            projectionIsDirty = false
            let metrics = historyMetrics
            let range = historyRange
            let now = Date()

            do {
                let projection = try await historyEngine.projection(
                    metrics: metrics,
                    range: range,
                    now: now
                )

                guard !Task.isCancelled,
                      generation == projectionTaskGeneration,
                      isHistoryPresentationActive else {
                    break
                }

                if metrics == historyMetrics, range == historyRange {
                    chartSeriesByMetric = projection.seriesByMetric
                    historyOperationErrorMessage = nil
                    updateDisplayedError()
                } else {
                    projectionIsDirty = true
                }
            } catch is CancellationError {
                break
            } catch {
                historyOperationErrorMessage = error.localizedDescription
                updateDisplayedError()
                logger.error("History projection failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        guard generation == projectionTaskGeneration else { return }
        projectionTask = nil
        if projectionIsDirty, isHistoryPresentationActive, !isShuttingDown {
            requestHistoryProjection()
        }
    }

    private func updateDisplayedError() {
        lastErrorMessage = historyPreparationErrorMessage
            ?? historyOperationErrorMessage
            ?? samplingErrorMessage
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private enum PanelSnapshotRefreshResult: Sendable {
    case success(PowerSnapshot)
    case failure(String)
}

private enum PanelHistoryRefreshResult: Sendable {
    case success(HistoryProjection)
    case failure(String)
}

private enum PanelRefreshEvent: Sendable {
    case snapshot(PanelSnapshotRefreshResult, Duration)
    case processes([ProcessEnergyStat], Duration)
    case history(PanelHistoryRefreshResult, Duration)
    case dataBudgetExpired
    case refreshDeadlineExpired
    case cancelled
}
