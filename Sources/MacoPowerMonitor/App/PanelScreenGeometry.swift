import Foundation

/// Pure screen-resolution geometry, deliberately free of `NSScreen` so it can be
/// exercised against synthetic display layouts without attached hardware.
///
/// `NSRect.contains` treats the max edges as exclusive, but a menu bar click can
/// land exactly on `frame.maxY`: the topmost pixel row of a display converts from
/// `cgY == 0` to `appkitY == frame.maxY`. When another display is docked directly
/// above, that row is also the upper display's `minY`, so plain `contains` hands
/// the click to the wrong screen. Resolution therefore uses inclusive bounds and
/// disambiguates shared edges through the menu bar band, which is sound because
/// every click that reaches this code path originated in a menu bar.
enum PanelScreenGeometry {
    struct Layout {
        let frame: NSRect
        let visibleFrame: NSRect

        init(frame: NSRect, visibleFrame: NSRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }

        /// Vertical band reserved for the menu bar, i.e. the gap between the top
        /// of the usable area and the top of the display.
        var menuBarBandContains: (CGFloat) -> Bool {
            let lowerBound = visibleFrame.maxY
            let upperBound = frame.maxY
            return { value in value >= lowerBound && value <= upperBound }
        }
    }

    enum Resolution: Equatable {
        /// Exactly one display owns the point.
        case unique
        /// Several displays share the point; the menu bar band picked the winner.
        case sharedEdgeMenuBar
        /// Several displays share the point and none owns a matching menu bar
        /// band; the nearest top edge picked the winner.
        case sharedEdgeNearestTopEdge
        /// No display owns the point; nearest display by clamped distance.
        case fallbackNearest
    }

    static func indexOfScreen(containing point: NSPoint, screens: [Layout]) -> Int? {
        resolve(point: point, screens: screens)?.index
    }

    static func resolve(point: NSPoint, screens: [Layout]) -> (index: Int, resolution: Resolution)? {
        guard !screens.isEmpty else { return nil }

        let candidates = screens.indices.filter { containsInclusive(screens[$0].frame, point) }

        if candidates.count == 1, let only = candidates.first {
            return (only, .unique)
        }

        if candidates.count > 1 {
            let menuBarMatches = candidates.filter { screens[$0].menuBarBandContains(point.y) }
            let pool = menuBarMatches.isEmpty ? candidates : menuBarMatches
            guard let winner = nearestTopEdge(to: point, among: pool, screens: screens) else {
                return nil
            }
            return (winner, menuBarMatches.isEmpty ? .sharedEdgeNearestTopEdge : .sharedEdgeMenuBar)
        }

        guard let nearest = screens.indices.min(by: { lhs, rhs in
            clampedDistanceSquared(from: point, to: screens[lhs].frame)
                < clampedDistanceSquared(from: point, to: screens[rhs].frame)
        }) else {
            return nil
        }

        return (nearest, .fallbackNearest)
    }

    /// `NSRect.contains` excludes `maxX`/`maxY`. Menu bar clicks land on exactly
    /// those edges, so both axes include their end points here.
    static func containsInclusive(_ rect: NSRect, _ point: NSPoint) -> Bool {
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }

    /// Distance to the nearest point on the rectangle rather than to its centre.
    /// Centre distance mis-ranks displays of unequal size, e.g. a 1920x1080
    /// external panel against a 1470x956 built-in one.
    static func clampedDistanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }

    private static func nearestTopEdge(
        to point: NSPoint,
        among pool: [Int],
        screens: [Layout]
    ) -> Int? {
        pool.min(by: { lhs, rhs in
            abs(point.y - screens[lhs].frame.maxY) < abs(point.y - screens[rhs].frame.maxY)
        })
    }
}
