import Foundation

/// The app a session lives in, when its transcript says so.
public struct SessionHost: Sendable, Equatable {
    public var name: String
    public var bundleID: String?

    public init(name: String, bundleID: String? = nil) {
        self.name = name
        self.bundleID = bundleID
    }

    public static let claudeDesktop = SessionHost(name: "Claude", bundleID: "com.anthropic.claudefordesktop")
    public static let codexDesktop = SessionHost(name: "Codex", bundleID: "com.openai.codex")
}

/// What a transcript on disk says about a session.
///
/// Hooks only speak when something happens, and only for agents that are
/// wired. The transcript an agent writes for itself is always there: it is how
/// a session that is idle, was started before the app, or belongs to a desktop
/// app shows up at all.
public struct TranscriptSnapshot: Sendable, Equatable {
    public var key: SessionKey
    public var path: String
    public var cwd: String?
    public var host: SessionHost?
    /// A name the agent or the user gave the session.
    public var title: String?
    public var firstPrompt: String?
    public var lastPrompt: String?
    /// The last thing the agent said.
    public var lastReply: String?
    public var phase: Session.Phase
    public var activity: Activity
    /// When the transcript was last written.
    public var updatedAt: Date
    /// When the current phase began, when the transcript shows it.
    public var phaseSince: Date?
    public var isSubagent: Bool
    public var parentID: String?

    public init(key: SessionKey, path: String, cwd: String? = nil, host: SessionHost? = nil, title: String? = nil,
                firstPrompt: String? = nil, lastPrompt: String? = nil, lastReply: String? = nil,
                phase: Session.Phase, activity: Activity, updatedAt: Date, phaseSince: Date? = nil,
                isSubagent: Bool = false, parentID: String? = nil) {
        self.key = key
        self.path = path
        self.cwd = cwd
        self.host = host
        self.title = title
        self.firstPrompt = firstPrompt
        self.lastPrompt = lastPrompt
        self.lastReply = lastReply
        self.phase = phase
        self.activity = activity
        self.updatedAt = updatedAt
        self.phaseSince = phaseSince
        self.isSubagent = isSubagent
        self.parentID = parentID
    }
}

enum TranscriptText {
    /// Lines longer than this are classified by a byte search instead of being parsed.
    static let parseLimit = 400_000

    /// A turn that has written nothing for this long is not treated as running any more.
    static let staleAfter: TimeInterval = 15 * 60

    static func lines(_ data: Data, dropFirst: Bool) -> [Data] {
        var out = data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
        if dropFirst, !out.isEmpty { out.removeFirst() }       // a tail read starts mid-line
        return out
    }

    static func object(_ line: Data) -> JSONObject? {
        guard line.count <= parseLimit else { return nil }
        return (try? JSONValue.parse(line))?.objectValue
    }

    static func contains(_ line: Data, _ needle: String, within limit: Int = .max) -> Bool {
        let haystack = limit < line.count ? line.prefix(limit) : line
        return haystack.range(of: Data(needle.utf8)) != nil
    }

    static func date(_ value: JSONValue?) -> Date? {
        guard let text = value?.stringValue else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    /// Text a person typed, as opposed to wrappers the agent adds around commands and context.
    static func prompt(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<"), !trimmed.hasPrefix("Caveat:") else { return nil }
        return trimmed.count > 600 ? String(trimmed.prefix(600)) : trimmed
    }

    static func reply(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 600 ? String(trimmed.prefix(600)) : trimmed
    }
}

/// Intermediate reading of a transcript's tail.
private enum Turn: Equatable {
    case unknown
    case thinking
    case tool(Activity)
    case finished
    case attention(Activity)
}

private func resolve(_ turn: Turn, modified: Date, now: Date) -> (Session.Phase, Activity) {
    let quiet = now.timeIntervalSince(modified)
    switch turn {
    case .finished: return (.waiting, .waiting)
    case .attention(let activity): return quiet > TranscriptText.staleAfter ? (.waiting, .waiting) : (.needsAttention, activity)
    case .tool(let activity): return quiet > TranscriptText.staleAfter ? (.waiting, .waiting) : (.working, activity)
    case .thinking: return quiet > TranscriptText.staleAfter ? (.waiting, .waiting) : (.working, .thinking)
    case .unknown: return quiet < 90 ? (.working, .thinking) : (.waiting, .waiting)
    }
}

// MARK: - Claude Code

/// `~/.claude/projects/<project>/<session id>.jsonl`, written by Claude Code in
/// the terminal and by the desktop app alike.
public enum ClaudeTranscript {
    public static let source = "claude"

    /// The first thing the user asked, from the start of the file.
    public static func firstPrompt(head: Data) -> String? {
        for line in TranscriptText.lines(head, dropFirst: false) {
            guard TranscriptText.contains(line, "\"user\"", within: 4096), let object = TranscriptText.object(line),
                  object["type"]?.stringValue == "user", object["isMeta"]?.boolValue != true,
                  object["isSidechain"]?.boolValue != true else { continue }
            if let text = text(of: object["message"]?["content"]).flatMap(TranscriptText.prompt) { return text }
        }
        return nil
    }

    private static func text(of content: JSONValue?) -> String? {
        if let text = content?.stringValue { return text }
        guard let items = content?.arrayValue else { return nil }
        let parts = items.compactMap { item -> String? in
            item["type"]?.stringValue == "text" ? item["text"]?.stringValue : nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    public static func snapshot(path: String, tail: Data, tailIsWholeFile: Bool = false, firstPrompt: String? = nil,
                                modified: Date, now: Date = Date()) -> TranscriptSnapshot? {
        let id = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard !id.isEmpty else { return nil }
        var cwd: String?
        var entrypoint: String?
        var title: String?
        var agentName: String?
        var lastPrompt: String?
        var lastReply: String?
        var turn = Turn.unknown
        var since: Date?

        for line in TranscriptText.lines(tail, dropFirst: !tailIsWholeFile) {
            guard let object = TranscriptText.object(line) else {
                // Too big to be worth parsing: almost always a tool result carrying a file.
                if TranscriptText.contains(line, "\"tool_result\"", within: 200_000) || TranscriptText.contains(line, "\"toolUseResult\"", within: 4096) {
                    turn = .thinking
                }
                continue
            }
            if object["isSidechain"]?.boolValue == true { continue }
            if let value = object["cwd"]?.stringValue { cwd = value }
            if let value = object["entrypoint"]?.stringValue { entrypoint = value }
            let stamp = TranscriptText.date(object["timestamp"])

            switch object["type"]?.stringValue {
            case "custom-title":
                title = object["customTitle"]?.stringValue ?? title
            case "agent-name":
                agentName = object["agentName"]?.stringValue ?? agentName
            case "last-prompt":
                lastPrompt = object["lastPrompt"]?.stringValue.flatMap(TranscriptText.prompt) ?? lastPrompt
            case "user":
                if object["isMeta"]?.boolValue == true { continue }
                let content = object["message"]?["content"]
                let isToolResult = object["toolUseResult"] != nil
                    || (content?.arrayValue ?? []).contains { $0["type"]?.stringValue == "tool_result" }
                if isToolResult {
                    turn = .thinking
                } else if let text = text(of: content) {
                    if text.hasPrefix("[Request interrupted") {
                        turn = .finished
                        since = stamp ?? since
                    } else if let prompt = TranscriptText.prompt(text) {
                        lastPrompt = prompt
                        turn = .thinking
                        since = stamp ?? since
                    }
                }
            case "assistant":
                let message = object["message"]
                var tool: Activity?
                for item in message?["content"]?.arrayValue ?? [] {
                    switch item["type"]?.stringValue {
                    case "text":
                        lastReply = item["text"]?.stringValue.flatMap(TranscriptText.reply) ?? lastReply
                    case "tool_use":
                        let name = item["name"]?.stringValue
                        if name == "AskUserQuestion" {
                            tool = Activity(verb: "has a question")
                        } else {
                            tool = Activity.forTool(name, input: item["input"]?.objectValue)
                        }
                    default:
                        break
                    }
                }
                switch message?["stop_reason"]?.stringValue {
                case "end_turn", "stop_sequence", "max_tokens", "refusal":
                    if turn != .finished { since = stamp ?? since }
                    turn = .finished
                default:
                    if let tool {
                        turn = tool.verb == "has a question" ? .attention(tool) : .tool(tool)
                    } else if turn == .unknown || turn == .finished {
                        turn = .thinking
                    }
                }
            default:
                break
            }
        }

        let (phase, activity) = resolve(turn, modified: modified, now: now)
        let host: SessionHost? = entrypoint == "claude-desktop" ? .claudeDesktop : nil
        return TranscriptSnapshot(
            key: SessionKey(source: source, sessionID: id), path: path, cwd: cwd, host: host,
            title: title ?? agentName, firstPrompt: firstPrompt ?? lastPrompt, lastPrompt: lastPrompt, lastReply: lastReply,
            phase: phase, activity: activity, updatedAt: modified, phaseSince: since)
    }
}

// MARK: - Codex

/// `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl`, written by the
/// Codex CLI, its IDE extension and the desktop app.
public enum CodexTranscript {
    public static let source = "codex"

    public struct Meta: Sendable, Equatable {
        public var id: String
        public var cwd: String?
        public var host: SessionHost?
        public var isSubagent = false
        public var parentID: String?
        public var role: String?
        public var firstPrompt: String?
    }

    /// Identity and context, from the start of the file.
    public static func meta(path: String, head: Data) -> Meta {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        // rollout-2026-10-12T19-34-40-<uuid>
        var meta = Meta(id: name.count > 36 ? String(name.suffix(36)) : name)
        for line in TranscriptText.lines(head, dropFirst: false) {
            guard let object = TranscriptText.object(line), let payload = object["payload"]?.objectValue else { continue }
            switch object["type"]?.stringValue {
            case "session_meta":
                if let id = (payload["id"] ?? payload["session_id"])?.stringValue, !id.isEmpty { meta.id = id }
                meta.cwd = payload["cwd"]?.stringValue ?? meta.cwd
                let originator = payload["originator"]?.stringValue?.lowercased() ?? ""
                if originator.contains("desktop") { meta.host = .codexDesktop }
                if payload["source"]?["subagent"] != nil || payload["thread_source"]?.stringValue == "subagent" {
                    meta.isSubagent = true
                    meta.parentID = (payload["parent_thread_id"] ?? payload["forked_from_id"])?.stringValue
                    meta.role = (payload["agent_role"] ?? payload["agent_nickname"])?.stringValue
                }
            case "event_msg" where meta.firstPrompt == nil && payload["type"]?.stringValue == "user_message":
                meta.firstPrompt = payload["message"]?.stringValue.flatMap(TranscriptText.prompt)
            case "response_item" where meta.firstPrompt == nil && payload["type"]?.stringValue == "message"
                && payload["role"]?.stringValue == "user":
                meta.firstPrompt = text(of: payload["content"]).flatMap(TranscriptText.prompt)
            default:
                break
            }
        }
        return meta
    }

    private static func text(of content: JSONValue?) -> String? {
        if let text = content?.stringValue { return text }
        let parts = (content?.arrayValue ?? []).compactMap { $0["text"]?.stringValue }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func activity(tool name: String?, namespace: String?, arguments: JSONValue?, input: String?) -> Activity {
        let lowered = (name ?? "").lowercased()
        if namespace == "collaboration" || lowered.contains("spawn") || lowered == "send_message" {
            return Activity(verb: "delegating", detail: arguments?["target"]?.stringValue.map { Activity.oneLine($0, limit: 64) })
        }
        if lowered == "apply_patch" { return Activity(verb: "editing") }
        if Activity.verb(forTool: lowered) == "running" {
            var command = (arguments?["cmd"] ?? arguments?["command"])?.stringValue
            if command == nil, let parts = (arguments?["command"] ?? arguments?["cmd"])?.arrayValue {
                // ["bash", "-lc", "the command"]
                command = parts.compactMap(\.stringValue).last
            }
            return Activity(verb: "running", detail: (command ?? input).map { Activity.oneLine($0, limit: 96) })
        }
        if lowered == "wait" { return .thinking }
        return Activity.forTool(name, input: arguments?.objectValue)
    }

    public static func snapshot(path: String, meta: Meta, tail: Data, tailIsWholeFile: Bool = false,
                                modified: Date, now: Date = Date()) -> TranscriptSnapshot? {
        var lastPrompt: String?
        var lastReply: String?
        var turn = Turn.unknown
        var since: Date?
        var cwd = meta.cwd
        var question: String?

        for line in TranscriptText.lines(tail, dropFirst: !tailIsWholeFile) {
            // Reasoning and bookkeeping lines are most of a rollout; neither changes what we show.
            if TranscriptText.contains(line, "\"token_count\"", within: 400) || TranscriptText.contains(line, "\"token_usage_record\"", within: 200)
                || TranscriptText.contains(line, "\"item_completed\"", within: 400) { continue }
            guard let object = TranscriptText.object(line), let payload = object["payload"]?.objectValue else { continue }
            let stamp = TranscriptText.date(object["timestamp"])
            let kind = payload["type"]?.stringValue ?? ""
            switch object["type"]?.stringValue {
            case "turn_context":
                cwd = payload["cwd"]?.stringValue ?? cwd
            case "event_msg":
                switch kind {
                case "task_started":
                    turn = .thinking
                    since = stamp ?? since
                    question = nil
                case "task_complete":
                    turn = .finished
                    since = stamp ?? since
                    question = nil
                    lastReply = payload["last_agent_message"]?.stringValue.flatMap(TranscriptText.reply) ?? lastReply
                case "turn_aborted", "error":
                    turn = .finished
                    since = stamp ?? since
                case "user_message":
                    lastPrompt = payload["message"]?.stringValue.flatMap(TranscriptText.prompt) ?? lastPrompt
                case "agent_message":
                    lastReply = payload["message"]?.stringValue.flatMap(TranscriptText.reply) ?? lastReply
                default:
                    if kind.hasSuffix("approval_request") {
                        turn = .attention(Activity(verb: "needs permission"))
                    }
                }
            case "response_item":
                switch kind {
                case "message":
                    let text = text(of: payload["content"])
                    switch payload["role"]?.stringValue {
                    case "user": lastPrompt = text.flatMap(TranscriptText.prompt) ?? lastPrompt
                    case "assistant": lastReply = text.flatMap(TranscriptText.reply) ?? lastReply
                    default: break
                    }
                case "function_call":
                    let name = payload["name"]?.stringValue
                    let arguments = payload["arguments"]?.stringValue.flatMap { try? JSONValue.parse(Data($0.utf8)) }
                    if (name ?? "").contains("request_user_input") {
                        question = payload["call_id"]?.stringValue ?? ""
                        turn = .attention(Activity(verb: "has a question"))
                    } else if turn != .finished {
                        turn = .tool(activity(tool: name, namespace: payload["namespace"]?.stringValue, arguments: arguments, input: nil))
                    }
                case "custom_tool_call":
                    if turn != .finished {
                        turn = .tool(activity(tool: payload["name"]?.stringValue, namespace: nil, arguments: nil, input: payload["input"]?.stringValue))
                    }
                case "function_call_output", "custom_tool_call_output":
                    guard turn != .finished else { break }
                    // Some other call returning does not answer a question that is still open.
                    if let pending = question, !pending.isEmpty, payload["call_id"]?.stringValue != pending { break }
                    question = nil
                    turn = .thinking
                case "reasoning":
                    if case .unknown = turn { turn = .thinking }
                default:
                    break
                }
            default:
                break
            }
        }

        let (phase, activity) = resolve(turn, modified: modified, now: now)
        return TranscriptSnapshot(
            key: SessionKey(source: source, sessionID: meta.id), path: path, cwd: cwd, host: meta.host,
            title: meta.isSubagent ? meta.role : nil, firstPrompt: meta.firstPrompt ?? lastPrompt, lastPrompt: lastPrompt,
            lastReply: lastReply, phase: phase, activity: activity, updatedAt: modified, phaseSince: since,
            isSubagent: meta.isSubagent, parentID: meta.parentID)
    }
}
