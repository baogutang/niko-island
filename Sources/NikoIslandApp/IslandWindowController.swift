import AppKit
import NikoCore
import SwiftUI

/// Owns the window the island lives in: a fixed, transparent canvas pinned to
/// the top centre of the screen, above the menu bar. The window lets every
/// click through except while the pointer is on the island itself, so the
/// island can change size freely without the window ever getting in the way.
@MainActor
final class IslandWindowController: NSObject {
    private let model: AppModel
    private let panel: IslandPanel
    private var metrics: IslandMetrics
    /// The island's rectangle inside the canvas (top-left origin), as SwiftUI laid it out.
    private var islandRect: CGRect = .zero
    private var monitors: [Any] = []
    private var pointerInside = false
    private var openTimer: DispatchWorkItem?
    private var closeTimer: DispatchWorkItem?
    private let traceLayout = ProcessInfo.processInfo.environment["NIKO_ISLAND_DEBUG"] != nil

    init(model: AppModel) {
        self.model = model
        let screen = IslandWindowController.targetScreen()
        self.metrics = screen.map(IslandMetrics.init(screen:)) ?? .plain
        self.panel = IslandPanel(contentRect: NSRect(origin: .zero, size: IslandMetrics.canvas),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar                     // above the menu bar (set after isFloatingPanel, which resets the level)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                      // the island draws its own
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true          // keys only when a text field asks
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        installContent()
        place()
        installMonitors()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    /// The display with a camera housing if there is one, else the one with the menu bar.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private func installContent() {
        let root = IslandView(model: model, metrics: metrics) { [weak self] rect in
            guard let self else { return }
            self.islandRect = rect
            self.pointerMoved()
            if self.traceLayout {
                // For the launch smoke test: proves the live window lays the island out where we think.
                self.model.log.info("island frame x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height)) expanded=\(self.model.isExpanded)")
            }
        }
        panel.contentView = NSHostingView(rootView: root)
    }

    private func place() {
        guard let screen = IslandWindowController.targetScreen() else { return }
        let size = IslandMetrics.canvas
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    @objc private func screensChanged() {
        let updated = IslandWindowController.targetScreen().map(IslandMetrics.init(screen:)) ?? .plain
        if updated != metrics {
            metrics = updated
            installContent()
        }
        place()
    }

    // MARK: Pointer tracking

    private func installMonitors() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.pointerMoved() }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            if let self { MainActor.assumeIsolated { self.pointerMoved() } }
            return event
        }) { monitors.append(monitor) }
        // A click anywhere else puts the island away. Nothing pending is decided by that.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.model.isExpanded, !self.pointerInside { self.model.collapse() }
            }
        }) { monitors.append(monitor) }
    }

    /// The island's rectangle in screen coordinates.
    private var islandScreenRect: CGRect {
        guard islandRect != .zero else { return .zero }
        let frame = panel.frame
        return CGRect(x: frame.minX + islandRect.minX, y: frame.maxY - islandRect.maxY,
                      width: islandRect.width, height: islandRect.height)
    }

    private func pointerMoved() {
        let rect = islandScreenRect
        let inside = rect != .zero && rect.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        guard inside != pointerInside else { return }
        pointerInside = inside
        panel.ignoresMouseEvents = !inside
        if inside {
            closeTimer?.cancel()
            guard !model.isExpanded, model.settings.expandOnHover else { return }
            schedule(&openTimer, after: 0.16) { [weak self] in
                guard let self, self.pointerInside else { return }
                self.model.expand(.hover)
            }
        } else {
            openTimer?.cancel()
            guard model.isExpanded, model.expandReason == .hover else { return }
            schedule(&closeTimer, after: 0.45) { [weak self] in
                guard let self, !self.pointerInside, self.model.expandReason == .hover else { return }
                self.model.collapse()
            }
        }
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        slot?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        slot = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

/// Borderless panels refuse key status by default; the question form's text field needs it.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit keeps ordinary windows below the menu bar. The island belongs on
    /// top of it, flush with the edge of the screen, so the frame is left alone.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
