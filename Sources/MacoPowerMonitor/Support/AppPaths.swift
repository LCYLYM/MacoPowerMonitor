import Foundation

enum AppPaths {
    static var applicationSupportDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return baseURL.appendingPathComponent("MacoPowerMonitor", isDirectory: true)
    }

    static var historyFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("power-history.json")
    }
}
