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
        for window in NSApp.windows {
            if let sheetParent = window.sheetParent {
                sheetParent.endSheet(window)
            }
        }
        PowerMonitorStore.shared.flushPendingBestEffort()
        NSApp.terminate(nil)
        exit(0)
    }
}
