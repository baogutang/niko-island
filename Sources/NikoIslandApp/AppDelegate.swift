import AppKit
import Combine
import NikoCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var island: IslandWindowController?
    private var settingsWindow: SettingsWindowController?
    private var notifier: SystemNotifier?
    private var sounds: SoundPlayer?
    private let onboarding = OnboardingWindowController()
    private var subscriptions: Set<AnyCancellable> = []
    public let model: AppModel

    public override init() {
        self.model = AppModel(paths: NikoPaths.resolve())
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Localization.use(language: model.settings.language)
        let settingsWindow = SettingsWindowController(model: model)
        self.settingsWindow = settingsWindow
        model.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }

        let notifier = SystemNotifier(model: model)
        self.notifier = notifier
        model.notifier = notifier

        let sounds = SoundPlayer(model: model)
        self.sounds = sounds
        model.soundPlayer = sounds
        model.onPreviewSound = { [weak sounds] event in sounds?.preview(event) }

        // The real thing: the system Keychain and the network. Tests and previews
        // never get here, so they cannot open either.
        let paths = model.paths
        let home = model.home
        model.makeLimitsClient = { onChange in
            ProviderLimitsClient(paths: paths, secrets: .system(home: home), onChange: onChange)
        }
        model.hasGLMKey = ProviderKeychain.exists(ProviderLimitsClient.glmAccount)
        model.start()
        if model.startFailure == .anotherInstanceRunning {
            // One island is enough: the running instance keeps the socket.
            NSApp.terminate(nil)
            return
        }

        let island = IslandWindowController(model: model)
        self.island = island
        island.show()
        statusItem = StatusItemController(model: model)

        Hotkey.shared.action = { [weak self] in self?.model.toggleExpanded() }
        model.$settings
            .receive(on: DispatchQueue.main)
            .sink { settings in
                Localization.use(language: settings.language)
                Hotkey.shared.setEnabled(settings.hotkeyEnabled)
            }
            .store(in: &subscriptions)
        model.$wantsOnboarding
            .receive(on: DispatchQueue.main)
            .sink { [weak self] wanted in
                guard let self, wanted else { return }
                self.model.wantsOnboarding = false
                self.onboarding.show(model: self.model)
            }
            .store(in: &subscriptions)

        // For screenshots and manual checks: `-NikoOpenSettings <page>` opens Settings straight away.
        if let page = UserDefaults.standard.string(forKey: "NikoOpenSettings").flatMap(SettingsPage.init(rawValue:)) {
            settingsWindow.show(page: page)
        }

        // …and `-NikoOpenIsland sessions|usage` opens the island and keeps it open.
        if let route = UserDefaults.standard.string(forKey: "NikoOpenIsland") {
            model.route = route == "usage" ? .usage : .sessions
            if let agent = UserDefaults.standard.string(forKey: "NikoUsageAgent") { model.usageAgent = agent }
            model.expand(.click)
            model.heldOpen = true
        }

        // The first launch gets the welcome (scripted launches say no thanks).
        if !model.settings.onboardingDone, !UserDefaults.standard.bool(forKey: "NikoOnboardingDisabled") {
            model.wantsOnboarding = true
        }
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
