import XCTest
@testable import NikoCore

final class BridgeBinaryTests: XCTestCase {
    private let permission = "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"s1\",\"cwd\":\"/tmp\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf build\"}}"

    func testBinaryExists() {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: bridgeBinaryPath), bridgeBinaryPath)
    }

    func testForwardsEventWithTimestampAndTerminalContext() throws {
        let island = try TestIsland()
        let before = Date().timeIntervalSince1970 * 1000
        let output = island.bridge(stdin: "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"cwd\":\"/tmp\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/tmp/a.txt\"}}",
                                   environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t2p0:GUID-1", "TMUX_PANE": "%7"])
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "")
        XCTAssertEqual(output.stderr, "")
        let event = try XCTUnwrap(island.collector.wait(count: 1).first?.event)
        XCTAssertEqual(event.source, "claude")
        XCTAssertEqual(event.name, "PreToolUse")
        XCTAssertGreaterThanOrEqual(event.timestampMS, before - 1)
        XCTAssertEqual(event.terminal.termProgram, "iTerm.app")
        XCTAssertEqual(event.terminal.itermSessionID, "w0t2p0:GUID-1")
        XCTAssertEqual(event.terminal.tmuxPane, "%7")
        XCTAssertEqual(event.terminal.pid, getpid(), "bridge reports its parent: the hook runner")
        XCTAssertFalse(event.terminal.ancestors.isEmpty)
    }

    func testStripsToolResponsesAndCapsLongStrings() throws {
        let island = try TestIsland()
        let big = String(repeating: "x", count: 50_000)
        let payload = JSONValue.object([
            "hook_event_name": .string("PostToolUse"), "session_id": .string("s1"), "cwd": .string("/tmp"),
            "tool_name": .string("Read"), "tool_input": .object(["file_path": .string("/tmp/a"), "content": .string(big)]),
            "tool_response": .object(["file": .object(["content": .string(big)])]),
            "prompt": .string(big),
        ]).serialized()
        XCTAssertEqual(island.bridge(stdin: payload).status, 0)
        let event = try XCTUnwrap(island.collector.wait(count: 1).first?.event)
        XCTAssertNil(event.raw["tool_response"], "tool output never leaves the agent")
        XCTAssertLessThan(event.toolInput?["content"]?.stringValue?.count ?? .max, 5000)
        XCTAssertEqual(event.raw["prompt"]?.stringValue?.count, 512)
    }

    func testSilentSuccessWhenAppIsNotRunning() {
        let scratch = Scratch()
        let output = runProcess(bridgeBinaryPath, ["--source", "claude"], stdin: Data(permission.utf8),
                                environment: ["NIKO_ISLAND_HOME": scratch.paths.root.path])
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout + output.stderr, "")
        XCTAssertLessThan(output.duration, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.root.path), "the bridge never creates our runtime dir")
    }

    func testGarbageInputIsSilentSuccess() throws {
        let island = try TestIsland()
        for stdin in ["", "not json", "[1,2,3]", "{\"no_event\":true}", "{\"hook_event_name\":42}", String(repeating: "[", count: 100_000)] {
            let output = island.bridge(stdin: stdin)
            XCTAssertEqual(output.status, 0, stdin.prefix(20).description)
            XCTAssertEqual(output.stdout + output.stderr, "")
        }
        XCTAssertTrue(island.collector.all.isEmpty)
    }

    func testApproveProducesClaudeAllowJSON() throws {
        let island = try TestIsland { _ in decisionReply("approve", reason: "user allowed") }
        let output = island.bridge(stdin: permission)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}\n")
        XCTAssertEqual(output.stderr, "")
        let event = try XCTUnwrap(island.collector.all.first?.event)
        XCTAssertEqual(event.toolInput?["command"]?.stringValue, "rm -rf build")
    }

    func testBehaviorIsCaseInsensitive() throws {
        let island = try TestIsland { _ in decisionReply("APPROVE") }
        XCTAssertTrue(island.bridge(stdin: permission).stdout.contains("\"behavior\":\"allow\""))
    }

    func testDenyAndBlockProduceClaudeDenyJSON() throws {
        let deny = try TestIsland { _ in decisionReply("deny", reason: "not on main") }
        XCTAssertEqual(deny.bridge(stdin: permission).stdout,
                       "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"deny\",\"message\":\"not on main\"}}}\n")
        let block = try TestIsland { _ in decisionReply("Block") }
        let output = block.bridge(stdin: permission)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout,
                       "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"deny\",\"message\":\"Denied in Niko Island\",\"interrupt\":true}}}\n")
    }

    func testQuestionAnswersAreTranslatedForClaude() throws {
        let question = """
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp","tool_name":"AskUserQuestion",
         "tool_input":{"questions":[{"question":"Which database?","header":"DB","options":[{"label":"Postgres"},{"label":"SQLite"}],"multiSelect":false},
                                    {"question":"Which features?","header":"Feat","options":[{"label":"Auth"},{"label":"Billing"},{"label":"Search"}],"multiSelect":true}]}}
        """
        let island = try TestIsland { event in
            var input = event.toolInput ?? JSONObject()
            input["answers"] = .array([.array([.string("SQLite")]), .array([.string("Auth"), .string("Search")])])
            return decisionReply("approve", updatedInput: input)
        }
        let output = island.bridge(stdin: question)
        let json = try JSONValue.parse(output.stdout)
        let updated = try XCTUnwrap(json.at("hookSpecificOutput", "decision", "updatedInput"))
        XCTAssertEqual(json.at("hookSpecificOutput", "decision", "behavior")?.stringValue, "allow")
        XCTAssertEqual(updated["answers"]?["Which database?"]?.stringValue, "SQLite")
        XCTAssertEqual(updated["answers"]?["Which features?"]?.stringValue, "Auth, Search")
        XCTAssertEqual(updated["questions"]?.arrayValue?.count, 2, "original questions are passed back untouched")
    }

    func testNoDecisionMeansNoOutput() throws {
        for reply: JSONValue in [.object(["ok": .bool(true), "reply": .null]), .object(["ok": .bool(false)]),
                                 .object(["ok": .bool(true), "reply": .object(["decision": .object(["behavior": .string("maybe")])])]),
                                 .string("nonsense")] {
            let island = try TestIsland { _ in reply }
            let output = island.bridge(stdin: permission)
            XCTAssertEqual(output.status, 0)
            XCTAssertEqual(output.stdout + output.stderr, "", "\(reply)")
        }
    }

    func testAppQuitWhilePendingReleasesTheAgent() throws {
        let island = try TestIsland()
        let server = island.server
        let collector = island.collector
        DispatchQueue.global().async {
            collector.wait(count: 1)
            usleep(150_000)
            server.stop()
        }
        let output = island.bridge(stdin: permission)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout + output.stderr, "")
        XCTAssertLessThan(output.duration, 5)
    }

    func testReplyTimeoutReleasesTheAgent() throws {
        let island = try TestIsland()
        let output = island.bridge(stdin: permission, environment: ["NIKO_BRIDGE_REPLY_TIMEOUT": "0.4"])
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout + output.stderr, "")
        XCTAssertLessThan(output.duration, 5)
        XCTAssertTrue(waitUntil { island.collector.all.first?.replier?.isOpen == false }, "app learns the request is gone")
    }

    func testTerminatedWhilePendingExitsZero() throws {
        let island = try TestIsland()
        let collector = island.collector
        let output = island.bridge(stdin: permission) { process in
            DispatchQueue.global().async {
                collector.wait(count: 1)
                kill(process.processIdentifier, SIGTERM)
            }
        }
        XCTAssertEqual(output.status, 0, "SIGTERM from the agent must not look like a hook failure")
        XCTAssertEqual(output.stdout, "")
    }

    func testFaultInjectionAlwaysExitsZero() throws {
        let island = try TestIsland { _ in decisionReply("approve") }
        for fault in ["crash", "abort", "segv"] {
            let output = island.bridge(stdin: permission, environment: ["NIKO_BRIDGE_FAULT": fault])
            XCTAssertEqual(output.status, 0, fault)
            XCTAssertEqual(output.stdout, "", fault)
        }
        let hang = island.bridge(stdin: permission, environment: ["NIKO_BRIDGE_FAULT": "hang", "NIKO_BRIDGE_WATCHDOG": "1"])
        XCTAssertEqual(hang.status, 0, "watchdog turns a hang into success")
        XCTAssertLessThan(hang.duration, 4)
    }

    func testWedgedAppDoesNotStallTheAgent() throws {
        // A listening socket that never accepts or reads: connect succeeds, nothing answers.
        let scratch = Scratch()
        try SecureDirectory.ensureTree(scratch.paths)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = try XCTUnwrap(SocketIO.makeUnixAddress(scratch.paths.socket.path))
        XCTAssertEqual(withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }, 0)
        XCTAssertEqual(listen(fd, 8), 0)
        let env = ["NIKO_ISLAND_HOME": scratch.paths.root.path]
        let event = runProcess(bridgeBinaryPath, ["--source", "claude"], stdin: Data("{\"hook_event_name\":\"Stop\",\"session_id\":\"s\"}".utf8), environment: env)
        XCTAssertEqual(event.status, 0)
        XCTAssertLessThan(event.duration, 2, "fire-and-forget events give up after the ack timeout")
        let pending = runProcess(bridgeBinaryPath, ["--source", "claude"], stdin: Data(permission.utf8),
                                 environment: env.merging(["NIKO_BRIDGE_REPLY_TIMEOUT": "0.5"]) { $1 })
        XCTAssertEqual(pending.status, 0)
        XCTAssertEqual(pending.stdout, "")
    }

    func testExitCodeReplyModeForAgentsWithoutJSONDecisions() throws {
        let deny = try TestIsland { _ in decisionReply("deny", reason: "nope") }
        let denied = deny.bridge(["--source", "generic", "--reply", "exit-code"], stdin: permission)
        XCTAssertEqual(denied.status, 2)
        XCTAssertEqual(denied.stderr, "nope\n")
        XCTAssertEqual(denied.stdout, "")
        let allow = try TestIsland { _ in decisionReply("approve") }
        let allowed = allow.bridge(["--source", "generic", "--reply", "exit-code"], stdin: permission)
        XCTAssertEqual(allowed.status, 0)
        XCTAssertEqual(allowed.stdout + allowed.stderr, "")
    }

    func testAdapterMarkedBlockingPreToolUseUsesPreToolUseDialect() throws {
        let island = try TestIsland { event in
            XCTAssertTrue(event.isBlocking)
            return decisionReply("deny", reason: "blocked by reviewer")
        }
        let output = island.bridge(["--source", "codex", "--blocking"],
                                   stdin: "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"cwd\":\"/tmp\",\"tool_name\":\"shell\",\"tool_input\":{\"command\":\"ls\"}}")
        XCTAssertEqual(output.stdout, "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"blocked by reviewer\"}}\n")
        XCTAssertEqual(island.collector.all.first?.event.source, "codex")
    }

    func testBlockingEventWithUnknownNameFallsBackToExitCodeTwoOnDeny() throws {
        let island = try TestIsland { _ in decisionReply("deny", reason: "no") }
        let output = island.bridge(["--source", "x", "--blocking"], stdin: "{\"hook_event_name\":\"Notification\",\"session_id\":\"s1\",\"cwd\":\"/tmp\"}")
        XCTAssertEqual(output.status, 2)
        XCTAssertEqual(output.stderr, "no\n")
    }

    func testOversizePayloadIsCutDownNotDropped() throws {
        let island = try TestIsland()
        let huge = String(repeating: "y", count: 3 << 20)
        let payload = "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"s1\",\"cwd\":\"/tmp\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/big.txt\",\"content\":\"\(huge)\"}}"
        let collector = island.collector
        let output = island.bridge(stdin: payload, environment: ["NIKO_BRIDGE_REPLY_TIMEOUT": "1"])
        XCTAssertEqual(output.status, 0)
        let event = try XCTUnwrap(collector.wait(count: 1).first?.event)
        XCTAssertEqual(event.raw["_niko"]?["truncated"]?.boolValue, true)
        XCTAssertEqual(event.toolInput?["file_path"]?.stringValue, "/tmp/big.txt")
        XCTAssertEqual(island.hub.counters.oversize, 0)
    }

    func testStatuslineTaskCachesRateLimits() throws {
        let scratch = Scratch()
        let cache = scratch.paths.rateLimitCache.path
        let payload = "{\"model\":{\"id\":\"claude-opus\",\"display_name\":\"Opus\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42.5,\"resets_at\":1760003600},\"seven_day\":{\"used_percentage\":12,\"resets_at\":1760500000}}}"
        let env = ["NIKO_ISLAND_HOME": scratch.paths.root.path]
        let first = runProcess(bridgeBinaryPath, ["--task", "statusline-cache", "--cache-file", cache], stdin: Data(payload.utf8), environment: env)
        XCTAssertEqual(first.status, 0)
        XCTAssertEqual(first.stdout + first.stderr, "")
        let written = try JSONValue.parse(Data(contentsOf: URL(fileURLWithPath: cache)))
        XCTAssertEqual(written.at("rate_limits", "five_hour", "used_percentage")?.doubleValue, 42.5)
        XCTAssertEqual(written["model"]?.stringValue, "Opus")
        XCTAssertNotNil(written["captured_at"]?.doubleValue)
        XCTAssertEqual(mode(of: URL(fileURLWithPath: cache)), 0o600)

        // A payload without rate limits (or junk) must not erase what we have.
        for stdin in ["{\"model\":{\"id\":\"x\"}}", "garbage", ""] {
            XCTAssertEqual(runProcess(bridgeBinaryPath, ["--task", "statusline-cache", "--cache-file", cache], stdin: Data(stdin.utf8), environment: env).status, 0)
        }
        XCTAssertEqual(try JSONValue.parse(Data(contentsOf: URL(fileURLWithPath: cache))), written)
    }

    func testVersionAndIntegrityCheck() throws {
        let version = runProcess(bridgeBinaryPath, ["--version"])
        XCTAssertEqual(version.stdout, "niko-bridge \(NikoVersion.current)\n")
        XCTAssertEqual(version.status, 0)

        let scratch = Scratch()
        let fake = scratch.file("Fake.app")
        try FileManager.default.createDirectory(at: fake.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let check = runProcess(bridgeBinaryPath, ["--integrity-check", fake.path])
        XCTAssertEqual(check.status, 1)
        XCTAssertTrue(check.stdout.contains("fail: Info.plist missing"))
        XCTAssertTrue(check.stdout.contains("fail: Contents/Helpers/niko-bridge missing"))
    }

    func testUnknownTaskAndFlagsAreIgnored() {
        let output = runProcess(bridgeBinaryPath, ["--task", "future-thing", "--frobnicate", "--source"], stdin: Data("{}".utf8))
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout + output.stderr, "")
    }
}

final class BridgeDecisionTests: XCTestCase {
    func testParsesProtocolReplyShapes() throws {
        let canonical = try JSONValue.parse("""
        {"ok":true,"reply":{"hookSpecificOutput":{"hookEventName":"PermissionRequest",
          "decision":{"behavior":"approve","reason":"user allowed","updatedInput":{"a":1}}}}}
        """)
        XCTAssertEqual(BridgeDecision(replyLine: canonical),
                       BridgeDecision(behavior: .allow, reason: "user allowed", updatedInput: JSONObject(["a": .number("1")])))
        XCTAssertEqual(BridgeDecision(replyLine: try JSONValue.parse(#"{"ok":true,"reply":{"decision":{"behavior":"BLOCK"}}}"#)),
                       BridgeDecision(behavior: .deny, interrupt: true))
        XCTAssertEqual(BridgeDecision(replyLine: try JSONValue.parse(#"{"reply":{"behavior":"Deny","message":"m"}}"#)),
                       BridgeDecision(behavior: .deny, reason: "m"))
        XCTAssertNil(BridgeDecision(replyLine: try JSONValue.parse(#"{"ok":false,"reply":{"decision":{"behavior":"approve"}}}"#)))
        XCTAssertNil(BridgeDecision(replyLine: .object(["ok": .bool(true)])))
    }

    func testInvocationParsingIsLenient() {
        let full = BridgeInvocation.parse(["--source", "codex", "--blocking", "--reply", "exit-code", "--task", "statusline-cache", "--cache-file", "/x"])
        XCTAssertEqual(full.source, "codex")
        XCTAssertTrue(full.forceBlocking)
        XCTAssertEqual(full.replyMode, .exitCode)
        XCTAssertEqual(full.task, "statusline-cache")
        XCTAssertEqual(full.cacheFile, "/x")
        XCTAssertEqual(BridgeInvocation.parse(["--source"]).source, "unknown")
        XCTAssertEqual(BridgeInvocation.parse(["--reply", "weird"]).replyMode, .json)
    }
}
