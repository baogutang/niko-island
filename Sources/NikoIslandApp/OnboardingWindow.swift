import AppKit
import NikoCore
import SwiftUI

/// Shows the welcome across the whole screen, above the menu bar and the
/// island itself, and takes it away again when the user is done.
@MainActor
final class OnboardingWindowController {
    private var panel: OnboardingPanel?

    var isShowing: Bool { panel != nil }

    func show(model: AppModel) {
        guard panel == nil, let screen = IslandWindowController.targetScreen() else { return }
        let panel = OnboardingPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        let view = OnboardingView(model: model, metrics: IslandMetrics(screen: screen)) { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(screen.frame, display: true)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.45
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.contentView = nil
            }
        })
    }
}

final class OnboardingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
