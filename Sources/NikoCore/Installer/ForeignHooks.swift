import Foundation

/// Hooks that other islands left behind in the agents' config files.
///
/// An island that is uninstalled does not always take its hooks with it. They stay in Claude
/// Code's, Codex's, Cursor's… settings and run on every event: Vibe Island's bridge, finding no
/// app, searches Spotlight for it each time (about 60 ms), an old Ping Island bridge looks for a
/// socket that is gone. They also stand in line in front of ours for permission requests.
///
/// Found here by the commands they run; taken out only when the user asks, one island at a time,
/// with a backup of every file changed. The other island's own folders are not touched.
public enum ForeignHooks {
    public struct Island: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        /// Text in a hook's command that says the hook is this island's.
        public let markers: [String]
        /// Where its app would be, to tell "left behind" from "still in use".
        public let bundleIDs: [String]
        public let appNames: [String]
    }

    public static let known: [Island] = [
        Island(id: "vibe-island", name: "Vibe Island", markers: ["vibe-island-bridge", "vibe-island-statusline", "/.vibe-island/"],
               bundleIDs: ["app.vibeisland.macos"], appNames: ["Vibe Island.app", "vibe-island.app"]),
        Island(id: "ping-island", name: "Ping Island", markers: ["ping-island-bridge", "/.ping-island/"],
               bundleIDs: [], appNames: ["Ping Island.app", "State Studio.app"]),
        Island(id: "codeisland", name: "CodeIsland", markers: ["codeisland-bridge", "/.codeisland/"],
               bundleIDs: [], appNames: ["CodeIsland.app"]),
    ]

    /// One config file holding an island's hooks.
    public struct Place: Sendable, Equatable {
        public var agent: String
        /// Relative to the home folder.
        public var file: String
        public var hooks: Int

        public init(agent: String, file: String, hooks: Int) {
            self.agent = agent
            self.file = file
            self.hooks = hooks
        }
    }

    public struct Finding: Sendable, Equatable, Identifiable {
        public var island: Island
        public var places: [Place]
        /// Claude Code's status line goes through the island's (directly, or via ours).
        public var statusLine = false
        /// Its app is still on this Mac: then these hooks are in use, not left behind.
        public var installed = false
        public var id: String { island.id }
        public var hooks: Int { places.reduce(0) { $0 + $1.hooks } }

        public init(island: Island, places: [Place], statusLine: Bool = false, installed: Bool = false) {
            self.island = island
            self.places = places
            self.statusLine = statusLine
            self.installed = installed
        }
        public var agents: [String] {
            var seen: [String] = []
            for place in places where !seen.contains(place.agent) { seen.append(place.agent) }
            return seen
        }
    }

    /// Whether a command belongs to the island.
    static func belongs(_ command: String, to island: Island) -> Bool {
        island.markers.contains { command.contains($0) }
    }

    /// A hook entry is the island's when one of the commands it runs is.
    static func isEntry(_ object: JSONObject, of island: Island) -> Bool {
        for key in ["command", "bash", "script"] {
            if let command = object[key]?.stringValue, belongs(command, to: island) { return true }
        }
        return false
    }

    /// The JSON config files of the agents Niko Island knows, relative to home, with their agent.
    static func configFiles() -> [(agent: String, file: String)] {
        var out: [(String, String)] = []
        for agent in AgentRegistry.installable {
            for file in agent.files where file.hasSuffix(".json") && !out.contains(where: { $0.1 == file }) {
                out.append((agent.id, file))
            }
        }
        return out
    }

    static func read(_ path: String) -> (root: JSONObject, text: String)? {
        guard let data = FileManager.default.contents(atPath: path), data.count < 4_000_000,
              let root = (try? JSONValue.parse(data))?.objectValue else { return nil }
        return (root, String(decoding: data, as: UTF8.self))
    }

    /// What each known island left in the agents' configs and in the status line.
    /// `isInstalled` says whether the island's app is on this Mac.
    public static func scan(home: URL, paths: NikoPaths, isInstalled: (Island) -> Bool) -> [Finding] {
        var findings: [Finding] = []
        let files = configFiles()
        let ours = (try? String(contentsOf: paths.statuslineScript, encoding: .utf8)).flatMap(Shims.extractUserSection) ?? ""
        let original = (try? String(contentsOf: paths.statuslineOriginal, encoding: .utf8)) ?? ""
        let claude = read(home.appendingPathComponent(".claude/settings.json").path)?.root["statusLine"]?["command"]?.stringValue ?? ""
        for island in known {
            var finding = Finding(island: island, places: [])
            for (agent, file) in files {
                guard let (root, _) = read(home.appendingPathComponent(file).path) else { continue }
                let count = strip(.object(root), island: island).removed
                if count > 0 { finding.places.append(Place(agent: agent, file: file, hooks: count)) }
            }
            finding.statusLine = belongs(ours, to: island) || belongs(original, to: island) || belongs(claude, to: island)
            guard !finding.places.isEmpty || finding.statusLine else { continue }
            finding.installed = isInstalled(island)
            findings.append(finding)
        }
        return findings
    }

    /// Takes the island's entries out of `value`. Hook lists, matcher groups and event keys that
    /// held nothing else are taken out with them; everything else is left as it was.
    static func strip(_ value: JSONValue, island: Island) -> (value: JSONValue, removed: Int, emptied: Bool) {
        switch value {
        case .array(let items):
            var kept: [JSONValue] = []
            var removed = 0
            for item in items {
                if let object = item.objectValue, isEntry(object, of: island) {
                    removed += 1
                    continue
                }
                let inner = strip(item, island: island)
                removed += inner.removed
                if !inner.emptied { kept.append(inner.value) }
            }
            return (.array(kept), removed, removed > 0 && kept.isEmpty)
        case .object(let object):
            var result = object
            var removed = 0
            for member in object.members {
                let inner = strip(member.value, island: island)
                guard inner.removed > 0 else { continue }
                removed += inner.removed
                if inner.emptied { result[member.key] = nil } else { result[member.key] = inner.value }
            }
            // A group left with only its settings (a matcher, a switch) held nothing but those hooks.
            let holdsMore = result.members.contains { $0.value.objectValue != nil || $0.value.arrayValue != nil }
            return (.object(result), removed, removed > 0 && !holdsMore)
        default:
            return (value, 0, false)
        }
    }

    public struct Cleaned: Sendable, Equatable {
        public var files: [String] = []
        public var backups: [String] = []
        public var hooks = 0
        public var statusLine = false
        public var failures: [String] = []
    }

    /// Takes the island's hooks out of every agent config, and its status line out of the chain.
    public static func clean(_ island: Island, home: URL, paths: NikoPaths, now: Date = Date()) -> Cleaned {
        var cleaned = Cleaned()
        let stamp: String = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            return formatter.string(from: now)
        }()
        func backup(_ path: String, _ data: Data, mode: mode_t) -> Bool {
            // Never over an earlier backup (two clean-ups in the same second would lose the original).
            var destination = path + Installer.backupInfix + stamp
            var counter = 2
            while FileManager.default.fileExists(atPath: destination) {
                destination = path + Installer.backupInfix + stamp + "-\(counter)"
                counter += 1
            }
            guard AtomicFile.write(data, to: destination, mode: mode) else { return false }
            cleaned.backups.append(destination)
            return true
        }
        func mode(of path: String) -> mode_t {
            var st = stat()
            return stat(path, &st) == 0 ? st.st_mode & 0o7777 : 0o600
        }

        for (_, file) in configFiles() {
            let path = home.appendingPathComponent(file).path
            guard let data = FileManager.default.contents(atPath: path), let (root, text) = read(path) else { continue }
            let result = strip(.object(root), island: island)
            guard var object = result.value.objectValue else { continue }
            var statusLine = false
            if file == ".claude/settings.json", let command = root["statusLine"]?["command"]?.stringValue, belongs(command, to: island) {
                // Its status line, set straight into Claude Code (not through ours): it only fed the island.
                object["statusLine"] = nil
                statusLine = true
            }
            guard result.removed > 0 || statusLine else { continue }
            let permissions = mode(of: path)
            // Write through symlinks (dotfile managers) instead of replacing the link.
            let target = NikoPaths.canonicalPath(path)
            guard backup(path, data, mode: permissions),
                  AtomicFile.write(JSONValue.object(object).serializedData(.detect(from: text)), to: target, mode: permissions) else {
                cleaned.failures.append(file)
                continue
            }
            cleaned.files.append(file)
            cleaned.hooks += result.removed
            if statusLine { cleaned.statusLine = true }
        }

        // Ours, chained to the island's status line when we were installed after it.
        if let script = try? String(contentsOf: paths.statuslineScript, encoding: .utf8),
           let section = Shims.extractUserSection(from: script), belongs(section, to: island) {
            let rewritten = Shims.statuslineScript(paths: paths)
            if backup(paths.statuslineScript.path, Data(script.utf8), mode: 0o700),
               AtomicFile.write(Data(rewritten.utf8), to: paths.statuslineScript.path, mode: 0o755) {
                cleaned.statusLine = true
            } else {
                cleaned.failures.append(paths.statuslineScript.path)
            }
        }
        // What uninstalling Niko Island would put back as the status line: not the island's.
        if let data = FileManager.default.contents(atPath: paths.statuslineOriginal.path),
           belongs(String(decoding: data, as: UTF8.self), to: island) {
            if backup(paths.statuslineOriginal.path, data, mode: 0o600) {
                unlink(paths.statuslineOriginal.path)
                cleaned.statusLine = true
            } else {
                cleaned.failures.append(paths.statuslineOriginal.path)
            }
        }
        return cleaned
    }
}
