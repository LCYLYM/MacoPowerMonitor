import Foundation

enum AppConstants {
    static let subsystem = "com.codex.MacoPowerMonitor"
    static let appVersion = "0.2.0"
    static let refreshInterval: TimeInterval = 30
    static let refreshTolerance: TimeInterval = 5
    static let panelWidth: CGFloat = 396
    static let panelHeight: CGFloat = 620
    static let repositoryURL = URL(string: "https://github.com/LCYLYM/MacoPowerMonitor")!
    static let latestReleaseURL = URL(string: "https://github.com/LCYLYM/MacoPowerMonitor/releases/latest")!
}
