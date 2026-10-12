import AppKit
import NikoCore
import SwiftUI

/// Borderless floating panel. On notched displays it hangs from the top-centre
/// of the screen; elsewhere it drops down from the menu-bar icon (SPEC §4).
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 420

    private let model: AppModel
    private let panel: NikoPanel
    private var clickMonitor: Any?

    init(model: AppModel) {
        self.model = model
        self.panel = NikoPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 320),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let attached = NSScreen.main.map(Self.hasNotch) ?? false
        let root = PanelView(model: model, attachedToTop: attached) { [weak self] height in
            self?.contentHeightChanged(height)
        }
        // Top-aligned so the content does not jump while the window catches up with a new height.
        let host = NSHostingView(rootView: root.frame(maxHeight: .infinity, alignment: .top))
        host.sizingOptions = []
        panel.contentView = host
    }

    private var contentHeight: CGFloat = 200
    private weak var anchor: NSStatusBarButton?

    /// SwiftUI reports its natural height; the panel follows it, top edge pinned.
    private func contentHeightChanged(_ height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        if panel.isVisible { position(relativeTo: anchor) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if panel.isVisible { hide() } else { show(relativeTo: button) }
    }

    func show(relativeTo button: NSStatusBarButton?) {
        if let button { anchor = button }
        position(relativeTo: anchor)
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeClickMonitor()
    }

    private func position(relativeTo button: NSStatusBarButton?) {
        let size = NSSize(width: Self.width, height: min(max(contentHeight, 80), 760))
        let screen = button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        var origin: NSPoint
        if Self.hasNotch(screen) {
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        } else if let button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)
        } else {
            origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 6)
        }
        let visible = screen.frame
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    // Clicking anywhere else collapses the panel. Pending approvals stay in the
    // model and keep the menu-bar badge lit; nothing is ever auto-decided.
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

/// Borderless panels refuse key status by default; text fields in the question wizard need it.
final class NikoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
