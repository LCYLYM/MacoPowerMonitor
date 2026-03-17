import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard ProcessInfo.processInfo.environment["MACO_POWER_MONITOR_DEBUG_WINDOW"] == "1" else {
            return
        }

        let hostingController = NSHostingController(rootView: ContentView(store: PowerMonitorStore.shared))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MacoPowerMonitor Preview"
        window.setContentSize(NSSize(width: AppConstants.panelWidth, height: 760))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }
}
