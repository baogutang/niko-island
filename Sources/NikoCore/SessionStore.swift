import Foundation

/// One agent session as shown on a card (SPEC §4).
public struct Session: Identifiable, Sendable, Equatable {
    public enum Phase: String, Sendable {
        case working
        /// The agent finished its turn and is idle until the user types.
        case waiting
        /// A permission request or question is blocking the agent.
        case needsAttention
    }

    public let key: SessionKey
    public var id: String { key.description }
    public var cwd: String?
    public var transcriptPath: String?
    public var title: String
    public var startedAt: Date
    public var lastEventAt: Date
    /// When the current phase began — the card's elapsed timer counts from here.
    public var phaseSince: Date
    public var activity: Activity
    public var phase: Phase
    public var terminal: TerminalContext
    public var ancestors: [ProcessNode]
    public var firstPrompt: String?
    public var toolCalls = 0

    public var source: String { key.source }
}

/// Pure reducer from canonical events to session state. No UI, no clocks of its own.
public struct SessionStore: Sendable {
    public enum Change: Sendable, Equatable {
        case updated(SessionKey)
        case ended(SessionKey)
        /// The agent stopped and is waiting for input (worth a notification).
        case becameIdle(SessionKey)
    }

    public static let idleExpiry: TimeInterval = 12 * 3600

    public private(set) var sessions: [SessionKey: Session] = [:]

    public init() {}

    /// Needs-attention first, then waiting, then working; newest activity first within each.
    public var ordered: [Session] {
        func rank(_ phase: Session.Phase) -> Int {
            switch phase {
            case .needsAttention: return 0
            case .waiting: return 1
            case .working: return 2
            }
        }
        return sessions.values.sorted {
            if rank($0.phase) != rank($1.phase) { return rank($0.phase) < rank($1.phase) }
            if $0.lastEventAt != $1.lastEventAt { return $0.lastEventAt > $1.lastEventAt }
            return $0.id < $1.id
        }
    }

    public subscript(key: SessionKey) -> Session? { sessions[key] }

    @discardableResult
    public mutating func apply(_ event: AgentEvent, evidence: AdmissionEvidence? = nil, now: Date = Date()) -> Change {
        let key = event.key
        if event.name == HookEvent.sessionEnd {
            sessions[key] = nil
            return .ended(key)
        }

        var session = sessions[key] ?? Session(
            key: key, cwd: event.cwd, transcriptPath: event.transcriptPath,
            title: AutoNamer.title(cwd: event.cwd, prompt: nil, source: event.source),
            startedAt: now, lastEventAt: now, phaseSince: now,
            activity: Activity(verb: "starting"), phase: .working,
            terminal: event.terminal, ancestors: evidence?.ancestors ?? [], firstPrompt: nil)
        let previousPhase = session.phase

        session.lastEventAt = now
        if let cwd = event.cwd, cwd != session.cwd {
            session.cwd = cwd
            session.title = AutoNamer.title(cwd: cwd, prompt: session.firstPrompt, source: event.source)
        }
        if let transcript = event.transcriptPath { session.transcriptPath = transcript }
        if !event.terminal.isEmpty { session.terminal = event.terminal }
        if let ancestors = evidence?.ancestors, !ancestors.isEmpty { session.ancestors = ancestors }

        switch event.name {
        case HookEvent.sessionStart:
            session.phase = .working
            session.activity = Activity(verb: "starting")
        case HookEvent.userPromptSubmit:
            session.phase = .working
            session.activity = .thinking
            if session.firstPrompt == nil, let prompt = event.raw["prompt"]?.stringValue, !prompt.isEmpty {
                session.firstPrompt = prompt
                session.title = AutoNamer.title(cwd: session.cwd, prompt: prompt, source: event.source)
            }
        case HookEvent.preToolUse:
            session.phase = .working
            session.activity = Activity.forTool(event.toolName, input: event.toolInput)
            session.toolCalls += 1
        case HookEvent.postToolUse:
            session.phase = .working
            session.activity = .thinking
        case HookEvent.permissionRequest:
            session.phase = .needsAttention
            session.activity = Questions.isQuestion(event)
                ? Activity(verb: "has a question")
                : Activity(verb: "needs permission", detail: event.toolName)
        case HookEvent.notification:
            let kind = event.raw["notification_type"]?.stringValue ?? ""
            let message = event.raw["message"]?.stringValue ?? ""
            if kind == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting for your input") {
                session.phase = .waiting
                session.activity = .waiting
            } else if kind == "permission_prompt" || message.localizedCaseInsensitiveContains("needs your permission") {
                session.phase = .needsAttention
                session.activity = Activity(verb: "needs permission", detail: Activity.oneLine(message, limit: 96))
            } else if !message.isEmpty {
                session.activity.detail = Activity.oneLine(message, limit: 96)
            }
        case HookEvent.stop:
            session.phase = .waiting
            session.activity = .waiting
        case HookEvent.subagentStop:
            break
        case HookEvent.preCompact:
            session.phase = .working
            session.activity = Activity(verb: "compacting")
        case HookEvent.postCompact:
            session.phase = .working
            session.activity = .thinking
        default:
            session.activity = Activity(verb: "working", detail: event.name)
        }

        if session.phase != previousPhase || sessions[key] == nil { session.phaseSince = now }
        sessions[key] = session
        if session.phase == .waiting, previousPhase != .waiting { return .becameIdle(key) }
        return .updated(key)
    }

    /// Called once a blocking request has been answered (or withdrawn).
    public mutating func resolveAttention(_ key: SessionKey, activity: Activity, now: Date = Date()) {
        guard var session = sessions[key], session.phase == .needsAttention else { return }
        session.phase = .working
        session.activity = activity
        session.phaseSince = now
        sessions[key] = session
    }

    /// Drops sessions that have been silent for `idleExpiry` (an agent that was killed never says goodbye).
    @discardableResult
    public mutating func prune(now: Date = Date()) -> [SessionKey] {
        let stale = sessions.values.filter { now.timeIntervalSince($0.lastEventAt) > SessionStore.idleExpiry }.map(\.key)
        stale.forEach { sessions[$0] = nil }
        return stale
    }

    public mutating func remove(_ key: SessionKey) { sessions[key] = nil }
}

/// Session auto-naming (SPEC v3): project name plus a few keywords from the first prompt.
public enum AutoNamer {
    static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "for", "with", "at", "by", "from", "into",
        "is", "are", "was", "be", "it", "this", "that", "these", "those", "my", "our", "your", "me", "we", "you", "i",
        "please", "can", "could", "would", "should", "let", "lets", "help", "need", "want", "some", "any", "all",
        "how", "what", "why", "when", "do", "does", "so", "as", "if", "then", "just", "also", "have", "has", "new",
    ]

    /// Name of the enclosing repository (directory holding `.git`), else the directory itself.
    public static func projectName(cwd: String?) -> String? {
        guard let cwd, cwd.hasPrefix("/") else { return nil }
        var url = URL(fileURLWithPath: cwd)
        let fallback = url.lastPathComponent
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.lastPathComponent
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path || parent.path == "/" { break }
            url = parent
        }
        return fallback.isEmpty || fallback == "/" ? nil : fallback
    }

    public static func keywords(from prompt: String, limit: Int = 4) -> [String] {
        var out: [String] = []
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        for raw in firstLine.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) {
            let word = String(raw)
            guard word.count > 1, !stopwords.contains(word.lowercased()) else { continue }
            out.append(word.count > 24 ? String(word.prefix(24)) : word)
            if out.count == limit { break }
        }
        return out
    }

    public static func title(cwd: String?, prompt: String?, source: String) -> String {
        let project = projectName(cwd: cwd) ?? AgentRegistry.displayName(for: source)
        guard let prompt else { return project }
        let words = keywords(from: prompt)
        return words.isEmpty ? project : "\(project) · \(words.joined(separator: " "))"
    }
}
