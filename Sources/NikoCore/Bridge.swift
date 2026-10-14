import Darwin
import Foundation

/// Parsed `niko-bridge` command line (PROTOCOLS §3).
public struct BridgeInvocation: Sendable, Equatable {
    public enum ReplyMode: String, Sendable {
        case json
        /// Only `behavior` (and a message on deny): for agents that fail
        /// closed on anything more (Codex, ZCode).
        case jsonStrict = "json-strict"
        case exitCode = "exit-code"
        /// Devin: `{"decision": "approve"}`, or `{"decision": "block", "reason": …}` and exit 2.
        case devin
    }

    public var source = "unknown"
    public var task: String?
    public var cacheFile: String?
    public var integrityCheck: String?
    public var showVersion = false
    /// Adapter says this event blocks for a decision even though it is not a PermissionRequest.
    public var forceBlocking = false
    public var replyMode: ReplyMode = .json
    /// The event, for agents whose payload does not name it (Copilot CLI's own format).
    public var event: String?
    /// The agent's approval hook can only watch: report the request, never hold the agent up.
    public var observeOnly = false

    public init() {}

    /// Lenient by design: unknown flags are ignored, never fatal.
    public static func parse(_ arguments: [String]) -> BridgeInvocation {
        var invocation = BridgeInvocation()
        var index = 0
        func value() -> String? {
            guard index + 1 < arguments.count else { return nil }
            index += 1
            return arguments[index]
        }
        while index < arguments.count {
            switch arguments[index] {
            case "--source": if let v = value() { invocation.source = v }
            case "--task": invocation.task = value()
            case "--cache-file": invocation.cacheFile = value()
            case "--integrity-check": invocation.integrityCheck = value()
            case "--reply": if let v = value(), let mode = ReplyMode(rawValue: v) { invocation.replyMode = mode }
            case "--blocking": invocation.forceBlocking = true
            case "--event": invocation.event = value()
            case "--observe": invocation.observeOnly = true
            case "--version": invocation.showVersion = true
            default: break
            }
            index += 1
        }
        return invocation
    }
}

public struct BridgeResult: Sendable, Equatable {
    public var exitCode: Int32 = 0
    public var stdout = Data()
    public var stderr = Data()

    public static let silentSuccess = BridgeResult()
    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public struct BridgeConfiguration: Sendable {
    public var paths: NikoPaths
    public var environment: [String: String]
    public var connectTimeoutMS: Int32 = 250
    public var sendTimeoutMS: Int32 = 1000
    /// How long a fire-and-forget event waits for the app to take the bytes.
    public var ackTimeoutMS: Int32 = 400
    /// PROTOCOLS §2.2: hooks are registered with an 86400 s timeout; we give up a little earlier.
    public var replyTimeout: TimeInterval = 23 * 3600
    /// Called right before the long wait for a decision, so the caller can disarm its watchdog.
    public var willAwaitReply: @Sendable () -> Void = {}

    public init(paths: NikoPaths = .resolve(), environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.paths = paths
        self.environment = environment
    }
}

/// A user decision as the agent should see it.
public struct BridgeDecision: Sendable, Equatable {
    public enum Behavior: String, Sendable { case allow, deny }

    public var behavior: Behavior
    /// `block`: deny and stop the agent's current turn.
    public var interrupt: Bool
    public var reason: String?
    public var updatedInput: JSONObject?

    public init(behavior: Behavior, interrupt: Bool = false, reason: String? = nil, updatedInput: JSONObject? = nil) {
        self.behavior = behavior
        self.interrupt = interrupt
        self.reason = reason
        self.updatedInput = updatedInput
    }

    /// Parses the app's reply line (PROTOCOLS §2.2). `nil` means "no decision":
    /// the bridge then stays silent and the agent falls back to its own prompt.
    public init?(replyLine: JSONValue) {
        guard replyLine["ok"]?.boolValue != false, let reply = replyLine["reply"], !reply.isNull else { return nil }
        let decision = reply.at("hookSpecificOutput", "decision") ?? reply["decision"] ?? reply
        guard let raw = (decision["behavior"] ?? decision["decision"])?.stringValue?.lowercased() else { return nil }
        switch raw {
        case "approve", "allow": behavior = .allow; interrupt = false
        case "deny": behavior = .deny; interrupt = false
        case "block": behavior = .deny; interrupt = true
        default: return nil
        }
        reason = (decision["reason"] ?? decision["message"])?.stringValue
        updatedInput = decision["updatedInput"]?.objectValue
    }
}

public enum BridgeRunner {
    public static let maxFrameBytes = LineFramer.defaultMaxLineBytes
    static let slimStringLimit = 4096
    static let promptLimit = 512

    /// Entry point. Whatever goes wrong in here, the result is exit 0 with no
    /// output — the agent must never fail because we do. The only non-zero
    /// exits are a user's explicit deny in exit-code mode (2) and the
    /// integrity self-check (1), which no hook ever calls.
    public static func run(_ invocation: BridgeInvocation, stdin: Data, configuration: BridgeConfiguration) -> BridgeResult {
        if invocation.showVersion {
            return BridgeResult(stdout: Data("niko-bridge \(NikoVersion.current)\n".utf8))
        }
        if let bundle = invocation.integrityCheck {
            return integrityCheck(bundlePath: bundle)
        }
        if invocation.task == "statusline-cache" {
            cacheStatusline(stdin, to: invocation.cacheFile ?? configuration.paths.rateLimitCache.path)
            return .silentSuccess
        }
        guard invocation.task == nil else { return .silentSuccess }
        return forward(invocation, stdin: stdin, configuration: configuration)
    }

    // MARK: Event forwarding

    static func forward(_ invocation: BridgeInvocation, stdin: Data, configuration: BridgeConfiguration) -> BridgeResult {
        guard let parsed = try? JSONValue.parse(stdin), var object = parsed.objectValue else { return .silentSuccess }
        // Most agents name the event `hook_event_name`; Cascade calls it `agent_action_name`;
        // Copilot CLI's own format leaves it to the command line.
        if (object["hook_event_name"] ?? object["agent_action_name"])?.stringValue?.isEmpty ?? true, let event = invocation.event {
            object["hook_event_name"] = .string(event)
        }
        guard var name = (object["hook_event_name"] ?? object["agent_action_name"])?.stringValue, !name.isEmpty else {
            return .silentSuccess
        }

        var invocation = invocation
        let chain = ancestry()
        let context = terminalContext(environment: configuration.environment, chain: chain)
        // Devin and Copilot CLI also run the hooks in Claude Code's settings. An
        // event that comes in as Claude Code's from inside one of them is theirs;
        // when their own hooks of ours are in place it is a copy, and goes.
        if invocation.source == "claude", let borrower = BorrowedHooks.borrower(in: chain) {
            if BorrowedHooks.ownHooksInstalled(borrower, home: configuration.environment["HOME"] ?? NikoPaths.userHome().path) {
                return .silentSuccess
            }
            invocation.source = borrower.agent
            invocation.replyMode = borrower.reply
            invocation.observeOnly = borrower.observeOnly
        }

        if invocation.observeOnly, name == HookEvent.permissionRequest {
            // Shown as "needs permission"; the agent asks in its own window as always.
            object["native_event"] = .string(name)
            object["hook_event_name"] = .string(HookEvent.notification)
            object["notification_type"] = .string("permission_prompt")
            object["message"] = .string(object["tool_name"]?.stringValue ?? "permission")
            name = HookEvent.notification
        }

        object["ts"] = .number(String(Int64(Date().timeIntervalSince1970 * 1000)))
        if invocation.forceBlocking { object[AgentEvent.blockingKey] = .bool(true) }
        let blocking = name == HookEvent.permissionRequest || invocation.forceBlocking

        var meta = context.json.objectValue ?? JSONObject()
        // Which adapter this is travels in our own envelope: agents use a
        // top-level "source" for other things (how a session started, for one).
        meta["source"] = .string(invocation.source)
        object = slim(object, blocking: blocking)
        object[AgentEvent.metaKey] = .object(meta)

        var line = JSONValue.object(object).serializedData(.compact)
        if line.count > maxFrameBytes {
            // Too big for one frame: send a cut-down copy so the session still
            // shows up. The flag tells the app never to echo this input back.
            meta["truncated"] = .bool(true)
            object = truncateStrings(in: object, limit: 2048)
            object[AgentEvent.metaKey] = .object(meta)
            line = JSONValue.object(object).serializedData(.compact)
            guard line.count <= maxFrameBytes else { return .silentSuccess }
        }
        line.append(0x0A)

        let socketPath = configuration.paths.socket.path
        var st = stat()
        guard lstat(socketPath, &st) == 0, st.st_mode & S_IFMT == S_IFSOCK, st.st_uid == getuid() else {
            return .silentSuccess   // app not running (or not ours): nothing to do
        }
        let fd = SocketIO.connectUnix(socketPath, timeoutMS: configuration.connectTimeoutMS)
        guard fd >= 0 else { return .silentSuccess }
        defer { close(fd) }
        guard SocketIO.writeAll(fd, line, timeoutMS: configuration.sendTimeoutMS) else { return .silentSuccess }

        guard blocking else {
            // Half-close and wait briefly for the app's EOF. Without this, macOS
            // can discard a connection that is closed before it was accepted.
            shutdown(fd, SHUT_WR)
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            _ = poll(&pfd, 1, configuration.ackTimeoutMS)
            return .silentSuccess
        }

        configuration.willAwaitReply()
        guard let replyData = readLine(fd, timeout: configuration.replyTimeout),
              let replyLine = try? JSONValue.parse(replyData),
              let decision = BridgeDecision(replyLine: replyLine) else {
            return .silentSuccess   // app quit, timed out, or declined to decide
        }
        return render(decision, eventName: name, event: object, mode: invocation.replyMode)
    }

    /// Reads one `\n`-terminated line, or nil on EOF/timeout/oversize.
    static func readLine(_ fd: Int32, timeout: TimeInterval) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(min(remaining, 3600) * 1000))
            if ready < 0, errno == EINTR { continue }
            if ready == 0 { continue }
            guard ready > 0 else { return nil }
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR || errno == EAGAIN { continue }
            guard n > 0 else { return nil }
            if let newline = buffer[0..<n].firstIndex(of: 0x0A) {
                out.append(contentsOf: buffer[0..<newline])
                return out
            }
            out.append(contentsOf: buffer[0..<n])
            guard out.count <= maxFrameBytes else { return nil }
        }
    }

    // MARK: Payload shaping

    /// The app needs names and short hints, not file contents. Drop what it
    /// never reads and cap long strings — except for blocking requests, whose
    /// `tool_input` must stay intact so an answer can be merged into it.
    static func slim(_ object: JSONObject, blocking: Bool) -> JSONObject {
        var out = object
        // Results, file contents and model traffic: never needed for a status line.
        for key in ["tool_response", "tool_result", "tool_output", "output", "content", "edits", "result_json",
                    "attachments", "llm_request", "llm_response", "prompt_response", "model_params", "user_email"] {
            out[key] = nil
        }
        if var info = out["tool_info"]?.objectValue {
            for key in ["edits", "mcp_result", "response", "mcp_tool_arguments"] { info[key] = nil }
            out["tool_info"] = .object(info)
        }
        if let prompt = out["prompt"]?.stringValue, prompt.count > promptLimit {
            out["prompt"] = .string(String(prompt.prefix(promptLimit)))
        }
        guard !blocking else { return out }
        return truncateStrings(in: out, limit: slimStringLimit)
    }

    static func truncateStrings(in object: JSONObject, limit: Int) -> JSONObject {
        JSONObject(object.members.map { .init($0.key, truncateStrings(in: $0.value, limit: limit)) })
    }

    static func truncateStrings(in value: JSONValue, limit: Int) -> JSONValue {
        switch value {
        case .string(let s) where s.utf8.count > limit:
            return .string(String(s.prefix(limit)) + "…")
        case .array(let items):
            return .array(items.map { truncateStrings(in: $0, limit: limit) })
        case .object(let object):
            return .object(truncateStrings(in: object, limit: limit))
        default:
            return value
        }
    }

    /// Terminal coordinates for click-to-jump, read from our own inherited
    /// environment (we are a child of the agent, inside its terminal).
    static func terminalContext(environment: [String: String], chain: [BorrowedHooks.Ancestor]? = nil) -> TerminalContext {
        var context = TerminalContext()
        func value(_ key: String) -> String? { environment[key].flatMap { $0.isEmpty ? nil : $0 } }
        context.termProgram = value("TERM_PROGRAM")
        context.itermSessionID = value("ITERM_SESSION_ID")
        context.tmux = value("TMUX")
        context.tmuxPane = value("TMUX_PANE")
        context.bundleID = value("__CFBundleIdentifier")
        context.tty = ProcessInspector.controllingTTY(of: getpid())
        context.pid = getppid()
        let chain = chain ?? ancestry()
        context.ancestors = chain.map(\.path)
        context.ancestorPIDs = chain.map(\.pid)
        return context
    }

    /// The bridge's parents, nearest first.
    static func ancestry() -> [BorrowedHooks.Ancestor] {
        var chain: [BorrowedHooks.Ancestor] = []
        var current = getppid()
        var seen: Set<pid_t> = []
        while current > 1, chain.count < 12, seen.insert(current).inserted,
              let path = ProcessInspector.path(of: current) {
            chain.append(BorrowedHooks.Ancestor(pid: current, path: path))
            guard let parent = ProcessInspector.parent(of: current) else { break }
            current = parent
        }
        return chain
    }

    // MARK: Reply translation

    /// Translates a decision into what a Claude-dialect hook runner expects.
    static func render(_ decision: BridgeDecision, eventName: String, event: JSONObject,
                       mode: BridgeInvocation.ReplyMode) -> BridgeResult {
        let denyMessage = decision.reason ?? "Denied in Niko Island"
        if mode == .exitCode {
            switch decision.behavior {
            case .allow: return .silentSuccess
            case .deny: return BridgeResult(exitCode: 2, stderr: Data((denyMessage + "\n").utf8))
            }
        }
        if mode == .devin {
            switch decision.behavior {
            case .allow:
                return BridgeResult(stdout: Data((JSONValue.object(["decision": .string("approve")]).serialized(.compact) + "\n").utf8))
            case .deny:
                // Exit 2 denies whatever Devin makes of the output; the reason goes both ways.
                let body = JSONValue.object(["decision": .string("block"), "reason": .string(denyMessage)])
                return BridgeResult(exitCode: 2, stdout: Data((body.serialized(.compact) + "\n").utf8),
                                    stderr: Data((denyMessage + "\n").utf8))
            }
        }

        var updatedInput = mode == .jsonStrict ? nil : decision.updatedInput
        if let input = updatedInput, event["tool_name"]?.stringValue == "AskUserQuestion" {
            updatedInput = claudeQuestionAnswers(input)
        }

        let output: JSONValue
        switch eventName {
        case HookEvent.permissionRequest:
            var body = JSONObject()
            switch decision.behavior {
            case .allow:
                body["behavior"] = .string("allow")
                if let updatedInput { body["updatedInput"] = .object(updatedInput) }
            case .deny:
                body["behavior"] = .string("deny")
                body["message"] = .string(denyMessage)
                if decision.interrupt, mode != .jsonStrict { body["interrupt"] = .bool(true) }
            }
            output = .object(["hookSpecificOutput": .object([
                "hookEventName": .string(HookEvent.permissionRequest),
                "decision": .object(body),
            ])])
        case HookEvent.preToolUse:
            var body = JSONObject(["hookEventName": .string(HookEvent.preToolUse)])
            body["permissionDecision"] = .string(decision.behavior == .allow ? "allow" : "deny")
            if let reason = decision.reason ?? (decision.behavior == .deny ? denyMessage : nil) {
                body["permissionDecisionReason"] = .string(reason)
            }
            if decision.behavior == .allow, let updatedInput { body["updatedInput"] = .object(updatedInput) }
            output = .object(["hookSpecificOutput": .object(body)])
        default:
            // No JSON form for this event: fall back to the universal convention.
            switch decision.behavior {
            case .allow: return .silentSuccess
            case .deny: return BridgeResult(exitCode: 2, stderr: Data((denyMessage + "\n").utf8))
            }
        }
        return BridgeResult(stdout: Data((output.serialized(.compact) + "\n").utf8))
    }

    /// Canonical answers are `answers[i] = [labels…]` (PROTOCOLS / INTEGRATIONS).
    /// Claude Code's question tool wants `answers = {"<question text>": "label, label"}`.
    static func claudeQuestionAnswers(_ input: JSONObject) -> JSONObject {
        guard let answers = input["answers"]?.arrayValue, let questions = input["questions"]?.arrayValue else {
            return input
        }
        var map = JSONObject()
        for (index, question) in questions.enumerated() where index < answers.count {
            guard let text = (question["question"] ?? question["text"])?.stringValue else { continue }
            let labels: [String]
            switch answers[index] {
            case .array(let items): labels = items.compactMap(\.stringValue)
            case .string(let single): labels = [single]
            default: labels = []
            }
            map[text] = .string(labels.joined(separator: ", "))
        }
        var out = input
        out["answers"] = .object(map)
        return out
    }

    // MARK: Statusline cache

    /// Extracts `rate_limits` from a statusline payload into the cache file
    /// (PROTOCOLS §4). A payload without rate limits leaves the cache alone.
    static func cacheStatusline(_ stdin: Data, to path: String) {
        guard let payload = try? JSONValue.parse(stdin), let limits = payload["rate_limits"], limits.objectValue != nil else {
            return
        }
        var cache = JSONObject()
        cache["captured_at"] = .number(String(Int64(Date().timeIntervalSince1970 * 1000)))
        cache["rate_limits"] = limits
        if let model = payload.at("model", "display_name") ?? payload.at("model", "id") { cache["model"] = model }
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: directory) {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        AtomicFile.write(JSONValue.object(cache).serializedData(.compact), to: path, mode: 0o600)
    }

    // MARK: Integrity self-check

    static func integrityCheck(bundlePath: String) -> BridgeResult {
        var problems: [String] = []
        var notes: [String] = []
        let bundle = URL(fileURLWithPath: bundlePath)
        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let identifier = plist["CFBundleIdentifier"] as? String ?? "?"
            if identifier == NikoVersion.bundleIdentifier {
                notes.append("bundle id \(identifier)")
            } else {
                problems.append("unexpected bundle id \(identifier)")
            }
            notes.append("version \(plist["CFBundleShortVersionString"] as? String ?? "?")")
        } else {
            problems.append("Info.plist missing or unreadable")
        }
        for relative in ["Contents/MacOS/niko-island", "Contents/Helpers/niko-bridge"] {
            let path = bundle.appendingPathComponent(relative).path
            if FileManager.default.isExecutableFile(atPath: path) {
                notes.append("\(relative) present")
            } else {
                problems.append("\(relative) missing or not executable")
            }
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["--verify", "--deep", "--strict", bundlePath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    notes.append("code signature valid")
                } else {
                    problems.append("code signature does not verify")
                }
            }
        }
        var text = notes.map { "ok: \($0)" }.joined(separator: "\n")
        if !problems.isEmpty { text += "\n" + problems.map { "fail: \($0)" }.joined(separator: "\n") }
        return BridgeResult(exitCode: problems.isEmpty ? 0 : 1, stdout: Data((text + "\n").utf8))
    }
}

/// Agents that run the hooks in Claude Code's settings as well as their own:
/// Devin does by default, and Copilot CLI reads them too.
public enum BorrowedHooks {
    public struct Ancestor: Sendable, Equatable {
        public var pid: pid_t
        public var path: String
        public init(pid: pid_t, path: String) {
            self.pid = pid
            self.path = path
        }
        var name: String { (path as NSString).lastPathComponent }
    }

    public struct Borrower: Sendable, Equatable {
        public var agent: String
        /// Executable names of its command-line tool.
        var names: Set<String>
        /// For one run by a script host (node, bun): what its script path contains.
        var scriptHints: [String]
        /// The file of ours that means its own hooks are in place.
        var ownHooks: String
        var reply: BridgeInvocation.ReplyMode
        var observeOnly: Bool
    }

    static let borrowers: [Borrower] = [
        Borrower(agent: "devin", names: ["devin"], scriptHints: [], ownHooks: ".config/devin/config.json",
                 reply: .devin, observeOnly: false),
        Borrower(agent: "copilot", names: ["copilot"], scriptHints: ["@github/copilot"], ownHooks: ".copilot/hooks/niko.json",
                 reply: .json, observeOnly: true),
    ]
    static let scriptHosts: Set<String> = ["node", "bun", "deno"]
    static let claudeHints = ["@anthropic-ai/claude-code"]

    /// The agent that ran the hook, looking up from the bridge until Claude Code itself turns up.
    static func borrower(in chain: [Ancestor], arguments: (pid_t) -> [String] = ProcessInspector.arguments(of:)) -> Borrower? {
        for ancestor in chain {
            let name = ancestor.name
            if name == "claude" { return nil }
            if let found = borrowers.first(where: { $0.names.contains(name) }) { return found }
            guard scriptHosts.contains(name) else { continue }
            let script = arguments(ancestor.pid).dropFirst().prefix(3).joined(separator: " ")
            if claudeHints.contains(where: script.contains) { return nil }
            if let found = borrowers.first(where: { $0.scriptHints.contains(where: script.contains) }) { return found }
        }
        return nil
    }

    static func ownHooksInstalled(_ borrower: Borrower, home: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: home + "/" + borrower.ownHooks), data.count <= ScanProbe.sizeCap else {
            return false
        }
        return HookMerge.isOurs(command: String(decoding: data, as: UTF8.self))
    }
}

public enum AtomicFile {
    /// tmp + rename in the same directory. Returns false on any failure.
    @discardableResult
    public static func write(_ data: Data, to path: String, mode: mode_t) -> Bool {
        let tmp = path + ".tmp.\(getpid()).\(UInt32.random(in: 0...UInt32.max))"
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode)
        guard fd >= 0 else { return false }
        let written = SocketIO.writeAll(fd, data, timeoutMS: 2000)
        fchmod(fd, mode)
        close(fd)
        guard written, rename(tmp, path) == 0 else {
            unlink(tmp)
            return false
        }
        return true
    }
}
