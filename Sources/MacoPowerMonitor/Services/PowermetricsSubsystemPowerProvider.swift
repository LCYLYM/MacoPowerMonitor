import Foundation
import OSLog

struct SubsystemPowerMetrics: Sendable {
    let cpuWatts: Double?
    let gpuWatts: Double?
    let aneWatts: Double?
    let unavailableReason: String?
}

final class PowermetricsSubsystemPowerProvider: @unchecked Sendable {
    static let shared = PowermetricsSubsystemPowerProvider()

    private let logger = Logger(subsystem: AppConstants.subsystem, category: "powermetrics")
    private let queue = DispatchQueue(label: "com.codex.MacoPowerMonitor.powermetrics")
    private var cachedMetrics = SubsystemPowerMetrics(cpuWatts: nil, gpuWatts: nil, aneWatts: nil, unavailableReason: nil)
    private var lastRefreshDate: Date?
    private let refreshInterval: TimeInterval = 120

    func currentMetrics() -> SubsystemPowerMetrics {
        queue.sync {
            let now = Date()
            if let lastRefreshDate,
               now.timeIntervalSince(lastRefreshDate) < refreshInterval {
                return cachedMetrics
            }

            do {
                cachedMetrics = try fetchMetrics()
            } catch {
                logger.error("powermetrics probe failed: \(error.localizedDescription, privacy: .public)")
                cachedMetrics = SubsystemPowerMetrics(
                    cpuWatts: nil,
                    gpuWatts: nil,
                    aneWatts: nil,
                    unavailableReason: "分项功耗需要管理员权限（powermetrics）"
                )
            }

            lastRefreshDate = now
            return cachedMetrics
        }
    }

    private func fetchMetrics() throws -> SubsystemPowerMetrics {
        let data = try CommandRunner.run(
            executable: "/usr/bin/sudo",
            arguments: ["-n", "/usr/bin/powermetrics", "--samplers", "cpu_power,gpu_power,ane_power", "-n", "1", "-f", "plist"]
        )

        let chunks = data.split(separator: 0)
        guard let first = chunks.first,
              let plist = try PropertyListSerialization.propertyList(from: Data(first), options: [], format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let cpuWatts = extractWatts(from: plist, matching: ["cpu"])
        let gpuWatts = extractWatts(from: plist, matching: ["gpu"])
        let aneWatts = extractWatts(from: plist, matching: ["ane"])

        return SubsystemPowerMetrics(cpuWatts: cpuWatts, gpuWatts: gpuWatts, aneWatts: aneWatts, unavailableReason: nil)
    }

    private func extractWatts(from object: Any, matching keywords: [String]) -> Double? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let loweredKey = key.lowercased()
                if keywords.allSatisfy(loweredKey.contains),
                   loweredKey.contains("power") {
                    if let number = value as? Double {
                        return number
                    }
                    if let number = value as? Int {
                        return Double(number)
                    }
                }

                if let nested = extractWatts(from: value, matching: keywords) {
                    return nested
                }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let nested = extractWatts(from: value, matching: keywords) {
                    return nested
                }
            }
        }

        return nil
    }
}
