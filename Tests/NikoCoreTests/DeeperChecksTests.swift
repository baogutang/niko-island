import XCTest
@testable import NikoCore

/// What an edit would change, how full a context is, and Claude Code looking
/// up its own plan usage.
final class DeeperChecksTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func jsonl(_ lines: [String]) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    private func request(_ tool: String, _ input: String) throws -> RequestSummary {
        let object = try XCTUnwrap(try JSONValue.parse(Data(input.utf8)).objectValue)
        let event = try AgentEvent(json: .object(["hook_event_name": .string(HookEvent.permissionRequest), "session_id": .string("s1"),
                                                  "tool_name": .string(tool), "tool_input": .object(object)]), defaultSource: "claude")
        return RequestSummary(event: event)
    }

    // MARK: What an edit would change

    func testAnEditRequestShowsWhatGoesAndWhatComes() throws {
        // A whole new file: its first lines, and how many more there are.
        let write = try request("Write", #"{"file_path":"/tmp/p/notes.md","content":"one\ntwo\n\tthree\nfour\nfive\nsix\nseven\neight"}"#)
        XCTAssertEqual(write.kind, .edit(file: "notes.md"))
        XCTAssertEqual(write.detail, "/tmp/p/notes.md")
        XCTAssertEqual(write.changes.prefix(3).map(\.text), ["one", "two", "  three"], "tabs are drawn as spaces")
        XCTAssertTrue(write.changes.dropLast().allSatisfy { $0.kind == .added })
        XCTAssertEqual(write.changes.last, .init(.more, "2"))
        XCTAssertEqual(write.changes.count, RequestSummary.changeLines + 1)

        // One replacement: what is taken out, then what is put in.
        let edit = try request("Edit", #"{"file_path":"/tmp/p/a.swift","old_string":"let retries = 3","new_string":"let retries = 5\nlet backoff = 0.25"}"#)
        XCTAssertEqual(edit.changes, [.init(.removed, "let retries = 3"), .init(.added, "let retries = 5"), .init(.added, "let backoff = 0.25")])
        // Taking something out without putting anything in is still shown.
        XCTAssertEqual(try request("Edit", #"{"file_path":"/a","old_string":"debugPrint(x)","new_string":""}"#).changes, [.init(.removed, "debugPrint(x)")])

        // Several replacements: the first, and how many more.
        let multi = try request("MultiEdit", #"{"file_path":"/a","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d"},{"old_string":"e","new_string":"f"}]}"#)
        XCTAssertEqual(multi.changes, [.init(.removed, "a"), .init(.added, "b"), .init(.more, "2 ✎")])

        // A patch: its plus and minus lines, not its headers.
        let patch = try request("apply_patch", #"{"input":"*** Begin Patch\n*** Update File: a.py\n--- a/a.py\n+++ b/a.py\n@@\n-x = 1\n+x = 2\n context\n*** End Patch"}"#)
        XCTAssertEqual(patch.changes, [.init(.removed, "x = 1"), .init(.added, "x = 2")])

        // A long line is cut, not wrapped across the island.
        let long = try request("Write", #"{"file_path":"/a","content":"\#(String(repeating: "x", count: 500))"}"#)
        XCTAssertEqual(long.changes.first?.text.count, RequestSummary.changeWidth)

        // Nothing to show: nothing shown. And only edits have changes.
        XCTAssertTrue(try request("Edit", #"{"file_path":"/a"}"#).changes.isEmpty)
        XCTAssertTrue(try request("Bash", #"{"command":"echo content","content":"not an edit"}"#).changes.isEmpty)
        XCTAssertTrue(try request("Read", #"{"file_path":"/a","content":"x"}"#).changes.isEmpty)
    }

    // MARK: How full the context is

    func testContextSizeIsReadWhereAnAgentWritesItDown() throws {
        // Claude Code: what the last answer was given to read. No window is written, so no percentage is claimed.
        let usage = try JSONValue.parse(Data(#"{"input_tokens":12,"cache_read_input_tokens":120000,"cache_creation_input_tokens":2488,"output_tokens":900}"#.utf8))
        let claude = try XCTUnwrap(ContextFill.claude(usage: usage))
        XCTAssertEqual(claude, ContextFill(tokens: 122_500))
        XCTAssertNil(claude.fraction)
        XCTAssertEqual(claude.label, "122k")
        XCTAssertFalse(claude.isNearlyFull, "without a known window nothing is called nearly full")
        XCTAssertEqual(ContextFill(tokens: 1_250_000).label, "1.2M")
        XCTAssertNil(ContextFill.claude(usage: try JSONValue.parse(Data("{}".utf8))))
        XCTAssertNil(ContextFill.claude(usage: nil))

        // Codex writes both the size of the last request and the model's window (shape as in a real rollout).
        let info = try JSONValue.parse(Data(#"{"total_token_usage":{"total_tokens":900000},"last_token_usage":{"input_tokens":230000,"cached_input_tokens":200000,"output_tokens":4000,"reasoning_output_tokens":1000,"total_tokens":234000},"model_context_window":258000}"#.utf8))
        let codex = try XCTUnwrap(ContextFill.codex(info: info))
        XCTAssertEqual(codex, ContextFill(tokens: 234_000, window: 258_000))
        XCTAssertEqual(codex.label, "91%")
        XCTAssertTrue(codex.isNearlyFull)
        XCTAssertFalse(ContextFill(tokens: 100_000, window: 258_000).isNearlyFull)
        XCTAssertNil(ContextFill.codex(info: try JSONValue.parse(Data(#"{"model_context_window":258000}"#.utf8))))

        // In the records themselves.
        let prompt = #"{"type":"user","sessionId":"s","cwd":"/tmp/proj","timestamp":"2027-01-15T08:00:00.000Z","message":{"role":"user","content":"Refactor the parser"}}"#
        let answer = #"{"type":"assistant","timestamp":"2027-01-15T08:00:02.000Z","message":{"role":"assistant","model":"claude-opus-5-5","usage":{"input_tokens":10,"cache_read_input_tokens":50000,"cache_creation_input_tokens":990,"output_tokens":5},"content":[{"type":"text","text":"On it."}]}}"#
        let made = #"{"type":"assistant","timestamp":"2027-01-15T08:00:03.000Z","message":{"role":"assistant","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0},"content":[{"type":"text","text":"API error"}]}}"#
        let snapshot = ClaudeTranscript.snapshot(path: "/h/.claude/projects/-tmp-proj/0f0e-session.jsonl", tail: jsonl([prompt, answer, made]), tailIsWholeFile: true,
                                                 firstPrompt: nil, modified: now.addingTimeInterval(-2), now: now)
        XCTAssertEqual(snapshot?.context, ContextFill(tokens: 51_000))

        let path = "/h/.codex/sessions/2027/01/15/rollout-2027-01-15T08-00-00-01a12fbc-aaaa-bbbb-cccc-0123456789ab.jsonl"
        let meta = #"{"timestamp":"2027-01-15T08:00:00.000Z","type":"session_meta","payload":{"id":"01a12fbc-aaaa-bbbb-cccc-0123456789ab","cwd":"/tmp/shot","originator":"Codex Desktop","source":"vscode"}}"#
        let started = #"{"timestamp":"2027-01-15T08:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t"}}"#
        let count = #"{"timestamp":"2027-01-15T08:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":64500},"model_context_window":258000},"rate_limits":{}}}"#
        let done = #"{"timestamp":"2027-01-15T08:00:09.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t","last_agent_message":"Done."}}"#
        let head = CodexTranscript.meta(path: path, head: jsonl([meta, started]))
        let rollout = CodexTranscript.snapshot(path: path, meta: head, tail: jsonl([started, count, done, count]), tailIsWholeFile: true,
                                               modified: now.addingTimeInterval(-2), now: now)
        XCTAssertEqual(rollout?.context?.label, "25%")
        XCTAssertEqual(rollout?.phase, .waiting, "counting tokens after the turn does not restart it")

        // On the session: kept until a newer figure comes.
        var store = SessionStore()
        let key = SessionKey(source: "codex", sessionID: "cx")
        var reading = TranscriptSnapshot(key: key, path: "/h/r.jsonl", cwd: "/tmp/shot", firstPrompt: "x", lastPrompt: "x", phase: .working, activity: .thinking, updatedAt: now)
        reading.context = ContextFill(tokens: 10, window: 100)
        store.merge([reading], live: false, now: now)
        XCTAssertEqual(store[key]?.context, ContextFill(tokens: 10, window: 100))
        reading.context = nil
        store.merge([reading], now: now)
        XCTAssertEqual(store[key]?.context?.tokens, 10)
        XCTAssertFalse(NikoSettings().showsChip(.context), "shown on request, or by itself when nearly full")
    }

    // MARK: What a session has used

    func testWhatASessionHasUsedIsAddedUpFromTheSameRecordsAsTheUsageView() throws {
        let scratch = Scratch()
        let paths = NikoPaths(root: scratch.file("ni"))
        let home = scratch.file("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let pricing = Pricing(rates: ["priced-model": .init(input: 1e-6, output: 2e-6, cacheRead: 0, cacheWrite: 0)], source: "test")
        let engine = UsageEngine(paths: paths, home: home, pricing: pricing) { _ in }
        _ = engine.scanNow()
        engine.stop()
        let store = try UsageStore(path: paths.usageDB.path)
        let t = Date().timeIntervalSince1970
        func record(_ id: String, agent: String, session: String?, model: String, at: Double, input: Int, output: Int) -> UsageRecord {
            UsageRecord(identityKey: id, timestamp: at, agent: agent, model: model, session: session, project: nil, input: input, output: output)
        }
        try store.commit(records: [
            record("1", agent: "claude", session: "s1", model: "priced-model", at: t - 600, input: 1_000_000, output: 100_000),
            record("2", agent: "claude", session: "s1", model: "priced-model", at: t - 60, input: 500_000, output: 0),
            record("3", agent: "codex", session: "s1", model: "unpriced", at: t - 60, input: 2_000_000, output: 500_000),
            record("4", agent: "claude", session: "old", model: "priced-model", at: t - 5 * 86_400, input: 9, output: 9),
            record("5", agent: "claude", session: nil, model: "priced-model", at: t - 60, input: 7, output: 7),
        ], pricing: pricing, file: nil)
        let totals = try store.sessionTotals(since: t - 2 * 86_400)
        store.close()
        XCTAssertEqual(Set(totals.keys), ["claude/s1", "codex/s1"], "the same id under two agents is two sessions; old ones and nameless ones are left out")
        XCTAssertEqual(totals["claude/s1"]?.tokens, 1_600_000)
        XCTAssertEqual(totals["claude/s1"]?.cost ?? 0, 1.7, accuracy: 0.0001)
        XCTAssertEqual(totals["claude/s1"]?.label, "$1.70")
        XCTAssertEqual(totals["codex/s1"]?.label, "2.5M", "no list price: the tokens are the figure")

        var snapshot = UsageSnapshot()
        snapshot.sessions = totals
        XCTAssertEqual(snapshot.use(of: SessionKey(source: "claude", sessionID: "s1"))?.tokens, 1_600_000)
        XCTAssertNil(snapshot.use(of: SessionKey(source: "claude", sessionID: "nobody")))
        XCTAssertEqual(UsageSnapshot.SessionUse(tokens: 800, cost: 0).label, "800")
        XCTAssertEqual(UsageSnapshot.SessionUse(tokens: 42_000, cost: 0.001).label, "42k")
        XCTAssertEqual(UsageSnapshot.SessionUse(tokens: 1, cost: 123.4).label, "$123")
        XCTAssertFalse(NikoSettings().showsChip(.cost), "a price on every row is for those who ask for it")
    }

    // MARK: Claude Code looks for itself

    /// A stand-in `claude`: a script that does what the test tells it to.
    private func fakeClaude(in home: URL, script: String) throws -> URL {
        let bin = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let file = bin.appendingPathComponent("claude")
        try Data(("#!/bin/sh\nHOME_DIR=\"$(cd \"$(dirname \"$0\")/../..\" && pwd)\"\n" + script + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private func cacheFile(fetched: Date) -> String {
        #"{"cachedUsageUtilization":{"fetchedAtMs":\#(Int(fetched.timeIntervalSince1970 * 1000)),"utilization":{"five_hour":{"utilization":40,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":{"utilization":18,"resets_at":"2099-01-03T00:00:00Z"}}}}"#
    }

    func testClaudeCodeIsAskedInItsQuietestFormAndItsOwnFileIsWhatIsRead() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        let paths = NikoPaths(root: scratch.file("ni"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        XCTAssertNil(ClaudeCodeUsage.locate(home: home))
        XCTAssertEqual(ClaudeCodeUsage.ask(home: home, paths: paths), .noClaudeCode)

        // Nothing is saved as a session, the user's settings (hooks, plugins) are not loaded, no MCP server, no browser.
        XCTAssertEqual(ClaudeCodeUsage.arguments, ["-p", "/usage", "--no-session-persistence", "--setting-sources", "project", "--strict-mcp-config", "--no-chrome"])

        // It looks, and keeps an answer: that file is the answer.
        let real = Date()
        let binary = try fakeClaude(in: home, script: """
            pwd > "$HOME_DIR/ran-in.txt"; echo "$@" > "$HOME_DIR/ran-with.txt"
            cat > "$HOME_DIR/.claude.json" <<'JSON'
            \(cacheFile(fetched: real))
            JSON
            """)
        XCTAssertEqual(ClaudeCodeUsage.locate(home: home), binary)
        XCTAssertEqual(ClaudeCodeUsage.ask(home: home, paths: paths), .fresh)
        let ranIn = try String(contentsOf: home.appendingPathComponent("ran-in.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(URL(fileURLWithPath: ranIn).lastPathComponent, "claude-usage", "in an empty folder of our own, not in anybody's project")
        XCTAssertTrue(ranIn.hasSuffix(ClaudeCodeUsage.workingDirectory(paths: paths).lastPathComponent))
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("ran-with.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                       ClaudeCodeUsage.arguments.joined(separator: " "))
        let limits = try XCTUnwrap(ClaudeUsageAPI.cached(home: home))
        XCTAssertEqual(limits.windows.map(\.usedPercent), [40, 18])
        XCTAssertEqual(limits.source, .agentCache)

        // It ran but kept nothing new (not signed in): said as such, and the old answer is not passed off as new.
        try Data(cacheFile(fetched: real.addingTimeInterval(-86_400)).utf8).write(to: home.appendingPathComponent(".claude.json"))
        _ = try fakeClaude(in: home, script: "exit 0")
        XCTAssertEqual(ClaudeCodeUsage.ask(home: home, paths: paths), .unchanged)
        try FileManager.default.removeItem(at: home.appendingPathComponent(".claude.json"))
        XCTAssertEqual(ClaudeCodeUsage.ask(home: home, paths: paths), .unchanged)

        // It failed, or hung: a state, not a crash, and not forever.
        _ = try fakeClaude(in: home, script: "exit 3")
        XCTAssertEqual(ClaudeCodeUsage.ask(home: home, paths: paths), .failed)
        _ = try fakeClaude(in: home, script: "sleep 30")
        let started = Date()
        XCTAssertEqual(ClaudeCodeUsage.ask(home: home, paths: paths, timeout: 0.5), .failed)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)

        // The desktop app's own copy is found when there is no other, newest version first.
        try FileManager.default.removeItem(at: home.appendingPathComponent(".local"))
        for version in ["2.1.9", "2.1.295", "2.1.30"] {
            let folder = home.appendingPathComponent("Library/Application Support/Claude/claude-code/\(version)/abc123/claude.app/Contents/MacOS")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: folder.appendingPathComponent("claude"))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent("claude").path)
        }
        XCTAssertEqual(ClaudeCodeUsage.locate(home: home)?.path.contains("/2.1.295/"), true)

        // This file starts a program; it does not talk to the network or read a sign-in itself.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/NikoCore/Usage/ClaudeCodeUsage.swift"), encoding: .utf8)
        for forbidden in ["URLSession", "SecItem", "Authorization", "accessToken"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        XCTAssertFalse(NikoSettings().claudeAsksItself, "off until switched on")
    }
}
