import Foundation

public enum HookMergeError: Error, CustomStringConvertible, Equatable {
    case unexpectedShape(String)

    public var description: String {
        switch self {
        case .unexpectedShape(let what): return "unexpected config shape: \(what)"
        }
    }
}

/// How an agent's config file spells a hook registration. The shapes below
/// come from each agent's own hook reference.
public struct HookDialect: Sendable, Equatable {
    public enum Layout: Sendable, Equatable {
        /// `event: [{ "matcher": …, "hooks": [entry] }]` — Claude Code, and the many agents that adopted its format.
        case groups
        /// `event: [entry]` — Cursor, Windsurf.
        case flat
    }

    /// A key the agent needs next to its hooks (a format version, an on switch).
    public struct Required: Sendable, Equatable {
        public var path: [String]
        public var value: JSONValue
    }

    /// Keys from the root of the file down to the object that maps event names to arrays.
    public var container: [String] = ["hooks"]
    public var layout: Layout = .groups
    /// Value of an entry's `type`; nil leaves the key out.
    public var entryType: String? = "command"
    /// Key of the per-hook timeout and how many of its units make a second; nil leaves it out.
    public var timeoutKey: String? = "timeout"
    public var timeoutScale = 1
    /// Fields added to every entry of ours.
    public var entryFields = JSONObject()
    public var required: [Required] = []

    public static let claude = HookDialect()
    /// `~/.cursor/hooks.json`: `{ "version": 1, "hooks": { event: [{ "command": … }] } }`.
    public static let cursor = HookDialect(layout: .flat, entryType: nil, required: [Required(path: ["version"], value: .int(1))])
    /// `~/.codeium/windsurf/hooks.json`: `{ "hooks": { event: [{ "command": …, "show_output": false }] } }`.
    public static let windsurf = HookDialect(layout: .flat, entryType: nil, timeoutKey: nil, entryFields: ["show_output": .bool(false)])
    /// `~/.gemini/settings.json`: Claude's shape, timeouts in milliseconds, entries carry a name.
    public static let gemini = HookDialect(timeoutScale: 1000, entryFields: ["name": .string("niko-island")])
    /// `~/.zcode/cli/config.json`: `{ "hooks": { "enabled": true, "events": { event: [group] } } }`.
    public static let zcode = HookDialect(container: ["hooks", "events"], timeoutKey: "timeoutMs", timeoutScale: 1000,
                                          entryFields: ["async": .bool(false)],
                                          required: [Required(path: ["hooks", "enabled"], value: .bool(true))])
    /// `~/.trae/hooks.json`: Claude's shape under a format version.
    public static let trae = HookDialect(required: [Required(path: ["version"], value: .int(1))])
}

/// Pure JSON surgery for hook configs (INTEGRATIONS "generic settings-adapter
/// pattern"). The only entries this code ever adds, changes or removes are
/// ones whose command contains our marker substring.
public enum HookMerge {
    public static let markers = [NikoVersion.hookMarker, NikoVersion.statuslineMarker]

    public static func isOurs(command: String) -> Bool {
        markers.contains { command.contains($0) }
    }

    /// A hook entry (`{"type":"command","command":…}`) or flat entry is ours iff its command says so.
    static func isOurs(_ entry: JSONValue) -> Bool {
        guard let command = entry["command"]?.stringValue else { return false }
        return isOurs(command: command)
    }

    // MARK: Paths

    static func value(at path: [String], in root: JSONObject) -> JSONValue? {
        var current: JSONValue = .object(root)
        for key in path {
            guard let next = current.objectValue?[key] else { return nil }
            current = next
        }
        return current
    }

    /// Sets (or with nil removes) the value at `path`. Parents created on the
    /// way in are objects; parents emptied by a removal are removed too.
    static func setting(_ value: JSONValue?, at path: [String], in root: JSONObject) -> JSONObject {
        guard let key = path.first else { return root }
        var out = root
        if path.count == 1 {
            out[key] = value
            return out
        }
        let child = setting(value, at: Array(path.dropFirst()), in: root[key]?.objectValue ?? JSONObject())
        out[key] = child.isEmpty && value == nil ? nil : .object(child)
        return out
    }

    // MARK: Entries

    static func entry(spec: HookSpec, command: String, dialect: HookDialect) -> JSONValue {
        var hook = JSONObject()
        if let type = dialect.entryType { hook["type"] = .string(type) }
        hook["command"] = .string(command)
        if let key = dialect.timeoutKey, let timeout = spec.timeout { hook[key] = .int(timeout * dialect.timeoutScale) }
        for member in dialect.entryFields.members { hook[member.key] = member.value }
        guard dialect.layout == .groups else { return .object(hook) }
        var group = JSONObject()
        if let matcher = spec.matcher { group["matcher"] = .string(matcher) }
        group["hooks"] = .array([.object(hook)])
        return .object(group)
    }

    public static func group(spec: HookSpec, command: String) -> JSONValue {
        entry(spec: spec, command: command, dialect: .claude)
    }

    /// Removes every entry of ours from the dialect's event table. Containers
    /// are only dropped when *we* emptied them; foreign content — including
    /// foreign empty arrays — is returned exactly as it was.
    public static func strip(_ root: JSONObject, dialect: HookDialect = .claude) -> (root: JSONObject, removed: Int) {
        guard let hooks = value(at: dialect.container, in: root)?.objectValue else { return (root, 0) }
        var removed = 0
        var newHooks = JSONObject()
        for member in hooks.members {
            guard let groups = member.value.arrayValue else {
                newHooks[member.key] = member.value
                continue
            }
            var removedHere = 0
            var newGroups: [JSONValue] = []
            for group in groups {
                if isOurs(group) {             // flat form: the group itself is the hook entry
                    removedHere += 1
                    continue
                }
                guard let object = group.objectValue, let entries = object["hooks"]?.arrayValue else {
                    newGroups.append(group)
                    continue
                }
                let kept = entries.filter { !isOurs($0) }
                let dropped = entries.count - kept.count
                removedHere += dropped
                if dropped > 0, kept.isEmpty { continue }   // the group existed only for us
                var copy = object
                if dropped > 0 { copy["hooks"] = .array(kept) }
                newGroups.append(.object(copy))
            }
            removed += removedHere
            if removedHere > 0, newGroups.isEmpty { continue }   // the event existed only for us
            newHooks[member.key] = removedHere > 0 ? .array(newGroups) : member.value
        }
        guard removed > 0 else { return (root, 0) }
        return (setting(newHooks.isEmpty ? nil : .object(newHooks), at: dialect.container, in: root), removed)
    }

    /// Strips any previous entries of ours, then appends one entry per spec
    /// after whatever the user already has for that event.
    public static func install(into root: JSONObject, specs: [HookSpec], dialect: HookDialect = .claude,
                               command: (HookSpec) -> String) throws -> JSONObject {
        var out = strip(root, dialect: dialect).root
        // Every step down to the event table has to be an object (or absent).
        for depth in 1...dialect.container.count {
            let prefix = Array(dialect.container.prefix(depth))
            if let existing = value(at: prefix, in: out), existing.objectValue == nil {
                throw HookMergeError.unexpectedShape("\"\(prefix.joined(separator: "."))\" is not an object")
            }
        }
        var hooks = value(at: dialect.container, in: out)?.objectValue ?? JSONObject()
        for spec in specs {
            var groups: [JSONValue]
            switch hooks[spec.event] {
            case .none: groups = []
            case .some(.array(let existing)): groups = existing
            case .some: throw HookMergeError.unexpectedShape("\(dialect.container.joined(separator: ".")).\(spec.event) is not an array")
            }
            groups.append(entry(spec: spec, command: command(spec), dialect: dialect))
            hooks[spec.event] = .array(groups)
        }
        out = setting(.object(hooks), at: dialect.container, in: out)
        for required in dialect.required {
            let current = value(at: required.path, in: out)
            // Add what is missing; the only thing overruled is an "off" switch, which would make connecting pointless.
            if current == nil || (current == .bool(false) && required.value == .bool(true)) {
                out = setting(required.value, at: required.path, in: out)
            }
        }
        return out
    }

    /// Drops empty event arrays and an empty event table (comparison helper).
    static func pruningEmptyContainers(_ root: JSONObject, dialect: HookDialect = .claude) -> JSONObject {
        guard let hooks = value(at: dialect.container, in: root)?.objectValue else { return root }
        let kept = JSONObject(hooks.members.filter { $0.value.arrayValue?.isEmpty != true })
        return setting(kept.isEmpty ? nil : .object(kept), at: dialect.container, in: root)
    }

    /// The config with everything installing can add taken out: empty
    /// containers and the dialect's required keys. Two configs that compare
    /// equal this way differ only by what `install` is allowed to touch.
    static func comparable(_ root: JSONObject, dialect: HookDialect) -> JSONObject {
        var out = pruningEmptyContainers(strip(root, dialect: dialect).root, dialect: dialect)
        for required in dialect.required { out = setting(nil, at: required.path, in: out) }
        return out
    }

    public static func containsOurs(_ root: JSONObject, dialect: HookDialect = .claude) -> Bool {
        strip(root, dialect: dialect).removed > 0 || statusLineIsOurs(root)
    }

    // MARK: statusLine

    public static func statusLineIsOurs(_ root: JSONObject) -> Bool {
        guard let command = root["statusLine"]?["command"]?.stringValue else { return false }
        return isOurs(command: command)
    }

    public enum StatusLineOutcome: Equatable {
        /// Ours is now installed. `displaced` is the user's previous value (`.null` if there was none).
        case installed(root: JSONObject, displaced: JSONValue?)
        /// Left alone because the existing value is not something we can wrap.
        case skipped(String)
    }

    public static func installStatusLine(into root: JSONObject, command: String) -> StatusLineOutcome {
        var out = root
        switch root["statusLine"] {
        case .none, .some(.null):
            out["statusLine"] = .object(["type": .string("command"), "command": .string(command)])
            return .installed(root: out, displaced: .null)
        case .some(.object(var existing)):
            let wasOurs = statusLineIsOurs(root)
            guard wasOurs || existing["command"]?.stringValue != nil else {
                return .skipped("statusLine has no command to chain")
            }
            let displaced: JSONValue? = wasOurs ? nil : .object(existing)
            existing["command"] = .string(command)
            if existing["type"] == nil { existing["type"] = .string("command") }
            out["statusLine"] = .object(existing)
            return .installed(root: out, displaced: displaced)
        case .some:
            return .skipped("statusLine is not an object")
        }
    }

    /// Puts back what `installStatusLine` displaced. No-op unless the current value is ours.
    public static func removeStatusLine(from root: JSONObject, restoring original: JSONValue?) -> JSONObject {
        guard statusLineIsOurs(root) else { return root }
        var out = root
        if let original, !original.isNull {
            out["statusLine"] = original
        } else {
            out["statusLine"] = nil
        }
        return out
    }
}
