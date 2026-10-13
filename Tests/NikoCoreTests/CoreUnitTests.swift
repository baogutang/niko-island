import XCTest
@testable import NikoCore

final class FramingTests: XCTestCase {
    func testSplitsLinesAcrossChunks() {
        var framer = LineFramer(maxLineBytes: 16)
        XCTAssertEqual(framer.feed(Data("ab".utf8)), [])
        XCTAssertEqual(framer.feed(Data("c\nde\n\nf".utf8)), [.line(Data("abc".utf8)), .line(Data("de".utf8)), .line(Data())])
        XCTAssertEqual(framer.feed(Data("\n".utf8)), [.line(Data("f".utf8))])
        XCTAssertEqual(framer.bufferedByteCount, 0)
    }

    func testOversizeReportedOnceAndBytesDiscarded() {
        var framer = LineFramer(maxLineBytes: 4)
        XCTAssertEqual(framer.feed(Data("12345".utf8)), [.oversize])
        XCTAssertEqual(framer.feed(Data("6789".utf8)), [])
        XCTAssertEqual(framer.bufferedByteCount, 0, "discarded bytes are not retained")
        XCTAssertEqual(framer.feed(Data("0\nok\n".utf8)), [.line(Data("ok".utf8))])
        XCTAssertEqual(framer.feed(Data("1234\n".utf8)), [.line(Data("1234".utf8))], "exactly max is allowed")
        XCTAssertEqual(framer.feed(Data("12345\nx\n".utf8)), [.oversize, .line(Data("x".utf8))])
    }

    func testRingBufferWrapsOldestFirst() {
        var ring = RingBuffer<Int>(capacity: 3)
        XCTAssertEqual(ring.elements, [])
        (1...2).forEach { ring.append($0) }
        XCTAssertEqual(ring.elements, [1, 2])
        (3...7).forEach { ring.append($0) }
        XCTAssertEqual(ring.elements, [5, 6, 7])
        XCTAssertEqual(ring.count, 3)
    }
}

final class EventTests: XCTestCase {
    func testParsesCanonicalEventAndBridgeMeta() throws {
        let json = try JSONValue.parse("""
        {"source":"Claude","hook_event_name":"PreToolUse","session_id":"u-1","transcript_path":"/t.jsonl",
         "cwd":"/w","tool_name":"Edit","tool_input":{"file_path":"/w/src/main.swift"},"ts":1760000000123,
         "_niko":{"term_program":"iTerm.app","iterm_session_id":"w0t1p0:ABC","tty":"ttys004","tmux_pane":"%3","pid":4242,
                  "ancestors":["/bin/zsh","/Applications/iTerm.app/Contents/MacOS/iTerm2"]}}
        """)
        let event = try AgentEvent(json: json)
        XCTAssertEqual(event.source, "claude")
        XCTAssertEqual(event.key.description, "claude/u-1")
        XCTAssertEqual(event.transcriptPath, "/t.jsonl")
        XCTAssertEqual(event.timestampMS, 1_760_000_000_123)
        XCTAssertEqual(event.terminal.itermSessionID, "w0t1p0:ABC")
        XCTAssertEqual(event.terminal.tty, "ttys004")
        XCTAssertEqual(event.terminal.pid, 4242)
        XCTAssertEqual(event.terminal.ancestors.count, 2)
        XCTAssertFalse(event.isBlocking)
        XCTAssertEqual(TerminalContext(json: event.terminal.json), event.terminal)
    }

    func testBlockingDetectionAndFallbacks() throws {
        XCTAssertTrue(try AgentEvent(json: .object(["hook_event_name": .string("PermissionRequest")])).isBlocking)
        XCTAssertTrue(try AgentEvent(json: .object(["hook_event_name": .string("Notification"), "_blocking": .bool(true)])).isBlocking)
        let bare = try AgentEvent(json: .object(["event": .string("Notification")]), defaultSource: "My Agent!", fallbackCwd: "/proj")
        XCTAssertEqual(bare.source, "myagent")
        XCTAssertEqual(bare.sessionID, "cwd:/proj")
        XCTAssertThrowsError(try AgentEvent(json: .array([])))
        XCTAssertThrowsError(try AgentEvent(json: .object(["session_id": .string("x")])))
    }

    func testNativeEventNamesAreTranslated() throws {
        func event(_ source: String, _ json: String) throws -> AgentEvent {
            try AgentEvent(json: JSONValue.parse(json), defaultSource: source)
        }
        // Cursor
        let table: [(String, String)] = [
            ("sessionStart", HookEvent.sessionStart), ("sessionEnd", HookEvent.sessionEnd),
            ("beforeSubmitPrompt", HookEvent.userPromptSubmit), ("afterAgentThought", HookEvent.postToolUse),
            ("afterShellExecution", HookEvent.postToolUse), ("afterFileEdit", HookEvent.postToolUse),
            ("postToolUseFailure", HookEvent.postToolUse), ("subagentStop", HookEvent.subagentStop),
            ("preCompact", HookEvent.preCompact), ("stop", HookEvent.stop),
        ]
        for (native, canonical) in table {
            let parsed = try event("cursor", #"{"hook_event_name":"\#(native)","conversation_id":"c1"}"#)
            XCTAssertEqual(parsed.name, canonical, native)
            XCTAssertEqual(parsed.raw["native_event"]?.stringValue, native)
            XCTAssertEqual(parsed.sessionID, "c1")
        }
        XCTAssertEqual(try event("cursor", #"{"hook_event_name":"stop","status":"error","conversation_id":"c1"}"#).name, HookEvent.stopFailure)
        let shell = try event("cursor", #"{"hook_event_name":"beforeShellExecution","conversation_id":"c1","command":"make","cwd":"/w"}"#)
        XCTAssertEqual(shell.name, HookEvent.preToolUse)
        XCTAssertEqual(shell.toolName, "Bash")
        XCTAssertEqual(shell.toolInput?["command"]?.stringValue, "make")
        XCTAssertEqual(try event("cursor", #"{"hook_event_name":"somethingNew","conversation_id":"c1"}"#).name, "somethingNew", "unknown events pass through")

        // Windsurf
        XCTAssertEqual(try event("windsurf", #"{"agent_action_name":"post_cascade_response","trajectory_id":"t"}"#).name, HookEvent.stop)
        let write = try event("windsurf", #"{"agent_action_name":"pre_write_code","trajectory_id":"t","tool_info":{"file_path":"/w/a.ts"}}"#)
        XCTAssertEqual(Activity.forTool(write.toolName, input: write.toolInput), Activity(verb: "editing", detail: "a.ts"))
        let asked = try event("windsurf", #"{"agent_action_name":"pre_user_prompt","trajectory_id":"t","tool_info":{"user_prompt":"Rename it"}}"#)
        XCTAssertEqual(asked.name, HookEvent.userPromptSubmit)
        XCTAssertEqual(asked.raw["prompt"]?.stringValue, "Rename it")
        XCTAssertThrowsError(try event("windsurf", #"{"trajectory_id":"t"}"#), "no event name at all")

        // Gemini CLI and Codex
        XCTAssertEqual(try event("gemini", #"{"hook_event_name":"AfterAgent","session_id":"g"}"#).name, HookEvent.stop)
        XCTAssertEqual(try event("gemini", #"{"hook_event_name":"BeforeAgent","session_id":"g","prompt":"hi"}"#).name, HookEvent.userPromptSubmit)
        XCTAssertEqual(try event("gemini", #"{"hook_event_name":"Notification","session_id":"g"}"#).name, HookEvent.notification)
        XCTAssertEqual(try event("codex", #"{"hook_event_name":"Interrupt","session_id":"x"}"#).name, HookEvent.stop)
        // Claude's own names are never rewritten, whatever the source.
        XCTAssertEqual(try event("claude", #"{"hook_event_name":"stop","session_id":"x"}"#).name, "stop")
    }

    func testAdapterIdComesFromTheEnvelopeNotTheAgentsPayload() throws {
        let enveloped = try AgentEvent(json: JSONValue.parse(#"{"hook_event_name":"SessionStart","session_id":"s","source":"resume","_niko":{"source":"codex"}}"#))
        XCTAssertEqual(enveloped.source, "codex")
        // In-process plugins have no envelope: the header value, then their own field.
        XCTAssertEqual(try AgentEvent(json: JSONValue.parse(#"{"hook_event_name":"Stop","session_id":"s","source":"opencode"}"#)).source, "opencode")
        XCTAssertEqual(try AgentEvent(json: JSONValue.parse(#"{"hook_event_name":"Stop","session_id":"s","source":"startup"}"#),
                                      defaultSource: "mimocode").source, "mimocode")
    }

    func testActivityMappingMatchesProtocolTable() {
        let table: [(String?, String)] = [
            ("Bash", "running"), ("Read", "reading"), ("Write", "editing"), ("Edit", "editing"),
            ("Grep", "finding"), ("Glob", "finding"), ("WebFetch", "fetching"), ("Task", "delegating"),
            ("SomethingElse", "working"), (nil, "working"),
        ]
        for (tool, verb) in table { XCTAssertEqual(Activity.verb(forTool: tool), verb, tool ?? "nil") }
        XCTAssertEqual(Activity.waiting.verb, "waiting for you")
    }

    func testActivityDetailIsShortAndSingleLine() {
        let bash = Activity.forTool("Bash", input: JSONObject(["command": .string("  make test\nrm -rf build  ")]))
        XCTAssertEqual(bash, Activity(verb: "running", detail: "make test"))
        let edit = Activity.forTool("Edit", input: JSONObject(["file_path": .string("/a/b/c/Main.swift")]))
        XCTAssertEqual(edit.detail, "Main.swift")
        let fetch = Activity.forTool("WebFetch", input: JSONObject(["url": .string("https://example.com/x?y=1")]))
        XCTAssertEqual(fetch.detail, "example.com")
        let long = Activity.forTool("Bash", input: JSONObject(["command": .string(String(repeating: "x", count: 500))]))
        XCTAssertEqual(long.detail?.count, 96)
    }
}

final class AdmissionTests: XCTestCase {
    private let me = getuid()

    private func evidence(uid: uid_t?, ancestors: [ProcessNode] = [], cwd: String? = nil,
                          channel: AdmissionEvidence.Channel = .unixSocket) -> AdmissionEvidence {
        AdmissionEvidence(channel: channel, peerUID: uid, peerPID: nil, cwd: cwd, ancestors: ancestors)
    }

    func testCrossUIDIsAlwaysRejected() {
        let policy = AdmissionPolicy(appUID: me, requireDeveloperEvidence: false)
        XCTAssertEqual(policy.evaluate(evidence(uid: me)), .admit)
        XCTAssertFalse(policy.evaluate(evidence(uid: me &+ 1)).isAdmitted)
        XCTAssertFalse(policy.evaluate(evidence(uid: 0)).isAdmitted, "root is not us either")
        XCTAssertFalse(policy.evaluate(evidence(uid: nil)).isAdmitted, "no credentials, no entry")
    }

    func testDeveloperEvidenceFromAncestorsOrProjectDirectory() throws {
        let policy = AdmissionPolicy(appUID: me)
        let shell = ProcessNode(pid: 10, path: "/bin/zsh")
        let iterm = ProcessNode(pid: 9, path: "/Applications/iTerm.app/Contents/MacOS/iTerm2", bundleID: "com.googlecode.iterm2")
        let random = ProcessNode(pid: 8, path: "/Applications/Calculator.app/Contents/MacOS/Calculator", bundleID: "com.apple.calculator")
        XCTAssertEqual(policy.evaluate(evidence(uid: me, ancestors: [random, shell])), .admit)
        XCTAssertEqual(policy.evaluate(evidence(uid: me, ancestors: [iterm])), .admit)
        XCTAssertEqual(policy.evaluate(evidence(uid: me, ancestors: [ProcessNode(pid: 1, path: "/opt/homebrew/bin/python3.12")])), .admit)
        XCTAssertEqual(policy.evaluate(evidence(uid: me, ancestors: [ProcessNode(pid: 1, path: "/bin/-zsh")])), .admit)
        XCTAssertFalse(policy.evaluate(evidence(uid: me, ancestors: [random])).isAdmitted)
        XCTAssertFalse(policy.evaluate(evidence(uid: me, cwd: "/definitely/not/here")).isAdmitted)

        let scratch = Scratch()
        scratch.write("repo/.git/HEAD", "ref: refs/heads/main\n")
        scratch.write("repo/src/deep/file.txt", "x")
        scratch.write("plain/file.txt", "x")
        XCTAssertEqual(policy.evaluate(evidence(uid: me, cwd: scratch.file("repo/src/deep").path)), .admit)
        XCTAssertFalse(policy.evaluate(evidence(uid: me, cwd: scratch.file("plain").path)).isAdmitted)
        XCTAssertFalse(policy.evaluate(evidence(uid: me, cwd: "relative/path")).isAdmitted)
    }

    func testDenyListedBundleWinsOverEverything() {
        let policy = AdmissionPolicy(appUID: me, deniedBundleIDs: ["com.googlecode.iterm2"], requireDeveloperEvidence: false)
        let iterm = ProcessNode(pid: 9, path: "/Applications/iTerm.app/Contents/MacOS/iTerm2", bundleID: "com.googlecode.iterm2")
        let decision = policy.evaluate(evidence(uid: me, ancestors: [ProcessNode(pid: 10, path: "/bin/zsh"), iterm]))
        XCTAssertEqual(decision, .deny("bundle com.googlecode.iterm2 is deny-listed"))
    }

    func testHTTPChannelDoesNotNeedPeerCredentials() {
        let policy = AdmissionPolicy(appUID: me)
        XCTAssertEqual(policy.evaluate(evidence(uid: nil, ancestors: [ProcessNode(pid: 1, path: "/usr/local/bin/node")], channel: .http)), .admit)
        XCTAssertFalse(policy.evaluate(evidence(uid: nil, channel: .http)).isAdmitted)
    }

    func testProcessInspectorSeesOurOwnLineage() {
        let chain = ProcessInspector.ancestors(of: getpid())
        XCTAssertEqual(chain.first?.pid, getpid())
        XCTAssertGreaterThan(chain.count, 1)
        XCTAssertEqual(ProcessInspector.parent(of: getpid()), getppid())
        XCTAssertNil(ProcessInspector.path(of: -5))
        XCTAssertEqual(BundleIDCache.enclosingApp("/Applications/A.app/Contents/Frameworks/B.app/Contents/MacOS/B"), "/Applications/A.app")
        XCTAssertNil(BundleIDCache.enclosingApp("/bin/zsh"))
    }
}

final class RedactorTests: XCTestCase {
    func testScrubsCredentialShapes() {
        let secrets = [
            "sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789",
            "sk-proj-abcdefghijklmnopqrstuvwxyz012345",
            "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
            "github_pat_11ABCDEFG0abcdefghijkl_mnopqrstuvwxyz",
            "xoxb-123456789012-abcdefghijkl",
            "AKIAIOSFODNN7EXAMPLE",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
            "ABCD-EFGH-IJKL-MNOP",
            "4f3c2b1a4f3c2b1a4f3c2b1a4f3c2b1a4f3c2b1a4f3c2b1a",
        ]
        for secret in secrets {
            let line = "context before \(secret) and after"
            let redacted = Redactor.redact(line, home: "/Users/nobody")
            XCTAssertFalse(redacted.contains(secret), "leaked: \(secret) → \(redacted)")
            XCTAssertTrue(redacted.contains("context before"))
        }
    }

    func testScrubsKeyValueAndHeaderForms() {
        let cases: [(String, String)] = [
            ("Authorization: Bearer abc.def-123", "abc.def-123"),
            ("authorization=Basic dXNlcjpwYXNz", "dXNlcjpwYXNz"),
            ("ANTHROPIC_API_KEY=hunter2hunter2", "hunter2hunter2"),
            ("{\"apiKey\": \"s3cr3t-value\", \"model\": \"x\"}", "s3cr3t-value"),
            ("password: 'correct horse'", "correct horse"),
            ("curl -H 'Cookie: session=abcdef'", "abcdef"),
            ("license_key=QWERTY12345", "QWERTY12345"),
            ("bearer abcdefgh12345678", "abcdefgh12345678"),
        ]
        for (line, secret) in cases {
            let redacted = Redactor.redact(line, home: "/Users/nobody")
            XCTAssertFalse(redacted.contains(secret), "leaked \(secret): \(redacted)")
            XCTAssertTrue(redacted.contains(Redactor.placeholder))
        }
        XCTAssertTrue(Redactor.redact("{\"apiKey\": \"s3cr3t\", \"model\": \"opus\"}", home: "/x/y").contains("\"model\": \"opus\""))
    }

    func testKeepsOrdinaryDiagnosticsReadableAndHidesHome() {
        let line = "ingress: session claude/6f1c2a9e-3b7d-4c1e-9a55-0d2e8b7f1a23 admitted from /Users/alice/dev/app (PreToolUse, 42 events)"
        let redacted = Redactor.redact(line, home: "/Users/alice")
        XCTAssertEqual(redacted, "ingress: session claude/6f1c2a9e-3b7d-4c1e-9a55-0d2e8b7f1a23 admitted from ~/dev/app (PreToolUse, 42 events)")
    }

    func testLoggerRedactsBeforeWritingAndRotates() throws {
        let scratch = Scratch()
        let url = scratch.file("log/app.log")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let log = NikoLog()
        log.configure(fileURL: url, maxBytes: 400, keep: 2)
        for index in 0..<40 { log.info("line \(index) token=sk-ant-api03-SECRETSECRETSECRET") }
        let current = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(current.contains("SECRETSECRET"))
        XCTAssertTrue(current.contains("token=\(Redactor.placeholder)"))
        XCTAssertEqual(mode(of: url), 0o600)
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).sorted()
        XCTAssertEqual(files, ["app.log", "app.log.1", "app.log.2"])
    }
}

final class SecureDirectoryTests: XCTestCase {
    func testCreatesPrivateTree() throws {
        let scratch = Scratch()
        try SecureDirectory.ensureTree(scratch.paths)
        for dir in scratch.paths.allDirectories { XCTAssertEqual(mode(of: dir), 0o700, dir.path) }
        XCTAssertNoThrow(try SecureDirectory.validate(scratch.paths.run))
    }

    func testRejectsFileInPlaceOfDirectory() throws {
        let scratch = Scratch()
        scratch.write("ni", "i am a file")
        XCTAssertThrowsError(try SecureDirectory.ensure(scratch.paths.root)) { error in
            XCTAssertEqual(error as? SecureDirectoryError, .notDirectory(scratch.paths.root.path))
        }
    }

    func testRejectsDirectoriesOwnedBySomeoneElse() {
        // /usr is a real directory, not a symlink, and owned by root.
        XCTAssertThrowsError(try SecureDirectory.validate(URL(fileURLWithPath: "/usr"))) { error in
            XCTAssertEqual(error as? SecureDirectoryError, .wrongOwner("/usr", 0))
        }
        XCTAssertThrowsError(try SecureDirectory.ensure(URL(fileURLWithPath: "/usr"))) { error in
            XCTAssertEqual(error as? SecureDirectoryError, .wrongOwner("/usr", 0), "and it is never chmod-ed into shape")
        }
        let foreign = NikoPaths(root: URL(fileURLWithPath: "/usr"))
        XCTAssertThrowsError(try UnixIngressServer(paths: foreign, hub: IngressHub(log: .inMemory())).start())
    }

    func testQuarantineDetection() throws {
        let scratch = Scratch()
        let file = scratch.write("Fake.app/Contents/Helpers/niko-bridge", "#!/bin/sh\n")
        XCTAssertFalse(Diagnostics.isQuarantined(file.path))
        let flag = "0083;6532b1f0;Safari;"
        XCTAssertEqual(setxattr(file.path, "com.apple.quarantine", flag, flag.utf8.count, 0, 0), 0)
        XCTAssertTrue(Diagnostics.isQuarantined(file.path))
        XCTAssertEqual(removexattr(file.path, "com.apple.quarantine", 0), 0)
        XCTAssertFalse(Diagnostics.isQuarantined(file.path))
        XCTAssertFalse(Diagnostics.isQuarantined("/no/such/file"))
        XCTAssertEqual(Diagnostics.quarantineFix(for: "/Applications/Niko Island.app/Contents/Helpers/niko-bridge"),
                       "xattr -cr '/Applications/Niko Island.app'")
        XCTAssertEqual(Diagnostics.quarantineFix(for: "/tmp/build/niko-bridge"), "xattr -cr '/tmp/build/niko-bridge'")
    }

    func testPathHelpers() {
        XCTAssertEqual(NikoPaths.normalize("/private/tmp//a/./b/../c/"), "/private/tmp/a/c")
        let custom = NikoPaths(root: URL(fileURLWithPath: "/private/tmp/it's here/ni"))
        XCTAssertEqual(custom.shellPath(custom.bridgeShim), "'/private/tmp/it'\\''s here/ni/bin/niko-bridge'")
        let standard = NikoPaths(root: URL(fileURLWithPath: "/Users/x/.niko-island"), isDefaultLocation: true)
        XCTAssertEqual(standard.shellPath(standard.bridgeShim), "\"$HOME/.niko-island/bin/niko-bridge\"")
        let resolved = NikoPaths.resolve(environment: ["NIKO_ISLAND_HOME": "/tmp/nk-resolve-test"])
        XCTAssertEqual(resolved.root.path, "/private/tmp/nk-resolve-test")
        XCTAssertFalse(resolved.isDefaultLocation)
        XCTAssertTrue(NikoPaths.resolve(environment: [:]).isDefaultLocation)
    }
}
