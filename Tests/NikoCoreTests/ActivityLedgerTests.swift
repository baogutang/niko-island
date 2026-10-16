import XCTest
@testable import NikoCore

final class ActivityLedgerTests: XCTestCase {
    var scratch: Scratch!

    override func setUp() { scratch = Scratch() }
    override func tearDown() { scratch = nil }

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func event(_ source: String, _ json: String) throws -> AgentEvent {
        var object = try XCTUnwrap(JSONValue.parse(Data(json.utf8)).objectValue)
        object["ts"] = .number(String(now.timeIntervalSince1970 * 1000))
        return try AgentEvent(json: .object(object), defaultSource: source)
    }

    func testEveryAgentIsCountedOncePerSessionPromptAndCall() throws {
        let ledger = ActivityLedger(path: scratch.file("activity.sqlite"), timeZone: TimeZone(identifier: "UTC")!, clock: { self.now })
        let claude = [
            #"{"hook_event_name":"SessionStart","session_id":"s1"}"#,
            #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"fix it"}"#,
            // One call, announced and then reported: counted once.
            #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"ls"}}"#,
            #"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"Bash","tool_use_id":"t1"}"#,
            // No call id: the session announces its calls, so the report after is the same call.
            #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"mcp__github__create_issue"}"#,
            #"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"mcp__github__create_issue"}"#,
            #"{"hook_event_name":"Stop","session_id":"s1"}"#,
            #"{"hook_event_name":"UserPromptSubmit","session_id":"s2","prompt":"another"}"#,
        ]
        for line in claude { ledger.record(try event("claude", line)) }
        // Cursor only reports after the fact, and sends its thoughts as events too.
        let cursor = [
            #"{"hook_event_name":"afterShellExecution","conversation_id":"c1","command":"npm test"}"#,
            #"{"hook_event_name":"afterShellExecution","conversation_id":"c1","command":"npm run build"}"#,
            #"{"hook_event_name":"afterAgentThought","conversation_id":"c1","text":"hmm"}"#,
            #"{"hook_event_name":"afterFileEdit","conversation_id":"c1","file_path":"/w/a.ts"}"#,
        ]
        for line in cursor { ledger.record(try event("cursor", line)) }

        let snapshot = ledger.snapshotNow(now: now)
        let day = try XCTUnwrap(snapshot.days["claude"]?.last)
        XCTAssertEqual(day.sessions, 2)
        XCTAssertEqual(day.prompts, 2)
        XCTAssertEqual(day.tools, 2)
        XCTAssertEqual(snapshot.tools["claude"]?.map(\.name).sorted(), ["Bash", "mcp:github.create_issue"])
        let cursorDay = try XCTUnwrap(snapshot.days["cursor"]?.last)
        XCTAssertEqual(cursorDay.sessions, 1)
        XCTAssertEqual(cursorDay.tools, 3)
        XCTAssertEqual(snapshot.tools["cursor"]?.first, ActivitySnapshot.Tool(name: "Bash", count: 2))
        XCTAssertEqual(snapshot.days["all"]?.last?.tools, 5)
        XCTAssertEqual(snapshot.days["all"]?.count, ActivityLedger.heatmapDays)
        XCTAssertEqual(snapshot.agents.map(\.id), ["claude", "cursor"])
        XCTAssertEqual(snapshot.streak("all"), 1)

        // A new ledger on the same file sees the same session as already counted today.
        let again = ActivityLedger(path: scratch.file("activity.sqlite"), timeZone: TimeZone(identifier: "UTC")!, clock: { self.now })
        again.record(try event("claude", #"{"hook_event_name":"Stop","session_id":"s1"}"#))
        XCTAssertEqual(again.snapshotNow(now: now).days["claude"]?.last?.sessions, 2)
    }

    func testToolNamesAreTidied() {
        XCTAssertEqual(ActivityLedger.toolName("mcp__github__create_issue"), "mcp:github.create_issue")
        XCTAssertEqual(ActivityLedger.toolName("mcp__linear"), "mcp:linear")
        XCTAssertEqual(ActivityLedger.toolName(" Bash "), "Bash")
    }

    func testNothingButCountsIsKept() throws {
        let ledger = ActivityLedger(path: scratch.file("activity.sqlite"), clock: { self.now })
        ledger.record(try event("claude", #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"my secret plan"}"#))
        ledger.record(try event("claude", #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}"#))
        ledger.flush()
        let bytes = try Data(contentsOf: scratch.file("activity.sqlite"))
            + ((try? Data(contentsOf: scratch.file("activity.sqlite-wal"))) ?? Data())
        XCTAssertNil(bytes.range(of: Data("secret".utf8)))
        XCTAssertNil(bytes.range(of: Data("id_rsa".utf8)))
    }
}
