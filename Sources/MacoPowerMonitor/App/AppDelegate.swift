import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PowerMonitorStore.shared
    private let runtimeSettings = AppRuntimeSettings.shared
    private let logger = Logger(subsystem: AppConstants.subsystem, category: "app")
    private let panelSignposter = OSSignposter(subsystem: AppConstants.subsystem, category: "panel-presentation")
    private let statusIconAnimator = StatusBarBatteryIconAnimator()
    private let panelContentContainer = PanelContainerViewController()
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
            if selfTest == "quit" {
                print("SELF_TEST=quit")
                print("TERMINATE_REPLY=terminateNow")
                AppControlActions.quitApplication()
                return
            }
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
        statusIconAnimator.invalidate()
        panelContentContainer.unmountContent()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    private func configureStatusItemIfNeeded() {
        statusItemConfigurationAttempts += 1

        if let existingItem = statusItem {
            if let existingButton = existingItem.button {
                existingItem.isVisible = true
                statusIconAnimator.attach(to: existingButton)
                updateStatusItem(snapshot: store.latestSnapshot)
                logger.notice("Status item became available on attempt \(self.statusItemConfigurationAttempts, privacy: .public)")
                return
            }

            NSStatusBar.system.removeStatusItem(existingItem)
            statusItem = nil
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        statusIconAnimator.attach(to: button)
        statusItem = item
        logger.notice("Configured status item on attempt \(self.statusItemConfigurationAttempts, privacy: .public)")
        updateStatusItem(snapshot: store.latestSnapshot)
        _ = ensurePanel()

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

        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateStatusItem(snapshot: self.store.latestSnapshot)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.closePanelForResignActiveIfNeeded()
            }
            .store(in: &cancellables)

    }

    /// Cmd-Tab produces no mouse event, so resigning active must also dismiss
    /// the panel. The osascript "with administrator privileges" prompt is
    /// presented by SecurityAgent in the foreground; resigning active to it is
    /// part of the in-panel authorization flow and must not close the panel.
    private func closePanelForResignActiveIfNeeded() {
        guard let panel, panel.isVisible else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.SecurityAgent" else { return }
        closePanel()
    }

    private func updateStatusItem(snapshot: PowerSnapshot?) {
        guard let button = statusItem?.button else { return }

        let connectionGlyph: StatusBarBatteryConnectionGlyph
        if let snapshot, snapshot.source == .acPower {
            connectionGlyph = snapshot.chargeHoldReason != nil || snapshot.isCharged
                ? .plug
                : .bolt
        } else {
            connectionGlyph = .none
        }

        statusIconAnimator.update(state: StatusBarBatteryIconState(
            level: snapshot?.batteryLevel,
            connectionGlyph: connectionGlyph,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        ))
        button.appearsDisabled = false
        button.toolTip = snapshot.map {
            let limit = $0.chargeLimitPercent.map { " · 充电目标 \($0)%" } ?? ""
            return "电量 \(PowerFormatting.percent($0.batteryLevel)) · \($0.displayStatusText)\(limit) · 适配器实时 \(PowerFormatting.watts($0.adapterRealtimePowerWatts)) · \($0.adapterProtocol?.shortName ?? "协议未知")"
        } ?? "正在读取电源信息"
        button.setAccessibilityLabel("Maco Power Monitor")
        button.setAccessibilityValue(snapshot.map {
            "电量 \(PowerFormatting.percent($0.batteryLevel))，\($0.displayStatusText)"
        } ?? "正在读取电源信息")
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
        let clock = ContinuousClock()
        let presentationStartedAt = clock.now
        let presentationState = panelSignposter.beginInterval("PanelPresentation")
        let panel = ensurePanel()
        position(panel: panel)
        panel.makeKeyAndOrderFront(nil)
        let openedAt = clock.now
        panelSignposter.endInterval("PanelPresentation", presentationState)
        let presentationMilliseconds = Self.milliseconds(from: presentationStartedAt.duration(to: openedAt))
        if presentationMilliseconds > 100 {
            logger.error("Panel presentation exceeded 100 ms: \(presentationMilliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        } else {
            logger.notice("Panel presentation completed in \(presentationMilliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        }
        NSApp.activate(ignoringOtherApps: true)
        startEventMonitors()
        store.beginPanelPresentation(openedAt: openedAt)

        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else { return }
            self.mountPanelContent(in: panel)
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        store.endPanelPresentation()
        panelContentContainer.unmountContent()
        stopEventMonitors()
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = FloatingPanel(contentViewController: panelContentContainer)
        panel.setContentSize(NSSize(width: AppConstants.panelWidth, height: AppConstants.panelHeight))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .statusBar
        self.panel = panel
        return panel
    }

    /// Mounts SwiftUI as a child of the permanent container instead of swapping
    /// the panel's `contentViewController`. The latter collapses the window to
    /// 0x0 and displaces `origin.y` by the panel height, which can throw the
    /// panel onto an adjacent display. See `PanelContainerViewController`.
    private func mountPanelContent(in panel: NSPanel) {
        guard panel.isVisible, !panelContentContainer.isContentMounted else {
            return
        }

        let frameBeforeMount = panel.frame
        let hostingController = NSHostingController(rootView: ContentView(store: store))
        // Disable automatic window resizing so the panel stays at the explicit
        // 396x620 we positioned it to, rather than growing to ~652 tall based on
        // the hosting controller's intrinsic content size.
        hostingController.sizingOptions = []
        panelContentContainer.mountContent(hostingController)
        let frameAfterMount = panel.frame

        // Mounting content must never move or resize the window. If this fires,
        // the panel can land on a display it was not positioned on.
        if !Self.framesMatch(frameBeforeMount, frameAfterMount) {
            logger.error("Mounting panel content moved the window from \(frameBeforeMount.debugDescription, privacy: .public) to \(frameAfterMount.debugDescription, privacy: .public)")
        }

        if ProcessInfo.processInfo.environment["MACO_DEBUG_PANEL"] == "1" {
            print("DEBUG_PANEL: frame before mount=\(frameBeforeMount)")
            print("DEBUG_PANEL: frame after mount =\(frameAfterMount) screen=\(panel.screen?.localizedName ?? "nil")")
        }
    }

    private static func framesMatch(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        let tolerance: CGFloat = 0.5
        return abs(lhs.origin.x - rhs.origin.x) < tolerance
            && abs(lhs.origin.y - rhs.origin.y) < tolerance
            && abs(lhs.width - rhs.width) < tolerance
            && abs(lhs.height - rhs.height) < tolerance
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private func position(panel: NSPanel) {
        let clickLocation = Self.clickLocationInScreenCoordinates()
        let resolved = Self.resolveScreen(for: clickLocation)
        let targetScreen = resolved?.screen
        if ProcessInfo.processInfo.environment["MACO_DEBUG_PANEL"] == "1" {
            print("DEBUG_PANEL: mouseLocation=\(clickLocation)")
            for s in NSScreen.screens {
                print("DEBUG_PANEL: screen name=\(s.localizedName) main=\(s == NSScreen.main) frame=\(s.frame) visible=\(s.visibleFrame)")
            }
            print("DEBUG_PANEL: targetScreen=\(targetScreen?.localizedName ?? "nil") resolution=\(resolved.map { "\($0.resolution)" } ?? "none")")
        }
        guard let targetScreen else {
            logger.warning("Panel positioning found no screen for click at \(clickLocation.debugDescription, privacy: .public); using fallback")
            positionFallback(panel: panel)
            return
        }

        let visibleFrame = targetScreen.visibleFrame
        let x = min(max(clickLocation.x - AppConstants.panelWidth, visibleFrame.minX + 8), visibleFrame.maxX - AppConstants.panelWidth - 8)
        let y = visibleFrame.maxY - AppConstants.panelHeight - 8
        panel.setFrame(NSRect(x: x, y: y, width: AppConstants.panelWidth, height: AppConstants.panelHeight), display: true)
        logger.notice("Positioned panel below menu bar on screen \(targetScreen.localizedName, privacy: .public)")
    }

    private static func clickLocationInScreenCoordinates() -> NSPoint {
        // NSStatusItem is rendered on every display's menu bar but its button
        // window is anchored to the primary display, so event.window coordinate
        // conversion is wrong for secondary-display clicks. The physical mouse
        // position is the only reliable source of the clicked screen.
        NSEvent.mouseLocation
    }

    private static func resolveScreen(
        for point: NSPoint
    ) -> (screen: NSScreen, resolution: PanelScreenGeometry.Resolution)? {
        let screens = NSScreen.screens
        guard let resolved = PanelScreenGeometry.resolve(
            point: point,
            screens: screens.map { PanelScreenGeometry.Layout(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        ) else {
            return nil
        }

        return (screens[resolved.index], resolved.resolution)
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
