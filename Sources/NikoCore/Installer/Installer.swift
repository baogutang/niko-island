import Foundation

public enum InstallAction: String, Sendable { case install, uninstall }

public struct InstallOptions: Sendable {
    /// Home directory that holds the agents' config directories.
    public var home: URL
    public var paths: NikoPaths
    /// `nil`: the stable defaults for install, every known agent for uninstall.
    public var agentIDs: [String]?
    public var dryRun = false
    public var includeStatusLine = true
    public var bridgeBinary: String?
    public var appExecutable: String?
    /// Uninstall only: also delete our runtime directory and config backups.
    public var purge = false
    public var now = Date()
    /// Test seams.
    public var failAfterWrites: Int?
    public var beforeVerify: (@Sendable () -> Void)?
    public var scanOverride: (@Sendable () throws -> ScanReport)?

    public init(home: URL = NikoPaths.userHome(), paths: NikoPaths = .resolve()) {
        self.home = home
        self.paths = paths
    }
}

public struct FileChange: Sendable, Equatable {
    public enum Kind: String, Sendable { case create, modify, delete }

    public var agent: String
    /// HOME-relative path as the agent sees it.
    public var relativePath: String
    public var kind: Kind
    public var before: Data?
    public var after: Data?
    public var summary: String
    /// Mode for files we create (existing files keep theirs).
    public var createMode: mode_t = 0o644
    /// Shared configs are backed up before every change. Files we generate
    /// ourselves are not: a copy of our own output next to it is only clutter.
    public var keepsBackup = false
}

public struct AgentOutcome: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case changed
        case unchanged
        case notDetected
        case skipped(String)
    }

    public var id: String
    public var status: Status
}

public struct InstallPlan: Sendable {
    public var action: InstallAction
    public var changes: [FileChange] = []
    public var outcomes: [AgentOutcome] = []
    public var notes: [String] = []
    /// Install: the user's previous `statusLine` value that we wrap (`.null` = there was none).
    public var displacedStatusLine: JSONValue?
    public var statuslineUserSection: String?
    public var enablesHTTPIngress = false

    public var isNoOp: Bool { changes.isEmpty }
}

public struct InstallResult: Sendable {
    public var plan: InstallPlan
    public var applied = false
    public var rolledBack = false
    public var error: String?
    public var backups: [String] = []

    public var succeeded: Bool { error == nil }

    /// The plan changes something for this agent.
    public func touched(_ agent: String) -> Bool { plan.changes.contains { $0.agent == agent } }
}

public enum InstallError: Error, CustomStringConvertible {
    case changedSinceScan(String)
    case writeFailed(String)
    case verificationFailed(String)
    case injectedFault

    public var description: String {
        switch self {
        case .changedSinceScan(let p): return "\(p) changed after it was scanned; nothing was written to it"
        case .writeFailed(let p): return "could not write \(p)"
        case .verificationFailed(let p): return "verification failed for \(p)"
        case .injectedFault: return "injected fault"
        }
    }
}

/// Hook installation (PROTOCOLS §5): scan → plan → mutate atomically with
/// backups → verify by rescanning → roll back on any mismatch.
public struct Installer: Sendable {
    public static let backupInfix = ".niko-backup-"
    static let backupsToKeep = 3

    public let options: InstallOptions

    public init(options: InstallOptions) { self.options = options }

    // MARK: Entry points

    public func agents(for action: InstallAction) -> [AgentDescriptor] {
        if let ids = options.agentIDs {
            return ids.compactMap(AgentRegistry.descriptor).filter { $0.stability != .planned }
        }
        switch action {
        case .install: return AgentRegistry.defaultIDs.compactMap(AgentRegistry.descriptor)
        case .uninstall: return AgentRegistry.installable
        }
    }

    public func scan(_ action: InstallAction, includeVersions: Bool = false) throws -> ScanReport {
        if let scanOverride = options.scanOverride { return try scanOverride() }
        return try ScanProbe.run(home: options.home, agents: agents(for: action), includeVersions: includeVersions)
    }

    /// Scan, plan and — unless `dryRun` — apply.
    public func run(_ action: InstallAction) -> InstallResult {
        let report: ScanReport
        do {
            report = try scan(action)
        } catch {
            return InstallResult(plan: InstallPlan(action: action), error: "scan failed, nothing was changed: \(error)")
        }
        let plan = self.plan(action, scan: report)
        if options.dryRun { return InstallResult(plan: plan) }
        return apply(plan)
    }

    // MARK: Planning (pure apart from reading our own backups/sidecar)

    public func plan(_ action: InstallAction, scan: ScanReport) -> InstallPlan {
        var plan = InstallPlan(action: action)
        for agent in agents(for: action) {
            guard let scanned = scan.agents[agent.id] else {
                plan.outcomes.append(.init(id: agent.id, status: .skipped("not scanned")))
                continue
            }
            switch scanned.directory {
            case .missing:
                plan.outcomes.append(.init(id: agent.id, status: .notDetected))
                continue
            case .unknown:
                plan.outcomes.append(.init(id: agent.id, status: .skipped("~/\(agent.directory) is not an accessible directory")))
                continue
            case .present:
                break
            }
            let before = plan.changes.count
            var skip: String?
            switch action {
            case .install: skip = planInstall(agent, scanned: scanned, into: &plan)
            case .uninstall: skip = planUninstall(agent, scanned: scanned, into: &plan)
            }
            // Whatever an earlier version left behind goes either way (only files that carry our marker).
            if skip == nil, !agent.legacyFiles.isEmpty {
                skip = planOwnedRemoval(agent, files: agent.legacyFiles, scanned: scanned, into: &plan)
            }
            if let skip {
                plan.changes.removeSubrange(before...)
                plan.outcomes.append(.init(id: agent.id, status: .skipped(skip)))
            } else {
                plan.outcomes.append(.init(id: agent.id, status: plan.changes.count > before ? .changed : .unchanged))
            }
        }
        return plan
    }

    /// Tolerant read of a shared JSON config: missing or blank means `{}`.
    private func parseShared(_ state: ScanReport.FileState, file: String) -> Result<(root: JSONObject, text: String?), InstallSkip> {
        switch state {
        case .unreadable: return .failure(InstallSkip("~/\(file) is not a readable regular file — left untouched"))
        case .tooLarge(let size): return .failure(InstallSkip("~/\(file) is \(size) bytes, over the scan limit — left untouched"))
        case .missing: return .success((JSONObject(), nil))
        case .present(let data):
            let text = String(decoding: data, as: UTF8.self)
            guard Data(text.utf8) == data else { return .failure(InstallSkip("~/\(file) is not valid UTF-8 — left untouched")) }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .success((JSONObject(), text)) }
            guard let value = try? JSONValue.parse(data) else {
                return .failure(InstallSkip("~/\(file) is not valid JSON — left untouched"))
            }
            guard let root = value.objectValue else {
                return .failure(InstallSkip("~/\(file) is not a JSON object — left untouched"))
            }
            return .success((root, text))
        }
    }

    private struct InstallSkip: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    private func serialize(_ root: JSONObject, like original: String?) -> Data {
        let blank = original?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let style: JSONStyle = blank ? .pretty : .detect(from: original ?? "")
        return JSONValue.object(root).serializedData(style)
    }

    private func planInstall(_ agent: AgentDescriptor, scanned: ScanReport.Agent, into plan: inout InstallPlan) -> String? {
        switch agent.mechanism {
        case .none:
            return "no adapter yet"

        case .sharedSettings(let file, let events, let wantsStatusLine, let dialect):
            let parsed: (root: JSONObject, text: String?)
            switch parseShared(scanned.files[file] ?? .unreadable, file: file) {
            case .failure(let skip): return skip.reason
            case .success(let value): parsed = value
            }
            var root: JSONObject
            do {
                root = try HookMerge.install(into: parsed.root, specs: events, dialect: dialect) { _ in
                    Shims.hookCommand(paths: options.paths, source: agent.id, extraArguments: agent.bridgeArguments)
                }
            } catch {
                return "\(error) in ~/\(file) — left untouched"
            }
            var summary = "\(events.count) hook entries"
            var touchedStatusLine = false
            if wantsStatusLine, options.includeStatusLine {
                switch HookMerge.installStatusLine(into: root, command: Shims.statuslineCommand(paths: options.paths)) {
                case .installed(let updated, let displaced):
                    root = updated
                    touchedStatusLine = true
                    if let displaced {
                        plan.displacedStatusLine = displaced
                        if let original = displaced["command"]?.stringValue {
                            plan.statuslineUserSection = Shims.chainedUserSection(originalCommand: original)
                            summary += ", statusLine wrapped (your command is chained)"
                        } else {
                            summary += ", statusLine added"
                        }
                    }
                case .skipped(let why):
                    plan.notes.append("\(agent.displayName): \(why) — statusLine left as is")
                }
            }
            // Invariant: once our own entries are taken back out, the config is
            // exactly what the user had. If that ever fails, refuse to write.
            // (Empty hook containers are ignored: stripping cannot tell an empty
            // array the user wrote from one that only ever held our entry.)
            var check = HookMerge.comparable(root, dialect: dialect)
            var original = HookMerge.comparable(parsed.root, dialect: dialect)
            if touchedStatusLine {
                check["statusLine"] = nil
                original["statusLine"] = nil
            }
            guard check == original else { return "internal check failed for ~/\(file) — left untouched" }

            let after = serialize(root, like: parsed.text)
            let before = scanned.files[file]?.data
            if after != before {
                plan.changes.append(FileChange(agent: agent.id, relativePath: file, kind: before == nil ? .create : .modify,
                                               before: before, after: after, summary: summary, createMode: 0o600,
                                               keepsBackup: true))
            }
            return nil

        case .ownedHookFile(let file, let events):
            return planOwned(agent, file: file, content: PluginTemplates.hookFile(agent: agent, events: events, paths: options.paths),
                             scanned: scanned, into: &plan)

        case .ownedPluginDirectory(let directory, let events):
            if let skip = planOwned(agent, file: directory + "/plugin.json", content: PluginTemplates.pluginManifest(agent: agent),
                                    scanned: scanned, into: &plan) { return skip }
            return planOwned(agent, file: directory + "/hooks.json",
                             content: PluginTemplates.hookFile(agent: agent, events: events, paths: options.paths),
                             scanned: scanned, into: &plan)

        case .jsPlugin(let file):
            let skip = planOwned(agent, file: file, content: PluginTemplates.openCodePlugin(agent: agent, paths: options.paths),
                                 scanned: scanned, into: &plan)
            if skip == nil { plan.enablesHTTPIngress = true }
            return skip
        }
    }

    /// A file that is wholly ours: create it, refresh it, or refuse if someone else's file is in the way.
    private func planOwned(_ agent: AgentDescriptor, file: String, content: String, scanned: ScanReport.Agent,
                           into plan: inout InstallPlan) -> String? {
        let after = Data(content.utf8)
        switch scanned.files[file] ?? .unreadable {
        case .unreadable, .tooLarge:
            return "~/\(file) exists but is not a readable regular file — left untouched"
        case .missing:
            plan.changes.append(FileChange(agent: agent.id, relativePath: file, kind: .create, before: nil, after: after,
                                           summary: "new file"))
        case .present(let data):
            guard HookMerge.isOurs(command: String(decoding: data, as: UTF8.self)) else {
                return "~/\(file) exists and is not ours — left untouched"
            }
            if data != after {
                plan.changes.append(FileChange(agent: agent.id, relativePath: file, kind: .modify, before: data, after: after,
                                               summary: "refreshed"))
            }
        }
        return nil
    }

    private func planUninstall(_ agent: AgentDescriptor, scanned: ScanReport.Agent, into plan: inout InstallPlan) -> String? {
        switch agent.mechanism {
        case .none:
            return nil

        case .sharedSettings(let file, _, _, let dialect):
            let state = scanned.files[file] ?? .unreadable
            guard case .present(let data) = state else {
                if case .missing = state { return nil }
                return "~/\(file) is not readable — if it contains niko-bridge entries, remove them by hand"
            }
            let parsed: (root: JSONObject, text: String?)
            switch parseShared(state, file: file) {
            case .failure(let skip): return skip.reason
            case .success(let value): parsed = value
            }
            guard HookMerge.containsOurs(parsed.root, dialect: dialect) else { return nil }
            let stripped = HookMerge.strip(parsed.root, dialect: dialect)
            var root = stripped.root
            var summary = "removed \(stripped.removed) hook entries"
            if HookMerge.statusLineIsOurs(root) {
                let original = (try? Data(contentsOf: options.paths.statuslineOriginal)).flatMap { try? JSONValue.parse($0) }
                root = HookMerge.removeStatusLine(from: root, restoring: original)
                summary += original.map { $0.isNull ? ", statusLine removed" : ", statusLine restored" } ?? ", statusLine removed"
            }
            // If nothing else changed since we installed, hand back the user's
            // original bytes rather than a re-serialisation of them.
            let after = pristineBackup(for: file, matching: root, dialect: dialect) ?? serialize(root, like: parsed.text)
            if after != data {
                plan.changes.append(FileChange(agent: agent.id, relativePath: file, kind: .modify, before: data, after: after,
                                               summary: summary, keepsBackup: true))
            }
            return nil

        case .ownedHookFile(let file, _):
            return planOwnedRemoval(agent, files: [file], scanned: scanned, into: &plan)
        case .ownedPluginDirectory(let directory, _):
            return planOwnedRemoval(agent, files: [directory + "/hooks.json", directory + "/plugin.json"], scanned: scanned, into: &plan)
        case .jsPlugin(let file):
            return planOwnedRemoval(agent, files: [file], scanned: scanned, into: &plan)
        }
    }

    private func planOwnedRemoval(_ agent: AgentDescriptor, files: [String], scanned: ScanReport.Agent,
                                  into plan: inout InstallPlan) -> String? {
        for file in files {
            guard case .present(let data) = scanned.files[file] ?? .missing else { continue }
            // Only ever delete a file that carries our marker.
            guard HookMerge.isOurs(command: String(decoding: data, as: UTF8.self)) else { continue }
            plan.changes.append(FileChange(agent: agent.id, relativePath: file, kind: .delete, before: data, after: nil,
                                           summary: "removed"))
        }
        return nil
    }

    // MARK: Backups

    func absolute(_ relative: String) -> String { options.home.path + "/" + relative }

    /// Existing backups for a config file, newest first.
    public func backups(for relative: String) -> [String] {
        let path = absolute(relative)
        let directory = (path as NSString).deletingLastPathComponent
        let prefix = (path as NSString).lastPathComponent + Installer.backupInfix
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted(by: >).map { directory + "/" + $0 }
    }

    /// Bytes of the newest backup that is free of our entries and structurally
    /// identical (same keys, same order, same values) to `root`.
    private func pristineBackup(for relative: String, matching root: JSONObject, dialect: HookDialect) -> Data? {
        for path in backups(for: relative) {
            guard let data = FileManager.default.contents(atPath: path),
                  let object = (try? JSONValue.parse(data))?.objectValue else { continue }
            // Empty hook containers are ignored: stripping cannot recreate an
            // empty object the user had, but the backup still has it.
            // Neither can it tell whether a key the agent requires was ours to add:
            // the backup is what says so.
            if !HookMerge.containsOurs(object, dialect: dialect),
               HookMerge.comparable(object, dialect: dialect) == HookMerge.comparable(root, dialect: dialect) { return data }
        }
        return nil
    }

    private func backupPath(for relative: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = absolute(relative) + Installer.backupInfix + formatter.string(from: options.now)
        var candidate = base
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }

    // MARK: Apply / verify / rollback

    private struct JournalEntry {
        let change: FileChange
        let path: String        // as the agent sees it
        let target: String      // symlink-resolved path we actually write
        let mode: mode_t?
        let backup: String?
        let createdDirectories: [String]
    }

    public func apply(_ plan: InstallPlan) -> InstallResult {
        var result = InstallResult(plan: plan)
        guard !plan.isNoOp else {
            finish(plan, result: &result)
            return result
        }

        var journal: [JournalEntry] = []
        let previousSidecar = FileManager.default.contents(atPath: options.paths.statuslineOriginal.path)
        do {
            if plan.action == .install {
                // Shims first: a hook must never point at something that is not there yet.
                // A freshly displaced statusline command replaces whatever an older
                // script chained to; otherwise the existing user section is kept.
                try Shims.install(paths: options.paths, bridgeBinary: options.bridgeBinary,
                                  appExecutable: options.appExecutable, statuslineUserSection: plan.statuslineUserSection,
                                  overrideUserSection: plan.statuslineUserSection != nil)
                if let displaced = plan.displacedStatusLine {
                    AtomicFile.write(displaced.serializedData(.pretty), to: options.paths.statuslineOriginal.path, mode: 0o600)
                }
            }
            for (index, change) in plan.changes.enumerated() {
                if let limit = options.failAfterWrites, index >= limit { throw InstallError.injectedFault }
                journal.append(try write(change))
            }
            options.beforeVerify?()
            try verify(plan)
        } catch {
            rollback(journal)
            if plan.action == .install {
                if let previousSidecar {
                    AtomicFile.write(previousSidecar, to: options.paths.statuslineOriginal.path, mode: 0o600)
                } else {
                    unlink(options.paths.statuslineOriginal.path)
                }
            }
            result.rolledBack = true
            result.error = "\(error) — every file was restored to its previous content"
            return result
        }

        result.applied = true
        result.backups = journal.compactMap(\.backup)
        for change in plan.changes { pruneBackups(for: change.relativePath) }
        finish(plan, result: &result)
        return result
    }

    private func write(_ change: FileChange) throws -> JournalEntry {
        let path = absolute(change.relativePath)
        let current = FileManager.default.contents(atPath: path)
        guard current == change.before else { throw InstallError.changedSinceScan(path) }

        var st = stat()
        let mode: mode_t? = stat(path, &st) == 0 ? st.st_mode & 0o7777 : nil
        // Write through symlinks (dotfile managers) instead of replacing the link.
        let target = current == nil ? path : NikoPaths.canonicalPath(path)

        var backup: String?
        if let before = change.before, change.keepsBackup {
            let destination = backupPath(for: change.relativePath)
            guard AtomicFile.write(before, to: destination, mode: mode ?? 0o600) else {
                throw InstallError.writeFailed(destination)
            }
            backup = destination
        }

        var created: [String] = []
        if let after = change.after {
            var directory = (target as NSString).deletingLastPathComponent
            var missing: [String] = []
            while !FileManager.default.fileExists(atPath: directory), directory.count > 1 {
                missing.append(directory)
                directory = (directory as NSString).deletingLastPathComponent
            }
            for dir in missing.reversed() {
                guard mkdir(dir, 0o755) == 0 || errno == EEXIST else {
                    if let backup { unlink(backup) }
                    throw InstallError.writeFailed(dir)
                }
                created.append(dir)
            }
            guard AtomicFile.write(after, to: target, mode: mode ?? change.createMode) else {
                created.reversed().forEach { rmdir($0) }
                if let backup { unlink(backup) }
                throw InstallError.writeFailed(target)
            }
        } else {
            guard unlink(target) == 0 else {
                if let backup { unlink(backup) }
                throw InstallError.writeFailed(target)
            }
        }
        return JournalEntry(change: change, path: path, target: target, mode: mode, backup: backup, createdDirectories: created)
    }

    /// Phase C: read everything back through the same probe and compare.
    private func verify(_ plan: InstallPlan) throws {
        let report = try scan(plan.action)
        for change in plan.changes {
            let state = report.file(change.relativePath, agent: change.agent)
            switch (change.after, state) {
            case (.some(let expected), .present(let actual)) where expected == actual:
                break
            case (.none, .missing):
                break
            default:
                throw InstallError.verificationFailed("~/" + change.relativePath)
            }
            guard let after = change.after, change.relativePath.hasSuffix(".json") else { continue }
            var dialect = HookDialect.claude
            if case .sharedSettings(_, _, _, let own)? = AgentRegistry.descriptor(change.agent)?.mechanism { dialect = own }
            guard let object = (try? JSONValue.parse(after))?.objectValue,
                  HookMerge.containsOurs(object, dialect: dialect) == (plan.action == .install)
                    || HookMerge.isOurs(command: String(decoding: after, as: UTF8.self)) == (plan.action == .install) else {
                throw InstallError.verificationFailed("~/" + change.relativePath)
            }
        }
    }

    private func rollback(_ journal: [JournalEntry]) {
        for entry in journal.reversed() {
            if let before = entry.change.before {
                AtomicFile.write(before, to: entry.target, mode: entry.mode ?? 0o600)
            } else {
                unlink(entry.target)
            }
            entry.createdDirectories.reversed().forEach { rmdir($0) }
            // Nothing changed in the end, so this run's backup is just clutter.
            if let backup = entry.backup { unlink(backup) }
        }
    }

    private func pruneBackups(for relative: String) {
        for stale in backups(for: relative).dropFirst(Installer.backupsToKeep) { unlink(stale) }
    }

    /// Side effects that only make sense once the configs are in their final state.
    private func finish(_ plan: InstallPlan, result: inout InstallResult) {
        switch plan.action {
        case .install:
            if plan.isNoOp {
                // Nothing to write, but keep the shims and bridge cache fresh.
                _ = try? Shims.install(paths: options.paths, bridgeBinary: options.bridgeBinary,
                                       appExecutable: options.appExecutable, statuslineUserSection: plan.statuslineUserSection)
            }
            if plan.enablesHTTPIngress {
                var settings = NikoSettings.load(paths: options.paths)
                if !settings.httpIngressEnabled {
                    settings.httpIngressEnabled = true
                    settings.save(paths: options.paths)
                }
                _ = try? HTTPIngressServer.loadOrCreateToken(paths: options.paths)
            }
        case .uninstall:
            if options.agentIDs == nil || options.agentIDs?.contains("claude") == true {
                unlink(options.paths.statuslineOriginal.path)
            }
            // A partial uninstall leaves the shims in place for the agents that still use them.
            guard options.agentIDs == nil else { return }
            Shims.remove(paths: options.paths)
            for agent in agents(for: .uninstall) {
                // Remove plugin directories that were created for us and are now empty.
                if case .ownedPluginDirectory(let directory, _) = agent.mechanism { rmdir(absolute(directory)) }
                for file in agent.legacyFiles { rmdir((absolute(file) as NSString).deletingLastPathComponent) }
            }
            guard options.purge else { return }
            for agent in agents(for: .uninstall) {
                for file in agent.files { backups(for: file).forEach { unlink($0) } }
            }
            let root = options.paths.root.path
            if (try? SecureDirectory.validate(options.paths.root)) != nil, root.split(separator: "/").count >= 2 {
                try? FileManager.default.removeItem(atPath: root)
            }
        }
    }
}

// MARK: - Human-readable reporting

extension InstallResult {
    public func report(home: String) -> String {
        var lines: [String] = []
        let verb = plan.action == .install ? "install" : "uninstall"
        for outcome in plan.outcomes {
            let name = AgentRegistry.displayName(for: outcome.id)
            switch outcome.status {
            case .notDetected:
                continue
            case .unchanged:
                lines.append("  \(name): already \(plan.action == .install ? "up to date" : "clean")")
            case .skipped(let reason):
                lines.append("  \(name): skipped — \(reason)")
            case .changed:
                for change in plan.changes where change.agent == outcome.id {
                    lines.append("  \(name): \(change.kind.rawValue) ~/\(change.relativePath) (\(change.summary))")
                }
            }
        }
        if plan.outcomes.allSatisfy({ $0.status == .notDetected }) {
            lines.append("  no supported agent directories were found under \(home)")
        }
        for note in plan.notes { lines.append("  note: \(note)") }
        if let error {
            lines.append("\(verb) failed: \(error)")
        } else if !applied, !plan.isNoOp {
            lines.append("Dry run: nothing was changed.")
        } else if applied {
            for backup in backups { lines.append("  backup: \(backup.replacingOccurrences(of: home, with: "~"))") }
            lines.append("\(verb) complete.")
        } else {
            lines.append("Nothing to do.")
        }
        return lines.joined(separator: "\n")
    }
}
