import AppKit
import NikoCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var panel: PanelController?
    public let model: AppModel

    public override init() {
        self.model = AppModel(paths: NikoPaths.resolve())
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PanelController(model: model)
        let statusItem = StatusItemController(model: model) { [weak panel] button in
            panel?.toggle(relativeTo: button)
        }
        self.panel = panel
        self.statusItem = statusItem
        model.onAttentionNeeded = { [weak panel, weak statusItem] in
            panel?.show(relativeTo: statusItem?.button)
        }
        model.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

/// Entry point used by the `niko-island` executable when no CLI subcommand was given.
@MainActor
public func runNikoIslandApp() -> Never {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu-bar only, mirrors LSUIElement for `swift run`
    withExtendedLifetime(delegate) { app.run() }
    exit(0)
}
