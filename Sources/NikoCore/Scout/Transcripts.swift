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
    /// The provider turned the agent away because this window is used up.
    public var limitReached: RateLimitWindow?
    /// The agent's own list of steps, when it keeps one.
    public var progress: TaskProgress?
    /// The model the session last ran on.
    public var model: String?
    /// How much of the model's context the session holds.
    public var context: ContextFill?

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
    /// A file whose state cannot be told counts as running for this long after its last write.
    static let unknownQuietAfter: TimeInterval = 90

    /// The moments after which the same file, unchanged, reads differently: a quiet turn stops
    /// counting as running, a window it was refused opens again. Until one passes, a reading stands.
    static func turningPoints(modified: Date, snapshot: TranscriptSnapshot?) -> [Date] {
        var points = [modified.addingTimeInterval(unknownQuietAfter), modified.addingTimeInterval(staleAfter)]
        if let resets = snapshot?.limitReached?.resetsAt { points.append(resets) }
        return points
    }

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
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Codex puts the files and editor state that came along in front of what was typed;
        // the person's own words follow a "## My request" heading.
        if trimmed.hasPrefix("# Files mentioned by the user") || trimmed.hasPrefix("# Context from my IDE setup") {
            guard let heading = trimmed.range(of: "\n## My request"),
                  let lineEnd = trimmed[heading.upperBound...].firstIndex(of: "\n") else { return nil }
            trimmed = trimmed[lineEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Project instructions handed to the agent in the user's name are not the user speaking.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<"), !trimmed.hasPrefix("Caveat:"),
              !trimmed.hasPrefix("# AGENTS.md instructions for") else { return nil }
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
    case .unknown: return quiet < TranscriptText.unknownQuietAfter ? (.working, .thinking) : (.waiting, .waiting)
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
        var limit: RateLimitWindow?
        var stoppedByLimit = false
        var progress: TaskProgress?
        var model: String?
        var context: ContextFill?

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
                        lastReply = nil   // the reply belongs to the prompt before it
                        turn = .thinking
                        since = stamp ?? since
                        stoppedByLimit = false
                    }
                }
            case "assistant":
                if let refused = limitReached(object) {
                    limit = refused
                    stoppedByLimit = true
                    turn = .finished
                    since = stamp ?? since
                    continue
                }
                let message = object["message"]
                if let name = message?["model"]?.stringValue, !name.isEmpty, name != "<synthetic>" {
                    model = name
                    context = ContextFill.claude(usage: message?["usage"]) ?? context
                }
                var tool: Activity?
                for item in message?["content"]?.arrayValue ?? [] {
                    switch item["type"]?.stringValue {
                    case "text":
                        lastReply = item["text"]?.stringValue.flatMap(TranscriptText.reply) ?? lastReply
                    case "tool_use":
                        let name = item["name"]?.stringValue
                        progress = TaskProgress.from(tool: name, input: item["input"]) ?? progress
                        if name == "AskUserQuestion" {
                            tool = Activity(verb: "has a question")
                        } else if name == Activity.planTool {
                            // Waiting for the plan to be approved, not running anything.
                            tool = Activity(verb: "has a plan for you")
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
                        turn = Activity.waitsOnUser.contains(tool.verb) ? .attention(tool) : .tool(tool)
                    } else if turn == .unknown || turn == .finished {
                        turn = .thinking
                    }
                }
            default:
                break
            }
        }

        var (phase, activity) = resolve(turn, modified: modified, now: now)
        // A window that has reset since is no longer news.
        if let resets = limit?.resetsAt, resets <= now { limit = nil }
        if stoppedByLimit, limit != nil, phase == .waiting { activity = Activity(verb: "hit its limit") }
        let host: SessionHost? = entrypoint == "claude-desktop" ? .claudeDesktop : nil
        var snapshot = TranscriptSnapshot(
            key: SessionKey(source: source, sessionID: id), path: path, cwd: cwd, host: host,
            title: title ?? agentName, firstPrompt: firstPrompt ?? lastPrompt, lastPrompt: lastPrompt, lastReply: lastReply,
            phase: phase, activity: activity, updatedAt: modified, phaseSince: since)
        snapshot.limitReached = limit
        snapshot.progress = progress
        snapshot.model = model
        snapshot.context = context
        return snapshot
    }

    /// Claude Code writes down why a request was refused: which window is full and when it opens again.
    static func limitReached(_ object: JSONObject) -> RateLimitWindow? {
        guard let info = object["apiErrorParams"]?["rate_limit_info"] ?? object["quotaLimits"], info.objectValue != nil,
              info["status"]?.stringValue == "rejected", let kind = info["rateLimitType"]?.stringValue, !kind.isEmpty,
              let resets = info["resetsAt"]?.doubleValue, resets > 0 else { return nil }
        return RateLimitWindow(id: kind, usedPercent: 100, resetsAt: Date(timeIntervalSince1970: resets > 100_000_000_000 ? resets / 1000 : resets))
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
        var progress: TaskProgress?
        var model: String?
        var context: ContextFill?

        for line in TranscriptText.lines(tail, dropFirst: !tailIsWholeFile) {
            // Reasoning and bookkeeping lines are most of a rollout; they change nothing we show, except that
            // a token count says how full the context is (it is small, and only the size and the window are taken).
            if TranscriptText.contains(line, "\"token_count\"", within: 400) {
                if line.count < 8192, let payload = TranscriptText.object(line)?["payload"] {
                    context = ContextFill.codex(info: payload["info"]) ?? context
                }
                continue
            }
            if TranscriptText.contains(line, "\"token_usage_record\"", within: 200) || TranscriptText.contains(line, "\"item_completed\"", within: 400) { continue }
            guard let object = TranscriptText.object(line), let payload = object["payload"]?.objectValue else { continue }
            let stamp = TranscriptText.date(object["timestamp"])
            let kind = payload["type"]?.stringValue ?? ""
            switch object["type"]?.stringValue {
            case "turn_context":
                cwd = payload["cwd"]?.stringValue ?? cwd
                model = payload["model"]?.stringValue ?? model
            case "event_msg":
                switch kind {
                case "task_started":
                    turn = .thinking
                    since = stamp ?? since
                    question = nil
                    lastReply = nil   // the reply belongs to the turn before it
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
                    if name == "update_plan" {
                        // Bookkeeping, not work: the list is noted and the row keeps saying what it said.
                        progress = TaskProgress.from(tool: name, input: arguments) ?? progress
                    } else if (name ?? "").contains("request_user_input") {
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
        var snapshot = TranscriptSnapshot(
            key: SessionKey(source: source, sessionID: meta.id), path: path, cwd: cwd, host: meta.host,
            title: meta.isSubagent ? meta.role : nil, firstPrompt: meta.firstPrompt ?? lastPrompt, lastPrompt: lastPrompt,
            lastReply: lastReply, phase: phase, activity: activity, updatedAt: modified, phaseSince: since,
            isSubagent: meta.isSubagent, parentID: meta.parentID)
        snapshot.progress = progress
        snapshot.model = model
        snapshot.context = context
        return snapshot
    }
}
