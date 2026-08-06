import Foundation
import OSLog

struct ProcessEnergyStat: Identifiable, Sendable {
    let pid: Int
    let command: String
    let cpuPercent: Double
    let powerScore: Double
    let memoryText: String

    var id: Int { pid }

    var primaryScoreText: String {
        if powerScore > 0 {
            return String(format: "%.1f power", powerScore)
        }

        return String(format: "%.1f%% CPU", cpuPercent)
    }
}

protocol ProcessEnergyStatsProviding: Sendable {
    func currentStats(limit: Int, forceRefresh: Bool) -> [ProcessEnergyStat]
}

final class ProcessEnergyStatsProvider: ProcessEnergyStatsProviding, @unchecked Sendable {
    static let shared = ProcessEnergyStatsProvider()

    private let logger = Logger(subsystem: AppConstants.subsystem, category: "process-energy")
    private let queue = DispatchQueue(label: "com.codex.MacoPowerMonitor.process-energy")
    private var cachedStats: [ProcessEnergyStat] = []
    private var lastRefreshDate: Date?
    private let refreshInterval: TimeInterval = 30

    func currentStats(limit: Int = 6, forceRefresh: Bool = false) -> [ProcessEnergyStat] {
        queue.sync {
            let now = Date()
            if !forceRefresh,
               let lastRefreshDate,
               now.timeIntervalSince(lastRefreshDate) < refreshInterval,
               !cachedStats.isEmpty {
                return Array(cachedStats.prefix(limit))
            }

            do {
                cachedStats = try fetchStats()
                lastRefreshDate = now
                return Array(cachedStats.prefix(limit))
            } catch is CancellationError {
                return Array(cachedStats.prefix(limit))
            } catch {
                logger.error("Failed to fetch process energy stats: \(error.localizedDescription, privacy: .public)")
                return Array(cachedStats.prefix(limit))
            }
        }
    }

    private func fetchStats() throws -> [ProcessEnergyStat] {
        let data = try CommandRunner.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,%cpu=,rss=,comm="],
            timeout: 0.25
        )

        let output = String(decoding: data, as: UTF8.self)
        return output.split(separator: "\n").map(String.init)
            .compactMap(parseRow(_:))
            .filter { $0.command != "ps" && $0.command != "MacoPowerMonitor" }
            .sorted { lhs, rhs in
                lhs.cpuPercent > rhs.cpuPercent
            }
    }

    private func parseRow(_ row: String) -> ProcessEnergyStat? {
        let parts = row.split(maxSplits: 3, whereSeparator: \.isWhitespace)
        guard parts.count == 4,
              let pid = Int(parts[0]),
              let cpu = Double(parts[1]),
              let residentKilobytes = Int(parts[2]) else {
            return nil
        }

        let command = URL(fileURLWithPath: String(parts[3])).lastPathComponent
        return ProcessEnergyStat(
            pid: pid,
            command: command,
            cpuPercent: cpu,
            powerScore: 0,
            memoryText: Self.memoryText(residentKilobytes: residentKilobytes)
        )
    }

    private static func memoryText(residentKilobytes: Int) -> String {
        if residentKilobytes >= 1_024 {
            return String(format: "%.0fM", Double(residentKilobytes) / 1_024)
        }
        return "\(residentKilobytes)K"
    }
}
