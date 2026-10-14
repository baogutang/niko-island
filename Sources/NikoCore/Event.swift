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
    /// The turn ended because of an error (reported by agents that have such a hook).
    public static let stopFailure = "StopFailure"
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
    /// Their process ids, in the same order: how the app tells that the agent has gone
    /// even when it never said goodbye.
    public var ancestorPIDs: [Int32] = []

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
        ancestorPIDs = (object["ancestor_pids"]?.arrayValue ?? []).compactMap { $0.intValue.flatMap { Int32(exactly: $0) } }
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
        if !ancestorPIDs.isEmpty { object["ancestor_pids"] = .array(ancestorPIDs.map { .int(Int($0)) }) }
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
        guard var object = json.objectValue else { throw EventError.notAnObject }
        // The bridge says which adapter it is in its own envelope. A top-level
        // "source" only counts for senders without one (the in-process
        // plugins): agents use that key for other things.
        func text(_ value: JSONValue?) -> String? { value?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
        let source = AgentEvent.sanitizeIdentifier(
            text(object[AgentEvent.metaKey]?["source"]) ?? defaultSource ?? text(object["source"]) ?? "unknown")
        EventDialect.normalize(&object, source: source)
        guard let name = (object["hook_event_name"] ?? object["event"])?.stringValue, !name.isEmpty else {
            throw EventError.missingEventName
        }
        self.raw = object
        self.name = name
        self.source = source
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

/// Agents that do not speak the Claude Code hook dialect are translated into
/// it here, so everything downstream sees one vocabulary. Field names follow
/// each agent's published hook reference.
enum EventDialect {
    static func normalize(_ object: inout JSONObject, source: String) {
        switch source {
        case "cursor": cursor(&object)
        case "windsurf": windsurf(&object)
        case "gemini": gemini(&object)
        case "copilot": copilot(&object)
        case "kiro": camelCase(&object)
        default: break
        }
        common(&object)
    }

    /// Names several agents share beyond Claude Code's own set.
    private static func common(_ object: inout JSONObject) {
        guard let native = object["hook_event_name"]?.stringValue else { return }
        let canonical: String
        switch native {
        // A tool that failed, or an answer to a permission prompt: the agent carries on.
        case "PostToolUseFailure", "PermissionResult": canonical = HookEvent.postToolUse
        case "PostCompaction": canonical = HookEvent.postCompact
        case "Interrupt": canonical = HookEvent.stop
        default: return
        }
        if object["native_event"] == nil { object["native_event"] = .string(native) }
        object["hook_event_name"] = .string(canonical)
    }

    /// Copilot CLI: with Claude's event names it sends Claude's payloads; its
    /// own camelCase format (sessionId, toolName, toolArgs as JSON text) is
    /// read too.
    private static func copilot(_ object: inout JSONObject) {
        if object["session_id"]?.stringValue?.isEmpty ?? true, let id = object["sessionId"]?.stringValue, !id.isEmpty {
            object["session_id"] = .string(id)
        }
        if object["tool_name"] == nil, let tool = object["toolName"] { object["tool_name"] = tool }
        if object["tool_input"] == nil, let args = object["toolArgs"] {
            if args.objectValue != nil {
                object["tool_input"] = args
            } else if let text = args.stringValue, let parsed = try? JSONValue.parse(Data(text.utf8)), parsed.objectValue != nil {
                object["tool_input"] = parsed
            }
        }
        if object["transcript_path"] == nil, let path = object["transcriptPath"] { object["transcript_path"] = path }
        if let error = object["error"]?.objectValue, object["message"] == nil, let message = error["message"] {
            object["message"] = message
        }
        camelCase(&object)
    }

    /// camelCase event names (Copilot CLI's own format, Kiro's older one).
    private static func camelCase(_ object: inout JSONObject) {
        guard let native = object["hook_event_name"]?.stringValue else { return }
        let canonical: String
        switch native {
        case "sessionStart", "agentSpawn": canonical = HookEvent.sessionStart
        case "sessionEnd": canonical = HookEvent.sessionEnd
        case "userPromptSubmitted", "userPromptSubmit": canonical = HookEvent.userPromptSubmit
        case "preToolUse": canonical = HookEvent.preToolUse
        case "postToolUse", "postToolUseFailure": canonical = HookEvent.postToolUse
        case "agentStop", "stop": canonical = HookEvent.stop
        case "subagentStop": canonical = HookEvent.subagentStop
        case "preCompact": canonical = HookEvent.preCompact
        case "notification": canonical = HookEvent.notification
        case "errorOccurred": canonical = HookEvent.stopFailure
        default: return
        }
        object["native_event"] = .string(native)
        object["hook_event_name"] = .string(canonical)
    }

    private static func tool(_ object: inout JSONObject, name: String, input: JSONObject) {
        if object["tool_name"]?.stringValue == nil { object["tool_name"] = .string(name) }
        if object["tool_input"]?.objectValue == nil { object["tool_input"] = .object(input) }
    }

    private static func cursor(_ object: inout JSONObject) {
        guard let native = object["hook_event_name"]?.stringValue else { return }
        if object["session_id"]?.stringValue?.isEmpty ?? true, let id = object["conversation_id"]?.stringValue {
            object["session_id"] = .string(id)
        }
        if object["cwd"]?.stringValue?.isEmpty ?? true, let root = object["workspace_roots"]?.arrayValue?.first?.stringValue {
            object["cwd"] = .string(root)
        }
        let canonical: String
        switch native {
        case "sessionStart": canonical = HookEvent.sessionStart
        case "sessionEnd": canonical = HookEvent.sessionEnd
        case "beforeSubmitPrompt": canonical = HookEvent.userPromptSubmit
        case "preToolUse": canonical = HookEvent.preToolUse
        case "beforeShellExecution":
            canonical = HookEvent.preToolUse
            tool(&object, name: "Bash", input: ["command": object["command"] ?? .string("")])
        case "beforeMCPExecution": canonical = HookEvent.preToolUse
        case "beforeReadFile":
            canonical = HookEvent.preToolUse
            tool(&object, name: "Read", input: ["file_path": object["file_path"] ?? .string("")])
        case "postToolUse", "postToolUseFailure", "afterShellExecution", "afterMCPExecution", "afterFileEdit",
             "afterAgentThought", "afterAgentResponse":
            canonical = HookEvent.postToolUse
        case "subagentStop": canonical = HookEvent.subagentStop
        case "preCompact": canonical = HookEvent.preCompact
        case "stop":
            canonical = object["status"]?.stringValue == "error" ? HookEvent.stopFailure : HookEvent.stop
        default: return                       // unknown or already canonical: leave it alone
        }
        object["native_event"] = .string(native)
        object["hook_event_name"] = .string(canonical)
    }

    private static func windsurf(_ object: inout JSONObject) {
        guard let native = (object["agent_action_name"] ?? object["hook_event_name"])?.stringValue else { return }
        if object["session_id"]?.stringValue?.isEmpty ?? true, let id = object["trajectory_id"]?.stringValue {
            object["session_id"] = .string(id)
        }
        let info = object["tool_info"]?.objectValue ?? JSONObject()
        if object["cwd"]?.stringValue?.isEmpty ?? true, let cwd = info["cwd"]?.stringValue { object["cwd"] = .string(cwd) }
        let canonical: String
        switch native {
        case "pre_user_prompt":
            canonical = HookEvent.userPromptSubmit
            if let prompt = info["user_prompt"] { object["prompt"] = prompt }
        case "pre_run_command":
            canonical = HookEvent.preToolUse
            tool(&object, name: "Bash", input: ["command": info["command_line"] ?? .string("")])
        case "pre_read_code":
            canonical = HookEvent.preToolUse
            tool(&object, name: "Read", input: ["file_path": info["file_path"] ?? .string("")])
        case "pre_write_code":
            canonical = HookEvent.preToolUse
            tool(&object, name: "Edit", input: ["file_path": info["file_path"] ?? .string("")])
        case "pre_mcp_tool_use":
            canonical = HookEvent.preToolUse
            tool(&object, name: info["mcp_tool_name"]?.stringValue ?? "MCP", input: JSONObject())
        case "post_run_command", "post_read_code", "post_write_code", "post_mcp_tool_use":
            canonical = HookEvent.postToolUse
        case "post_cascade_response", "post_cascade_response_with_transcript":
            canonical = HookEvent.stop
        default: return
        }
        object["native_event"] = .string(native)
        object["hook_event_name"] = .string(canonical)
    }

    private static func gemini(_ object: inout JSONObject) {
        guard let native = object["hook_event_name"]?.stringValue else { return }
        let canonical: String
        switch native {
        case "BeforeAgent": canonical = HookEvent.userPromptSubmit
        case "AfterAgent": canonical = HookEvent.stop
        case "BeforeTool": canonical = HookEvent.preToolUse
        case "AfterTool": canonical = HookEvent.postToolUse
        case "PreCompress": canonical = HookEvent.preCompact
        default: return
        }
        object["native_event"] = .string(native)
        object["hook_event_name"] = .string(canonical)
    }
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
        case "bash", "shell", "exec", "exec_command", "run_terminal_cmd", "run_shell_command", "local_shell", "executebash", "execute_bash":
            return "running"
        case "read", "read_file", "view", "notebookread", "readfile", "readmultiplefiles", "fs_read":
            return "reading"
        case "write", "edit", "multiedit", "notebookedit", "write_file", "edit_file", "apply_patch", "str_replace", "replace", "patch",
             "fswrite", "fsappend", "strreplace", "fs_write", "deletefile":
            return "editing"
        case "grep", "glob", "search", "find", "ls", "list", "search_file_content", "codebase_search", "toolsearch", "websearch", "web_search",
             "grepsearch", "filesearch", "listdirectory":
            return "finding"
        case "taskcreate", "taskupdate", "tasklist", "taskget", "todowrite", "todo_write", "update_plan":
            // Keeping its own list of steps (Claude Code's task tools, and the older single list).
            return "planning"
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
            case "planning":
                detail = (input["subject"] ?? input["activeForm"])?.stringValue
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
