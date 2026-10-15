import AppKit
import Combine
import NikoCore
import SwiftUI

/// Owns the windows the island lives in.
///
/// The island is meant to behave like part of the menu bar, and the menu bar
/// belongs to desktop Spaces: it slides away with the desktop when you move to
/// a full-screen app, slides back with it, stays put between desktops and in
/// Mission Control, and inside a full-screen Space it only comes down when the
/// pointer touches the top edge. Two windows give exactly that:
///
/// - the **desktop window** is on every desktop Space and on no full-screen
///   Space (`.fullScreenNone`), so the window server itself moves it with the
///   desktop, finger-tracked swipes included; `.stationary` keeps it in place
///   in Mission Control, like the menu bar.
/// - the **overlay window** may sit over a full-screen app. It is ordered out
///   unless the menu bar is revealed there (then it follows the bar frame by
///   frame), an agent needs a decision, or the user asked for "always".
///
/// Both are fixed transparent canvases pinned to the top centre of the screen
/// that let every click through except while the pointer is on the island.
@MainActor
final class IslandWindowController: NSObject {
    private let model: AppModel
    private let deskPanel: IslandPanel
    private let overlayPanel: IslandPanel
    private var metrics: IslandMetrics
    /// The island's rectangle inside each canvas (top-left origin), as SwiftUI laid it out.
    private var deskRect: CGRect = .zero
    private var overlayRect: CGRect = .zero
    private var monitors: [Any] = []
    private var pointerInside = false
    /// A two-finger pull on the island is under way, and how far it has gone.
    private var pulling = false
    private var pulled: CGFloat = 0
    private var openTimer: DispatchWorkItem?
    private var closeTimer: DispatchWorkItem?
    private let traceLayout = ProcessInfo.processInfo.environment["NIKO_ISLAND_DEBUG"] != nil

    // Menu bar following.
    private var baseOrigin: NSPoint = .zero
    private var displayBounds: CGRect = .zero
    private var screenTop: CGFloat = 0
    private var placement = IslandPlacement(surface: .desktop, lift: 0)
    private var deskLift: CGFloat = 0
    private var barTrusted = false
    private var barMissingSince: Date?
    /// The menu bar has been seen to hide on a desktop: the "automatically hide" setting is on.
    private var desktopBarHides = false
    private var slowTimer: Timer?
    private var fastTimer: Timer?
    private var fastUntil = Date.distantPast
    private var overlayLeaving = false
    private var overlaySettlesAt = Date.distantPast
    private var lastTrace = ""
    private var subscriptions: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        let screen = IslandWindowController.targetScreen(preference: model.settings.islandDisplay)
        self.metrics = screen.map(IslandMetrics.init(screen:)) ?? .plain
        self.deskPanel = IslandWindowController.makePanel()
        self.overlayPanel = IslandWindowController.makePanel()
        super.init()

        // On every desktop, never in a full-screen Space, unmoved by Mission Control.
        deskPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .stationary, .ignoresCycle]
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        installContent()
        // A finished-turn card is only worth showing where the island can be seen.
        model.islandIsVisible = { [weak self] in self?.placement.surface != .hidden }
        place()
        installMonitors()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // Opening, closing and a request arriving or leaving all change whether the island may slide away.
        Publishers.Merge(model.$isExpanded.map { _ in () }, model.$pending.map(\.count).removeDuplicates().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.quicken(for: 0.3)
                self?.follow()
            }
            .store(in: &subscriptions)
        model.$settings.map(\.islandDisplay).removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &subscriptions)
    }

    private static func makePanel() -> IslandPanel {
        let panel = IslandPanel(contentRect: NSRect(origin: .zero, size: IslandMetrics.canvas),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        panel.animationBehavior = .none
        return panel
    }

    func show() {
        deskPanel.orderFrontRegardless()
        startFollowing()
        follow()
    }

    /// The display the user picked by name; otherwise the one with a camera
    /// housing if there is one, else the one with the menu bar.
    static func targetScreen(preference: String = "auto") -> NSScreen? {
        if preference != "auto", let chosen = NSScreen.screens.first(where: { $0.localizedName == preference }) { return chosen }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private var screen: NSScreen? { IslandWindowController.targetScreen(preference: model.settings.islandDisplay) }

    private func installContent() {
        let desk = IslandView(model: model, metrics: metrics) { [weak self] rect in
            guard let self else { return }
            self.deskRect = rect
            self.pointerMoved()
            if self.traceLayout {
                // For the launch smoke test: proves the live window lays the island out where we think.
                self.model.log.info("island frame x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height)) expanded=\(self.model.isExpanded)")
            }
        }
        deskPanel.contentView = NSHostingView(rootView: desk)
        let overlay = IslandView(model: model, metrics: metrics) { [weak self] rect in
            guard let self else { return }
            self.overlayRect = rect
            self.pointerMoved()
        }
        overlayPanel.contentView = NSHostingView(rootView: overlay)
    }

    private func place() {
        guard let screen else { return }
        let size = IslandMetrics.canvas
        baseOrigin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        screenTop = screen.frame.maxY
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        }
        deskPanel.setFrame(NSRect(x: baseOrigin.x, y: baseOrigin.y + deskLift, width: size.width, height: size.height), display: true)
        overlayPanel.setFrame(NSRect(origin: baseOrigin, size: size), display: false)
    }

    @objc private func screensChanged() {
        let updated = screen.map(IslandMetrics.init(screen:)) ?? .plain
        // A full-screen Space has no menu bar to measure; keep the band the desktop gave us.
        if updated.hasNotch != metrics.hasNotch || updated.notchWidth != metrics.notchWidth
            || (deskPanel.isOnActiveSpace && updated != metrics) {
            metrics = updated
            installContent()
        }
        place()
        follow()
    }

    @objc private func spaceChanged() {
        quicken(for: 0.8)
        follow()
    }

    // MARK: Following the menu bar

    private func startFollowing() {
        guard slowTimer == nil else { return }
        // A quiet heartbeat; the fast timer only runs while something is moving.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        slowTimer = timer
    }

    /// Follow at display rate for a moment: something is about to move, or is moving.
    private func quicken(for duration: TimeInterval) {
        fastUntil = max(fastUntil, Date().addingTimeInterval(duration))
        guard fastTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.follow()
                if Date() > self.fastUntil {
                    self.fastTimer?.invalidate()
                    self.fastTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fastTimer = timer
    }

    /// The menu bar windows currently on screen.
    private func menuBarWindows() -> [MenuBarProbe.Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [MenuBarProbe.Window] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == MenuBarProbe.menuBarLayer,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { continue }
            out.append(MenuBarProbe.Window(layer: layer, bounds: bounds))
        }
        return out
    }

    /// The island must not slide away from under the user.
    private var pinned: Bool {
        if model.isExpanded || pointerInside { return true }
        return model.settings.attentionBreaksFullScreen && !model.pending.isEmpty
    }

    private func follow() {
        let now = Date()
        let onDesktop = deskPanel.isOnActiveSpace
        let offset = MenuBarProbe.offset(onScreen: menuBarWindows(), display: displayBounds)
        if let offset {
            barMissingSince = nil
            if onDesktop, offset == 0 { barTrusted = true }
        } else if barMissingSince == nil {
            barMissingSince = now
        }
        let activeRect = onDesktop ? deskRect : overlayRect
        let hideDistance = max(activeRect.height, metrics.bandHeight) + 20
        let next = IslandFollow.placement(.init(
            onDesktopSpace: onDesktop, barOffset: offset, barTrusted: barTrusted,
            barMissingFor: barMissingSince.map { now.timeIntervalSince($0) } ?? 0,
            pinned: pinned, policy: model.settings.fullScreenPolicy,
            hideDistance: hideDistance, currentDesktopLift: deskLift))
        // Only a menu bar caught sliding on a desktop proves the "automatically hide" setting;
        // one that is simply gone may be an app on its way into full screen.
        if onDesktop, let offset, offset < 0 { desktopBarHides = true }
        let moving = next != placement || (offset.map { $0 < 0 } ?? false)
        // While the island is riding a revealed menu bar, the bar can leave at any moment:
        // keep watching at display rate so it leaves with it, not a beat later.
        let riding = !pinned && offset != nil && (next.surface == .overlay || (onDesktop && desktopBarHides))
        apply(next)
        if moving || riding { quicken(for: 0.4) }
        if traceLayout {
            let line = "island placement surface=\(next.surface) lift=\(Int(next.lift)) bar=\(offset.map { String(Int($0)) } ?? "none") desktop=\(onDesktop)"
            if line != lastTrace {
                lastTrace = line
                model.log.info(line)
            }
        }
    }

    private func apply(_ next: IslandPlacement) {
        let previous = placement
        placement = next
        let size = IslandMetrics.canvas

        if next.surface == .desktop, next.lift != deskLift {
            deskLift = next.lift
            deskPanel.setFrameOrigin(NSPoint(x: baseOrigin.x, y: baseOrigin.y + deskLift))
        }

        switch next.surface {
        case .overlay:
            overlayLeaving = false
            let origin = NSPoint(x: baseOrigin.x, y: baseOrigin.y + next.lift)
            if !overlayPanel.isVisible {
                // Arriving without a menu bar to ride on (an agent needs you): come down from above.
                let rides = next.lift > 0
                let start = rides ? origin : NSPoint(x: origin.x, y: origin.y + metrics.bandHeight + 20)
                overlayPanel.setFrame(NSRect(origin: start, size: size), display: true)
                overlayPanel.orderFrontRegardless()
                if !rides {
                    overlaySettlesAt = Date().addingTimeInterval(0.24)
                    slide(overlayPanel, to: origin, duration: 0.22)
                }
            } else if overlayPanel.frame.origin != origin, next.lift > 0 || Date() > overlaySettlesAt {
                // Riding the menu bar, or at rest: no animation of ours to disturb.
                overlayPanel.setFrameOrigin(origin)
            }
        case .desktop, .hidden:
            guard overlayPanel.isVisible, !overlayLeaving else { return }
            if next.surface == .desktop || previous.lift > 0 {
                // Back on a desktop, or it rode the menu bar out: nothing left to animate.
                overlayPanel.orderOut(nil)
            } else {
                overlayLeaving = true
                let away = NSPoint(x: baseOrigin.x, y: baseOrigin.y + max(overlayRect.height, metrics.bandHeight) + 20)
                slide(overlayPanel, to: away, duration: 0.18) { [weak self] in
                    guard let self, self.overlayLeaving else { return }
                    self.overlayLeaving = false
                    self.overlayPanel.orderOut(nil)
                }
            }
        }
    }

    private func slide(_ panel: NSPanel, to origin: NSPoint, duration: TimeInterval, then completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(origin: origin, size: panel.frame.size), display: true)
        }, completionHandler: {
            MainActor.assumeIsolated { completion?() }
        })
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
        // Two fingers on the island: see `scrolled`.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.scrolled(event) } ? nil : event
        }) { monitors.append(monitor) }
        // A click anywhere else puts the island away. Nothing pending is decided by that.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.model.isExpanded, !self.pointerInside { self.model.collapse() }
            }
        }) { monitors.append(monitor) }
    }

    /// The window the island is currently shown in.
    private var activePanel: IslandPanel { placement.surface == .overlay ? overlayPanel : deskPanel }

    /// The island's rectangle in screen coordinates.
    private var islandScreenRect: CGRect {
        let overlay = placement.surface == .overlay
        let rect = overlay ? overlayRect : deskRect
        guard rect != .zero, placement.surface != .hidden else { return .zero }
        let frame = (overlay ? overlayPanel : deskPanel).frame
        return CGRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        // The menu bar is revealed from the top edge: be ready to move with it from its first frame.
        if location.y >= screenTop - 3, location.x >= displayBounds.minX, location.x <= displayBounds.maxX { quicken(for: 0.6) }

        let rect = islandScreenRect
        let inside = rect != .zero && rect.insetBy(dx: -2, dy: -2).contains(location)
        guard inside != pointerInside else { return }
        pointerInside = inside
        deskPanel.ignoresMouseEvents = !(inside && activePanel === deskPanel)
        overlayPanel.ignoresMouseEvents = !(inside && activePanel === overlayPanel)
        if inside {
            closeTimer?.cancel()
            // A finished-turn card is being read: resting on it keeps it, and does not open the list over it.
            guard !model.isExpanded, model.settings.expandOnHover, model.completion == nil else { return }
            schedule(&openTimer, after: Double(model.settings.hoverOpenDelayMS) / 1000) { [weak self] in
                guard let self, self.pointerInside else { return }
                self.model.expand(.hover)
            }
        } else {
            openTimer?.cancel()
            quicken(for: 0.6)
            guard model.isExpanded, model.expandReason == .hover else { return }
            schedule(&closeTimer, after: Double(model.settings.hoverCloseDelayMS) / 1000) { [weak self] in
                guard let self, !self.pointerInside, self.model.expandReason == .hover else { return }
                self.model.collapse()
                self.quicken(for: 0.6)
            }
        }
    }

    /// Pulling the closed island down with two fingers opens it; pushing the open island's
    /// top band up closes it. The island follows the fingers with resistance and springs back
    /// if they let go before it gives. Only a trackpad does this: a mouse wheel scrolls the list.
    /// Returns true when the event was used up here.
    private func scrolled(_ event: NSEvent) -> Bool {
        guard event.hasPreciseScrollingDeltas else { return false }
        // Momentum after the fingers left belongs to the pull that started it.
        if event.phase.isEmpty, !event.momentumPhase.isEmpty { return pulling }
        let fingersDown = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        if event.phase.contains(.began) {
            let location = NSEvent.mouseLocation
            let rect = islandScreenRect
            let onTopBand = rect != .zero && location.y >= rect.maxY - 44
            pulling = pointerInside && (!model.isExpanded || onTopBand)
            pulled = 0
            return pulling
        }
        guard pulling else { return false }
        if event.phase.contains(.changed) {
            pulled += fingersDown
            let shown = model.isExpanded ? min(0, pulled) : max(0, pulled)
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { model.pull = shown }
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            pulling = false
            if !model.isExpanded, pulled > 36 {
                model.expand(.click)
            } else if model.isExpanded, pulled < -46 {
                model.collapse()
            }
            withAnimation(Motion.snappy(model.settings.motion.factor)) { model.pull = 0 }
        }
        return true
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
