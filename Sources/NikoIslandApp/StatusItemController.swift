import AppKit
import NikoCore

/// The menu-bar icon. Left click toggles the island, right click opens a small menu.
@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let model: AppModel
    private var badgeWatch: Watch<AppModel.Badge>?

    var button: NSStatusBarButton? { item.button }

    init(model: AppModel) {
        self.model = model
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            button.image = Self.glyph(attention: false)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel(NikoVersion.displayName)
        }
        badgeWatch = Watch({ [model] in model.badge }) { [weak self] badge in self?.render(badge) }
    }

    private func render(_ badge: AppModel.Badge) {
        guard let button = item.button else { return }
        button.image = Self.glyph(attention: badge.pending > 0)
        button.title = badge.pending > 0 ? " \(badge.pending)" : (badge.active > 0 ? " \(badge.active)" : "")
    }

    /// Original glyph: a pill-shaped "island" with a status dot. Drawn, not borrowed.
    static func glyph(attention: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let pill = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 20, height: 8), xRadius: 4, yRadius: 4)
            NSColor.black.setFill()
            pill.fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let dot = NSBezierPath(ovalIn: NSRect(x: attention ? 13.5 : 14.5, y: attention ? 5.5 : 6.5,
                                                  width: attention ? 5 : 3, height: attention ? 5 : 3))
            dot.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            model.toggleExpanded()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        if model.settings.isQuietNow(at: Date()) {
            let until = Date(timeIntervalSince1970: model.settings.quietNowUntil)
            menu.addItem(withTitle: L("Quiet until %@", until.formatted(date: .omitted, time: .shortened)), action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(withTitle: L("Stop being quiet"), action: #selector(quietOff), keyEquivalent: "").target = self
        } else {
            let quiet = NSMenuItem(title: L("Quiet now"), action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for minutes in [30, 60, 120, 240] {
                let entry = choices.addItem(withTitle: minutes < 60 ? L("For %lld min", minutes) : L("For %lld h", minutes / 60),
                                            action: #selector(quietFor(_:)), keyEquivalent: "")
                entry.target = self
                entry.tag = minutes
            }
            choices.addItem(withTitle: L("For a day"), action: #selector(quietFor(_:)), keyEquivalent: "").target = self
            quiet.submenu = choices
            menu.addItem(quiet)
        }
        menu.addItem(withTitle: L("Find a Session…"), action: #selector(openSwitcher), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("Open Releases Page"), action: #selector(openReleases), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit Niko Island"), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() { model.onOpenSettings?() }

    @objc private func openSwitcher() { model.onOpenSwitcher?() }

    @objc private func quietFor(_ sender: NSMenuItem) { model.setQuietNow(minutes: sender.tag == 0 ? nil : sender.tag) }

    @objc private func quietOff() { model.setQuietNow(minutes: 0) }

    @objc private func openReleases() {
        if let url = URL(string: NikoVersion.releasesURL) { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
