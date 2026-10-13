import XCTest
@testable import NikoCore

/// What a row can say beyond "working": how far through its own list an agent
/// is, which branch it is on, which model it runs, and what it said last.
final class SessionDetailsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func jsonl(_ lines: [String]) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }
    private func items(_ json: String) throws -> [JSONValue] { try XCTUnwrap(try JSONValue.parse(Data(json.utf8)).arrayValue) }

    // MARK: Task lists

    func testAListOfStepsIsCountedWhateverTheAgentCallsItsFields() throws {
        // Claude Code's TodoWrite.
        let todos = try items(#"[{"content":"Read the code","status":"completed","activeForm":"Reading the code"},{"content":"Write the fix","status":"in_progress","activeForm":"Writing the fix"},{"content":"Run the tests","status":"pending","activeForm":"Running the tests"}]"#)
        XCTAssertEqual(TaskProgress.from(items: todos), TaskProgress(done: 1, total: 3, current: "Writing the fix"))
        // Codex's update_plan.
        let plan = try items(#"[{"step":"Find the bug","status":"completed"},{"step":"Patch it","status":"completed"},{"step":"Explain","status":"in_progress"}]"#)
        let progress = try XCTUnwrap(TaskProgress.from(items: plan))
        XCTAssertEqual(progress, TaskProgress(done: 2, total: 3, current: "Explain"))
        XCTAssertEqual(progress.fraction, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertFalse(progress.isComplete)
        // Dropped steps are not steps; a finished list knows it is finished.
        let finished = try items(#"[{"subject":"A","status":"completed"},{"subject":"B","status":"done"},{"subject":"C","status":"cancelled"},{"subject":"D","status":"deleted"}]"#)
        XCTAssertEqual(TaskProgress.from(items: finished), TaskProgress(done: 2, total: 2))
        XCTAssertEqual(TaskProgress.from(items: finished)?.isComplete, true)
        XCTAssertNil(TaskProgress.from(items: []))
        XCTAssertNil(TaskProgress.from(items: try items(#"["not a step", 3]"#)))
        // A step is one line on a row, however long the agent made it.
        let long = try items(#"[{"content":"\#(String(repeating: "word ", count: 80))","status":"in_progress"}]"#)
        XCTAssertLessThanOrEqual(TaskProgress.from(items: long)?.current?.count ?? 999, 97)

        // The tool calls that carry a whole list.
        let write = try JSONValue.parse(Data(#"{"todos":[{"content":"A","status":"completed"},{"content":"B","status":"pending"}]}"#.utf8))
        XCTAssertEqual(TaskProgress.from(tool: "TodoWrite", input: write), TaskProgress(done: 1, total: 2))
        let update = try JSONValue.parse(Data(#"{"explanation":"x","plan":[{"step":"A","status":"in_progress"}]}"#.utf8))
        XCTAssertEqual(TaskProgress.from(tool: "update_plan", input: update), TaskProgress(done: 0, total: 1, current: "A"))
        XCTAssertNil(TaskProgress.from(tool: "Bash", input: write))
        XCTAssertNil(TaskProgress.from(tool: "TodoWrite", input: nil))
        XCTAssertNil(TaskProgress.from(tool: nil, input: write))
    }

    func testTheTaskToolsARealClaudeCodeUsesReadAsPlanning() {
        // Seen from Claude Code 2.1.295: no TodoWrite any more, but TaskCreate {subject, description} and
        // TaskUpdate {taskId, status}, with one file per task under ~/.claude/tasks/<session id>/.
        XCTAssertEqual(Activity.forTool("TaskCreate", input: ["subject": .string("Boil the water"), "description": .string("Until it bubbles")]),
                       Activity(verb: "planning", detail: "Boil the water"))
        XCTAssertEqual(Activity.forTool("TaskUpdate", input: ["taskId": .string("1"), "status": .string("completed")]), Activity(verb: "planning"))
        XCTAssertEqual(Activity.forTool("TodoWrite", input: nil).verb, "planning")
        XCTAssertEqual(Activity.forTool("update_plan", input: nil).verb, "planning")
        XCTAssertEqual(Activity.forTool("ToolSearch", input: ["query": .string("select:TaskCreate"), "max_results": .int(3)]),
                       Activity(verb: "finding", detail: "select:TaskCreate"))
    }

    func testClaudeCodesTaskFilesAreCountedAndLeftAlone() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        XCTAssertNil(TaskProgress.claudeTasks(home: home, sessionID: "abc"))
        let folder = home.appendingPathComponent(".claude/tasks/abc")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertNil(TaskProgress.claudeTasks(home: home, sessionID: "abc"), "an empty folder is no list")
        try Data(#"{"id":"1","subject":"Map the module","status":"completed"}"#.utf8).write(to: folder.appendingPathComponent("1.json"))
        try Data(#"{"id":"2","subject":"Move the parser","activeForm":"Moving the parser","status":"in_progress"}"#.utf8).write(to: folder.appendingPathComponent("2.json"))
        try Data(#"{"id":"3","subject":"Delete the old one","status":"pending"}"#.utf8).write(to: folder.appendingPathComponent("3.json"))
        try Data("not a task".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        // What a real folder also holds: an empty lock, a counter, and tasks with more fields than are read.
        try Data().write(to: folder.appendingPathComponent(".lock"))
        try Data("3".utf8).write(to: folder.appendingPathComponent(".highwatermark"))
        try Data(#"{"id":"3","subject":"Delete the old one","description":"…","status":"pending","blocks":[],"blockedBy":["2"]}"#.utf8)
            .write(to: folder.appendingPathComponent("3.json"))
        try Data("{ broken".utf8).write(to: folder.appendingPathComponent("4.json"))
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(TaskProgress.claudeTasks(home: home, sessionID: "abc"), TaskProgress(done: 1, total: 3, current: "Moving the parser"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), before)
        XCTAssertNil(TaskProgress.claudeTasks(home: home, sessionID: "someone-else"))
    }

    // MARK: Branch and model

    func testTheBranchIsReadFromGitsOwnFilesWithoutRunningGit() throws {
        let scratch = Scratch()
        let repo = scratch.file("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("Sources/Deep/er"), withIntermediateDirectories: true)
        try Data("ref: refs/heads/feature/upload-retry\n".utf8).write(to: repo.appendingPathComponent(".git/HEAD"))
        XCTAssertEqual(GitInfo.branch(cwd: repo.path), "feature/upload-retry")
        XCTAssertEqual(GitInfo.branch(cwd: repo.appendingPathComponent("Sources/Deep/er").path), "feature/upload-retry", "anywhere inside the repository")

        // A commit checked out by itself has no branch to name.
        try Data("4b825dc642cb6eb9a060e54bf8d69288fbee4904\n".utf8).write(to: repo.appendingPathComponent(".git/HEAD"))
        XCTAssertNil(GitInfo.branch(cwd: repo.path))

        // A worktree: `.git` is a file that points at the real place.
        let worktree = scratch.file("wt")
        let real = repo.appendingPathComponent(".git/worktrees/wt")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("gitdir: \(real.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        try Data("ref: refs/heads/fix/flaky\n".utf8).write(to: real.appendingPathComponent("HEAD"))
        XCTAssertEqual(GitInfo.branch(cwd: worktree.path), "fix/flaky")
        // A pointer that leads nowhere is no branch, not a crash.
        try Data("gitdir: /nowhere/at/all\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        XCTAssertNil(GitInfo.branch(cwd: worktree.path))

        XCTAssertNil(GitInfo.branch(cwd: scratch.file("plain").path), "not a repository")
        XCTAssertNil(GitInfo.branch(cwd: "/"))
    }

    func testModelNamesAreShortenedToWhatFitsOnAChip() {
        XCTAssertEqual(ModelLabel.short("claude-sonnet-5-5-20260801"), "sonnet-5-5")
        XCTAssertEqual(ModelLabel.short("claude-opus-5-5"), "opus-5-5")
        XCTAssertEqual(ModelLabel.short("gpt-6-astra"), "gpt-6-astra")
        XCTAssertEqual(ModelLabel.short("zai/glm-5.1"), "glm-5.1")
        XCTAssertEqual(ModelLabel.short("models/gemini-3-pro"), "gemini-3-pro")
        XCTAssertEqual(ModelLabel.short(""), "")
    }

    // MARK: Read from the agents' own records

    func testClaudeTranscriptsCarryTheModelAndTheList() throws {
        let prompt = #"{"type":"user","sessionId":"s","cwd":"/tmp/proj","timestamp":"2027-01-15T08:00:00.000Z","message":{"role":"user","content":"Refactor the parser"}}"#
        let plan = #"{"type":"assistant","timestamp":"2027-01-15T08:00:02.000Z","message":{"role":"assistant","model":"claude-opus-5-5-20260801","content":[{"type":"text","text":"Planning."},{"type":"tool_use","id":"t1","name":"TodoWrite","input":{"todos":[{"content":"Map it","status":"in_progress","activeForm":"Mapping it"},{"content":"Move it","status":"pending","activeForm":"Moving it"}]}}]}}"#
        let later = #"{"type":"assistant","timestamp":"2027-01-15T08:00:06.000Z","message":{"role":"assistant","model":"claude-opus-5-5-20260801","content":[{"type":"tool_use","id":"t2","name":"TodoWrite","input":{"todos":[{"content":"Map it","status":"completed","activeForm":"Mapping it"},{"content":"Move it","status":"in_progress","activeForm":"Moving it"}]}}]}}"#
        let synthetic = #"{"type":"assistant","timestamp":"2027-01-15T08:00:07.000Z","message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"API error"}]}}"#
        func read(_ lines: [String]) -> TranscriptSnapshot {
            ClaudeTranscript.snapshot(path: "/h/.claude/projects/-tmp-proj/0f0e-session.jsonl", tail: jsonl(lines), tailIsWholeFile: true,
                                      firstPrompt: nil, modified: now.addingTimeInterval(-2), now: now)!
        }
        var snapshot = read([prompt])
        XCTAssertNil(snapshot.progress)
        XCTAssertNil(snapshot.model)
        snapshot = read([prompt, plan])
        XCTAssertEqual(snapshot.progress, TaskProgress(done: 0, total: 2, current: "Mapping it"))
        XCTAssertEqual(snapshot.model, "claude-opus-5-5-20260801")
        snapshot = read([prompt, plan, later, synthetic])
        XCTAssertEqual(snapshot.progress, TaskProgress(done: 1, total: 2, current: "Moving it"), "the latest list wins")
        XCTAssertEqual(snapshot.model, "claude-opus-5-5-20260801", "a made-up model name is not the model")

        // What was said before the newest prompt is not this turn's reply.
        let done = #"{"type":"assistant","timestamp":"2027-01-15T08:00:09.000Z","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"All moved."}]}}"#
        let again = #"{"type":"user","timestamp":"2027-01-15T08:01:00.000Z","message":{"role":"user","content":"Now the tests"}}"#
        XCTAssertEqual(read([prompt, plan, done]).lastReply, "All moved.")
        XCTAssertNil(read([prompt, plan, done, again]).lastReply)
    }

    func testCodexRolloutsCarryTheModelAndThePlan() throws {
        let path = "/h/.codex/sessions/2027/01/15/rollout-2027-01-15T08-00-00-01a12fbc-aaaa-bbbb-cccc-0123456789ab.jsonl"
        let meta = #"{"timestamp":"2027-01-15T08:00:00.000Z","type":"session_meta","payload":{"id":"01a12fbc-aaaa-bbbb-cccc-0123456789ab","cwd":"/tmp/shot","originator":"Codex Desktop","source":"vscode"}}"#
        let started = #"{"timestamp":"2027-01-15T08:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t"}}"#
        let context = #"{"timestamp":"2027-01-15T08:00:01.050Z","type":"turn_context","payload":{"cwd":"/tmp/shot","model":"gpt-6-astra"}}"#
        let exec = #"{"timestamp":"2027-01-15T08:00:03.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","call_id":"c1","input":"swift build"}}"#
        let plan = #"{"timestamp":"2027-01-15T08:00:04.000Z","type":"response_item","payload":{"type":"function_call","name":"update_plan","call_id":"p1","arguments":"{\"plan\":[{\"step\":\"Build\",\"status\":\"completed\"},{\"step\":\"Wire the button\",\"status\":\"in_progress\"},{\"step\":\"Test\",\"status\":\"pending\"}]}"}}"#
        let complete = #"{"timestamp":"2027-01-15T08:00:09.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t","last_agent_message":"Button wired."}}"#
        func read(_ lines: [String]) -> TranscriptSnapshot {
            let head = CodexTranscript.meta(path: path, head: jsonl([meta, started]))
            return CodexTranscript.snapshot(path: path, meta: head, tail: jsonl(lines), tailIsWholeFile: true, modified: now.addingTimeInterval(-2), now: now)!
        }
        var snapshot = read([started, context, exec, plan])
        XCTAssertEqual(snapshot.model, "gpt-6-astra")
        XCTAssertEqual(snapshot.progress, TaskProgress(done: 1, total: 3, current: "Wire the button"))
        XCTAssertEqual(snapshot.activity, Activity(verb: "running", detail: "swift build"), "noting the plan is bookkeeping: the row keeps saying what is being done")
        XCTAssertEqual(snapshot.phase, .working)
        snapshot = read([started, context, exec, plan, complete])
        XCTAssertEqual(snapshot.lastReply, "Button wired.")
        XCTAssertNil(read([started, context, exec, plan, complete, started]).lastReply, "a new turn has not said anything yet")
    }

    func testWhatCodexWrapsAroundAPromptIsNotThePrompt() {
        let withFiles = "# Files mentioned by the user:\n\n## Upload.swift: /Users/me/atlas/Upload.swift\n\n## My request:\nWhy does the retry fire twice?\n"
        XCTAssertEqual(TranscriptText.prompt(withFiles), "Why does the retry fire twice?")
        let fromEditor = "# Context from my IDE setup:\n\n## Active file: a.ts\n\n## Open tabs:\n- a.ts\n\n## My request for Codex:\nRename the hook\nand keep the tests green"
        XCTAssertEqual(TranscriptText.prompt(fromEditor), "Rename the hook\nand keep the tests green")
        XCTAssertNil(TranscriptText.prompt("# Files mentioned by the user:\n\n## a.swift: /a.swift\n"), "files alone say nothing a person typed")
        XCTAssertNil(TranscriptText.prompt("# AGENTS.md instructions for /Users/me/atlas\n\n<INSTRUCTIONS>\nUse tabs.\n</INSTRUCTIONS>"))
        XCTAssertNil(TranscriptText.prompt("<environment_context>\n  <cwd>/tmp</cwd>\n</environment_context>"))
        // A person may write headings of their own.
        XCTAssertEqual(TranscriptText.prompt("# Plan\n\nDo the thing"), "# Plan\n\nDo the thing")

        // In a rollout: the wrapped message names the session by what was asked, and the instructions name nothing.
        let path = "/h/.codex/sessions/2027/01/15/rollout-2027-01-15T08-00-00-01a12fbc-aaaa-bbbb-cccc-0123456789ab.jsonl"
        let meta = #"{"timestamp":"2027-01-15T08:00:00.000Z","type":"session_meta","payload":{"id":"01a12fbc-aaaa-bbbb-cccc-0123456789ab","cwd":"/tmp/shot","originator":"Codex Desktop","source":"vscode"}}"#
        let instructions = ##"{"timestamp":"2027-01-15T08:00:00.500Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for /tmp/shot\n\n<INSTRUCTIONS>\nUse tabs.\n</INSTRUCTIONS>"}]}}"##
        let asked = ##"{"timestamp":"2027-01-15T08:00:01.100Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# Files mentioned by the user:\n\n## Shot.swift: /tmp/shot/Shot.swift\n\n## My request:\nAdd a share sheet\n"}]}}"##
        let head = CodexTranscript.meta(path: path, head: jsonl([meta, instructions, asked]))
        let snapshot = CodexTranscript.snapshot(path: path, meta: head, tail: jsonl([instructions, asked]), tailIsWholeFile: true,
                                                modified: now.addingTimeInterval(-2), now: now)
        XCTAssertEqual(snapshot?.firstPrompt, "Add a share sheet")
        XCTAssertEqual(snapshot?.lastPrompt, "Add a share sheet")
    }

    func testZCodesStepsComeFromItsTodoTable() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".zcode/cli/db"), withIntermediateDirectories: true)
        let db = try SQLiteDB(path: ZCodeSessions.databasePath(home: home))
        try db.execute("""
            CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT, title TEXT, time_created INTEGER,
                                  time_updated INTEGER, time_archived INTEGER, task_type TEXT);
            CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT, sequence INTEGER);
            CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT, sequence INTEGER);
            CREATE TABLE todo (session_id TEXT, content TEXT, status TEXT, priority TEXT, position INTEGER);
            """)
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        for id in ["sess_a", "sess_b"] {
            try db.run("INSERT INTO session VALUES (?, NULL, '/Users/me/projects/atlas', 'Upload retry', ?, ?, NULL, 'interactive')", [.text(id), .integer(ms - 60_000), .integer(ms - 3000)])
            try db.run("INSERT INTO message VALUES (?, ?, ?, ?, ?, 1)", [.text("u_\(id)"), .text(id), .integer(ms), .integer(ms), .text(#"{"role":"user"}"#)])
            try db.run("INSERT INTO part VALUES (?, ?, ?, ?, ?, ?, 0)", [.text("up_\(id)"), .text("u_\(id)"), .text(id), .integer(ms), .integer(ms), .text(#"{"type":"text","text":"Fix the retry"}"#)])
            try db.run("INSERT INTO message VALUES (?, ?, ?, ?, ?, 2)", [.text("a_\(id)"), .text(id), .integer(ms), .integer(ms), .text(#"{"role":"assistant","modelId":"glm-5.1","time":{"created":3}}"#)])
            try db.run("INSERT INTO part VALUES (?, ?, ?, ?, ?, ?, 0)", [.text("ap_\(id)"), .text("a_\(id)"), .text(id), .integer(ms), .integer(ms), .text(#"{"type":"text","text":"On it."}"#)])
        }
        for (position, row) in [("Read the retry code", "completed"), ("Add a backoff", "in_progress"), ("Run the tests", "pending")].enumerated() {
            try db.run("INSERT INTO todo VALUES ('sess_a', ?, ?, 'medium', ?)", [.text(row.0), .text(row.1), .integer(Int64(position))])
        }
        db.close()

        let found = ZCodeSessions(home: home).snapshots(since: now.addingTimeInterval(-3600), now: now)
        let listed = try XCTUnwrap(found.first { $0.key.sessionID == "sess_a" })
        XCTAssertEqual(listed.progress, TaskProgress(done: 1, total: 3, current: "Add a backoff"))
        XCTAssertEqual(listed.model, "glm-5.1")
        XCTAssertNil(found.first { $0.key.sessionID == "sess_b" }?.progress, "no list, no bar")
    }

    // MARK: On the session

    private func event(_ name: String, _ extra: [String: JSONValue] = [:]) throws -> AgentEvent {
        var object: JSONObject = ["hook_event_name": .string(name), "session_id": .string("s1"), "cwd": .string("/tmp/proj")]
        for (key, value) in extra { object[key] = value }
        return try AgentEvent(json: .object(object), defaultSource: "claude")
    }

    func testHooksCarryTheListAndTheClosingWords() throws {
        var store = SessionStore()
        let key = SessionKey(source: "claude", sessionID: "s1")
        store.apply(try event(HookEvent.userPromptSubmit, ["prompt": .string("Refactor the parser")]), now: now)
        let todos = try JSONValue.parse(Data(#"{"todos":[{"content":"Map it","status":"completed"},{"content":"Move it","status":"in_progress","activeForm":"Moving it"}]}"#.utf8))
        store.apply(try event(HookEvent.preToolUse, ["tool_name": .string("TodoWrite"), "tool_input": todos]), now: now)
        XCTAssertEqual(store[key]?.progress, TaskProgress(done: 1, total: 2, current: "Moving it"))
        store.apply(try event(HookEvent.preToolUse, ["tool_name": .string("Bash"), "tool_input": .object(["command": .string("make")])]), now: now)
        XCTAssertEqual(store[key]?.progress?.total, 2, "another tool does not wipe the list")

        // Closing words that come with the event are on the session at once, kept to a card's length.
        store.apply(try event(HookEvent.stop, ["last_assistant_message": .string("Moved the parser.\n\n" + String(repeating: "x", count: 900))]), now: now)
        XCTAssertEqual(store[key]?.phase, .waiting)
        XCTAssertEqual(store[key]?.lastReply?.hasPrefix("Moved the parser."), true)
        XCTAssertEqual(store[key]?.lastReply?.count, 600)
        // The next prompt makes them old news; a Stop without words leaves nothing behind either.
        store.apply(try event(HookEvent.userPromptSubmit, ["prompt": .string("Now the tests")]), now: now)
        XCTAssertNil(store[key]?.lastReply)
        store.apply(try event(HookEvent.stop, ["last_assistant_message": .string("   ")]), now: now)
        XCTAssertNil(store[key]?.lastReply)
    }

    func testTheTranscriptAddsListModelAndReplyToAHookSession() throws {
        var store = SessionStore()
        let key = SessionKey(source: "claude", sessionID: "s1")
        store.apply(try event(HookEvent.userPromptSubmit, ["prompt": .string("Refactor the parser")]), now: now)
        func snapshot(_ phase: Session.Phase, reply: String? = nil, progress: TaskProgress? = nil, model: String? = nil) -> TranscriptSnapshot {
            var snapshot = TranscriptSnapshot(key: key, path: "/h/t.jsonl", cwd: "/tmp/proj", host: nil, title: nil, firstPrompt: "Refactor the parser",
                                              lastPrompt: "Refactor the parser", lastReply: reply, phase: phase,
                                              activity: phase == .working ? .thinking : .waiting, updatedAt: now, phaseSince: now)
            snapshot.progress = progress
            snapshot.model = model
            return snapshot
        }
        store.merge([snapshot(.working, reply: "Looking.", progress: TaskProgress(done: 0, total: 2, current: "Map it"), model: "claude-opus-5-5")], now: now)
        XCTAssertEqual(store[key]?.origin, .hooks)
        XCTAssertEqual(store[key]?.progress, TaskProgress(done: 0, total: 2, current: "Map it"))
        XCTAssertEqual(store[key]?.model, "claude-opus-5-5")
        // A reading without a list or a model does not forget the ones it had.
        store.merge([snapshot(.working, reply: "Looking.")], now: now)
        XCTAssertEqual(store[key]?.progress?.total, 2)
        XCTAssertEqual(store[key]?.model, "claude-opus-5-5")

        // The hook says "finished" with the closing words; a transcript one step behind does not take them back.
        store.apply(try event(HookEvent.stop, ["last_assistant_message": .string("Parser moved.")]), now: now)
        store.merge([snapshot(.working, reply: "Looking.")], now: now)
        XCTAssertEqual(store[key]?.lastReply, "Parser moved.")
        store.merge([snapshot(.waiting, reply: "Parser moved. Tests pass.")], now: now)
        XCTAssertEqual(store[key]?.lastReply, "Parser moved. Tests pass.", "once it has caught up, the transcript's fuller text is used")

        // Mid-turn with nothing said yet: the previous turn's words are not shown as this one's.
        store.apply(try event(HookEvent.userPromptSubmit, ["prompt": .string("Now the tests")]), now: now)
        store.merge([snapshot(.working)], now: now)
        XCTAssertNil(store[key]?.lastReply)
    }

    // MARK: Links into an agent's own app

    func testACodexDesktopConversationHasALinkOfItsOwn() {
        func session(_ id: String, source: String = "codex", host: SessionHost? = .codexDesktop, terminal: TerminalContext = TerminalContext()) -> Session {
            var session = Session(key: SessionKey(source: source, sessionID: id), cwd: "/tmp/shot", transcriptPath: nil, title: "t", startedAt: now,
                                  lastEventAt: now, phaseSince: now, activity: .waiting, phase: .waiting, terminal: terminal, ancestors: [], firstPrompt: nil)
            session.host = host
            return session
        }
        XCTAssertEqual(TerminalJump.threadURL(for: session("01a12fbc-aaaa-bbbb-cccc-0123456789ab"))?.absoluteString,
                       "codex://threads/01a12fbc-aaaa-bbbb-cccc-0123456789ab")
        XCTAssertNil(TerminalJump.threadURL(for: session("abc", host: nil)), "a session in a terminal is reached through its terminal")
        XCTAssertNil(TerminalJump.threadURL(for: session("abc", source: "claude", host: .claudeDesktop)), "no such link is known for other apps")
        XCTAssertNil(TerminalJump.threadURL(for: session("abc/../../etc?x=1")), "an id is only ever an id")
        XCTAssertNil(TerminalJump.threadURL(for: session("")))
    }

    // MARK: Settings

    func testWhatIsNewIsOffOrGentleUntilChosen() {
        let settings = NikoSettings()
        XCTAssertEqual(settings.completionStyle, .card)
        XCTAssertEqual(settings.replyLines, 1)
        XCTAssertFalse(settings.decisionHotkeys, "global keys are never claimed unasked")
        XCTAssertTrue(settings.quietWhenAway)
        XCTAssertEqual(settings.reminderMinutes, 0, "nothing repeats itself unless asked to")
        XCTAssertFalse(settings.codexLimitsLookup)
        XCTAssertEqual(NikoSettings.RowChip.allCases.filter(settings.showsChip), [.elapsed, .agent, .host, .branch])
        XCTAssertFalse(settings.showsChip(.model), "long, and rarely news")

        // Whoever had switched the notice off keeps it off; whoever had it on gets the card.
        XCTAssertEqual(NikoSettings(raw: ["showCompletionToast": .bool(false)]).completionStyle, .off)
        XCTAssertEqual(NikoSettings(raw: ["showCompletionToast": .bool(true)]).completionStyle, .card)
        var changed = NikoSettings()
        changed.completionStyle = .notice
        XCTAssertEqual(changed.completionStyle, .notice)
        XCTAssertTrue(changed.showCompletionToast)
        changed.completionStyle = .off
        XCTAssertFalse(changed.showCompletionToast)
        XCTAssertEqual(NikoSettings(raw: ["completionStyle": .string("hologram")]).completionStyle, .card)

        changed.replyLines = 9
        XCTAssertEqual(changed.replyLines, 3)
        changed.replyLines = -1
        XCTAssertEqual(changed.replyLines, 0)
        XCTAssertEqual(NikoSettings(raw: ["reminderMinutes": .int(7)]).reminderMinutes, 0, "only the offered waits")
        XCTAssertEqual(NikoSettings(raw: ["reminderMinutes": .int(5)]).reminderMinutes, 5)
        XCTAssertTrue(NikoSettings(raw: ["codexLimitsLookup": .bool(true)]).asksProvider("codex"))
        XCTAssertFalse(settings.asksProvider("claude") || settings.asksProvider("zcode") || settings.asksProvider("codex") || settings.asksProvider("gemini"))
    }
}
