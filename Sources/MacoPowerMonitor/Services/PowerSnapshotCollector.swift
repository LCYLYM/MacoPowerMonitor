import Foundation

protocol PowerSnapshotCollecting: Sendable {
    func readSnapshot() throws -> PowerSnapshot
}

enum PowerSnapshotCollectorError: LocalizedError {
    case noPowerSourceFound
    case unableToReadRegistryProperties

    var errorDescription: String? {
        switch self {
        case .noPowerSourceFound:
            return "未找到可用的电源信息。"
        case .unableToReadRegistryProperties:
            return "无法读取 AppleSmartBattery 注册表属性。"
        }
    }
}
