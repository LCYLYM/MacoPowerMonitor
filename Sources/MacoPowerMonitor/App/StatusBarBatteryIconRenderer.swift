import AppKit

enum StatusBarBatteryConnectionGlyph: Equatable {
    case none
    case bolt
    case plug
}

struct StatusBarBatteryIconState: Equatable {
    let level: Double?
    let connectionGlyph: StatusBarBatteryConnectionGlyph
    let isLowPowerModeEnabled: Bool
}

enum StatusBarBatteryIconTransition {
    case steady
    case enteringConnection(labelProgress: CGFloat, glyphProgress: CGFloat)
    case leavingConnection(
        previousGlyph: StatusBarBatteryConnectionGlyph,
        labelProgress: CGFloat,
        glyphProgress: CGFloat
    )
    case swappingConnectionGlyph(
        previousGlyph: StatusBarBatteryConnectionGlyph,
        progress: CGFloat
    )
}

/// Draws the menu bar battery using the geometry, colors, and motion from
/// battery-status-prototype.html, with a native plug glyph for charge holds.
@MainActor
enum StatusBarBatteryIconRenderer {
    private enum Appearance: Equatable {
        case normal
        case externalPower
        case lowPower
        case critical

        var fillColor: NSColor {
            switch self {
            case .normal:
                return NSColor(srgbRed: 0x43 / 255, green: 0x45 / 255, blue: 0x47 / 255, alpha: 1)
            case .externalPower:
                return NSColor(srgbRed: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
            case .lowPower:
                return NSColor(srgbRed: 0xFF / 255, green: 0xCC / 255, blue: 0, alpha: 1)
            case .critical:
                return NSColor(srgbRed: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)
            }
        }
    }

    private struct GlyphPresentation {
        let glyph: StatusBarBatteryConnectionGlyph
        let scale: CGFloat
        let opacity: CGFloat
    }

    private struct LabelPresentation {
        let fontReferenceSize: CGFloat
        let usesCompactLayout: Bool
        let glyphs: [GlyphPresentation]
    }

    private struct Keyframe {
        let progress: CGFloat
        let value: CGFloat
    }

    private static let imageSize = NSSize(width: 27, height: 15)
    private static let referenceScale: CGFloat = 13.2 / 39
    private static let emptyColor = NSColor(
        srgbRed: 0xB8 / 255,
        green: 0xB9 / 255,
        blue: 0xBA / 255,
        alpha: 1
    )
    private static let labelColor = NSColor.white
    private static let plugSymbol: NSImage? = {
        guard let image = NSImage(
            systemSymbolName: "powerplug.fill",
            accessibilityDescription: nil
        ) else {
            return nil
        }
        let size = NSImage.SymbolConfiguration(pointSize: 5.4, weight: .semibold)
        let color = NSImage.SymbolConfiguration(paletteColors: [labelColor])
        return image.withSymbolConfiguration(size.applying(color))
    }()

    static func image(
        state: StatusBarBatteryIconState,
        transition: StatusBarBatteryIconTransition = .steady
    ) -> NSImage {
        let clampedLevel = min(max(state.level ?? 0, 0), 1)
        let levelText = state.level.map {
            String(Int((min(max($0, 0), 1) * 100).rounded()))
        } ?? "--"
        let appearance = appearance(for: state)
        let labelPresentation = labelPresentation(
            state: state,
            transition: transition
        )

        let image = NSImage(size: imageSize, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            context.saveGState()
            context.setShouldAntialias(true)

            let bodyRect = NSRect(
                x: 0.5,
                y: 0.9,
                width: 69.5 * referenceScale,
                height: 39 * referenceScale
            )
            let bodyPath = NSBezierPath(
                roundedRect: bodyRect,
                xRadius: 12 * referenceScale,
                yRadius: 12 * referenceScale
            )

            let terminalRect = NSRect(
                x: bodyRect.maxX,
                y: bodyRect.minY + 12 * referenceScale,
                width: 7 * referenceScale,
                height: 15 * referenceScale
            )
            let terminalPath = rightRoundedTerminalPath(
                in: terminalRect,
                cornerRadius: 3.5 * referenceScale
            )

            context.setFillColor(emptyColor.cgColor)
            terminalPath.fill()
            bodyPath.fill()

            let fillWidth = bodyRect.width * clampedLevel
            if fillWidth > 0 {
                let fillRect = NSRect(
                    x: bodyRect.minX,
                    y: bodyRect.minY,
                    width: fillWidth,
                    height: bodyRect.height
                )
                context.saveGState()
                bodyPath.addClip()
                context.setFillColor(appearance.fillColor.cgColor)
                NSBezierPath(rect: fillRect).fill()
                context.restoreGState()
            }

            drawContents(
                levelText,
                presentation: labelPresentation,
                bodyRect: bodyRect,
                bodyPath: bodyPath,
                context: context
            )

            context.restoreGState()
            return true
        }

        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription(
            state: state,
            percentageText: levelText
        )
        return image
    }

    private static func appearance(for state: StatusBarBatteryIconState) -> Appearance {
        switch state.connectionGlyph {
        case .bolt:
            return .externalPower
        case .plug:
            return .normal
        case .none:
            break
        }

        if let level = state.level, level < 0.2 {
            return .critical
        }
        if state.isLowPowerModeEnabled {
            return .lowPower
        }
        return .normal
    }

    private static func labelPresentation(
        state: StatusBarBatteryIconState,
        transition: StatusBarBatteryIconTransition
    ) -> LabelPresentation {
        switch transition {
        case .steady:
            let compact = state.connectionGlyph != .none
            let glyphs = compact
                ? [GlyphPresentation(glyph: state.connectionGlyph, scale: 1, opacity: 1)]
                : []
            return LabelPresentation(
                fontReferenceSize: compact ? 27 : 34,
                usesCompactLayout: compact,
                glyphs: glyphs
            )

        case let .enteringConnection(labelProgress, glyphProgress):
            let labelTiming = UnitBezier(x1: 0.16, y1: 0.92, x2: 0.24, y2: 1)
            let glyphTiming = UnitBezier(x1: 0.22, y1: 0.8, x2: 0.28, y2: 1)
            return LabelPresentation(
                fontReferenceSize: keyframedValue(
                    at: labelProgress,
                    frames: [
                        Keyframe(progress: 0, value: 34),
                        Keyframe(progress: 0.58, value: 25.8),
                        Keyframe(progress: 0.8, value: 27.7),
                        Keyframe(progress: 1, value: 27),
                    ],
                    timing: labelTiming
                ),
                usesCompactLayout: true,
                glyphs: [
                    GlyphPresentation(
                        glyph: state.connectionGlyph,
                        scale: keyframedValue(
                            at: glyphProgress,
                            frames: [
                                Keyframe(progress: 0, value: 0.35),
                                Keyframe(progress: 0.52, value: 1.18),
                                Keyframe(progress: 0.78, value: 0.92),
                                Keyframe(progress: 1, value: 1),
                            ],
                            timing: glyphTiming
                        ),
                        opacity: keyframedValue(
                            at: glyphProgress,
                            frames: [
                                Keyframe(progress: 0, value: 0),
                                Keyframe(progress: 0.52, value: 1),
                                Keyframe(progress: 1, value: 1),
                            ],
                            timing: glyphTiming
                        )
                    ),
                ]
            )

        case let .leavingConnection(previousGlyph, labelProgress, glyphProgress):
            let labelTiming = UnitBezier(x1: 0.16, y1: 0.92, x2: 0.24, y2: 1)
            let glyphTiming = UnitBezier(x1: 0.4, y1: 0, x2: 0.7, y2: 0.2)
            return LabelPresentation(
                fontReferenceSize: keyframedValue(
                    at: labelProgress,
                    frames: [
                        Keyframe(progress: 0, value: 27),
                        Keyframe(progress: 0.58, value: 35.2),
                        Keyframe(progress: 0.8, value: 33.3),
                        Keyframe(progress: 1, value: 34),
                    ],
                    timing: labelTiming
                ),
                usesCompactLayout: false,
                glyphs: [
                    GlyphPresentation(
                        glyph: previousGlyph,
                        scale: keyframedValue(
                            at: glyphProgress,
                            frames: [
                                Keyframe(progress: 0, value: 1),
                                Keyframe(progress: 0.48, value: 0.82),
                                Keyframe(progress: 1, value: 0.35),
                            ],
                            timing: glyphTiming
                        ),
                        opacity: keyframedValue(
                            at: glyphProgress,
                            frames: [
                                Keyframe(progress: 0, value: 1),
                                Keyframe(progress: 0.48, value: 1),
                                Keyframe(progress: 1, value: 0),
                            ],
                            timing: glyphTiming
                        )
                    ),
                ]
            )

        case let .swappingConnectionGlyph(previousGlyph, progress):
            let timing = UnitBezier(x1: 0.4, y1: 0, x2: 0.2, y2: 1)
            let eased = timing.solve(min(max(progress, 0), 1))
            return LabelPresentation(
                fontReferenceSize: 27,
                usesCompactLayout: true,
                glyphs: [
                    GlyphPresentation(
                        glyph: previousGlyph,
                        scale: 1 - 0.25 * eased,
                        opacity: 1 - eased
                    ),
                    GlyphPresentation(
                        glyph: state.connectionGlyph,
                        scale: 0.7 + 0.3 * eased,
                        opacity: eased
                    ),
                ]
            )
        }
    }

    private static func drawContents(
        _ text: String,
        presentation: LabelPresentation,
        bodyRect: NSRect,
        bodyPath: NSBezierPath,
        context: CGContext
    ) {
        let font = NSFont.systemFont(
            ofSize: presentation.fontReferenceSize * referenceScale,
            weight: .medium
        )
        let finalCompactFont = NSFont.systemFont(
            ofSize: 27 * referenceScale,
            weight: .medium
        )
        let attributedText = attributedLevelText(text, font: font)
        let finalCompactText = attributedLevelText(text, font: finalCompactFont)
        let measuredSize = attributedText.size()
        let finalCompactSize = finalCompactText.size()

        let compactStartX = bodyRect.midX
            + 3.5 * referenceScale
            - (finalCompactSize.width + 9.5 * referenceScale) / 2
        let textX = presentation.usesCompactLayout
            ? compactStartX
            : bodyRect.midX - measuredSize.width / 2
        let textY = bodyRect.midY
            - measuredSize.height / 2
            + 0.35
            - 2 * referenceScale
            + (presentation.usesCompactLayout ? referenceScale : 0)

        context.saveGState()
        bodyPath.addClip()
        attributedText.draw(at: NSPoint(x: textX, y: textY))
        context.restoreGState()

        let glyphX = compactStartX + finalCompactSize.width + 0.5 * referenceScale
        for glyph in presentation.glyphs where glyph.glyph != .none && glyph.opacity > 0 {
            drawGlyph(
                glyph,
                originX: glyphX,
                bodyRect: bodyRect,
                context: context
            )
        }
    }

    private static func attributedLevelText(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: labelColor,
                .strokeColor: labelColor,
                .strokeWidth: -2.05,
                .kern: 0.5 * referenceScale,
            ]
        )
    }

    private static func drawGlyph(
        _ presentation: GlyphPresentation,
        originX: CGFloat,
        bodyRect: NSRect,
        context: CGContext
    ) {
        switch presentation.glyph {
        case .none:
            return
        case .bolt:
            let path = chargingBoltPath(
                originX: originX,
                bodyRect: bodyRect,
                scale: presentation.scale
            )
            context.saveGState()
            context.setAlpha(presentation.opacity)
            context.setFillColor(labelColor.cgColor)
            path.fill()
            context.restoreGState()
        case .plug:
            drawPlug(
                originX: originX,
                bodyRect: bodyRect,
                scale: presentation.scale,
                opacity: presentation.opacity,
                context: context
            )
        }
    }

    private static func chargingBoltPath(
        originX: CGFloat,
        bodyRect: NSRect,
        scale boltScale: CGFloat
    ) -> NSBezierPath {
        let points: [NSPoint] = [
            NSPoint(x: 4, y: 0),
            NSPoint(x: 0, y: 7),
            NSPoint(x: 3, y: 7),
            NSPoint(x: 2, y: 12),
            NSPoint(x: 9, y: 4.5),
            NSPoint(x: 5.6, y: 4.5),
            NSPoint(x: 7, y: 0),
        ]
        let center = NSPoint(x: 4.5, y: 6)
        let boltTopY = bodyRect.maxY - 14 * referenceScale

        func mappedPoint(_ point: NSPoint) -> NSPoint {
            let scaledX = center.x + (point.x - center.x) * boltScale
            let scaledY = center.y + (point.y - center.y) * boltScale
            return NSPoint(
                x: originX + scaledX * referenceScale,
                y: boltTopY - scaledY * referenceScale
            )
        }

        let path = NSBezierPath()
        path.move(to: mappedPoint(points[0]))
        for point in points.dropFirst() {
            path.line(to: mappedPoint(point))
        }
        path.close()
        return path
    }

    private static func drawPlug(
        originX: CGFloat,
        bodyRect: NSRect,
        scale: CGFloat,
        opacity: CGFloat,
        context: CGContext
    ) {
        let baseRect = NSRect(
            x: originX + 0.25 * referenceScale,
            y: bodyRect.midY - 7.2 * referenceScale,
            width: 8.5 * referenceScale,
            height: 14.4 * referenceScale
        )
        let rect = scaledRect(baseRect, scale: scale)

        if let plugSymbol {
            context.saveGState()
            context.setAlpha(opacity)
            plugSymbol.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            context.restoreGState()
            return
        }

        // Fallback for systems that do not provide the SF Symbol.
        let fallback = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.24, yRadius: rect.width * 0.24)
        context.saveGState()
        context.setAlpha(opacity)
        context.setFillColor(labelColor.cgColor)
        fallback.fill()
        context.restoreGState()
    }

    private static func scaledRect(_ rect: NSRect, scale: CGFloat) -> NSRect {
        NSRect(
            x: rect.midX - rect.width * scale / 2,
            y: rect.midY - rect.height * scale / 2,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private static func keyframedValue(
        at rawProgress: CGFloat,
        frames: [Keyframe],
        timing: UnitBezier
    ) -> CGFloat {
        guard let first = frames.first, let last = frames.last else {
            return 0
        }

        let progress = min(max(rawProgress, 0), 1)
        if progress <= first.progress { return first.value }
        if progress >= last.progress { return last.value }

        for (start, end) in zip(frames, frames.dropFirst()) where progress <= end.progress {
            let segmentLength = end.progress - start.progress
            let localProgress = segmentLength > 0
                ? (progress - start.progress) / segmentLength
                : 1
            let easedProgress = timing.solve(localProgress)
            return start.value + (end.value - start.value) * easedProgress
        }

        return last.value
    }

    private static func accessibilityDescription(
        state: StatusBarBatteryIconState,
        percentageText: String
    ) -> String {
        guard state.level != nil else {
            return "正在读取电池电量"
        }

        let status: String
        switch state.connectionGlyph {
        case .bolt:
            status = "已接入电源"
        case .plug:
            status = "已接入电源，充电已暂停"
        case .none:
            switch appearance(for: state) {
            case .lowPower:
                status = "低电量模式"
            case .critical:
                status = "电量不足"
            case .normal, .externalPower:
                status = "电池供电"
            }
        }
        return "\(status)，电池电量 \(percentageText)%"
    }

    private static func rightRoundedTerminalPath(
        in rect: NSRect,
        cornerRadius: CGFloat
    ) -> NSBezierPath {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        path.appendArc(
            withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: -90,
            endAngle: 0,
            clockwise: false
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
        path.appendArc(
            withCenter: NSPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: 0,
            endAngle: 90,
            clockwise: false
        )
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }
}

@MainActor
final class StatusBarBatteryIconAnimator {
    private enum ActiveTransition {
        case enteringConnection(startedAt: TimeInterval)
        case leavingConnection(
            previousGlyph: StatusBarBatteryConnectionGlyph,
            startedAt: TimeInterval
        )
        case swappingConnectionGlyph(
            previousGlyph: StatusBarBatteryConnectionGlyph,
            startedAt: TimeInterval
        )
    }

    private weak var button: NSStatusBarButton?
    private var latestState: StatusBarBatteryIconState?
    private var previousGlyph: StatusBarBatteryConnectionGlyph?
    private var activeTransition: ActiveTransition?
    private var timer: Timer?

    func attach(to button: NSStatusBarButton) {
        self.button = button
        if let latestState, activeTransition == nil {
            render(state: latestState, transition: .steady)
        }
    }

    func update(state: StatusBarBatteryIconState) {
        latestState = state

        guard let previousGlyph else {
            self.previousGlyph = state.connectionGlyph
            render(state: state, transition: .steady)
            return
        }

        guard previousGlyph != state.connectionGlyph else {
            if activeTransition == nil {
                render(state: state, transition: .steady)
            }
            return
        }

        self.previousGlyph = state.connectionGlyph
        if previousGlyph == .none {
            startTransition(.enteringConnection(startedAt: currentUptime))
        } else if state.connectionGlyph == .none {
            startTransition(
                .leavingConnection(
                    previousGlyph: previousGlyph,
                    startedAt: currentUptime
                )
            )
        } else {
            startTransition(
                .swappingConnectionGlyph(
                    previousGlyph: previousGlyph,
                    startedAt: currentUptime
                )
            )
        }
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
        activeTransition = nil
    }

    private var currentUptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func startTransition(_ transition: ActiveTransition) {
        timer?.invalidate()
        activeTransition = transition
        renderAnimationFrame()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderAnimationFrame()
            }
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func renderAnimationFrame() {
        guard let latestState, let activeTransition else {
            return
        }

        let transition: StatusBarBatteryIconTransition
        let isComplete: Bool

        switch activeTransition {
        case let .enteringConnection(startedAt):
            let elapsed = currentUptime - startedAt
            let labelProgress = min(max(elapsed / 0.42, 0), 1)
            let glyphProgress = min(max(elapsed / 0.38, 0), 1)
            transition = .enteringConnection(
                labelProgress: labelProgress,
                glyphProgress: glyphProgress
            )
            isComplete = labelProgress >= 1 && glyphProgress >= 1

        case let .leavingConnection(previousGlyph, startedAt):
            let elapsed = currentUptime - startedAt
            let labelProgress = min(max(elapsed / 0.42, 0), 1)
            let glyphProgress = min(max(elapsed / 0.26, 0), 1)
            transition = .leavingConnection(
                previousGlyph: previousGlyph,
                labelProgress: labelProgress,
                glyphProgress: glyphProgress
            )
            isComplete = labelProgress >= 1 && glyphProgress >= 1

        case let .swappingConnectionGlyph(previousGlyph, startedAt):
            let progress = min(max((currentUptime - startedAt) / 0.26, 0), 1)
            transition = .swappingConnectionGlyph(
                previousGlyph: previousGlyph,
                progress: progress
            )
            isComplete = progress >= 1
        }

        render(state: latestState, transition: transition)

        if isComplete {
            timer?.invalidate()
            timer = nil
            self.activeTransition = nil
            render(state: latestState, transition: .steady)
        }
    }

    private func render(
        state: StatusBarBatteryIconState,
        transition: StatusBarBatteryIconTransition
    ) {
        button?.image = StatusBarBatteryIconRenderer.image(
            state: state,
            transition: transition
        )
    }
}

private struct UnitBezier {
    let x1: CGFloat
    let y1: CGFloat
    let x2: CGFloat
    let y2: CGFloat

    func solve(_ rawX: CGFloat) -> CGFloat {
        let x = min(max(rawX, 0), 1)
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        var parameter = x

        for _ in 0..<12 {
            let estimate = sample(parameter, firstControl: x1, secondControl: x2)
            if abs(estimate - x) < 0.0001 {
                break
            }
            if estimate < x {
                lower = parameter
            } else {
                upper = parameter
            }
            parameter = (lower + upper) / 2
        }

        return sample(parameter, firstControl: y1, secondControl: y2)
    }

    private func sample(
        _ parameter: CGFloat,
        firstControl: CGFloat,
        secondControl: CGFloat
    ) -> CGFloat {
        let inverse = 1 - parameter
        return 3 * inverse * inverse * parameter * firstControl
            + 3 * inverse * parameter * parameter * secondControl
            + parameter * parameter * parameter
    }
}
