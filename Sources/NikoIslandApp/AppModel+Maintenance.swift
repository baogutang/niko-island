import Foundation
import NikoCore

/// State of the "Hooks" section in Settings.
public struct MaintenanceState: Sendable, Equatable {
    public struct AgentRow: Identifiable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var stability: AgentDescriptor.Stability
        public var wired: Bool
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
            return MaintenanceState.AgentRow(id: agent.id, name: agent.displayName, stability: agent.stability, wired: wired)
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
