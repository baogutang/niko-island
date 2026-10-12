import Foundation

public enum HookMergeError: Error, CustomStringConvertible, Equatable {
    case unexpectedShape(String)

    public var description: String {
        switch self {
        case .unexpectedShape(let what): return "unexpected config shape: \(what)"
        }
    }
}

/// Pure JSON surgery for Claude-dialect hook configs (INTEGRATIONS "generic
/// settings-adapter pattern"). The only entries this code ever adds, changes
/// or removes are ones whose command contains our marker substring.
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

    public static func group(spec: HookSpec, command: String) -> JSONValue {
        var hook = JSONObject(["type": .string("command"), "command": .string(command)])
        if let timeout = spec.timeout { hook["timeout"] = .int(timeout) }
        var group = JSONObject()
        if let matcher = spec.matcher { group["matcher"] = .string(matcher) }
        group["hooks"] = .array([.object(hook)])
        return .object(group)
    }

    /// Removes every entry of ours under `root.hooks`. Containers are only
    /// dropped when *we* emptied them; foreign content — including foreign
    /// empty arrays — is returned exactly as it was.
    public static func strip(_ root: JSONObject) -> (root: JSONObject, removed: Int) {
        guard let hooks = root["hooks"]?.objectValue else { return (root, 0) }
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
        var out = root
        if removed > 0, newHooks.isEmpty {
            out["hooks"] = nil
        } else if removed > 0 {
            out["hooks"] = .object(newHooks)
        }
        return (out, removed)
    }

    /// Strips any previous entries of ours, then appends one group per spec
    /// after whatever the user already has for that event.
    public static func install(into root: JSONObject, specs: [HookSpec], command: (HookSpec) -> String) throws -> JSONObject {
        var out = strip(root).root
        var hooks: JSONObject
        switch out["hooks"] {
        case .none: hooks = JSONObject()
        case .some(.object(let existing)): hooks = existing
        case .some: throw HookMergeError.unexpectedShape("\"hooks\" is not an object")
        }
        for spec in specs {
            var groups: [JSONValue]
            switch hooks[spec.event] {
            case .none: groups = []
            case .some(.array(let existing)): groups = existing
            case .some: throw HookMergeError.unexpectedShape("hooks.\(spec.event) is not an array")
            }
            groups.append(group(spec: spec, command: command(spec)))
            hooks[spec.event] = .array(groups)
        }
        out["hooks"] = .object(hooks)
        return out
    }

    /// Drops empty event arrays and an empty `hooks` object (comparison helper).
    static func pruningEmptyContainers(_ root: JSONObject) -> JSONObject {
        guard let hooks = root["hooks"]?.objectValue else { return root }
        let kept = JSONObject(hooks.members.filter { $0.value.arrayValue?.isEmpty != true })
        var out = root
        out["hooks"] = kept.isEmpty ? nil : .object(kept)
        return out
    }

    public static func containsOurs(_ root: JSONObject) -> Bool {
        strip(root).removed > 0 || statusLineIsOurs(root)
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
