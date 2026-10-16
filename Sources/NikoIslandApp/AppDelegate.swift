import AppKit
import Combine
import NikoCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var switcher: QuickSwitcherController?
    private var island: IslandWindowController?
    private var settingsWindow: SettingsWindowController?
    private var notifier: SystemNotifier?
    private var sounds: SoundPlayer?
    private let onboarding = OnboardingWindowController()
    private var subscriptions: Set<AnyCancellable> = []
    public let model: AppModel
    private var observers: [NSObjectProtocol] = []

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

        // A terminal that refused our Apple events costs the jump to its tab: the first refusal
        // of each terminal opens the guide; later ones only say so on the island.
        PermissionGuideController.shared.center = model.permissions
        TerminalJumper.onAutomationDenied = { [weak model] target in
            guard let model else { return }
            let first = !model.permissions.refusals.contains(target)
            model.permissions.recordRefusal(target)
            if first {
                PermissionGuideController.shared.present(.automation(target),
                    reason: L("Without it, a session only brings %@ forward, not its own tab.", target.displayName))
            } else {
                model.notify(AppModel.Toast(key: SessionKey(source: "", sessionID: ""),
                                            title: L("%@ tabs need Automation: Settings → General", target.displayName),
                                            kind: .notice), for: 8)
            }
        }
        Task { await model.permissions.refresh() }

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
        model.hasKimiKey = ProviderKeychain.exists(ProviderLimitsClient.kimiAccount)
        model.hasMiniMaxKey = ProviderKeychain.exists(ProviderLimitsClient.minimaxAccount)
        model.hasPushKey = ProviderKeychain.exists(PushClient.account)
        model.hasPushSignIn = ProviderKeychain.exists(PushClient.signInAccount)
        // Development: `-NikoUsageDisabled YES` leaves usage counting off, so a run measures what it is about.
        model.start(usage: !UserDefaults.standard.bool(forKey: "NikoUsageDisabled"))
        if model.startFailure == .anotherInstanceRunning {
            // One island is enough: the running instance keeps the socket.
            NSApp.terminate(nil)
            return
        }

        let island = IslandWindowController(model: model)
        self.island = island
        island.show()
        statusItem = StatusItemController(model: model)
        let switcher = QuickSwitcherController(model: model)
        self.switcher = switcher
        model.onOpenSwitcher = { [weak switcher] in switcher?.toggle() }

        Hotkey.shared.action = { [weak self] in self?.model.toggleExpanded() }
        Hotkey.shared.actions[.allow] = { [weak self] in self?.model.decideByKey(.allow) }
        Hotkey.shared.actions[.deny] = { [weak self] in self?.model.decideByKey(.deny) }
        Hotkey.shared.actions[.jump] = { [weak self] in self?.model.jumpToWhatNeedsMe() }
        Hotkey.shared.actions[.switcher] = { [weak self] in self?.switcher?.toggle() }
        model.$settings
            .receive(on: DispatchQueue.main)
            .sink { settings in
                Localization.use(language: settings.language)
                Hotkey.shared.setEnabled(settings.hotkeyEnabled)
                Hotkey.shared.set(.jump, enabled: settings.jumpHotkey)
                Hotkey.shared.set(.switcher, enabled: settings.switcherHotkey)
            }
            .store(in: &subscriptions)
        // ⌃⌥A and ⌃⌥D belong to us only while a request is waiting; otherwise other apps keep them.
        model.$pending.map { !$0.isEmpty }
            .combineLatest(model.$settings.map(\.decisionHotkeys))
            .receive(on: DispatchQueue.main)
            .sink { waiting, enabled in
                Hotkey.shared.set(.allow, enabled: waiting && enabled)
                Hotkey.shared.set(.deny, enabled: waiting && enabled)
            }
            .store(in: &subscriptions)
        model.isFrontmost = { TerminalJumper.isFrontmost($0) }
        model.replySender = { session, text in await TerminalJumper.reply(text, to: session) }
        // After an update is in place: start it once this process has gone, then go.
        model.relaunch = { app in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
            try? process.run()
            NSApp.terminate(nil)
        }
        model.checkForUpdates()
        model.refreshWiringAfterUpdate(isBundled: Bundle.main.bundleURL.pathExtension == "app")
        watchScreen()
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

        // `-NikoAwayFor <seconds>` stands in for a locked screen, to look at what happens on return.
        let awayFor = UserDefaults.standard.double(forKey: "NikoAwayFor")
        if awayFor > 0 {
            model.isAway = true
            DispatchQueue.main.asyncAfter(deadline: .now() + awayFor) { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated { self.model.isAway = false }
            }
        }

        // The first launch gets the welcome (scripted launches say no thanks).
        if !model.settings.onboardingDone, !UserDefaults.standard.bool(forKey: "NikoOnboardingDisabled") {
            model.wantsOnboarding = true
        }
    }

    private var screenLocked = false
    private var screenAsleep = false

    /// Nobody is at a locked or sleeping screen: sounds and cards wait until
    /// somebody is. A display that wakes to the lock screen is still nobody.
    private func noteScreen(locked: Bool? = nil, asleep: Bool? = nil) {
        if let locked { screenLocked = locked }
        if let asleep { screenAsleep = asleep }
        let away = screenLocked || screenAsleep
        if model.isAway != away { model.isAway = away }
    }

    private func watchScreen() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.noteScreen(locked: true) }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.noteScreen(locked: false) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.noteScreen(asleep: true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.noteScreen(asleep: false) }
        })
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// `nikoisland://` links, from Shortcuts, a Focus automation, a launcher or a script.
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let link = IslandLink(url) else {
                model.log.info("ignored a link it does not know: \(url.scheme ?? "")://\(url.host ?? "")")
                continue
            }
            model.follow(link)
        }
    }
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
