import Foundation

/// Canonical event names (PROTOCOLS §1.1).
public enum HookEvent {
    public static let sessionStart = "SessionStart"
    public static let sessionEnd = "SessionEnd"
    public static let userPromptSubmit = "UserPromptSubmit"
    public static let preToolUse = "PreToolUse"
    public static let postToolUse = "PostToolUse"
    public static let notification = "Notification"
    public static let stop = "Stop"
    public static let subagentStop = "SubagentStop"
    public static let preCompact = "PreCompact"
    public static let postCompact = "PostCompact"
    /// Extension: same payload as PreToolUse, but the sender blocks for a reply.
    public static let permissionRequest = "PermissionRequest"

    public static let canonical: [String] = [
        sessionStart, sessionEnd, userPromptSubmit, preToolUse, postToolUse,
        notification, stop, subagentStop, preCompact, permissionRequest,
    ]
}

public struct SessionKey: Hashable, Sendable, CustomStringConvertible {
    public let source: String
    public let sessionID: String
    public init(source: String, sessionID: String) {
        self.source = source
        self.sessionID = sessionID
    }
    public var description: String { "\(source)/\(sessionID)" }
}

/// Where the agent is running, as reported by the bridge from its own
/// (inherited) environment. Used only for click-to-jump and admission hints.
public struct TerminalContext: Sendable, Equatable {
    public var termProgram: String?
    public var itermSessionID: String?
    public var tty: String?
    public var tmux: String?
    public var tmuxPane: String?
    public var bundleID: String?
    public var pid: Int32?
    /// Executable paths of the bridge's ancestors, nearest first (self-reported).
    public var ancestors: [String] = []

    public init() {}

    public init(json: JSONValue?) {
        guard let object = json?.objectValue else { return }
        termProgram = object["term_program"]?.stringValue
        itermSessionID = object["iterm_session_id"]?.stringValue
        tty = object["tty"]?.stringValue
        tmux = object["tmux"]?.stringValue
        tmuxPane = object["tmux_pane"]?.stringValue
        bundleID = object["bundle_id"]?.stringValue
        pid = object["pid"]?.intValue.flatMap { Int32(exactly: $0) }
        ancestors = (object["ancestors"]?.arrayValue ?? []).compactMap(\.stringValue)
    }

    public var json: JSONValue {
        var object = JSONObject()
        if let termProgram { object["term_program"] = .string(termProgram) }
        if let itermSessionID { object["iterm_session_id"] = .string(itermSessionID) }
        if let tty { object["tty"] = .string(tty) }
        if let tmux { object["tmux"] = .string(tmux) }
        if let tmuxPane { object["tmux_pane"] = .string(tmuxPane) }
        if let bundleID { object["bundle_id"] = .string(bundleID) }
        if let pid { object["pid"] = .int(Int(pid)) }
        if !ancestors.isEmpty { object["ancestors"] = .array(ancestors.map(JSONValue.string)) }
        return .object(object)
    }

    public var isEmpty: Bool { self == TerminalContext() }
}

public enum EventError: Error, Equatable, CustomStringConvertible {
    case notAnObject
    case missingEventName

    public var description: String {
        switch self {
        case .notAnObject: return "event is not a JSON object"
        case .missingEventName: return "event has no hook_event_name"
        }
    }
}

/// One normalised agent event (PROTOCOLS §1).
public struct AgentEvent: Sendable, Equatable {
    /// Key under which the bridge attaches terminal context. Never part of an agent's own payload.
    public static let metaKey = "_niko"
    public static let blockingKey = "_blocking"

    public var source: String
    public var name: String
    public var sessionID: String
    public var transcriptPath: String?
    public var cwd: String?
    public var toolName: String?
    public var toolInput: JSONObject?
    public var timestampMS: Double
    public var terminal: TerminalContext
    public var raw: JSONObject

    public var key: SessionKey { SessionKey(source: source, sessionID: sessionID) }

    /// The sender is holding its connection open for a decision.
    public var isBlocking: Bool {
        name == HookEvent.permissionRequest || raw[AgentEvent.blockingKey]?.boolValue == true
    }

    public init(json: JSONValue, defaultSource: String? = nil, fallbackCwd: String? = nil) throws {
        guard let object = json.objectValue else { throw EventError.notAnObject }
        guard let name = (object["hook_event_name"] ?? object["event"])?.stringValue, !name.isEmpty else {
            throw EventError.missingEventName
        }
        self.raw = object
        self.name = name
        let source = object["source"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        self.source = AgentEvent.sanitizeIdentifier(source ?? defaultSource ?? "unknown")
        self.cwd = object["cwd"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackCwd
        if let id = object["session_id"]?.stringValue, !id.isEmpty {
            self.sessionID = id
        } else {
            // Agents without session ids get one session per working directory.
            self.sessionID = "cwd:" + (self.cwd ?? "unknown")
        }
        self.transcriptPath = object["transcript_path"]?.stringValue
        self.toolName = object["tool_name"]?.stringValue
        self.toolInput = object["tool_input"]?.objectValue
        self.timestampMS = object["ts"]?.doubleValue ?? Date().timeIntervalSince1970 * 1000
        self.terminal = TerminalContext(json: object[AgentEvent.metaKey])
    }

    /// Adapter ids end up in log lines and UI labels; keep them boring.
    static func sanitizeIdentifier(_ raw: String) -> String {
        let allowed = raw.lowercased().unicodeScalars.filter {
            ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39) || $0 == "-" || $0 == "_"
        }
        let cleaned = String(String.UnicodeScalarView(allowed.prefix(32)))
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    public var date: Date { Date(timeIntervalSince1970: timestampMS / 1000) }
}

/// Human activity for the status line (PROTOCOLS §1.2).
public struct Activity: Sendable, Equatable {
    public var verb: String
    public var detail: String?

    public init(verb: String, detail: String? = nil) {
        self.verb = verb
        self.detail = detail
    }

    public static let waiting = Activity(verb: "waiting for you")
    public static let thinking = Activity(verb: "thinking")

    public static func verb(forTool tool: String?) -> String {
        guard let tool, !tool.isEmpty else { return "working" }
        switch tool.lowercased() {
        case "bash", "shell", "exec", "exec_command", "run_terminal_cmd", "run_shell_command", "local_shell":
            return "running"
        case "read", "read_file", "view", "notebookread":
            return "reading"
        case "write", "edit", "multiedit", "notebookedit", "write_file", "edit_file", "apply_patch", "str_replace", "replace", "patch":
            return "editing"
        case "grep", "glob", "search", "find", "ls", "list", "search_file_content", "codebase_search":
            return "finding"
        case "webfetch", "web_fetch", "fetch":
            return "fetching"
        case "task", "agent", "subagent":
            return "delegating"
        default:
            return "working"
        }
    }

    /// Activity for a tool call. `detail` is a short, single-line hint; long
    /// inputs are truncated so nothing sensitive sprawls across the panel.
    public static func forTool(_ tool: String?, input: JSONObject?) -> Activity {
        let verb = verb(forTool: tool)
        var detail: String?
        if let input {
            switch verb {
            case "running":
                detail = (input["command"] ?? input["cmd"])?.stringValue
            case "reading", "editing":
                detail = (input["file_path"] ?? input["path"] ?? input["notebook_path"])?.stringValue
                    .map { ($0 as NSString).lastPathComponent }
            case "finding":
                detail = (input["pattern"] ?? input["query"] ?? input["path"])?.stringValue
            case "fetching":
                detail = input["url"]?.stringValue.flatMap { URL(string: $0)?.host ?? $0 }
            case "delegating":
                detail = (input["description"] ?? input["subagent_type"])?.stringValue
            default:
                detail = tool
            }
        } else if verb == "working" {
            detail = tool
        }
        return Activity(verb: verb, detail: detail.map { Activity.oneLine($0, limit: 96) })
    }

    public static func oneLine(_ text: String, limit: Int) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }
}
