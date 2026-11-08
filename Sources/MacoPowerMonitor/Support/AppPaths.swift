import Foundation

enum AppPaths {
    static var applicationSupportDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return baseURL.appendingPathComponent("MacoPowerMonitor", isDirectory: true)
    }

    static var historyDirectoryURL: URL {
        applicationSupportDirectory.appendingPathComponent("power-history", isDirectory: true)
    }

    static var legacyHistoryFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("power-history.json")
    }

    @available(*, deprecated, renamed: "legacyHistoryFileURL")
    static var historyFileURL: URL {
        legacyHistoryFileURL
    }
}
