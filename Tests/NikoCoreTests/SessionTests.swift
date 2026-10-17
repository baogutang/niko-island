import XCTest
@testable import NikoCore

final class SessionStoreTests: XCTestCase {
    private func event(_ name: String, session: String = "s1", source: String = "claude", cwd: String? = "/work/app",
                       fields: JSONObject = JSONObject()) -> AgentEvent {
        var object = JSONObject(["source": .string(source), "hook_event_name": .string(name), "session_id": .string(session)])
        if let cwd { object["cwd"] = .string(cwd) }
        for member in fields.members { object[member.key] = member.value }
        return try! AgentEvent(json: .object(object))
    }

    private let key = SessionKey(source: "claude", sessionID: "s1")
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testFullTurnProducesTheExpectedStates() {
        var store = SessionStore()
        XCTAssertEqual(store.apply(event("SessionStart"), now: t0), .updated(key))
        XCTAssertEqual(store[key]?.activity.verb, "starting")
        XCTAssertEqual(store[key]?.title, "app")

        store.apply(event("UserPromptSubmit", fields: ["prompt": .string("Please add a retry to the uploader\nsecond line")]), now: t0 + 1)
        XCTAssertEqual(store[key]?.activity, .thinking)
        XCTAssertEqual(store[key]?.title, "app · add retry uploader")
        XCTAssertEqual(store[key]?.firstPrompt?.hasPrefix("Please add"), true)

        store.apply(event("PreToolUse", fields: ["tool_name": .string("Grep"), "tool_input": .object(["pattern": .string("retry")])]), now: t0 + 2)
        XCTAssertEqual(store[key]?.activity, Activity(verb: "finding", detail: "retry"))
        XCTAssertEqual(store[key]?.toolCalls, 1)
        store.apply(event("PostToolUse", fields: ["tool_name": .string("Grep")]), now: t0 + 3)
        XCTAssertEqual(store[key]?.activity, .thinking)
        XCTAssertEqual(store[key]?.phaseSince, t0, "still the same working phase")

        store.apply(event("PreCompact"), now: t0 + 4)
        XCTAssertEqual(store[key]?.activity.verb, "compacting")
        store.apply(event("SubagentStop"), now: t0 + 5)
        XCTAssertEqual(store[key]?.activity.verb, "compacting", "SubagentStop does not change what the main agent is doing")

        XCTAssertEqual(store.apply(event("Stop"), now: t0 + 9), .becameIdle(key))
        XCTAssertEqual(store[key]?.phase, .waiting)
        XCTAssertEqual(store[key]?.activity, .waiting)
        XCTAssertEqual(store[key]?.phaseSince, t0 + 9)
        XCTAssertEqual(store.apply(event("Stop"), now: t0 + 10), .updated(key), "already idle: no second announcement")

        XCTAssertEqual(store.apply(event("SessionEnd"), now: t0 + 11), .ended(key))
        XCTAssertNil(store[key])
    }

    func testPermissionAndNotificationPhases() {
        var store = SessionStore()
        store.apply(event("PermissionRequest", fields: ["tool_name": .string("Bash")]), now: t0)
        XCTAssertEqual(store[key]?.phase, .needsAttention)
        XCTAssertEqual(store[key]?.activity, Activity(verb: "needs permission", detail: "Bash"))
        store.resolveAttention(key, activity: Activity(verb: "running"), now: t0 + 3)
        XCTAssertEqual(store[key]?.phase, .working)
        XCTAssertEqual(store[key]?.phaseSince, t0 + 3)

        XCTAssertEqual(store.apply(event("Notification", fields: ["notification_type": .string("idle_prompt"), "message": .string("x")]), now: t0 + 4), .becameIdle(key))
        store.apply(event("Notification", fields: ["message": .string("Claude needs your permission to use Bash")]), now: t0 + 5)
        XCTAssertEqual(store[key]?.phase, .needsAttention)
        store.apply(event("UserPromptSubmit"), now: t0 + 6)
        store.apply(event("Notification", fields: ["message": .string("Build finished\nwith details")]), now: t0 + 7)
        XCTAssertEqual(store[key]?.phase, .working)
        XCTAssertEqual(store[key]?.activity.detail, "Build finished")
        // An event with no meaning here says the session is alive, not what it is doing.
        let before = store[key]?.activity
        store.apply(event("TotallyNewEvent"), now: t0 + 8)
        XCTAssertEqual(store[key]?.activity, before)
        XCTAssertEqual(store[key]?.lastEventAt, t0 + 8)

        store.resolveAttention(key, activity: Activity(verb: "running"))   // no-op when not waiting on the user
        XCTAssertEqual(store[key]?.activity, before)
    }

    func testTheListStaysStillWhileAgentsWork() {
        var store = SessionStore()
        store.apply(event("PreToolUse", session: "working-old"), now: t0)
        store.apply(event("PreToolUse", session: "working-new"), now: t0 + 50)
        store.apply(event("Stop", session: "idle"), now: t0 + 10)
        XCTAssertEqual(store.ordered.map(\.id), ["claude/idle", "claude/working-new", "claude/working-old"])
        // Another tool in a session that is already at work does not move it (it used to go to the top,
        // and with several agents at work the list reshuffled, animated, on almost every event).
        store.apply(event("PreToolUse", session: "working-old"), now: t0 + 70)
        store.apply(event("PostToolUse", session: "working-old"), now: t0 + 71)
        XCTAssertEqual(store.ordered.map(\.id), ["claude/idle", "claude/working-new", "claude/working-old"])
        // Finishing is news: it moves the session to the top of the waiting ones.
        store.apply(event("Stop", session: "working-old"), now: t0 + 80)
        XCTAssertEqual(store.ordered.map(\.id), ["claude/working-old", "claude/idle", "claude/working-new"])
    }

    func testOrderingKeysAndPruning() {
        var store = SessionStore()
        store.apply(event("PreToolUse", session: "working-old"), now: t0)
        store.apply(event("PreToolUse", session: "working-new"), now: t0 + 50)
        store.apply(event("Stop", session: "idle"), now: t0 + 10)
        store.apply(event("PermissionRequest", session: "blocked"), now: t0 + 5)
        store.apply(event("PreToolUse", session: "working-new", source: "codex"), now: t0 + 60)
        XCTAssertEqual(store.ordered.map(\.id), ["claude/blocked", "claude/idle", "codex/working-new", "claude/working-new", "claude/working-old"])
        XCTAssertEqual(store.sessions.count, 5, "same session id under another agent is a different session")

        XCTAssertEqual(store.prune(now: t0 + SessionStore.idleExpiry + 30).map(\.sessionID).sorted(), ["blocked", "idle", "working-old"])
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testCwdChangeRetitlesButKeepsPromptKeywords() {
        var store = SessionStore()
        store.apply(event("UserPromptSubmit", cwd: "/a/first", fields: ["prompt": .string("rename module")]), now: t0)
        XCTAssertEqual(store[key]?.title, "first · rename module")
        store.apply(event("PreToolUse", cwd: "/a/second"), now: t0 + 1)
        XCTAssertEqual(store[key]?.title, "second · rename module")
        store.apply(event("UserPromptSubmit", cwd: "/a/second", fields: ["prompt": .string("something else")]), now: t0 + 2)
        XCTAssertEqual(store[key]?.title, "second · rename module", "the first prompt names the session")
    }

    func testAutoNamer() throws {
        let scratch = Scratch()
        scratch.write("repo-root/.git/HEAD", "x")
        scratch.write("repo-root/packages/web/src/x.ts", "x")
        XCTAssertEqual(AutoNamer.projectName(cwd: scratch.file("repo-root/packages/web/src").path), "repo-root")
        XCTAssertEqual(AutoNamer.projectName(cwd: "/no/such/dir/leaf"), "leaf")
        XCTAssertNil(AutoNamer.projectName(cwd: nil))
        XCTAssertNil(AutoNamer.projectName(cwd: "relative"))
        XCTAssertEqual(AutoNamer.keywords(from: "Can you please fix the flaky upload-retry test in CI?"), ["fix", "flaky", "upload-retry", "test"])
        XCTAssertEqual(AutoNamer.keywords(from: "修复 上传 重试 的 问题"), ["修复", "上传", "重试", "问题"])
        XCTAssertEqual(AutoNamer.keywords(from: "   \n"), [])
        XCTAssertEqual(AutoNamer.title(cwd: nil, prompt: nil, source: "codex"), "Codex")
        XCTAssertEqual(AutoNamer.title(cwd: "/x/proj", prompt: "the a an", source: "claude"), "proj")
    }
}

final class ApprovalLogicTests: XCTestCase {
    private func request(tool: String, session: String = "s", input: JSONObject = JSONObject(), meta: JSONObject? = nil) -> AgentEvent {
        var object = JSONObject(["source": .string("claude"), "hook_event_name": .string("PermissionRequest"),
                                 "session_id": .string(session), "tool_name": .string(tool), "tool_input": .object(input)])
        if let meta { object["_niko"] = .object(meta) }
        return try! AgentEvent(json: .object(object))
    }

    func testReplyLinesFollowTheProtocol() throws {
        let event = request(tool: "Bash")
        let approve = ReplyBuilder.line(for: .allowOnce, event: event)
        XCTAssertEqual(approve.serialized(), #"{"ok":true,"reply":{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"approve","reason":"user allowed"}}}}"#)
        XCTAssertEqual(ReplyBuilder.line(for: .allowAlwaysTool, event: event), approve)
        XCTAssertEqual(ReplyBuilder.line(for: .allowAllSession, event: event), approve)
        XCTAssertEqual(ReplyBuilder.line(for: .deny, event: event).at("reply", "hookSpecificOutput", "decision", "behavior")?.stringValue, "deny")
        XCTAssertEqual(ReplyBuilder.line(for: .block, event: event).at("reply", "hookSpecificOutput", "decision", "behavior")?.stringValue, "block")
        XCTAssertEqual(ReplyBuilder.line(for: .passToTerminal, event: event).serialized(), #"{"ok":true,"reply":null}"#)
        // Every line must be understood by the bridge the same way.
        XCTAssertEqual(BridgeDecision(replyLine: approve)?.behavior, .allow)
        XCTAssertEqual(BridgeDecision(replyLine: ReplyBuilder.line(for: .block, event: event)), BridgeDecision(behavior: .deny, interrupt: true, reason: "Blocked in Niko Island"))
        XCTAssertNil(BridgeDecision(replyLine: ReplyBuilder.line(for: .passToTerminal, event: event)))
    }

    func testAnswersAreMergedIntoTheOriginalInput() throws {
        let input = JSONObject(["questions": .array([.object(["question": .string("Q1"), "options": .array([.string("A"), .string("B")])])]),
                                "metadata": .string("keep me")])
        let event = request(tool: "AskUserQuestion", input: input)
        let line = ReplyBuilder.line(for: .answer([["A", "B"]]), event: event)
        let updated = try XCTUnwrap(line.at("reply", "hookSpecificOutput", "decision", "updatedInput"))
        XCTAssertEqual(updated["answers"], .array([.array([.string("A"), .string("B")])]))
        XCTAssertEqual(updated["metadata"]?.stringValue, "keep me")
        XCTAssertEqual(updated["questions"], input["questions"])

        let truncated = request(tool: "AskUserQuestion", input: input, meta: ["truncated": .bool(true)])
        XCTAssertNil(ReplyBuilder.line(for: .answer([["A"]]), event: truncated).at("reply", "hookSpecificOutput", "decision", "updatedInput"),
                     "a cut-down request is never echoed back as input")
    }

    func testQuestionParsingAcceptsBothDialects() {
        let claude = Questions.parse(toolInput: JSONObject(["questions": .array([
            .object(["question": .string("Pick one"), "header": .string("H"), "multiSelect": .bool(true),
                     "options": .array([.object(["label": .string("A"), "description": .string("first")]), .object(["nolabel": .bool(true)])])]),
            .object(["options": .array([])]),   // no text: skipped
        ])]))
        XCTAssertEqual(claude, [AgentQuestion(id: 0, text: "Pick one", header: "H", options: [.init(label: "A", detail: "first")], multiSelect: true)])
        let canonical = Questions.parse(toolInput: JSONObject(["questions": .array([
            .object(["text": .string("T"), "options": .array([.string("x"), .string("y")]), "multiple": .bool(false)]),
        ])]))
        XCTAssertEqual(canonical.first?.options.map(\.label), ["x", "y"])
        XCTAssertEqual(canonical.first?.multiSelect, false)
        XCTAssertTrue(Questions.parse(toolInput: nil).isEmpty)
        XCTAssertTrue(Questions.parse(toolInput: JSONObject(["questions": .string("nope")])).isEmpty)
        XCTAssertFalse(Questions.isQuestion(request(tool: "AskUserQuestion")), "no parsable questions: treat as a plain permission request")
    }

    func testGrantsAreScopedToSessionAndTool() {
        var grants = SessionGrants()
        let bash = request(tool: "Bash"), edit = request(tool: "Edit"), other = request(tool: "Bash", session: "other")
        let question = request(tool: "AskUserQuestion", input: JSONObject(["questions": .array([.object(["question": .string("Q")])])]))
        XCTAssertFalse(grants.covers(bash))
        grants.record(.allowOnce, for: bash)
        grants.record(.deny, for: bash)
        XCTAssertFalse(grants.covers(bash))
        grants.record(.allowAlwaysTool, for: bash)
        XCTAssertTrue(grants.covers(bash))
        XCTAssertFalse(grants.covers(edit))
        XCTAssertFalse(grants.covers(other))
        grants.record(.allowAllSession, for: edit)
        XCTAssertTrue(grants.covers(edit))
        XCTAssertFalse(grants.covers(question), "questions can never be pre-approved")
        XCTAssertFalse(grants.covers(other))
        XCTAssertEqual(grants.summary(for: bash.key).tools, ["Bash"])
        XCTAssertTrue(grants.hasGrants(for: bash.key))
        grants.revoke(bash.key)
        XCTAssertFalse(grants.covers(bash))
        XCTAssertFalse(grants.hasGrants(for: bash.key))
    }

    func testRequestSummaries() {
        XCTAssertEqual(RequestSummary(event: request(tool: "Bash", input: ["command": .string("ls")])).kind, .command)
        let edit = RequestSummary(event: request(tool: "Write", input: ["file_path": .string("/a/b/Main.swift")]))
        XCTAssertEqual(edit.kind, .edit(file: "Main.swift"))
        XCTAssertEqual(edit.detail, "/a/b/Main.swift")
        XCTAssertEqual(RequestSummary(event: request(tool: "WebFetch", input: ["url": .string("https://x.dev")])).detail, "https://x.dev")
        XCTAssertEqual(RequestSummary(event: request(tool: "mcp__db__query")).kind, .other(tool: "mcp__db__query"))
        let long = RequestSummary(event: request(tool: "Bash", input: ["command": .string(String(repeating: "x", count: 5000))]))
        XCTAssertEqual(long.detail?.count, 600)
    }
}

final class TerminalJumpTests: XCTestCase {
    private func context(_ configure: (inout TerminalContext) -> Void) -> TerminalContext {
        var context = TerminalContext()
        configure(&context)
        return context
    }

    func testITermTargetAndScript() throws {
        let target = JumpTarget(terminal: context {
            $0.termProgram = "iTerm.app"
            $0.itermSessionID = "w1t3p0:6A1B-GUID"
            $0.tty = "ttys007"
        })
        XCTAssertEqual(target.app, .iterm2)
        XCTAssertEqual(target.itermSessionGUID, "6A1B-GUID")
        XCTAssertEqual(target.ttyDevice, "/dev/ttys007")
        XCTAssertEqual(target.bundleID, "com.googlecode.iterm2")
        let script = try XCTUnwrap(TerminalJump.appleScript(for: target))
        XCTAssertTrue(script.contains("tell application \"iTerm2\""))
        XCTAssertTrue(script.contains("if (unique id of aSession) is \"6A1B-GUID\" then"))
        XCTAssertTrue(script.contains("tell aSession to select"))
        XCTAssertTrue(TerminalJump.tmuxCommands(for: target).isEmpty)
    }

    func testTerminalAppScriptCompiles() throws {
        let target = JumpTarget(terminal: context {
            $0.termProgram = "Apple_Terminal"
            $0.tty = "/dev/ttys003"
        })
        XCTAssertEqual(target.app, .appleTerminal)
        let script = try XCTUnwrap(TerminalJump.appleScript(for: target))
        XCTAssertTrue(script.contains("if (tty of aTab) is \"/dev/ttys003\" then"))
        XCTAssertTrue(script.contains("set selected tab of aWindow to aTab"))
        // Compile only (never run): checks syntax and Terminal's scripting terms.
        let scratch = Scratch()
        let compiled = runProcess("/usr/bin/osacompile", ["-o", scratch.file("jump.scpt").path, "-e", script])
        XCTAssertEqual(compiled.status, 0, compiled.stderr)
        let viaTmux = try XCTUnwrap(TerminalJump.appleScript(for: target, clientTTY: "/dev/ttys011"))
        XCTAssertTrue(viaTmux.contains("\"/dev/ttys011\""), "inside tmux the client's tty is what the tab owns")
    }

    func testTmuxCommandsAndInjectionSafety() {
        let target = JumpTarget(terminal: context {
            $0.termProgram = "tmux"
            $0.itermSessionID = "w0t0p0:GUID"
            $0.tmux = "/private/tmp/tmux-501/default,4242,0"
            $0.tmuxPane = "%12"
        })
        XCTAssertEqual(target.app, .iterm2, "tmux inside iTerm2 still jumps to the iTerm2 session")
        XCTAssertEqual(TerminalJump.tmuxCommands(for: target), [
            ["-S", "/private/tmp/tmux-501/default", "select-window", "-t", "%12"],
            ["-S", "/private/tmp/tmux-501/default", "select-pane", "-t", "%12"],
        ])
        XCTAssertEqual(TerminalJump.tmuxClientQuery(for: target)?.suffix(4), ["-t", "%12", "-F", "#{client_tty}"])

        let hostile = JumpTarget(terminal: context {
            $0.termProgram = "iTerm.app"
            $0.itermSessionID = "w0:x\" then\ndo shell script \"rm -rf ~\"\n--"
            $0.tmux = "/s,1,0"
            $0.tmuxPane = "%1; kill-server"
        })
        let script = TerminalJump.appleScript(for: hostile) ?? ""
        XCTAssertTrue(script.contains("is \"x\\\" then do shell script \\\"rm -rf ~\\\" --\" then"), "quotes escaped, newlines flattened: stays one string literal")
        XCTAssertTrue(TerminalJump.tmuxCommands(for: hostile).isEmpty, "malformed pane ids are refused")
        XCTAssertNil(TerminalJump.tmuxClientQuery(for: hostile))
    }

    func testOtherHostsFallBackToActivation() {
        let ide = JumpTarget(terminal: context { $0.termProgram = "vscode"; $0.bundleID = "com.microsoft.VSCode" })
        XCTAssertEqual(ide.app, .other(bundleID: "com.microsoft.VSCode"))
        XCTAssertNil(TerminalJump.appleScript(for: ide))
        XCTAssertEqual(ide.bundleID, "com.microsoft.VSCode")
        let viaAncestors = JumpTarget(terminal: TerminalContext(), ancestors: [
            ProcessNode(pid: 1, path: "/bin/zsh"),
            ProcessNode(pid: 2, path: "/Applications/Ghostty.app/Contents/MacOS/ghostty", bundleID: "com.mitchellh.ghostty"),
        ])
        XCTAssertEqual(viaAncestors.bundleID, "com.mitchellh.ghostty")
        XCTAssertEqual(JumpTarget(terminal: TerminalContext(), ancestors: [ProcessNode(pid: 2, path: "/x", bundleID: "com.apple.Terminal")]).app, .appleTerminal)
        XCTAssertEqual(TerminalJump.appleScript(for: JumpTarget(terminal: context { $0.termProgram = "Apple_Terminal" })), "tell application \"Terminal\" to activate")
    }
}
