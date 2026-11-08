import Foundation

protocol PowerSnapshotCollecting: Sendable {
    func readSnapshot() throws -> PowerSnapshot
    func prewarmSlowMetrics()
}

extension PowerSnapshotCollecting {
    func prewarmSlowMetrics() {}
}

enum PowerSnapshotCollectorError: LocalizedError {
    case noPowerSourceFound

    var errorDescription: String? {
        switch self {
        case .noPowerSourceFound:
            return "未找到可用的电源信息。"
        }
    }
}
