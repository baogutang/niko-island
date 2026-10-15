import AppKit
import SwiftUI

/// Where the island sits and how big its resting state is on a given screen.
struct IslandMetrics: Equatable, Sendable {
    /// The display has a camera housing the island can grow out of.
    var hasNotch: Bool
    /// Width of the camera housing (0 without one).
    var notchWidth: CGFloat
    /// Height of the menu-bar band: the collapsed island is exactly this tall.
    var bandHeight: CGFloat

    static let expandedWidth: CGFloat = 640
    static let wing: CGFloat = 46
    /// The transparent window the island is drawn in.
    static let canvas = CGSize(width: 780, height: 760)

    static let plain = IslandMetrics(hasNotch: false, notchWidth: 0, bandHeight: 28)
    /// A typical notched laptop display, for documentation images.
    static let notched = IslandMetrics(hasNotch: true, notchWidth: 186, bandHeight: 34)

    @MainActor
    init(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchWidth = max(120, screen.frame.width - left.width - right.width)
            bandHeight = top
        } else {
            hasNotch = false
            notchWidth = 0
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            bandHeight = min(max(menuBar, 26), 34)
        }
    }

    init(hasNotch: Bool, notchWidth: CGFloat, bandHeight: CGFloat) {
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.bandHeight = bandHeight
    }

    /// Width of the collapsed island for the given amount of text.
    func collapsedWidth(contentWidth: CGFloat) -> CGFloat {
        if hasNotch { return notchWidth + IslandMetrics.wing * 2 }
        return min(max(contentWidth, 96), 360)
    }
}

/// The island's outline: flush with the top of the screen, flaring into small
/// concave "ears" where it meets the edge, with generously rounded bottom corners.
///
/// The bottom corners are continuous-curvature corners (the curvature ramps
/// up instead of jumping from straight to round), and each ear is a cubic
/// Bézier that leaves the screen edge along it and meets the island's side
/// along that side: the island grows out of the edge instead of being stuck
/// to it. Ear and radius animate, so the closed tab, the open island and a
/// card are one body changing shape.
struct IslandShape: Shape {
    var ear: CGFloat = 8
    var radius: CGFloat = 26

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, radius) }
        set {
            ear = newValue.first
            radius = newValue.second
        }
    }

    /// A continuous corner of radius r runs this far along each side (the curvature ramps in over it).
    static let reach: CGFloat = 1.52866

    func path(in rect: CGRect) -> Path {
        guard rect.width > 1, rect.height > 1 else { return Path(rect) }
        let k = Self.reach
        let e = max(0, min(ear, rect.width / 4))
        // The ears, a little taller than wide so they read as a fillet, not a notch; the corners fit below them.
        let height = e > 0.5 ? min(e * 1.3, rect.height * 0.45) : 0
        let r = max(0, min(radius, (rect.width - 2 * e) / (2 * k), (rect.height - height) / k))
        let left = rect.minX + e, right = rect.maxX - e, top = rect.minY, bottom = rect.maxY

        // Drawn as one outline rather than a union of shapes: no boolean operation on every frame.
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: top))
        if height > 0 {
            // Leaves the screen edge along it, meets the island's side along that side.
            path.addCurve(to: CGPoint(x: left, y: top + height),
                          control1: CGPoint(x: rect.minX + e * 0.62, y: top),
                          control2: CGPoint(x: left, y: top + height * 0.38))
        } else {
            path.addLine(to: CGPoint(x: left, y: top))
        }
        path.addLine(to: CGPoint(x: left, y: bottom - k * r))
        Self.corner(&path, at: CGPoint(x: left, y: bottom), r: r, dx: 1, dy: -1, vertical: true)
        path.addLine(to: CGPoint(x: right - k * r, y: bottom))
        Self.corner(&path, at: CGPoint(x: right, y: bottom), r: r, dx: -1, dy: -1, vertical: false)
        path.addLine(to: CGPoint(x: right, y: top + height))
        if height > 0 {
            path.addCurve(to: CGPoint(x: rect.maxX, y: top),
                          control1: CGPoint(x: right, y: top + height * 0.38),
                          control2: CGPoint(x: rect.maxX - e * 0.62, y: top))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: top))
        }
        path.closeSubpath()
        return path
    }

    /// One continuous corner (the three cubics of the usual "squircle" corner) at `point`.
    /// `dx`, `dy` point from the corner into the shape; `vertical`: arriving along the vertical side.
    private static func corner(_ path: inout Path, at point: CGPoint, r: CGFloat, dx: CGFloat, dy: CGFloat, vertical: Bool) {
        guard r > 0.01 else {
            path.addLine(to: point)
            return
        }
        // Offsets along the side the corner starts on (a) and the other one (b), in radii.
        let segments: [((CGFloat, CGFloat), (CGFloat, CGFloat), (CGFloat, CGFloat))] = [
            ((0, 1.08849), (0, 0.86840), (0.07491, 0.63149)),
            ((0.16906, 0.37282), (0.37282, 0.16906), (0.63149, 0.07491)),
            ((0.86840, 0), (1.08849, 0), (1.52866, 0)),
        ]
        func at(_ offset: (CGFloat, CGFloat)) -> CGPoint {
            // offset.0 runs along the side the corner ends on, offset.1 along the one it starts on.
            vertical ? CGPoint(x: point.x + dx * offset.0 * r, y: point.y + dy * offset.1 * r)
                     : CGPoint(x: point.x + dx * offset.1 * r, y: point.y + dy * offset.0 * r)
        }
        for (c1, c2, end) in segments {
            path.addCurve(to: at(end), control1: at(c1), control2: at(c2))
        }
    }
}

struct IslandFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
