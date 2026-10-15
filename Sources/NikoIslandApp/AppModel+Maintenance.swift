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
    /// Why an agent's hooks could not be put back, by agent id: what to fix by hand.
    public var repairNotes: [String: String] = [:]

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

    /// After an update, the agents an earlier version connected get this version's wiring:
    /// an adapter whose format changed (Kiro and Copilot CLI in 0.9.0) would otherwise keep
    /// the old one until the user thought of pressing Connect again. Only agents whose
    /// configs already carry our marker are touched, with the usual scan, backup and
    /// rollback; the status line is left as it is. Only the installed app does this: a
    /// build running on another runtime folder must never point real configs at it.
    func refreshWiringAfterUpdate(isBundled: Bool) {
        guard isBundled, paths.isDefaultLocation, settings.lastWiredVersion != NikoVersion.current, !maintenance.busy else { return }
        let home = self.home, paths = self.paths
        let bridge = Shims.locateBridgeBinary(), executable = Bundle.main.executablePath
        Task.detached(priority: .utility) {
            var options = InstallOptions(home: home, paths: paths)
            guard let report = try? Installer(options: options).scan(.uninstall) else { return }
            let ids = Installer.connectedAgents(in: report)
            var result: InstallResult?
            if !ids.isEmpty {
                options.agentIDs = ids
                options.includeStatusLine = false
                options.bridgeBinary = bridge
                options.appExecutable = executable
                result = Installer(options: options).run(.install)
            }
            let rows = AppModel.scanRows(home: home)
            await MainActor.run {
                if result?.succeeded ?? true { self.settings.lastWiredVersion = NikoVersion.current }
                if let result {
                    if result.applied {
                        // An agent with two config files has two changes; name it once.
                        var named: [String] = []
                        for agent in result.plan.changes.map(\.agent) where !named.contains(agent) { named.append(agent) }
                        self.log.info("brought connected agents up to date: \(named.joined(separator: ", "))")
                    } else if let error = result.error {
                        self.log.error("bringing connected agents up to date failed: \(error)")
                    }
                }
                self.maintenance.agents = rows
            }
        }
    }

    /// Hooks of an agent the user connected, taken out since by another tool (a config
    /// switcher, a dotfiles sync), are put back, and the user is told so. Checked every two
    /// minutes; an agent is put back at most once every ten minutes, so a tool that keeps
    /// taking them out is not fought over and over. Only the installed app on the standard
    /// runtime folder does this, as with the re-wiring after an update.
    func restoreRemovedHooks(now: Date = Date(), isBundled: Bool = Bundle.main.bundleURL.pathExtension == "app") {
        guard settings.restoreRemovedHooks, isBundled, paths.isDefaultLocation,
              !maintenance.busy, !restoreRunning, now.timeIntervalSince(restoreCheckedAt) >= 120 else { return }
        restoreCheckedAt = now
        restoreRunning = true
        let home = self.home, paths = self.paths
        let recent = restoredAt.filter { now.timeIntervalSince($0.value) < 600 }.map(\.key)
        let bridge = Shims.locateBridgeBinary(), executable = Bundle.main.executablePath
        Task.detached(priority: .utility) {
            var options = InstallOptions(home: home, paths: paths)
            var missing: [String] = []
            var result: InstallResult?
            let wanted = ConnectedAgents.load(paths: paths).sorted()
            if !wanted.isEmpty, let report = try? Installer(options: options).scan(.uninstall) {
                let wired = Installer.wiredAgents(in: report)
                // An agent that is no longer on this Mac has nothing to put back.
                missing = wanted.filter { id in
                    report.agents[id]?.directory == .present && !wired.contains(id) && !recent.contains(id)
                }
                if !missing.isEmpty {
                    options.agentIDs = missing
                    options.includeStatusLine = false
                    options.bridgeBinary = bridge
                    options.appExecutable = executable
                    result = Installer(options: options).run(.install)
                }
            }
            await MainActor.run { self.restored(missing, result: result, at: now) }
        }
    }

    private func restored(_ agents: [String], result: InstallResult?, at now: Date) {
        restoreRunning = false
        guard let result, !agents.isEmpty else { return }
        for id in agents { restoredAt[id] = now }
        var back: [String] = []
        for outcome in result.plan.outcomes where agents.contains(outcome.id) {
            if case .skipped(let reason) = outcome.status {
                maintenance.repairNotes[outcome.id] = reason
            } else if result.touched(outcome.id), result.applied {
                maintenance.repairNotes[outcome.id] = nil
                back.append(outcome.id)
            }
        }
        if let error = result.error { log.error("putting hooks back failed: \(error)") }
        guard !back.isEmpty else { return }
        let names = Localization.list(back.map { AgentRegistry.displayName(for: $0) })
        log.info("hooks taken out by another tool were put back: \(back.joined(separator: ", "))")
        refreshMaintenance()
        guard !isExpanded, completion == nil, pending.isEmpty else { return }
        notify(Toast(key: SessionKey(source: back[0], sessionID: ""), title: L("%@: hooks put back", names), kind: .notice), for: 10)
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
                                           gemini: settings.geminiLimitsLookup, copilot: settings.copilotLimitsLookup)
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
