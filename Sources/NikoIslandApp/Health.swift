import AppKit
import Foundation
import NikoCore

/// Whether another island's app is on this Mac.
enum IslandApps {
    static func isInstalled(_ island: ForeignHooks.Island) -> Bool {
        if island.bundleIDs.contains(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) { return true }
        let folders = ["/Applications", NSHomeDirectory() + "/Applications"]
        return island.appNames.contains { name in folders.contains { FileManager.default.fileExists(atPath: $0 + "/" + name) } }
    }
}

/// What the health card checks that is not already in the model: other islands' leftovers.
public struct HealthState: Sendable, Equatable {
    public var leftovers: [ForeignHooks.Finding] = []
    public var checkedAt: Date?
    /// The island whose hooks are being taken out.
    public var cleaning: String?
    /// How the last clean-up went, in a sentence.
    public var message: String?
}

/// One thing the health card says, with what fixes it.
struct HealthItem: Identifiable {
    enum Fix {
        case clean(ForeignHooks.Island)
        case disconnect([String])
        case addKey
        case turnOff(String)
        case keepClaudeCurrent
    }
    var id: String
    var title: String
    var detail: String
    var fix: Fix?
    var fixLabel: String?
    /// Something wrong (the gear on the island gets a dot), not only a suggestion.
    var urgent = true
}

extension AppModel {
    /// Looks for other islands' hooks in the agents' configs (read-only, off the main thread).
    public func refreshHealth() {
        let home = self.home, paths = self.paths
        Task.detached(priority: .utility) {
            let findings = ForeignHooks.scan(home: home, paths: paths, isInstalled: IslandApps.isInstalled)
            await MainActor.run {
                if self.health.leftovers != findings { self.health.leftovers = findings }
                self.health.checkedAt = Date()
            }
        }
    }

    /// Takes one island's hooks out of every agent config (a backup next to each file), on the user's word.
    public func cleanLeftovers(_ island: ForeignHooks.Island) {
        guard health.cleaning == nil else { return }
        health.cleaning = island.id
        health.message = nil
        let home = self.home, paths = self.paths
        Task.detached(priority: .userInitiated) {
            let cleaned = ForeignHooks.clean(island, home: home, paths: paths)
            let findings = ForeignHooks.scan(home: home, paths: paths, isInstalled: IslandApps.isInstalled)
            await MainActor.run {
                self.health.cleaning = nil
                self.health.leftovers = findings
                self.health.checkedAt = Date()
                self.health.message = cleaned.failures.isEmpty
                    ? L("%@: %lld hooks taken out of %lld files. A backup of each file is next to it.", island.name, cleaned.hooks, cleaned.files.count)
                    : L("Some files could not be written: %@", cleaned.failures.joined(separator: ", "))
                self.log.info("cleaned up \(island.id): \(cleaned.hooks) hooks in \(cleaned.files.count) files, status line \(cleaned.statusLine)")
            }
        }
    }

    /// Everything the health card has to say, most useful first. Empty when all is well.
    var healthItems: [HealthItem] {
        var items: [HealthItem] = []
        for finding in health.leftovers {
            let names = finding.agents.map { AgentRegistry.displayName(for: $0) }
            // A few agents are named in the title; more are counted there and named below.
            let agents = Localization.list(names)
            if finding.installed {
                items.append(HealthItem(id: "island-" + finding.id,
                                        title: L("%@ is also connected to %@", finding.island.name, agents),
                                        detail: L("Two islands answer the same requests and announce the same turns. Remove one of them from these agents if that is not what you want."),
                                        urgent: false))
            } else {
                var detail = L("%@ is no longer on this Mac, but its %lld hooks still run on every event of these agents, with nothing to answer them.", finding.island.name, finding.hooks)
                if names.count > 3 { detail = Localization.sentences(detail, L("They are in %@.", agents)) }
                if finding.statusLine { detail = Localization.sentences(detail, L("Claude Code's status line still goes through it too.")) }
                items.append(HealthItem(id: "island-" + finding.id,
                                        title: names.count > 3 ? L("%@ left hooks in %lld agents", finding.island.name, names.count)
                                            : L("%@ left hooks in %@", finding.island.name, agents),
                                        detail: detail, fix: .clean(finding.island), fixLabel: L("Clean up…")))
            }
        }
        let absent = maintenance.agents.filter { $0.wired && !$0.installed }
        if !absent.isEmpty {
            items.append(HealthItem(id: "absent", title: L("%lld connected agents are not on this Mac", absent.count),
                                    detail: L("%@. Their hooks stay in place until they are disconnected.", Localization.list(absent.map(\.name))),
                                    fix: .disconnect(absent.map(\.id)), fixLabel: L("Disconnect them")))
        }
        for (agent, result) in providerLookups.sorted(by: { $0.key < $1.key }) where settings.asksProvider(agent) {
            guard let text = ProviderLookupText.problem(result.state, agent: agent) else { continue }
            let name = AgentRegistry.displayName(for: agent)
            let fix: HealthItem.Fix = result.state == .noKey || result.state == .unauthorized ? .addKey : .turnOff(agent)
            items.append(HealthItem(id: "lookup-" + agent, title: L("Asking about %@'s plan does not work", name), detail: text,
                                    fix: fix, fixLabel: result.state == .noKey || result.state == .unauthorized ? L("Add a key…") : L("Stop asking")))
        }
        if let claude = usage.agent(ProviderLimitsClient.claude), !claude.limits.isEmpty,
           LimitFreshness.isStale(claude.limitsCapturedAt, now: Date()), !settings.claudeAsksItself, !settings.claudeLimitsLookup {
            items.append(HealthItem(id: "claude-stale", title: L("Claude Code's limits are an old reading"),
                                    detail: L("Claude Code's status line only runs in a terminal, so in the Claude app these figures stop coming. Having Claude Code look for itself keeps them current."),
                                    fix: .keepClaudeCurrent, fixLabel: L("Keep current"), urgent: false))
        }
        return items
    }

    func apply(_ fix: HealthItem.Fix) {
        switch fix {
        case .clean(let island): cleanLeftovers(island)
        case .disconnect(let agents): runInstaller(.uninstall, agents: agents)
        case .addKey:
            settingsPage = "usage"
            onOpenSettings?()
        case .turnOff(let agent): settings.setAsksProvider(agent, false)
        case .keepClaudeCurrent: settings.claudeAsksItself = true
        }
    }
}
