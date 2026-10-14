import XCTest
@testable import NikoCore

/// Kiro's own session folders, read without any hook (the shapes of Kiro 1.3's files).
final class KiroSessionsTests: XCTestCase {
    private func write(_ scratch: Scratch, session: String, records: [String], title: String = "Tidy the header",
                       workspace: String = "/Users/dev/code/site") -> URL {
        let folder = "home/.kiro/sessions/ab98e92178f5b58c/sess_\(session)"
        scratch.write(folder + "/session.json", """
        {"schemaVersion":"1.0.0","id":"sess_\(session)","title":"\(title)","agentMode":"vibe","workspacePaths":["\(workspace)"],
         "createdAt":"2026-10-14T10:00:00.000Z","lastModifiedAt":"2026-10-14T10:05:00.000Z","modelId":"claude-sonnet-4.5","status":"idle"}
        """)
        return scratch.write(folder + "/messages.jsonl", records.joined(separator: "\n") + "\n")
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func record(_ type: String, _ fields: String = "", ago seconds: TimeInterval = 30) -> String {
        let time = Self.iso(Date().addingTimeInterval(-seconds))
        return #"{"id":"m-\#(UUID().uuidString)","timestamp":"\#(time)","payload":{"type":"\#(type)"\#(fields.isEmpty ? "" : "," + fields)}}"#
    }

    func testAFinishedTurnShowsItsPromptAndReply() throws {
        let scratch = Scratch()
        _ = write(scratch, session: "a", records: [
            record("session_start"),
            record("tool_call", #""toolName":"fetch_cloud_config","kind":"other","status":"completed""#),
            record("turn_start"),
            record("user", #""content":"Make the header sticky""#),
            record("tool_call", #""toolName":"fsWrite","kind":"edit","args":{"path":"src/Header.tsx"},"status":"completed""#),
            record("assistant", #""content":"The header now sticks to the top.""#),
            record("turn_end", #""status":"success""#, ago: 20),
        ])
        let found = KiroSessions(home: scratch.file("home")).snapshots(since: Date().addingTimeInterval(-60))
        let session = try XCTUnwrap(found.first)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(session.key, SessionKey(source: "kiro", sessionID: "sess_a"))
        XCTAssertEqual(session.host, .kiroDesktop)
        XCTAssertEqual(session.cwd, "/Users/dev/code/site")
        XCTAssertEqual(session.title, "Tidy the header")
        XCTAssertEqual(session.lastPrompt, "Make the header sticky")
        XCTAssertEqual(session.lastReply, "The header now sticks to the top.")
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertEqual(session.model, "claude-sonnet-4.5")
    }

    func testATurnUnderWayShowsTheToolAtWork() throws {
        let scratch = Scratch()
        _ = write(scratch, session: "b", records: [
            record("turn_start"),
            record("user", #""content":"Run the tests""#),
            record("tool_call", #""toolName":"executeBash","kind":"execute","args":{"command":"npm test"},"status":"in_progress""#),
        ])
        let session = try XCTUnwrap(KiroSessions(home: scratch.file("home")).snapshots(since: Date().addingTimeInterval(-60)).first)
        XCTAssertEqual(session.phase, .working)
        XCTAssertEqual(session.activity, Activity(verb: "running", detail: "npm test"))
    }

    func testOldSessionsAndStrangeFilesAreLeftOut() throws {
        let scratch = Scratch()
        let file = write(scratch, session: "c", records: [record("turn_end")])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: file.path)
        _ = write(scratch, session: "d", records: ["not json", record("turn_start")])
        // Asked yesterday and never answered; since then only Kiro's own housekeeping, which keeps the file fresh.
        _ = write(scratch, session: "e", records: [
            record("user", #""content":"hi""#, ago: 86_400),
            record("tool_call", #""toolName":"fetch_cloud_config","kind":"other","toolCallId":"h1","status":"completed""#),
            record("tool_result", #""toolCallId":"h1","success":true"#),
        ])
        scratch.write("home/.kiro/sessions/ab98e92178f5b58c/.index/index.json", "{}")
        let reader = KiroSessions(home: scratch.file("home"))
        let found = reader.snapshots(since: Date().addingTimeInterval(-600))
        XCTAssertEqual(found.map(\.key.sessionID), ["sess_d"], "too old to list, housekeeping is not work, and a broken line skipped")
        XCTAssertEqual(found.first?.phase, .working)
        XCTAssertTrue(KiroSessions(home: scratch.file("nobody")).snapshots(since: .distantPast).isEmpty)
    }

    func testAgentsConnectedByAnEarlierVersionAreFound() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        // 0.8 put Kiro's entries in a file Kiro never ran hooks from; a later version must move them.
        scratch.write("home/.kiro/settings/cli.json", #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/bin/sh -c 'niko-bridge --source kiro'"}]}]}}"#)
        scratch.write("home/.copilot/hooks/other.json", "{}")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let report = try ScanProbe.run(home: home, agents: AgentRegistry.installable)
        XCTAssertEqual(Installer.connectedAgents(in: report), ["kiro"])

        var options = InstallOptions(home: home, paths: scratch.paths)
        options.agentIDs = Installer.connectedAgents(in: report)
        options.includeStatusLine = false
        options.bridgeBinary = bridgeBinaryPath
        XCTAssertTrue(Installer(options: options).run(.install).applied)
        XCTAssertTrue(scratch.read("home/.kiro/hooks/niko.json")?.contains("niko-bridge") == true)
        XCTAssertFalse(scratch.read("home/.kiro/settings/cli.json")?.contains("niko-bridge") == true)
        XCTAssertEqual(AgentRegistry.descriptor("kiro")?.apps, ["dev.kiro.desktop"])
    }

    func testKirosToolNamesReadAsWork() {
        XCTAssertEqual(Activity.verb(forTool: "executeBash"), "running")
        XCTAssertEqual(Activity.verb(forTool: "readFile"), "reading")
        XCTAssertEqual(Activity.verb(forTool: "fsWrite"), "editing")
        XCTAssertEqual(Activity.verb(forTool: "strReplace"), "editing")
        XCTAssertEqual(Activity.verb(forTool: "grepSearch"), "finding")
    }
}
