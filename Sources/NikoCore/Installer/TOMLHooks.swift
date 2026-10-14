import Foundation

/// Kimi Code keeps its hooks as `[[hooks]]` tables in `config.toml`, next to
/// the user's own settings. Ours go in one block at the end of the file,
/// between two marker comments, and nothing outside that block is changed.
/// Should a tool rewrite the file and drop the comments, a `[[hooks]]` table
/// whose command carries our marker is still recognised as ours.
///
/// Kimi Code refuses to load a config with a key it does not know, so a table
/// of ours holds `event`, `matcher`, `command` and `timeout` and nothing else.
public enum TOMLHooks {
    public static let beginMarker = "# >>> niko-island (niko-bridge)"
    public static let endMarker = "# <<< niko-island (niko-bridge)"
    static let header = "[[hooks]]"

    public struct Refusal: Error, Equatable {
        public let reason: String
    }

    /// Takes any earlier block of ours out, then appends a fresh one.
    public static func install(into text: String, specs: [HookSpec], command: (HookSpec) -> String) -> Result<String, Refusal> {
        if let conflict = conflictingHooksKey(in: text) {
            return .failure(Refusal(reason: "already defines \(conflict), which a [[hooks]] table would clash with"))
        }
        var out = strip(text).text
        if !out.isEmpty {
            if !out.hasSuffix("\n") { out += "\n" }
            out += "\n"
        }
        out += block(specs: specs, command: command)
        return .success(out)
    }

    /// The text without our block or tables, and how many tables of ours there were.
    public static func strip(_ text: String) -> (text: String, removed: Int) {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var removed = 0
        var index = 0
        func trimmed(_ i: Int) -> String { lines[i].trimmingCharacters(in: .whitespaces) }
        while index < lines.count {
            let line = trimmed(index)
            if line.hasPrefix(beginMarker),
               let end = (index + 1..<lines.count).first(where: { trimmed($0).hasPrefix(endMarker) }) {
                removed += (index..<end).filter { trimmed($0).hasPrefix(header) }.count
                // The blank line we put in front of the block goes with it.
                if out.count > 0, out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
                index = end + 1
                continue
            }
            if line.hasPrefix(header) {
                // A table runs to the next header; comments and blank lines at its
                // end belong to whatever follows.
                let next = (index + 1..<lines.count).first { trimmed($0).hasPrefix("[") } ?? lines.count
                let last = (index..<next).last { !trimmed($0).isEmpty && !trimmed($0).hasPrefix("#") } ?? index
                if HookMerge.isOurs(command: lines[index...last].joined(separator: "\n")) {
                    removed += 1
                    index = last + 1
                    continue
                }
            }
            out.append(lines[index])
            index += 1
        }
        guard removed > 0 else { return (text, 0) }
        return (out.joined(separator: "\n"), removed)
    }

    public static func containsOurs(_ text: String) -> Bool { strip(text).removed > 0 }

    static func block(specs: [HookSpec], command: (HookSpec) -> String) -> String {
        var lines = [beginMarker + ": hooks managed by Niko Island. `niko-island uninstall` removes this block."]
        for (index, spec) in specs.enumerated() {
            if index > 0 { lines.append("") }
            lines.append(header)
            lines.append("event = \(quoted(spec.event))")
            if let matcher = spec.matcher { lines.append("matcher = \(quoted(matcher))") }
            lines.append("command = \(quoted(command(spec)))")
            lines.append("timeout = \(min(max(spec.timeout ?? 30, 1), 600))")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    /// A TOML basic string.
    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// A root-level `hooks` that is not an array of tables: a key, a dotted key,
    /// or a table. Appending `[[hooks]]` to such a file would make it invalid.
    static func conflictingHooksKey(in text: String) -> String? {
        var atRoot = true
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[[") {
                atRoot = false
                let name = tableName(line.dropFirst(2).prefix { $0 != "]" })
                if name != "hooks", name.hasPrefix("hooks.") { return "a [[\(name)]] table" }
                continue
            }
            if line.hasPrefix("[") {
                atRoot = false
                let name = tableName(line.dropFirst().prefix { $0 != "]" })
                if name == "hooks" || name.hasPrefix("hooks.") { return "a [\(name)] table" }
                continue
            }
            guard atRoot, let equals = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
            let key = tableName(line[..<equals])
            if key == "hooks" || key.hasPrefix("hooks.") { return "a root-level \"\(key)\" key" }
        }
        return nil
    }

    /// `hooks`, ` "hooks" `, `'hooks'.x` → `hooks`, `hooks.x`.
    private static func tableName<S: StringProtocol>(_ raw: S) -> String {
        raw.split(separator: ".").map {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }.joined(separator: ".")
    }
}
