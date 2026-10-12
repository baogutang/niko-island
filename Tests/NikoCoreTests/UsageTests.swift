import XCTest
@testable import NikoCore

private func claudeLine(id: String, request: String = "req", model: String = "claude-opus-4-5-20251101", input: Int = 10, output: Int,
                        cacheRead: Int = 0, cacheWrite: Int = 0, time: String = "2026-10-12T03:00:00.000Z",
                        session: String = "sess-1", cwd: String = "/work/app") -> String {
    """
    {"parentUuid":"p","cwd":"\(cwd)","sessionId":"\(session)","type":"assistant","message":{"id":"\(id)","role":"assistant","model":"\(model)","content":[{"type":"text","text":"SECRET-TEXT-NEVER-STORED"}],"usage":{"input_tokens":\(input),"cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead),"output_tokens":\(output)}},"requestId":"\(request)","timestamp":"\(time)"}
    """
}

private let userLine = #"{"type":"user","sessionId":"sess-1","message":{"role":"user","content":"please do the thing, usage of words"},"timestamp":"2026-10-12T02:59:00.000Z"}"#

final class UsageEngineTests: XCTestCase {
    var scratch: Scratch!
    var store: UsageStore!
    var tailer: TranscriptTailer!
    let utc = TimeZone(identifier: "UTC")!

    var pricing: Pricing {
        Pricing(rates: [
            "claude-opus-4-5-20251101": .init(input: 5e-6, output: 25e-6, cacheRead: 5e-7, cacheWrite: 6.25e-6),
            "gpt-5-codex": .init(input: 1.25e-6, output: 1e-5, cacheRead: 1.25e-7, cacheWrite: nil),
        ], source: "test")
    }

    override func setUpWithError() throws {
        scratch = Scratch()
        try SecureDirectory.ensureTree(scratch.paths)
        store = try UsageStore(path: scratch.paths.usageDB.path, timeZone: utc)
        tailer = TranscriptTailer(store: store, pricing: pricing)
    }

    override func tearDown() {
        store?.close()
        scratch = nil
    }

    private func append(_ relative: String, _ text: String) {
        let url = scratch.file(relative)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }

    private func week() throws -> [UsageTotals] { try store.totals(fromDay: "2026-10-06", toDay: "2026-10-12") }

    // MARK: Schema

    func testSchemaMatchesTheProtocol() throws {
        let db = try SQLiteDB(path: scratch.paths.usageDB.path)
        func columns(_ table: String) throws -> [String] {
            try db.query("PRAGMA table_info(\(table))").map { "\($0[1].stringValue ?? "") \($0[2].stringValue ?? "")" }
        }
        XCTAssertEqual(try columns("source_files"), [
            "id INTEGER", "path TEXT", "provider TEXT", "file_identity TEXT", "generation INTEGER", "size INTEGER", "mtime REAL",
            "committed_offset INTEGER", "tail_hash TEXT", "parser_version INTEGER", "status TEXT",
        ])
        XCTAssertEqual(try columns("events"), [
            "id INTEGER", "identity_key TEXT", "event_kind TEXT", "ts REAL", "day TEXT", "agent TEXT", "model TEXT", "session TEXT",
            "project TEXT", "input_tokens INTEGER", "output_tokens INTEGER", "cache_read_tokens INTEGER", "cache_write_tokens INTEGER",
            "reasoning_tokens INTEGER", "estimated_cost REAL", "cost_source TEXT",
        ])
        XCTAssertEqual(try db.query("PRAGMA journal_mode").first?.first?.stringValue, "wal")
        XCTAssertEqual(mode(of: scratch.paths.usageDB), 0o600)
    }

    // MARK: Claude

    func testClaudeTranscriptIsCountedOncePerMessage() throws {
        let lines = [
            userLine,
            claudeLine(id: "msg_1", output: 8),                       // streamed: early partial count
            claudeLine(id: "msg_1", output: 120, cacheRead: 5000),    // same message, final numbers
            claudeLine(id: "msg_2", output: 40, cacheWrite: 2000),
            claudeLine(id: "msg_3", model: "<synthetic>", output: 99),
            claudeLine(id: "msg_4", input: 0, output: 0),
            "{ this line is not json \"usage\"",
            "",
        ]
        append("t/a.jsonl", lines.joined(separator: "\n") + "\n")
        XCTAssertEqual(try tailer.sync(path: scratch.file("t/a.jsonl").path, provider: .claude), .read(records: 3, restarted: false))
        let totals = try week()
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].agent, "claude")
        XCTAssertEqual(totals[0].model, "claude-opus-4-5-20251101")
        XCTAssertEqual(totals[0].messages, 2)
        XCTAssertEqual(totals[0].input, 20)
        XCTAssertEqual(totals[0].output, 160)
        XCTAssertEqual(totals[0].cacheRead, 5000)
        XCTAssertEqual(totals[0].cacheWrite, 2000)
        var expected = 20.0 * 5e-6
        expected += 160.0 * 25e-6
        expected += 5000.0 * 5e-7
        expected += 2000.0 * 6.25e-6
        XCTAssertEqual(totals[0].cost, expected, accuracy: 1e-9)

        // Nothing but numbers and identifiers reaches the database.
        store.close()
        var raw = try Data(contentsOf: scratch.paths.usageDB)
        if let wal = try? Data(contentsOf: URL(fileURLWithPath: scratch.paths.usageDB.path + "-wal")) { raw.append(wal) }
        XCTAssertNil(raw.range(of: Data("SECRET-TEXT".utf8)))
        XCTAssertNil(raw.range(of: Data("please do the thing".utf8)))
    }

    func testResumedSessionCopyIsNotCountedTwice() throws {
        let shared = claudeLine(id: "msg_1", output: 100) + "\n"
        append("t/original.jsonl", shared)
        append("t/resumed.jsonl", shared + claudeLine(id: "msg_2", output: 50, session: "sess-2") + "\n")
        try tailer.sync(path: scratch.file("t/original.jsonl").path, provider: .claude)
        try tailer.sync(path: scratch.file("t/resumed.jsonl").path, provider: .claude)
        XCTAssertEqual(try store.eventCount(), 2)
        XCTAssertEqual(try week().first?.output, 150)
    }

    // MARK: Tailing

    func testResumesAtCommittedOffsetAndWaitsForCompleteLines() throws {
        let path = scratch.file("t/a.jsonl").path
        append("t/a.jsonl", claudeLine(id: "m1", output: 10) + "\n")
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .read(records: 1, restarted: false))
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .unchanged)
        let first = try XCTUnwrap(store.latestState(for: path))
        XCTAssertEqual(first.committedOffset, first.size)
        XCTAssertEqual(first.generation, 0)
        XCTAssertEqual(first.status, "active")
        XCTAssertFalse(first.tailHash.isEmpty)

        // The agent is in the middle of writing the next line.
        let next = claudeLine(id: "m2", output: 20)
        let cut = next.index(next.startIndex, offsetBy: 150)
        append("t/a.jsonl", String(next[..<cut]))
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .read(records: 0, restarted: false))
        XCTAssertEqual(try store.latestState(for: path)?.committedOffset, first.committedOffset, "a half line is not committed")
        append("t/a.jsonl", String(next[cut...]) + "\n" + claudeLine(id: "m3", output: 30) + "\n")
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .read(records: 2, restarted: false))
        XCTAssertEqual(try store.eventCount(), 3)
        XCTAssertEqual(try week().first?.output, 60)

        // A fresh tailer (app restart) picks up exactly where the last one stopped.
        let restarted = TranscriptTailer(store: store, pricing: pricing)
        XCTAssertEqual(try restarted.sync(path: path, provider: .claude), .unchanged)
        append("t/a.jsonl", claudeLine(id: "m4", output: 1) + "\n")
        XCTAssertEqual(try restarted.sync(path: path, provider: .claude), .read(records: 1, restarted: false))
        XCTAssertEqual(try store.eventCount(), 4)
    }

    func testTruncatedFileStartsANewGenerationWithoutDuplicates() throws {
        let path = scratch.file("t/a.jsonl").path
        let one = claudeLine(id: "m1", output: 10) + "\n", two = claudeLine(id: "m2", output: 20) + "\n"
        append("t/a.jsonl", one + two)
        try tailer.sync(path: path, provider: .claude)
        // Truncate in place (same inode) and write less than before.
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        handle.truncateFile(atOffset: 0)
        handle.write(Data(one.utf8))
        try handle.close()
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .read(records: 1, restarted: true))
        XCTAssertEqual(try store.latestState(for: path)?.generation, 1)
        XCTAssertEqual(try store.eventCount(), 2, "m1 was seen again but not counted again; m2 stays counted")
        XCTAssertEqual(try week().first?.output, 30)
    }

    func testRotatedFileBumpsGenerationAndDedupes() throws {
        let path = scratch.file("t/a.jsonl").path
        append("t/a.jsonl", claudeLine(id: "m1", output: 10) + "\n" + claudeLine(id: "m2", output: 20) + "\n")
        try tailer.sync(path: path, provider: .claude)
        // Log rotation: a different file appears under the same name, longer than the old one.
        append("t/new.jsonl", claudeLine(id: "m2", output: 20) + "\n" + claudeLine(id: "m3", output: 30) + "\n" + claudeLine(id: "m4", output: 40) + "\n")
        XCTAssertEqual(rename(scratch.file("t/new.jsonl").path, path), 0)
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .read(records: 3, restarted: true))
        let state = try XCTUnwrap(store.latestState(for: path))
        XCTAssertEqual(state.generation, 1)
        XCTAssertEqual(try store.eventCount(), 4)
        XCTAssertEqual(try week().first?.output, 100, "m2 appears in both generations and is counted once")
    }

    func testInPlaceRewriteIsCaughtByTheTailHash() throws {
        let path = scratch.file("t/a.jsonl").path
        let original = claudeLine(id: "m1", output: 10) + "\n"
        append("t/a.jsonl", original)
        try tailer.sync(path: path, provider: .claude)
        // Same inode, longer than before, and the bytes just before the old
        // committed offset are different (here: another timestamp).
        let replacement = claudeLine(id: "m9", output: 10, time: "2026-10-12T04:44:44.444Z") + "\n" + claudeLine(id: "m8", output: 5) + "\n"
        XCTAssertEqual(replacement.utf8.count > original.utf8.count, true)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        handle.write(Data(replacement.utf8))
        try handle.close()
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .read(records: 2, restarted: true))
        XCTAssertEqual(try store.latestState(for: path)?.generation, 1)
        XCTAssertEqual(try store.eventCount(), 3, "m1 stays counted; m9 and m8 are new")
    }

    func testParserVersionChangeRereadsWithoutDoubleCounting() throws {
        let path = scratch.file("t/a.jsonl").path
        append("t/a.jsonl", claudeLine(id: "m1", output: 10) + "\n")
        try tailer.sync(path: path, provider: .claude)
        var state = try XCTUnwrap(store.latestState(for: path))
        state.parserVersion = 0   // as if written by an older build
        try store.commit(records: [], pricing: pricing, file: state)
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .read(records: 1, restarted: true))
        XCTAssertEqual(try store.eventCount(), 1)
    }

    func testMissingFileIsMarkedAndForgotten() throws {
        let path = scratch.file("t/a.jsonl").path
        append("t/a.jsonl", claudeLine(id: "m1", output: 10) + "\n")
        try tailer.sync(path: path, provider: .claude)
        try FileManager.default.removeItem(atPath: path)
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .missing)
        XCTAssertEqual(try store.latestState(for: path)?.status, "missing")
        XCTAssertEqual(try store.eventCount(), 1, "usage that happened stays counted")
        XCTAssertEqual(try tailer.sync(path: scratch.file("never-existed.jsonl").path, provider: .claude), .missing)
    }

    func testVeryLongLinesAndManyLines() throws {
        let path = scratch.file("t/big.jsonl").path
        var text = ""
        for index in 0..<3000 { text += claudeLine(id: "m\(index)", output: 1) + "\n" }
        // A tool result far larger than the read chunk, without the needle: skipped cheaply.
        text += "{\"type\":\"user\",\"blob\":\"" + String(repeating: "x", count: 3 << 20) + "\"}\n"
        text += claudeLine(id: "last", output: 5) + "\n"
        append("t/big.jsonl", text)
        XCTAssertEqual(try tailer.sync(path: path, provider: .claude), .read(records: 3001, restarted: false))
        XCTAssertEqual(try week().first?.output, 3005)
        XCTAssertEqual(try store.latestState(for: path)?.committedOffset, text.utf8.count)
    }

    // MARK: Codex

    private let codexLines = [
        #"{"timestamp":"2026-10-12T05:00:00.000Z","type":"session_meta","payload":{"id":"cx-1","cwd":"/work/svc","cli_version":"0.50.0"}}"#,
        #"{"timestamp":"2026-10-12T05:00:01.000Z","type":"turn_context","payload":{"cwd":"/work/svc","model":"gpt-5-codex"}}"#,
        #"{"timestamp":"2026-10-12T05:00:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":100,"reasoning_output_tokens":40,"total_tokens":1100},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":100,"reasoning_output_tokens":40,"total_tokens":1100}}}}"#,
        #"{"timestamp":"2026-10-12T05:00:06.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":100,"reasoning_output_tokens":40,"total_tokens":1100},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":100,"reasoning_output_tokens":40,"total_tokens":1100}}}}"#,
        #"{"timestamp":"2026-10-12T05:00:07.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":3}}}}"#,
        #"{"timestamp":"2026-10-12T05:00:08.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"token_count is just a word here"}]}}"#,
        #"{"timestamp":"2026-10-12T05:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000,"cached_input_tokens":2100,"output_tokens":250,"reasoning_output_tokens":90,"total_tokens":3250},"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":150,"reasoning_output_tokens":50,"total_tokens":2150}}}}"#,
    ]

    func testCodexRolloutCountsDeltasAndSeparatesCachedInput() throws {
        let path = scratch.file("codex/sessions/2026/10/12/rollout-1.jsonl").path
        append("codex/sessions/2026/10/12/rollout-1.jsonl", codexLines.joined(separator: "\n") + "\n")
        XCTAssertEqual(try tailer.sync(path: path, provider: .codex), .read(records: 3, restarted: false))
        let totals = try XCTUnwrap(week().first)
        XCTAssertEqual(totals.agent, "codex")
        XCTAssertEqual(totals.model, "gpt-5-codex")
        XCTAssertEqual(totals.messages, 2, "the repeated token_count is one event")
        XCTAssertEqual(totals.input, (1000 - 600) + (2000 - 1500))
        XCTAssertEqual(totals.cacheRead, 600 + 1500)
        XCTAssertEqual(totals.output, 250)
        XCTAssertEqual(totals.reasoning, 90)
        var expectedCost = 900.0 * 1.25e-6
        expectedCost += 2100.0 * 1.25e-7
        expectedCost += 250.0 * 1e-5
        XCTAssertEqual(totals.cost, expectedCost, accuracy: 1e-9)

        // Codex moves finished sessions into the archive: same content, new path.
        let archived = scratch.file("codex/archived_sessions/rollout-1.jsonl")
        try FileManager.default.createDirectory(at: archived.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(atPath: path, toPath: archived.path)
        XCTAssertEqual(try tailer.sync(path: path, provider: .codex), .missing)
        try tailer.sync(path: archived.path, provider: .codex)
        XCTAssertEqual(try store.eventCount(), 2)
    }

    func testCodexContextSurvivesAnAppRestart() throws {
        let relative = "codex/sessions/rollout-2.jsonl"
        append(relative, codexLines.prefix(3).joined(separator: "\n") + "\n")
        try tailer.sync(path: scratch.file(relative).path, provider: .codex)
        // New process: no parser in memory, but the model and session were announced earlier in the file.
        let restarted = TranscriptTailer(store: store, pricing: pricing)
        append(relative, codexLines[6] + "\n")
        XCTAssertEqual(try restarted.sync(path: scratch.file(relative).path, provider: .codex), .read(records: 1, restarted: false))
        let rows = try week()
        XCTAssertEqual(rows.map(\.model), ["gpt-5-codex"], "not 'unknown'")
        XCTAssertEqual(rows.first?.messages, 2)
    }

    func testCodexTotalsOnlyLogsAreDiffed() {
        var parser = CodexUsageParser()
        func line(_ input: Int, _ output: Int) -> JSONValue {
            try! JSONValue.parse("{\"timestamp\":\"2026-10-12T05:00:05Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":0,\"output_tokens\":\(output)}}}}")
        }
        XCTAssertEqual(parser.parse(line: line(100, 10), offset: 0, file: "f").first?.output, 10)
        let second = parser.parse(line: line(250, 35), offset: 50, file: "f").first
        XCTAssertEqual(second?.input, 150)
        XCTAssertEqual(second?.output, 25)
        XCTAssertEqual(second?.model, "unknown")
    }

    // MARK: OpenCode family

    func testOpenCodeFamilyShapes() throws {
        let lines = [
            #"{"id":"msg_a","sessionID":"oc-1","role":"assistant","modelID":"claude-opus-4-5-20251101","providerID":"anthropic","cost":0.0421,"tokens":{"input":120,"output":300,"reasoning":10,"cache":{"read":4000,"write":500}},"time":{"created":1791781200000,"completed":1791781205000},"path":{"cwd":"/work/oc"}}"#,
            #"{"type":"message.updated","properties":{"info":{"id":"msg_b","sessionID":"oc-1","role":"assistant","modelID":"gpt-5-codex","tokens":{"input":50,"output":60,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":1791781300000}}}}"#,
            #"{"message":{"id":"msg_c","role":"assistant","model":"some-local-model","usage":{"prompt_tokens":900,"completion_tokens":100,"prompt_tokens_details":{"cached_tokens":700}}},"timestamp":"2026-10-12T05:20:00Z"}"#,
            #"{"id":"msg_d","role":"user","tokens":{"input":5,"output":0,"cache":{"read":0,"write":0}}}"#,
            #"{"id":"msg_e","role":"assistant","tokens":{"input":0,"output":0,"cache":{"read":0,"write":0}}}"#,
            #"{"type":"session.idle","properties":{"sessionID":"oc-1"},"usage":"not an object"}"#,
        ]
        append("oc/transcript.jsonl", lines.joined(separator: "\n") + "\n")
        XCTAssertEqual(try tailer.sync(path: scratch.file("oc/transcript.jsonl").path, provider: .opencode), .read(records: 3, restarted: false))
        let rows = try week()
        XCTAssertEqual(Set(rows.map(\.model)), ["claude-opus-4-5-20251101", "gpt-5-codex", "some-local-model"])
        let reported = try XCTUnwrap(rows.first { $0.model == "claude-opus-4-5-20251101" })
        XCTAssertEqual(reported.cost, 0.0421, accuracy: 1e-9, "a cost stated by the transcript wins over our estimate")
        XCTAssertEqual(reported.cacheRead, 4000)
        let openAIStyle = try XCTUnwrap(rows.first { $0.model == "some-local-model" })
        XCTAssertEqual(openAIStyle.input, 200)
        XCTAssertEqual(openAIStyle.cacheRead, 700)
        XCTAssertEqual(openAIStyle.cost, 0)
        XCTAssertEqual(try store.unpricedModels(fromDay: "2026-10-06", toDay: "2026-10-12"), ["some-local-model"])
    }

    // MARK: Aggregation

    func testDaysFollowTheConfiguredTimeZone() throws {
        let tokyo = try UsageStore(path: scratch.file("tokyo.sqlite").path, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        defer { tokyo.close() }
        // 2026-10-11T16:30Z is already the 12th in Tokyo.
        let record = UsageRecord(identityKey: "k1", timestamp: try XCTUnwrap(ISOTime.parse("2026-10-11T16:30:00Z")), agent: "claude",
                                 model: "claude-opus-4-5-20251101", input: 1, output: 1)
        try tokyo.commit(records: [record], pricing: pricing, file: nil)
        try store.commit(records: [record], pricing: pricing, file: nil)
        XCTAssertEqual(try tokyo.totals(fromDay: "2026-10-12", toDay: "2026-10-12").count, 1)
        XCTAssertEqual(try store.totals(fromDay: "2026-10-12", toDay: "2026-10-12").count, 0)
        XCTAssertEqual(try store.dailyTotals(fromDay: "2026-10-01", toDay: "2026-10-31")["2026-10-11"]?.tokens, 2)
    }

    func testRepricingUpdatesEstimatesButNotReportedCosts() throws {
        try store.commit(records: [
            UsageRecord(identityKey: "a", timestamp: 1_791_781_200, agent: "x", model: "mystery-model", input: 1000, output: 1000),
            UsageRecord(identityKey: "b", timestamp: 1_791_781_200, agent: "x", model: "mystery-model", input: 1000, output: 1000, reportedCost: 9),
        ], pricing: pricing, file: nil)
        XCTAssertEqual(try week().first?.cost, 9)
        try store.reprice(with: Pricing(rates: ["mystery-model": .init(input: 1e-3, output: 2e-3, cacheRead: nil, cacheWrite: nil)], source: "t"))
        XCTAssertEqual(try week().first?.cost ?? 0, 9 + 3, accuracy: 1e-9)
    }

    // MARK: Robustness (REVIEW "SQLite WAL corruption tolerated")

    func testGarbageDatabaseIsSetAsideAndRebuilt() throws {
        append("t/a.jsonl", claudeLine(id: "m1", output: 10) + "\n")
        try tailer.sync(path: scratch.file("t/a.jsonl").path, provider: .claude)
        store.close()
        let db = scratch.paths.usageDB.path
        for suffix in ["-wal", "-shm"] { unlink(db + suffix) }
        try Data(repeating: 0xAB, count: 8192).write(to: URL(fileURLWithPath: db))

        let rebuilt = try UsageStore(path: db, timeZone: utc)
        defer { rebuilt.close() }
        XCTAssertTrue(rebuilt.recoveredFromCorruption)
        XCTAssertEqual(try rebuilt.eventCount(), 0)
        let kept = try FileManager.default.contentsOfDirectory(atPath: scratch.paths.usageDir.path).filter { $0.contains(".corrupt-") }
        XCTAssertEqual(kept.count, 1, "the broken file is kept aside, not silently deleted")
        // Everything comes back from the transcripts.
        let fresh = TranscriptTailer(store: rebuilt, pricing: pricing)
        XCTAssertEqual(try fresh.sync(path: scratch.file("t/a.jsonl").path, provider: .claude), .read(records: 1, restarted: false))
        XCTAssertEqual(try rebuilt.eventCount(), 1)
    }

    func testDeletedOrDamagedWALIsTolerated() throws {
        append("t/a.jsonl", claudeLine(id: "m1", output: 10) + "\n")
        try tailer.sync(path: scratch.file("t/a.jsonl").path, provider: .claude)
        let db = scratch.paths.usageDB.path
        XCTAssertTrue(FileManager.default.fileExists(atPath: db + "-wal"), "WAL mode is really on")

        // 1. The -wal file vanishes while the database is closed.
        store.close()
        unlink(db + "-wal")
        unlink(db + "-shm")
        var reopened = try UsageStore(path: db, timeZone: utc)
        XCTAssertFalse(reopened.recoveredFromCorruption)
        XCTAssertNoThrow(try reopened.eventCount())
        try reopened.commit(records: [UsageRecord(identityKey: "z", timestamp: 1_791_781_200, agent: "claude", model: "m", output: 1)],
                            pricing: pricing, file: nil)
        reopened.close()

        // 2. The -wal file is replaced by garbage.
        try Data(repeating: 0x5A, count: 4096).write(to: URL(fileURLWithPath: db + "-wal"))
        reopened = try UsageStore(path: db, timeZone: utc)
        defer { reopened.close() }
        XCTAssertNoThrow(try reopened.eventCount())
        XCTAssertNoThrow(try reopened.commit(records: [UsageRecord(identityKey: "y", timestamp: 1_791_781_200, agent: "claude", model: "m", output: 1)],
                                             pricing: pricing, file: nil))
        // Whatever was lost is restored by re-reading the transcript.
        let fresh = TranscriptTailer(store: reopened, pricing: pricing)
        try fresh.sync(path: scratch.file("t/a.jsonl").path, provider: .claude)
        XCTAssertEqual(try reopened.totals(fromDay: "2026-10-12", toDay: "2026-10-12").first { $0.model.hasPrefix("claude-opus") }?.output, 10)
    }
}

final class UsageSupportTests: XCTestCase {
    func testISOTime() throws {
        XCTAssertEqual(ISOTime.parse("1970-01-01T00:00:00Z"), 0)
        XCTAssertEqual(ISOTime.parse("2026-10-12T13:45:12.250Z"), 1_791_812_712.25)
        XCTAssertEqual(ISOTime.parse("2026-10-12T21:45:12+08:00"), 1_791_812_712)
        XCTAssertEqual(ISOTime.parse("2026-10-12T08:45:12-0500"), 1_791_812_712)
        XCTAssertEqual(ISOTime.parse("2024-02-29T12:00:00Z"), 1_709_208_000)
        XCTAssertEqual(ISOTime.parse("2026-10-12 13:45:12"), 1_791_812_712)
        for bad in ["", "2026-10-12", "not a date at all!!", "2026-13-01T00:00:00Z", "2026-10-12T25:00:00Z"] {
            XCTAssertNil(ISOTime.parse(bad), bad)
        }
        XCTAssertEqual(ISOTime.flexible(.number("1791781200000")), 1_791_781_200)
        XCTAssertEqual(ISOTime.flexible(.number("1791781200")), 1_791_781_200)
        XCTAssertEqual(ISOTime.flexible(.string("1970-01-01T00:00:10Z")), 10)
        XCTAssertNil(ISOTime.flexible(.bool(true)))
        // Cross-check against Foundation.
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(ISOTime.parse("2031-07-04T23:59:59Z"), formatter.date(from: "2031-07-04T23:59:59Z")?.timeIntervalSince1970)
    }

    func testPricingLookupAndMath() throws {
        let pricing = try XCTUnwrap(Pricing.parse(Data("""
        {"sample_spec":{"max_tokens":"x","input_cost_per_token":0,"output_cost_per_token":0,"mode":"chat"},
         "claude-opus-4-5-20251101":{"input_cost_per_token":5e-06,"output_cost_per_token":2.5e-05,"cache_read_input_token_cost":5e-07,"cache_creation_input_token_cost":6.25e-06,"litellm_provider":"anthropic","mode":"chat"},
         "claude-opus-4-5":{"input_cost_per_token":5e-06,"output_cost_per_token":2.5e-05},
         "gemini/gemini-2.5-pro":{"input_cost_per_token":1.25e-06,"output_cost_per_token":1e-05},
         "gpt-5-codex":{"input_cost_per_token":1.25e-06,"output_cost_per_token":1e-05,"cache_read_input_token_cost":1.25e-07},
         "dall-e-3":{"output_cost_per_image":0.04},
         "broken":{"input_cost_per_token":"free","output_cost_per_token":1}}
        """.utf8), source: "t"))
        XCTAssertNotNil(pricing.rate(for: "claude-opus-4-5-20251101"))
        XCTAssertNotNil(pricing.rate(for: "anthropic/claude-opus-4-5-20251101"), "provider prefix on the transcript side")
        XCTAssertNotNil(pricing.rate(for: "Claude-Opus-4-5-20251101"))
        XCTAssertNotNil(pricing.rate(for: "claude-opus-4-5-20990101"), "unknown dated variant falls back to the undated model")
        XCTAssertNotNil(pricing.rate(for: "claude-opus-4-5[1m]"))
        XCTAssertNotNil(pricing.rate(for: "gemini-2.5-pro"), "provider prefix on the table side")
        XCTAssertNotNil(pricing.rate(for: "gpt-5-codex-2026-01-15"))
        XCTAssertNil(pricing.rate(for: "totally-unknown"))
        XCTAssertNil(pricing.rate(for: "dall-e-3"))
        XCTAssertNil(pricing.rate(for: "broken"))
        XCTAssertNil(pricing.rate(for: "gpt-5"), "a shorter name must not match a longer model")

        let record = UsageRecord(identityKey: "", timestamp: 0, agent: "codex", model: "gpt-5-codex", input: 1000, output: 100, cacheRead: 4000, cacheWrite: 10)
        // No cache-write price for this model: charged at the input rate.
        var expected = 1000.0 * 1.25e-6
        expected += 100.0 * 1e-5
        expected += 4000.0 * 1.25e-7
        expected += 10.0 * 1.25e-6
        let actual: Double = try XCTUnwrap(pricing.cost(of: record))
        XCTAssertEqual(actual, expected, accuracy: 1e-12)
        XCTAssertNil(pricing.cost(of: UsageRecord(identityKey: "", timestamp: 0, agent: "x", model: "nope")))
        XCTAssertNil(Pricing.parse(Data("[]".utf8), source: "t"))
        XCTAssertNil(Pricing.parse(Data("{}".utf8), source: "t"))
    }

    func testBundledSnapshotIsSaneAndCarriesItsNotice() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Assets/pricing.json"))
        let pricing = try XCTUnwrap(Pricing.parse(data, source: "bundled"))
        XCTAssertGreaterThan(pricing.rates.count, 200)
        for model in ["claude-opus-4-5-20251101", "claude-sonnet-4-5-20250929", "gpt-5-codex", "gemini-2.5-pro"] {
            let rate = try XCTUnwrap(pricing.rate(for: model), model)
            XCTAssertGreaterThan(rate.input, 0)
            XCTAssertLessThan(rate.input, 0.001, "per-token prices are tiny; a per-million figure here would be a unit mistake")
            XCTAssertGreaterThanOrEqual(rate.output, rate.input)
        }
        let meta = try XCTUnwrap(JSONValue.parse(data)["_meta"])
        XCTAssertTrue(meta["license"]?.stringValue?.contains("MIT") ?? false)
        let notice = try String(contentsOf: root.appendingPathComponent("Assets/LITELLM-NOTICE.txt"), encoding: .utf8)
        XCTAssertTrue(notice.contains("MIT License") && notice.contains("Berri AI") && notice.contains("Permission is hereby granted"))

        // The refresh path produces the same shape the loader reads.
        let pruned = try XCTUnwrap(Pricing.prune(data))
        XCTAssertEqual(Pricing.parse(pruned, source: "x")?.rates.count, pricing.rates.count)
    }

    func testPricingLoadPrefersTheRefreshedCache() throws {
        let scratch = Scratch()
        try SecureDirectory.ensureTree(scratch.paths)
        let explicit = scratch.write("explicit.json", #"{"m":{"input_cost_per_token":1e-6,"output_cost_per_token":2e-6}}"#)
        XCTAssertEqual(Pricing.load(paths: scratch.paths, bundle: Bundle(for: UsageSupportTests.self), extraCandidates: [explicit]).source, "explicit")
        try Data(#"{"m":{"input_cost_per_token":3e-6,"output_cost_per_token":4e-6}}"#.utf8).write(to: scratch.paths.pricingCache)
        let loaded = Pricing.load(paths: scratch.paths, bundle: Bundle(for: UsageSupportTests.self), extraCandidates: [explicit])
        XCTAssertEqual(loaded.source, "refreshed")
        XCTAssertEqual(loaded.rate(for: "m")?.input, 3e-6)
        XCTAssertTrue(PricingRefresher.isDue(paths: scratch.paths, now: Date().addingTimeInterval(8 * 86_400)))
        XCTAssertFalse(PricingRefresher.isDue(paths: scratch.paths))
    }

    func testRateLimitCacheParsing() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let cache = RateLimits.parse(Data("""
        {"captured_at":1759999990000,"model":"Opus","rate_limits":{
          "five_hour":{"used_percentage":42.5,"resets_at":1760003600},
          "seven_day":{"used_percentage":140,"resets_at":"2025-10-12T00:00:00Z"},
          "expired":{"used_percentage":99,"resets_at":1759990000},
          "odd":{"utilization":7},
          "junk":"x","nopercent":{"resets_at":1760003600}}}
        """.utf8), now: now)
        XCTAssertEqual(cache.windows.map(\.id), ["five_hour", "seven_day", "odd"])
        XCTAssertEqual(cache.windows[0].usedPercent, 42.5)
        XCTAssertEqual(cache.windows[0].resetsAt, Date(timeIntervalSince1970: 1_760_003_600))
        XCTAssertEqual(cache.windows[1].usedPercent, 100, "clamped")
        XCTAssertNil(cache.windows[2].resetsAt)
        XCTAssertEqual(cache.capturedAt, Date(timeIntervalSince1970: 1_759_999_990))
        XCTAssertEqual(cache.model, "Opus")
        XCTAssertEqual(RateLimits.parse(Data("garbage".utf8)), RateLimits.Cache())
        XCTAssertEqual(RateLimits.parse(Data("{}".utf8)), RateLimits.Cache())
    }
}

/// The engine end to end on a fake home directory: discovery, snapshot, live tailing.
final class UsageEngineIntegrationTests: XCTestCase {
    private func nowISO(_ offset: TimeInterval = 0) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date().addingTimeInterval(offset))
    }

    private final class SnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var latest = UsageSnapshot()
        func set(_ snapshot: UsageSnapshot) { lock.lock(); latest = snapshot; lock.unlock() }
        var value: UsageSnapshot { lock.lock(); defer { lock.unlock() }; return latest }
    }

    func testDiscoveryScanAndSnapshot() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        scratch.write("home/.claude/projects/-work-app/s1.jsonl",
                      claudeLine(id: "m1", output: 100, time: nowISO()) + "\n" + claudeLine(id: "m2", output: 50, time: nowISO(-3 * 86_400)) + "\n"
                      + claudeLine(id: "old", output: 999, time: nowISO(-30 * 86_400)) + "\n")
        scratch.write("home/.claude/projects/-work-app/subagents/agent-1.jsonl", claudeLine(id: "m3", model: "claude-haiku-9-9", output: 7, time: nowISO()) + "\n")
        scratch.write("home/.claude/projects/-work-app/notes.txt", claudeLine(id: "ignored", output: 1, time: nowISO()) + "\n")
        scratch.write("home/.codex/sessions/2026/10/12/rollout-x.jsonl", """
        {"timestamp":"\(nowISO())","type":"session_meta","payload":{"id":"cx","cwd":"/w"}}
        {"timestamp":"\(nowISO())","type":"turn_context","payload":{"model":"gpt-5-codex"}}
        {"timestamp":"\(nowISO())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20},"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20}}}}

        """)
        scratch.write("home/.local/share/opencode/project/abc/transcript.jsonl",
                      "{\"id\":\"oc1\",\"role\":\"assistant\",\"modelID\":\"gpt-5-codex\",\"tokens\":{\"input\":10,\"output\":5,\"cache\":{\"read\":0,\"write\":0}},\"time\":{\"created\":\(Int(Date().timeIntervalSince1970 * 1000))}}\n")
        scratch.write("home/.local/share/opencode/project/abc/other.jsonl", "{\"id\":\"oc2\",\"role\":\"assistant\",\"tokens\":{\"input\":10,\"output\":5}}\n")
        try SecureDirectory.ensureTree(scratch.paths)
        try Data("{\"captured_at\":\(Int(Date().timeIntervalSince1970 * 1000)),\"rate_limits\":{\"five_hour\":{\"used_percentage\":12,\"resets_at\":\(Int(Date().timeIntervalSince1970) + 3600)}}}".utf8)
            .write(to: scratch.paths.rateLimitCache)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pricing = try XCTUnwrap(Pricing.parse(Data(contentsOf: root.appendingPathComponent("Assets/pricing.json")), source: "bundled"))
        let engine = UsageEngine(paths: scratch.paths, home: home, pricing: pricing, log: .inMemory()) { _ in }
        defer { engine.stop() }

        XCTAssertEqual(engine.discover().count, 4, "txt files and unlisted opencode files are not transcripts")
        let snapshot = engine.scanNow()
        XCTAssertNil(snapshot.failure)
        XCTAssertEqual(Set(snapshot.today.map { "\($0.agent)/\($0.model)" }),
                       ["claude/claude-opus-4-5-20251101", "claude/claude-haiku-9-9", "codex/gpt-5-codex", "opencode/gpt-5-codex"])
        XCTAssertEqual(snapshot.today.first { $0.model == "claude-opus-4-5-20251101" }?.output, 100)
        XCTAssertEqual(snapshot.week.first { $0.model == "claude-opus-4-5-20251101" }?.output, 150, "the 30-day-old message is outside the week")
        XCTAssertEqual(snapshot.days.count, 7)
        XCTAssertEqual(snapshot.days.last?.tokens, snapshot.todayTokens)
        XCTAssertGreaterThan(snapshot.todayCost, 0)
        XCTAssertEqual(snapshot.unpricedModels, ["claude-haiku-9-9"])
        XCTAssertEqual(snapshot.rateLimits.map(\.id), ["five_hour"])
        XCTAssertEqual(snapshot.pricingSource, "bundled")
        XCTAssertEqual(UsageSnapshot.byAgent(snapshot.today).map(\.agent).sorted(), ["claude", "codex", "opencode"])

        // A second pass reads nothing new and changes nothing.
        XCTAssertEqual(engine.scanNow().today, snapshot.today)
    }

    func testLiveAppendIsPickedUp() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        let transcript = scratch.write("home/.claude/projects/-p/live.jsonl", claudeLine(id: "m1", output: 10, time: nowISO()) + "\n")
        let box = SnapshotBox()
        let engine = UsageEngine(paths: scratch.paths, home: home, pricing: Pricing(), log: .inMemory()) { box.set($0) }
        engine.start()
        defer { engine.stop() }
        XCTAssertTrue(waitUntil(timeout: 10) { box.value.todayTokens > 0 && !box.value.indexing })
        XCTAssertEqual(box.value.today.first?.output, 10)

        let handle = try FileHandle(forWritingTo: transcript)
        handle.seekToEndOfFile()
        handle.write(Data((claudeLine(id: "m2", output: 32, time: nowISO()) + "\n").utf8))
        try handle.close()
        // FSEvents delivers within a second or two; the 300 s poll is only the fallback.
        XCTAssertTrue(waitUntil(timeout: 30) { box.value.today.first?.output == 42 }, "output is \(box.value.today.first?.output ?? -1)")

        // A brand-new session file in a brand-new project directory.
        scratch.write("home/.claude/projects/-other/new.jsonl", claudeLine(id: "m3", output: 8, time: nowISO()) + "\n")
        XCTAssertTrue(waitUntil(timeout: 30) { box.value.today.first?.output == 50 })
    }

    func testEngineRebuildsAfterDatabaseDamage() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        scratch.write("home/.claude/projects/-p/a.jsonl", claudeLine(id: "m1", output: 10, time: nowISO()) + "\n")
        var engine = UsageEngine(paths: scratch.paths, home: home, pricing: Pricing(), log: .inMemory()) { _ in }
        XCTAssertEqual(engine.scanNow().today.first?.output, 10)
        engine.stop()
        for suffix in ["-wal", "-shm"] { unlink(scratch.paths.usageDB.path + suffix) }
        try Data(repeating: 0x00, count: 100).write(to: scratch.paths.usageDB)
        try Data("this is not a database".utf8).write(to: scratch.paths.usageDB)
        let log = NikoLog.inMemory()
        engine = UsageEngine(paths: scratch.paths, home: home, pricing: Pricing(), log: log) { _ in }
        defer { engine.stop() }
        let snapshot = engine.scanNow()
        XCTAssertNil(snapshot.failure)
        XCTAssertEqual(snapshot.today.first?.output, 10, "rebuilt from the transcript")
        XCTAssertTrue(log.lines.contains { $0.contains("rebuilt from the transcripts") })
    }
}
