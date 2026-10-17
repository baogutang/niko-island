import CoreGraphics
import Foundation

/// What the island does where there is no menu bar (full-screen Spaces).
public enum FullScreenPolicy: String, Sendable, CaseIterable {
    /// Behave like the menu bar: gone in full screen, and it comes down with
    /// the menu bar when the pointer reveals it.
    case followMenuBar
    /// Stay visible over full-screen apps.
    case always
    /// Never show over full-screen apps.
    case never
}

/// Finds the menu bar among the window server's on-screen windows.
///
/// Every Space has its own menu bar window. While it is hidden (a full-screen
/// Space, or the "automatically hide the menu bar" setting) it is not on
/// screen; while it slides in or out its bounds move, one step per frame. That
/// makes the window list the one place that says where the menu bar really is.
public enum MenuBarProbe {
    public struct Window: Sendable, Equatable {
        public var layer: Int
        public var bounds: CGRect

        public init(layer: Int, bounds: CGRect) {
            self.layer = layer
            self.bounds = bounds
        }
    }

    /// `CGWindowLevelForKey(.mainMenuWindow)`.
    public static let menuBarLayer = 24

    /// Vertical position of the menu bar on `display`, relative to where it
    /// rests: 0 when fully shown, negative while it slides, nil when it is not
    /// on screen at all. Coordinates are Quartz global (origin top left).
    public static func offset(onScreen windows: [Window], display: CGRect) -> CGFloat? {
        var best: CGFloat?
        for window in windows where window.layer == menuBarLayer {
            let bounds = window.bounds
            // The menu bar spans its display and is a couple of dozen points tall.
            guard bounds.height >= 16, bounds.height <= 80,
                  abs(bounds.minX - display.minX) <= 2, bounds.width >= display.width - 2 else { continue }
            let offset = bounds.minY - display.minY
            guard offset <= 1, offset > -400 else { continue }
            best = max(best ?? -.greatestFiniteMagnitude, min(0, offset))
        }
        return best
    }
}

/// Where the island should be right now.
public struct IslandPlacement: Equatable, Sendable {
    public enum Surface: Sendable, Equatable {
        /// The window that lives on desktop Spaces and slides with them.
        case desktop
        /// The window that may sit over a full-screen app.
        case overlay
        case hidden
    }

    public var surface: Surface
    /// How far above its resting place the island is pushed (0 = at rest).
    public var lift: CGFloat

    public init(surface: Surface, lift: CGFloat) {
        self.surface = surface
        self.lift = lift
    }
}

public enum IslandFollow {
    public struct Input: Sendable {
        /// The desktop window is on the active Space (false in a full-screen Space).
        public var onDesktopSpace: Bool
        /// From `MenuBarProbe.offset`.
        public var barOffset: CGFloat?
        /// The probe has found the menu bar at rest at least once, so "not on
        /// screen" can be believed.
        public var barTrusted: Bool
        /// How long the menu bar has been missing from the screen.
        public var barMissingFor: TimeInterval
        /// The island is open, under the pointer, or showing something that
        /// must not slide away.
        public var pinned: Bool
        public var policy: FullScreenPolicy
        /// Lift at which nothing of the island is left on screen.
        public var hideDistance: CGFloat
        /// The lift currently applied on the desktop window.
        public var currentDesktopLift: CGFloat

        public init(onDesktopSpace: Bool, barOffset: CGFloat?, barTrusted: Bool, barMissingFor: TimeInterval = 0,
                    pinned: Bool, policy: FullScreenPolicy, hideDistance: CGFloat, currentDesktopLift: CGFloat = 0) {
            self.onDesktopSpace = onDesktopSpace
            self.barOffset = barOffset
            self.barTrusted = barTrusted
            self.barMissingFor = barMissingFor
            self.pinned = pinned
            self.policy = policy
            self.hideDistance = hideDistance
            self.currentDesktopLift = currentDesktopLift
        }
    }

    /// A menu bar that vanished without sliding (a Space change in progress)
    /// is only believed after this long, so the island never jumps mid-swipe.
    public static let missingGrace: TimeInterval = 0.35

    public static func placement(_ input: Input) -> IslandPlacement {
        let hidden = max(0, input.hideDistance)
        func lift(for offset: CGFloat) -> CGFloat { min(hidden, max(0, -offset)) }

        if input.onDesktopSpace {
            // On a desktop the window server already moves the island with the
            // Space. All that is left to follow is an auto-hiding menu bar.
            guard input.policy == .followMenuBar, input.barTrusted, !input.pinned else {
                return IslandPlacement(surface: .desktop, lift: 0)
            }
            if let offset = input.barOffset { return IslandPlacement(surface: .desktop, lift: lift(for: offset)) }
            if input.barMissingFor < missingGrace { return IslandPlacement(surface: .desktop, lift: input.currentDesktopLift) }
            return IslandPlacement(surface: .desktop, lift: hidden)
        }

        // A full-screen Space: the desktop window is not here.
        if input.pinned || input.policy == .always { return IslandPlacement(surface: .overlay, lift: 0) }
        if input.policy == .never { return IslandPlacement(surface: .hidden, lift: hidden) }
        if let offset = input.barOffset {
            let amount = lift(for: offset)
            return amount >= hidden ? IslandPlacement(surface: .hidden, lift: hidden) : IslandPlacement(surface: .overlay, lift: amount)
        }
        return IslandPlacement(surface: .hidden, lift: hidden)
    }
}

/// When the island follows the menu bar at display rate instead of its slow heartbeat.
///
/// Only while something moves: the bar sliding, or the island moving with it. A bar that
/// is shown and may hide by itself (the island is riding it) goes only after the pointer
/// leaves it, or after a click closes its menu, so that is when it is watched closely.
/// Watching it at display rate the whole time it was shown cost 10-20 % CPU all day where
/// it never hides (a notched display's full-screen apps).
public struct BarWatch: Sendable {
    /// How long to follow closely after the bar or the island moved.
    public static let moving: TimeInterval = 0.4
    /// After the pointer reaches the top edge, where a hidden bar comes down from.
    public static let reveal: TimeInterval = 0.6
    /// While the pointer is near a bar that may hide, and for this long after it left.
    public static let leaving: TimeInterval = 1.2

    /// The island rides a shown menu bar that may hide by itself.
    public private(set) var ridingBar = false
    private var pointerNearBar = false

    public init() {}

    /// After a pass: how long to follow closely, if at all.
    public mutating func passed(moving: Bool, ridingBar: Bool) -> TimeInterval? {
        self.ridingBar = ridingBar
        return moving ? Self.moving : nil
    }

    /// After the pointer moved: how long to follow closely, if at all.
    public mutating func pointerMoved(atTopEdge: Bool, nearBar: Bool) -> TimeInterval? {
        defer { pointerNearBar = nearBar }
        if ridingBar, nearBar || pointerNearBar { return Self.leaving }
        return atTopEdge ? Self.reveal : nil
    }

    /// After a click anywhere: one that closes a menu lets a bar that may hide go.
    public func clicked() -> TimeInterval? { ridingBar ? Self.leaving : nil }
}
