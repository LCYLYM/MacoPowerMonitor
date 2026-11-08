import AppKit

/// Permanent `contentViewController` of the floating panel.
///
/// Reassigning `NSWindow.contentViewController` while the window is on screen
/// collapses the frame to 0x0, and AppKit preserves the *top* edge while doing
/// so, which moves `origin.y` up by the full panel height. Restoring the size
/// then grows the window upward from the displaced origin, so the panel can
/// land on a display above the one it was positioned on. This container is
/// therefore installed once and never replaced; SwiftUI is mounted and
/// unmounted as a child view controller so the window frame never changes.
final class PanelContainerViewController: NSViewController {
    private var hostedController: NSViewController?

    /// First-frame stand-in so the panel reads as glass before SwiftUI mounts.
    ///
    /// This must be a *hideable subview* rather than the container's own view.
    /// `ContentView` draws its own 24pt rounded glass card, so a square-cornered
    /// `NSVisualEffectView` spanning the whole window would show through at the
    /// corners and double up the `.behindWindow` blur.
    private lazy var placeholderGlassView: NSVisualEffectView = {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = PanelContainerViewController.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        return visualEffectView
    }()

    /// Matches the `RoundedRectangle(cornerRadius:)` that `ContentView` draws,
    /// so the stand-in and the real card have the same silhouette.
    static let cornerRadius: CGFloat = 24

    var isContentMounted: Bool { hostedController != nil }

    /// Exposed so the mount/unmount invariant can be asserted directly: exactly
    /// one glass layer must be live at any time.
    var isPlaceholderVisible: Bool { !placeholderGlassView.isHidden }

    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true
        view = containerView

        pin(placeholderGlassView, into: containerView)
    }

    func mountContent(_ controller: NSViewController) {
        guard hostedController == nil else { return }

        addChild(controller)
        pin(controller.view, into: view)
        hostedController = controller
        // ContentView supplies its own glass from here on; leaving the stand-in
        // visible would double the blur and square off the corners.
        placeholderGlassView.isHidden = true
    }

    func unmountContent() {
        guard let hostedController else { return }

        placeholderGlassView.isHidden = false
        hostedController.view.removeFromSuperview()
        hostedController.removeFromParent()
        self.hostedController = nil
    }

    private func pin(_ subview: NSView, into container: NSView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            subview.topAnchor.constraint(equalTo: container.topAnchor),
            subview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
