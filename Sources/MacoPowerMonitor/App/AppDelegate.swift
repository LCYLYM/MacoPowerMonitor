import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PowerMonitorStore.shared
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureObservers()

        if ProcessInfo.processInfo.environment["MACO_POWER_MONITOR_DEBUG_WINDOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanelFromStatusItem)
        item.button?.sendAction(on: [.leftMouseUp])
        item.button?.font = .systemFont(ofSize: 12, weight: .semibold)
        statusItem = item
        updateStatusItem(snapshot: store.latestSnapshot)
    }

    private func configureObservers() {
        store.$latestSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusItem(snapshot: snapshot)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(snapshot: PowerSnapshot?) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let title: String

        if let snapshot {
            if snapshot.isCharging {
                symbolName = "bolt.batteryblock.fill"
            } else {
                switch snapshot.batteryLevel {
                case ..<0.15: symbolName = "battery.0"
                case ..<0.35: symbolName = "battery.25"
                case ..<0.60: symbolName = "battery.50"
                case ..<0.85: symbolName = "battery.75"
                default: symbolName = "battery.100"
                }
            }

            title = PowerFormatting.percent(snapshot.batteryLevel)
        } else {
            symbolName = "battery.0"
            title = "--%"
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Power Monitor")
        button.imagePosition = .imageLeading
        button.title = title
        button.toolTip = snapshot.map {
            "电量 \(PowerFormatting.percent($0.batteryLevel)) · \($0.displayStatusText) · \(PowerFormatting.watts($0.preferredPowerWatts))"
        } ?? "正在读取电源信息"
    }

    @objc
    private func togglePanelFromStatusItem() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let panel = ensurePanel()
        guard let button = statusItem?.button else { return }

        position(panel: panel, relativeTo: button)
        panel.orderFrontRegardless()
        panel.makeKey()
        startEventMonitors()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        stopEventMonitors()
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            if let hostingController = panel.contentViewController as? NSHostingController<ContentView> {
                hostingController.rootView = ContentView(store: store)
            }
            return panel
        }

        let contentView = ContentView(store: store)
        let hostingController = NSHostingController(rootView: contentView)
        let panel = FloatingPanel(contentViewController: hostingController)
        panel.setContentSize(NSSize(width: AppConstants.panelWidth, height: AppConstants.panelHeight))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .statusBar
        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel, relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        let buttonFrameOnScreen = button.convert(button.bounds, to: nil)
        let buttonFrame = buttonWindow.convertToScreen(buttonFrameOnScreen)
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let x = min(max(buttonFrame.maxX - AppConstants.panelWidth, visibleFrame.minX + 8), visibleFrame.maxX - AppConstants.panelWidth - 8)
        let y = buttonFrame.minY - AppConstants.panelHeight - 8
        panel.setFrame(NSRect(x: x, y: y, width: AppConstants.panelWidth, height: AppConstants.panelHeight), display: true)
    }

    private func startEventMonitors() {
        stopEventMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closePanel()
                return nil
            }

            if let panel = self.panel, panel.isVisible, let eventWindow = event.window, eventWindow != panel {
                self.closePanel()
            }
            return event
        }
    }

    private func stopEventMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    convenience init(contentViewController: NSViewController) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: AppConstants.panelWidth, height: AppConstants.panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}
