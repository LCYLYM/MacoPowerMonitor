import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PowerMonitorStore.shared
    private let runtimeSettings = AppRuntimeSettings.shared
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "app")
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var statusItemConfigurationAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        runtimeSettings.configureOnLaunch()

        if let selfTest = ProcessInfo.processInfo.environment["MACO_POWER_MONITOR_SELF_TEST"] {
            print(runtimeSettings.runSelfTest(named: selfTest))
            NSApp.terminate(nil)
            return
        }

        configureObservers()
        DispatchQueue.main.async { [weak self] in
            self?.configureStatusItemIfNeeded()
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

    private func configureStatusItemIfNeeded() {
        statusItemConfigurationAttempts += 1

        if let existingItem = statusItem {
            if existingItem.button != nil {
                existingItem.isVisible = true
                updateStatusItem(snapshot: store.latestSnapshot)
                logger.notice("Status item became available on attempt \(self.statusItemConfigurationAttempts, privacy: .public)")
                return
            }

            NSStatusBar.system.removeStatusItem(existingItem)
            statusItem = nil
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true

        guard let button = item.button else {
            logger.error("Failed to create status item button on attempt \(self.statusItemConfigurationAttempts, privacy: .public)")
            scheduleStatusItemRetryIfNeeded()
            return
        }

        button.target = self
        button.action = #selector(togglePanelFromStatusItem)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        statusItem = item
        logger.notice("Configured status item on attempt \(self.statusItemConfigurationAttempts, privacy: .public)")
        updateStatusItem(snapshot: store.latestSnapshot)

        if ProcessInfo.processInfo.environment["MACO_POWER_MONITOR_DEBUG_WINDOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showPanel()
            }
        }
    }

    private func scheduleStatusItemRetryIfNeeded() {
        guard statusItemConfigurationAttempts < 6 else {
            logger.fault("Giving up after repeated status item creation failures")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.configureStatusItemIfNeeded()
        }
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

        if let snapshot {
            if snapshot.isCharging {
                symbolName = "battery.100percent.bolt"
            } else {
                switch snapshot.batteryLevel {
                case ..<0.15: symbolName = "battery.25percent"
                case ..<0.35: symbolName = "battery.25percent"
                case ..<0.60: symbolName = "battery.50percent"
                case ..<0.85: symbolName = "battery.75percent"
                default: symbolName = "battery.100percent"
                }
            }
        } else {
            symbolName = "battery.0percent"
        }

        let resolvedSymbolName: String
        if NSImage(systemSymbolName: symbolName, accessibilityDescription: "Power Monitor") != nil {
            resolvedSymbolName = symbolName
        } else {
            resolvedSymbolName = "battery.100percent"
        }

        let image = NSImage(systemSymbolName: resolvedSymbolName, accessibilityDescription: "Power Monitor")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = false
        button.toolTip = snapshot.map {
            "电量 \(PowerFormatting.percent($0.batteryLevel)) · \($0.displayStatusText) · 系统输入 \(PowerFormatting.watts($0.systemPowerWatts))"
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
        if let button = statusItem?.button {
            position(panel: panel, relativeTo: button)
        } else {
            logger.warning("Showing panel without status item button; using fallback positioning")
            positionFallback(panel: panel)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private func positionFallback(panel: NSPanel) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = max(visibleFrame.maxX - AppConstants.panelWidth - 12, visibleFrame.minX + 8)
        let y = max(visibleFrame.maxY - AppConstants.panelHeight - 24, visibleFrame.minY + 8)
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

            if let panel = self.panel, panel.isVisible, !self.belongsToPanelHierarchy(event.window) {
                self.closePanel()
            }
            return event
        }
    }

    private func belongsToPanelHierarchy(_ window: NSWindow?) -> Bool {
        guard let panel, let window else {
            return false
        }

        var currentWindow: NSWindow? = window
        var visitedWindowNumbers = Set<Int>()

        while let resolvedWindow = currentWindow {
            if resolvedWindow == panel {
                return true
            }

            if !visitedWindowNumbers.insert(resolvedWindow.windowNumber).inserted {
                break
            }

            currentWindow = resolvedWindow.sheetParent ?? resolvedWindow.parent
        }

        return panel.childWindows?.contains(where: { $0 == window }) ?? false
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
