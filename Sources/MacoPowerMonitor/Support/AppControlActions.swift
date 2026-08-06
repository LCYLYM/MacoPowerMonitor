import AppKit
import Foundation

@MainActor
enum AppControlActions {
    static func openRepository() {
        NSWorkspace.shared.open(AppConstants.repositoryURL)
    }

    static func openLatestRelease() {
        NSWorkspace.shared.open(AppConstants.latestReleaseURL)
    }

    static func quitApplication() {
        PowerMonitorStore.shared.flushPendingBestEffort()
        NSApp.terminate(nil)
    }
}
