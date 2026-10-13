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

    func path(in rect: CGRect) -> Path {
        let e = min(ear, rect.width / 4)
        let r = min(radius, (rect.width - 2 * e) / 2, rect.height - e)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + e, y: rect.minY + e), control: CGPoint(x: rect.minX + e, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + e, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + e + r, y: rect.maxY), control: CGPoint(x: rect.minX + e, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - e - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - e, y: rect.maxY - r), control: CGPoint(x: rect.maxX - e, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - e, y: rect.minY + e))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - e, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct IslandFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
