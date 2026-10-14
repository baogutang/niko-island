import AppKit
import Foundation
import NikoCore

/// State of the "Hooks" section in Settings.
public struct MaintenanceState: Sendable, Equatable {
    public struct AgentRow: Identifiable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var stability: AgentDescriptor.Stability
        public var wired: Bool
        /// The island can decide permission requests for this agent.
        public var approvals = false
        /// Something the user still has to do in the agent itself.
        public var followUp: String?

        public init(id: String, name: String, stability: AgentDescriptor.Stability, wired: Bool,
                    approvals: Bool = false, followUp: String? = nil) {
            self.id = id
            self.name = name
            self.stability = stability
            self.wired = wired
            self.approvals = approvals
            self.followUp = followUp
        }
    }

    public var agents: [AgentRow] = []
    public var busy = false
    public var message: String?
    /// Set when the bundled bridge still carries the download quarantine flag:
    /// the shell command that clears it.
    public var quarantineFix: String?

    public init() {}
}

extension AppModel {
    /// Read-only scan of the agents' config directories for the Settings tab.
    public func refreshMaintenance() {
        let home = self.home
        Task.detached(priority: .utility) {
            let rows = AppModel.scanRows(home: home)
            let fix = Shims.locateBridgeBinary().flatMap { Diagnostics.isQuarantined($0) ? Diagnostics.quarantineFix(for: $0) : nil }
            await MainActor.run {
                self.maintenance.agents = rows
                self.maintenance.quarantineFix = fix
            }
        }
    }

    nonisolated static func scanRows(home: URL) -> [MaintenanceState.AgentRow] {
        let installer = Installer(options: InstallOptions(home: home))
        guard let report = try? installer.scan(.uninstall) else { return [] }
        return AgentRegistry.installable.compactMap { agent in
            guard let scanned = report.agents[agent.id], scanned.directory == .present else { return nil }
            let wired = agent.activeFiles.contains { file in
                scanned.files[file]?.data.map { HookMerge.isOurs(command: String(decoding: $0, as: UTF8.self)) } ?? false
            }
            return MaintenanceState.AgentRow(id: agent.id, name: agent.displayName, stability: agent.stability, wired: wired,
                                             approvals: agent.approvals, followUp: agent.followUp)
        }
    }

    /// Runs the installer off the main thread. Only ever called from an explicit click.
    public func runInstaller(_ action: InstallAction, agents: [String]? = nil) {
        guard !maintenance.busy else { return }
        maintenance.busy = true
        maintenance.message = nil
        var options = InstallOptions(home: home, paths: paths)
        options.agentIDs = agents
        options.bridgeBinary = Shims.locateBridgeBinary()
        options.appExecutable = Bundle.main.executablePath
        let home = self.home
        Task.detached(priority: .userInitiated) {
            let result = Installer(options: options).run(action)
            let rows = AppModel.scanRows(home: home)
            let summary = result.report(home: home.path)
            await MainActor.run {
                self.maintenance.busy = false
                self.maintenance.message = summary
                self.maintenance.agents = rows
                if result.succeeded, action == .install {
                    // The installer may have switched on the loopback ingress for a JS plugin.
                    self.settings = NikoSettings.load(paths: self.paths)
                }
            }
        }
    }

    public func exportDiagnostics() -> URL? {
        let extra = [
            "sessions: \(sessions.count)", "pending requests: \(pending.count)",
            "ingress: \(hub.counters)", "http ingress port: \(httpPort)",
        ]
        let text = Diagnostics.export(paths: paths, home: home, extra: extra)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = paths.logs.appendingPathComponent("diagnostics-\(formatter.string(from: Date())).txt")
        guard AtomicFile.write(Data(text.utf8), to: url.path, mode: 0o600) else { return nil }
        return url
    }

    // MARK: Usage

    func startUsageEngine() {
        let engine = UsageEngine(paths: paths, home: home, pricing: Pricing.load(paths: paths), log: log) { [weak self] snapshot in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.usage = snapshot }
            }
        }
        usageEngine = engine
        engine.start()
        refreshPricingIfDue()
        reconcileProviderLimits()
    }

    // MARK: Limits the providers keep (opt-in)

    var providerLimitsConfig: ProviderLimitsClient.Config {
        let region = GLMQuotaAPI.Region(rawValue: settings.glmRegion) ?? GLMQuotaAPI.regionZCodeUses(home: home) ?? .bigmodel
        return ProviderLimitsClient.Config(claude: settings.claudeLimitsLookup, glm: settings.glmLimitsLookup, glmRegion: region,
                                           codex: settings.codexLimitsLookup, kimi: settings.kimiLimitsLookup,
                                           minimax: settings.minimaxLimitsLookup,
                                           minimaxRegion: MiniMaxQuotaAPI.Region(rawValue: settings.minimaxRegion) ?? .cn,
                                           gemini: settings.geminiLimitsLookup)
    }

    /// Starts, stops or re-aims the lookups after a setting changed. Nothing is
    /// asked, and no login is read, unless one of the switches is on.
    func reconcileProviderLimits() {
        let config = providerLimitsConfig
        if limitsClient == nil {
            guard config.asksAnyone else { return }
            limitsClient = makeLimitsClient { [weak self] results in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.receive(providerLimits: results) }
                }
            }
        }
        guard let client = limitsClient else { return }
        Task { await client.configure(config) }
        for provider in ProviderLimitsClient.providers where !config.asks(provider) { providerLookups[provider] = nil }
    }

    func receive(providerLimits results: [String: ProviderLimitsClient.Result]) {
        providerLookups = results
        usageEngine?.setAskedLimits(results.compactMapValues(\.limits))
    }

    /// "Check now" in the usage view and in Settings.
    public func refreshProviderLimits() {
        askClaudeCode(force: true)
        guard let client = limitsClient else { return }
        Task { await client.refresh(force: true) }
    }

    // MARK: Claude Code looks for itself (opt-in)

    /// Has Claude Code look up the plan's usage (`claude -p /usage`) when that is due:
    /// right after switching it on, every five minutes while a Claude Code session is
    /// listed, and when "Check now" is pressed. What it keeps is read like any local file.
    func askClaudeCode(force: Bool = false, now: Date = Date()) {
        guard settings.claudeAsksItself, !claudeIsLooking else { return }
        if let last = claudeLookedAt {
            let wait: TimeInterval = force ? 20 : 300
            guard now.timeIntervalSince(last) >= wait else { return }
            // Nobody is using Claude Code: the figures can wait until somebody is, or asks.
            guard force || sessions.contains(where: { $0.source == "claude" }) else { return }
        }
        claudeLookedAt = now
        claudeIsLooking = true
        let ask = claudeAsker
        let home = self.home, paths = self.paths
        let done: @MainActor @Sendable (ClaudeCodeUsage.Outcome) -> Void = { [weak self] outcome in
            guard let self else { return }
            self.claudeIsLooking = false
            self.claudeLookup = outcome
            self.usageEngine?.limitsChanged()
        }
        DispatchQueue.global(qos: .utility).async {
            let outcome = ask(home, paths)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { done(outcome) }
            }
        }
    }

    /// The key for the GLM Coding Plan, typed by the user. Kept in the Keychain, never in a file.
    public func setGLMKey(_ key: String?) {
        setProviderKey(key, for: ProviderLimitsClient.glm)
    }

    /// A plan's key, typed by the user (GLM, Kimi, MiniMax). Kept in the Keychain, never in a file.
    public func setProviderKey(_ key: String?, for provider: String) {
        guard let account = AppModel.keyAccounts[provider] else { return }
        ProviderKeychain.store(key, account: account)
        let saved = ProviderKeychain.exists(account)
        switch provider {
        case ProviderLimitsClient.glm:
            hasGLMKey = saved
            if !saved { settings.glmLimitsLookup = false }
        case ProviderLimitsClient.kimi:
            hasKimiKey = saved
            if !saved { settings.kimiLimitsLookup = false }
        default:
            hasMiniMaxKey = saved
            if !saved { settings.minimaxLimitsLookup = false }
        }
        if saved { refreshProviderLimits() }
    }

    /// The Keychain account of each plan whose key the user types in.
    nonisolated static let keyAccounts: [String: String] = [
        ProviderLimitsClient.glm: ProviderLimitsClient.glmAccount,
        ProviderLimitsClient.kimi: ProviderLimitsClient.kimiAccount,
        ProviderLimitsClient.minimax: ProviderLimitsClient.minimaxAccount,
    ]

    func hasKey(for provider: String) -> Bool {
        switch provider {
        case ProviderLimitsClient.glm: return hasGLMKey
        case ProviderLimitsClient.kimi: return hasKimiKey
        case ProviderLimitsClient.minimax: return hasMiniMaxKey
        default: return false
        }
    }

    // MARK: New versions (opt-in)

    /// Asks GitHub for the latest release: once a day while the switch is on, or now when pressed.
    public func checkForUpdates(force: Bool = false, now: Date = Date()) {
        guard settings.updateChecks || force, updateState != .checking, updateState != .installing else { return }
        if !force, now.timeIntervalSince1970 - settings.lastUpdateCheck < UpdateCheck.interval { return }
        settings.lastUpdateCheck = now.timeIntervalSince1970
        updateState = .checking
        let updater = makeUpdater()
        Task { [weak self] in
            let release = await updater.latest()
            guard let self else { return }
            guard let release else {
                self.updateState = .failed(L("GitHub could not be asked."))
                return
            }
            if UpdateCheck.isNewer(release.version, than: NikoVersion.current) {
                self.availableUpdate = release
                self.updateState = .idle
            } else {
                self.availableUpdate = nil
                self.updateState = .upToDate
            }
        }
    }

    /// Downloads the new release for this Mac, checks it, puts it where this app is, and starts it.
    /// The old app goes to the Trash.
    public func installUpdate() {
        guard let release = availableUpdate, updateState != .installing else { return }
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app" else {
            updateState = .failed(L("Only an installed app can replace itself."))
            return
        }
        updateState = .installing
        let updater = makeUpdater()
        let folder = paths.cache.appendingPathComponent("update")
        Task { [weak self] in
            do {
                let app = try await updater.prepare(release, in: folder)
                try Updater.replace(current, with: app)
                guard let self else { return }
                self.relaunch(current)
            } catch {
                guard let self else { return }
                let reason: String
                switch error as? Updater.Failure {
                case .checksumMismatch?: reason = L("The download did not match the release's checksum, so it was not used.")
                case .notOurApp?: reason = L("The download is not this app, so it was not used.")
                case .noPackage?: reason = L("This release has no package for this Mac.")
                case .cannotReplace(let why)?: reason = L("The app could not be replaced: %@", why)
                default: reason = L("The download did not finish.")
                }
                self.updateState = .failed(reason)
            }
        }
    }

    /// Puts text on the clipboard (a reply, a command), and nothing else.
    public func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Shows a session's folder in Finder.
    public func reveal(_ folder: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
        collapse()
    }

    /// Brings an agent's own app forward: where a quota reset is actually spent.
    public func openAgentApp(_ id: String) {
        guard let bundle = AgentRegistry.all.first(where: { $0.id == id })?.apps.first,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        collapse()
    }

    /// The only network request the app makes on its own, and only after the
    /// user switched it on in Settings (SPEC §5).
    func refreshPricingIfDue() {
        guard settings.pricingRefreshEnabled, PricingRefresher.isDue(paths: paths) else { return }
        let paths = self.paths
        Task.detached(priority: .utility) {
            let outcome = await PricingRefresher.refresh(paths: paths)
            await MainActor.run {
                switch outcome {
                case .updated(let models):
                    self.log.info("pricing table refreshed (\(models) models)")
                    self.usageEngine?.setPricing(Pricing.load(paths: paths))
                case .failed(let reason):
                    self.log.warn("pricing refresh failed: \(reason)")
                }
            }
        }
    }
}
