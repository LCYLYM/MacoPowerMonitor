import Foundation

final class RepeatingTaskScheduler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.codex.MacoPowerMonitor.scheduler", qos: .utility)
    private let interval: TimeInterval
    private let tolerance: TimeInterval
    private var timer: DispatchSourceTimer?

    init(interval: TimeInterval, tolerance: TimeInterval) {
        self.interval = interval
        self.tolerance = tolerance
    }

    func start(handler: @escaping @Sendable () -> Void) {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .milliseconds(Int(tolerance * 1_000))
        )
        timer.setEventHandler(handler: handler)
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
