import Foundation

/// One question of an AskUserQuestion-style request, in canonical form
/// (INTEGRATIONS: `tool_input.questions[{text, options[], multiSelect}]`).
public struct AgentQuestion: Sendable, Equatable, Identifiable {
    public struct Option: Sendable, Equatable, Identifiable {
        public var label: String
        public var detail: String?
        public var id: String { label }
    }

    public var id: Int
    public var text: String
    public var header: String?
    public var options: [Option]
    public var multiSelect: Bool
}

public enum Questions {
    public static let toolName = "AskUserQuestion"

    /// Accepts both the canonical shape and Claude Code's own
    /// (`question`, `options[{label, description}]`).
    public static func parse(toolInput: JSONObject?) -> [AgentQuestion] {
        guard let items = toolInput?["questions"]?.arrayValue else { return [] }
        var out: [AgentQuestion] = []
        for (index, item) in items.enumerated() {
            guard let text = (item["text"] ?? item["question"])?.stringValue, !text.isEmpty else { continue }
            let options: [AgentQuestion.Option] = (item["options"]?.arrayValue ?? []).compactMap { option in
                if let label = option.stringValue { return .init(label: label, detail: nil) }
                guard let label = option["label"]?.stringValue else { return nil }
                return .init(label: label, detail: option["description"]?.stringValue)
            }
            out.append(AgentQuestion(id: index, text: text, header: item["header"]?.stringValue, options: options,
                                     multiSelect: (item["multiSelect"] ?? item["multiple"])?.boolValue ?? false))
        }
        return out
    }

    public static func isQuestion(_ event: AgentEvent) -> Bool {
        event.toolName == toolName && !parse(toolInput: event.toolInput).isEmpty
    }

    /// `updatedInput`: the original input with `answers[i] = [labels…]` merged in.
    public static func updatedInput(original: JSONObject?, selections: [[String]]) -> JSONObject {
        var out = original ?? JSONObject()
        out["answers"] = .array(selections.map { .array($0.map(JSONValue.string)) })
        return out
    }
}

/// What the user chose on a card.
public enum UserDecision: Sendable, Equatable {
    case allowOnce
    /// Allow, and keep allowing this tool for the rest of the session.
    case allowAlwaysTool
    /// Allow, and keep allowing everything for the rest of the session.
    case allowAllSession
    case deny
    /// Deny and stop the agent's current turn.
    case block
    /// Question wizard result: one array of labels per question.
    case answer([[String]])
    /// "Open in terminal": make no decision here, let the agent ask in its own UI.
    case passToTerminal

    public var isApproval: Bool {
        switch self {
        case .allowOnce, .allowAlwaysTool, .allowAllSession, .answer: return true
        case .deny, .block, .passToTerminal: return false
        }
    }
}

/// Builds the single reply line of PROTOCOLS §2.2.
public enum ReplyBuilder {
    public static func line(for decision: UserDecision, event: AgentEvent, reason: String? = nil) -> JSONValue {
        var body = JSONObject()
        switch decision {
        case .passToTerminal:
            return .object(["ok": .bool(true), "reply": .null])
        case .allowOnce, .allowAlwaysTool, .allowAllSession:
            body["behavior"] = .string("approve")
            body["reason"] = .string(reason ?? "user allowed")
        case .answer(let selections):
            body["behavior"] = .string("approve")
            body["reason"] = .string(reason ?? "user answered")
            // A request that was cut down in transit must never be echoed back as input.
            if event.raw[AgentEvent.metaKey]?["truncated"]?.boolValue != true {
                body["updatedInput"] = .object(Questions.updatedInput(original: event.toolInput, selections: selections))
            }
        case .deny:
            body["behavior"] = .string("deny")
            body["reason"] = .string(reason ?? "Denied in Niko Island")
        case .block:
            body["behavior"] = .string("block")
            body["reason"] = .string(reason ?? "Blocked in Niko Island")
        }
        return .object(["ok": .bool(true), "reply": .object(["hookSpecificOutput": .object([
            "hookEventName": .string(event.name),
            "decision": .object(body),
        ])])])
    }
}

/// "Allow always" / "Allow all" grants. In memory only, scoped to one session,
/// gone when the session ends or the app quits.
public struct SessionGrants: Sendable, Equatable {
    private var allowAll: Set<SessionKey> = []
    private var tools: [SessionKey: Set<String>] = [:]

    public init() {}

    public mutating func record(_ decision: UserDecision, for event: AgentEvent) {
        switch decision {
        case .allowAllSession:
            allowAll.insert(event.key)
        case .allowAlwaysTool:
            if let tool = event.toolName { tools[event.key, default: []].insert(tool) }
        default:
            break
        }
    }

    /// Whether an incoming request is already covered. Questions never are:
    /// nobody can pre-approve an answer.
    public func covers(_ event: AgentEvent) -> Bool {
        guard !Questions.isQuestion(event) else { return false }
        if allowAll.contains(event.key) { return true }
        guard let tool = event.toolName else { return false }
        return tools[event.key]?.contains(tool) ?? false
    }

    public func summary(for key: SessionKey) -> (all: Bool, tools: [String]) {
        (allowAll.contains(key), (tools[key] ?? []).sorted())
    }

    public func hasGrants(for key: SessionKey) -> Bool {
        allowAll.contains(key) || !(tools[key]?.isEmpty ?? true)
    }

    public mutating func revoke(_ key: SessionKey) {
        allowAll.remove(key)
        tools[key] = nil
    }
}

/// What a permission request wants to do, in a form the UI can localise.
public struct RequestSummary: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case command
        case edit(file: String?)
        case read(file: String?)
        case fetch
        case search
        case subagent
        case other(tool: String)
    }

    /// One line of what an edit would take out or put in.
    public struct ChangeLine: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case removed, added, more }
        public var kind: Kind
        public var text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    public var kind: Kind
    /// The command, path, URL or pattern in question (clipped).
    public var detail: String?
    /// For an edit: the first lines of what goes and what comes. Empty when the request does not say.
    public var changes: [ChangeLine] = []

    static let changeLines = 6
    static let changeWidth = 160

    /// The first lines of a text, as lines of one kind; what was left out is counted, not shown.
    static func lines(_ text: String?, _ kind: ChangeLine.Kind, limit: Int = changeLines) -> [ChangeLine] {
        guard let text, !text.isEmpty else { return [] }
        let all = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var out = all.prefix(limit).map { ChangeLine(kind, clip($0.replacingOccurrences(of: "\t", with: "  "), changeWidth)) }
        if all.count > limit { out.append(ChangeLine(.more, "\(all.count - limit)")) }
        return out
    }

    /// What an edit request would change, from the shapes agents use: a whole
    /// file (`content`), one replacement (`old_string` → `new_string`), several
    /// (`edits`), or a patch whose lines start with `+` and `-`.
    static func changes(of input: JSONObject?) -> [ChangeLine] {
        guard let input else { return [] }
        func text(_ keys: String...) -> String? {
            for key in keys { if let value = input[key]?.stringValue, !value.isEmpty { return value } }
            return nil
        }
        if let edits = input["edits"]?.arrayValue, let first = edits.first {
            var out = lines(first["old_string"]?.stringValue, .removed, limit: 3) + lines(first["new_string"]?.stringValue, .added, limit: 3)
            if edits.count > 1 { out.append(ChangeLine(.more, "\(edits.count - 1) ✎")) }
            return out
        }
        if input["old_string"] != nil || input["new_string"] != nil {
            return lines(text("old_string"), .removed, limit: 4) + lines(text("new_string"), .added, limit: 4)
        }
        if let whole = text("content", "contents", "file_text", "new_source") { return lines(whole, .added) }
        if let patch = text("patch", "input", "diff") {
            let marked = patch.split(whereSeparator: \.isNewline).filter { line in
                (line.hasPrefix("+") || line.hasPrefix("-")) && !line.hasPrefix("+++") && !line.hasPrefix("---")
            }
            var out = marked.prefix(changeLines).map { line in
                ChangeLine(line.hasPrefix("+") ? .added : .removed, clip(String(line.dropFirst()).replacingOccurrences(of: "\t", with: "  "), changeWidth))
            }
            if marked.count > changeLines { out.append(ChangeLine(.more, "\(marked.count - changeLines)")) }
            return out
        }
        return []
    }

    public init(event: AgentEvent) {
        let tool = event.toolName ?? "tool"
        let input = event.toolInput
        func text(_ keys: String...) -> String? {
            for key in keys { if let value = input?[key]?.stringValue, !value.isEmpty { return value } }
            return nil
        }
        func fileName(_ path: String?) -> String? { path.map { ($0 as NSString).lastPathComponent } }
        switch Activity.verb(forTool: tool) {
        case "running":
            kind = .command
            detail = text("command", "cmd").map { RequestSummary.clip($0, 600) }
        case "editing":
            let path = text("file_path", "path", "notebook_path")
            kind = .edit(file: fileName(path))
            detail = path
            changes = RequestSummary.changes(of: input)
        case "reading":
            let path = text("file_path", "path")
            kind = .read(file: fileName(path))
            detail = path
        case "fetching":
            kind = .fetch
            detail = text("url")
        case "finding":
            kind = .search
            detail = text("pattern", "query")
        case "delegating":
            kind = .subagent
            detail = text("description", "prompt").map { RequestSummary.clip($0, 300) }
        default:
            kind = .other(tool: tool)
            detail = text("title", "description", "pattern", "command").map { RequestSummary.clip($0, 300) }
        }
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}
