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

final class ProcessEnergyStatsProvider: @unchecked Sendable {
    static let shared = ProcessEnergyStatsProvider()

    private let logger = Logger(subsystem: AppConstants.subsystem, category: "process-energy")
    private let queue = DispatchQueue(label: "com.codex.MacoPowerMonitor.process-energy")
    private var cachedStats: [ProcessEnergyStat] = []
    private var lastRefreshDate: Date?
    private let refreshInterval: TimeInterval = 30

    func currentStats(limit: Int = 6) -> [ProcessEnergyStat] {
        queue.sync {
            let now = Date()
            if let lastRefreshDate,
               now.timeIntervalSince(lastRefreshDate) < refreshInterval,
               !cachedStats.isEmpty {
                return Array(cachedStats.prefix(limit))
            }

            do {
                cachedStats = try fetchStats()
                lastRefreshDate = now
                return Array(cachedStats.prefix(limit))
            } catch {
                logger.error("Failed to fetch process energy stats: \(error.localizedDescription, privacy: .public)")
                return Array(cachedStats.prefix(limit))
            }
        }
    }

    private func fetchStats() throws -> [ProcessEnergyStat] {
        let data = try CommandRunner.run(
            executable: "/usr/bin/top",
            arguments: ["-l", "1", "-o", "cpu", "-stats", "pid,command,cpu,mem,power"]
        )

        let output = String(decoding: data, as: UTF8.self)
        let rows = output.split(separator: "\n").map(String.init)
        guard let headerIndex = rows.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("PID") }) else {
            return []
        }

        return rows
            .dropFirst(headerIndex + 1)
            .compactMap(parseRow(_:))
            .filter { $0.command != "top" && $0.command != "MacoPowerMonitor" }
            .sorted { lhs, rhs in
                if lhs.powerScore == rhs.powerScore {
                    return lhs.cpuPercent > rhs.cpuPercent
                }
                return lhs.powerScore > rhs.powerScore
            }
    }

    private func parseRow(_ row: String) -> ProcessEnergyStat? {
        let parts = row.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 5,
              let pid = Int(parts[0]),
              let cpu = Double(parts[2]),
              let power = Double(parts[4]) else {
            return nil
        }

        return ProcessEnergyStat(
            pid: pid,
            command: String(parts[1]),
            cpuPercent: cpu,
            powerScore: power,
            memoryText: String(parts[3])
        )
    }
}
