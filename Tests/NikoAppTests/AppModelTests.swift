import XCTest
@testable import NikoCore
@testable import NikoIslandApp

@MainActor
final class RecordingSoundPlayer: SoundPlaying {
    var played: [SoundEvent] = []
    func play(_ event: SoundEvent) { played.append(event) }
}

@MainActor
final class RecordingNotifier: AttentionNotifying {
    var notes: [(kind: NikoSettings.EventKind, key: SessionKey, body: String)] = []
    var cleared: [SessionKey] = []
    func notify(kind: NikoSettings.EventKind, session: Session, body: String) { notes.append((kind, session.key, body)) }
    func clear(session: SessionKey) { cleared.append(session) }
}

/// The app model driven by the real bridge binary over the real socket.
@MainActor
final class AppModelTests: XCTestCase, @unchecked Sendable {   // main-actor confined; lets `async let` call helpers
    var scratch: Scratch!
    var model: AppModel!
    var notifier: RecordingNotifier!
    var jumps: [SessionKey] = []
    var attentionRequests = 0

    override func setUp() async throws {
        scratch = Scratch()
        try FileManager.default.createDirectory(at: scratch.file("home"), withIntermediateDirectories: true)
        model = AppModel(paths: scratch.paths, home: scratch.file("home"), log: .inMemory())
        notifier = RecordingNotifier()
        model.notifier = notifier
        jumps = []
        attentionRequests = 0
        model.jumpHandler = { [weak self] session in self?.jumps.append(session.key) }
        model.onAttentionNeeded = { [weak self] in self?.attentionRequests += 1 }
        XCTAssertTrue(model.start(usage: false))
    }

    override func tearDown() async throws {
        model.stop()
        model = nil
        scratch = nil
    }

    /// What the bridge sees of the terminal it runs in; a test sets it to stand in a tmux pane or a desktop app.
    private var terminalEnvironment: [String: String] = [:]

    private func bridge(_ stdin: String, _ arguments: [String] = ["--source", "claude"],
                        onStart: (@Sendable (Int32) -> Void)? = nil) async -> ProcessOutput {
        var environment = ["NIKO_ISLAND_HOME": scratch.paths.root.path]
        for (name, value) in terminalEnvironment { environment[name] = value }
        return await runProcessAsync(bridgeBinaryPath, arguments, stdin: Data(stdin.utf8), environment: environment, onStart: onStart)
    }

    private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func event(_ name: String, session: String = "s1", tool: String? = nil, command: String = "make test",
                       extra: String = "") -> String {
        var json = "{\"hook_event_name\":\"\(name)\",\"session_id\":\"\(session)\",\"cwd\":\"/tmp/demo-project\""
        if let tool { json += ",\"tool_name\":\"\(tool)\",\"tool_input\":{\"command\":\"\(command)\",\"file_path\":\"/tmp/demo-project/a.swift\"}" }
        return json + extra + "}"
    }

    private func behavior(_ output: ProcessOutput) -> String? {
        (try? JSONValue.parse(output.stdout))?.at("hookSpecificOutput", "decision", "behavior")?.stringValue
    }

    private let key = SessionKey(source: "claude", sessionID: "s1")

    // MARK: Sessions

    func testSessionLifecycleFromBridgeEvents() async throws {
        _ = await bridge(event("SessionStart"))
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"refactor the socket server\""))
        _ = await bridge(event("PreToolUse", tool: "Bash"))
        let appeared = await eventually { self.model.sessions.first?.activity.verb == "running" }
        XCTAssertTrue(appeared)
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(session.title, "demo-project · refactor socket server")
        XCTAssertEqual(session.activity, Activity(verb: "running", detail: "make test"))
        XCTAssertEqual(session.phase, .working)
        XCTAssertEqual(session.cwd, "/tmp/demo-project")
        XCTAssertEqual(model.badge, AppModel.Badge(active: 1, pending: 0))

        _ = await bridge(event("PostToolUse", tool: "Bash"))
        _ = await bridge(event("Stop"))
        let idle = await eventually { self.model.sessions.first?.phase == .waiting }
        XCTAssertTrue(idle)
        XCTAssertEqual(model.sessions.first?.activity, .waiting)
        XCTAssertEqual(notifier.notes.map(\.kind), [.idle])
        XCTAssertEqual(model.badge.active, 0)

        _ = await bridge(event("SessionEnd"))
        let gone = await eventually { self.model.sessions.isEmpty }
        XCTAssertTrue(gone)
        XCTAssertEqual(notifier.cleared.last, key)
    }

    // MARK: The four decisions (REVIEW "Approvals: all four decisions produce correct bridge output")

    func testAllowOnce() async throws {
        async let pendingBridge = bridge(event("PermissionRequest", tool: "Bash", command: "rm -rf build"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        let request = try XCTUnwrap(model.pending.first)
        XCTAssertFalse(request.isQuestion)
        XCTAssertEqual(request.summary, RequestSummary(event: request.event))
        XCTAssertEqual(request.summary.kind, .command)
        XCTAssertEqual(request.summary.detail, "rm -rf build")
        XCTAssertEqual(model.sessions.first?.phase, .needsAttention)
        XCTAssertEqual(model.badge.pending, 1)
        XCTAssertEqual(attentionRequests, 1, "the island is asked to show itself")
        XCTAssertEqual(notifier.notes.map(\.kind), [.permission])

        model.decide(request.id, .allowOnce)
        let output = await pendingBridge
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}\n")
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertEqual(model.sessions.first?.phase, .working)
        XCTAssertFalse(model.grantedSessions.contains(key), "allow once grants nothing for later")

        // The next identical request has to be asked again.
        async let again = bridge(event("PermissionRequest", tool: "Bash"))
        let askedAgain = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(askedAgain)
        model.decide(model.pending[0].id, .deny)
        _ = await again
    }

    func testAllowAlwaysForTool() async throws {
        async let first = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        model.decide(model.pending[0].id, .allowAlwaysTool)
        let firstOutput = await first
        XCTAssertEqual(behavior(firstOutput), "allow")
        XCTAssertTrue(model.grantedSessions.contains(key))
        XCTAssertEqual(model.grantSummary(for: key).tools, ["Bash"])

        let second = await bridge(event("PermissionRequest", tool: "Bash", command: "ls"))
        XCTAssertEqual(behavior(second), "allow", "same tool, same session: approved without asking")
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertEqual(attentionRequests, 1)

        async let otherTool = bridge(event("PermissionRequest", tool: "Edit"))
        let asked = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(asked, "a different tool still asks")
        async let otherSession = bridge(event("PermissionRequest", session: "s2", tool: "Bash"))
        let askedBoth = await eventually { self.model.pending.count == 2 }
        XCTAssertTrue(askedBoth, "a different session still asks")
        for request in model.pending { model.decide(request.id, .deny) }
        _ = await (otherTool, otherSession)
    }

    func testAllowAllForSession() async throws {
        async let first = bridge(event("PermissionRequest", tool: "Bash"))
        async let queued = bridge(event("PermissionRequest", tool: "Edit"))
        let shown = await eventually { self.model.pending.count == 2 }
        XCTAssertTrue(shown)
        let bashRequest = try XCTUnwrap(model.pending.first { $0.event.toolName == "Bash" })
        model.decide(bashRequest.id, .allowAllSession)
        let (firstOutput, queuedOutput) = await (first, queued)
        XCTAssertEqual(behavior(firstOutput), "allow")
        XCTAssertEqual(behavior(queuedOutput), "allow", "what was already queued for the session is settled too")
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertTrue(model.grantSummary(for: key).all)

        let later = await bridge(event("PermissionRequest", tool: "WebFetch"))
        XCTAssertEqual(behavior(later), "allow")

        model.revokeGrants(for: key)
        XCTAssertFalse(model.grantedSessions.contains(key))
        async let afterRevoke = bridge(event("PermissionRequest", tool: "Bash"))
        let asked = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(asked, "after revoking, requests are asked again")
        model.decide(model.pending[0].id, .allowAllSession)
        _ = await afterRevoke

        _ = await bridge(event("SessionEnd"))
        let ended = await eventually { self.model.sessions.isEmpty }
        XCTAssertTrue(ended)
        async let newSession = bridge(event("PermissionRequest", tool: "Bash"))
        let askedAfterEnd = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(askedAfterEnd, "grants die with the session")
        model.decide(model.pending[0].id, .deny)
        _ = await newSession
    }

    func testDenyAndBlock() async throws {
        async let denied = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        model.decide(model.pending[0].id, .deny)
        let output = await denied
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"deny\",\"message\":\"Denied in Niko Island\"}}}\n")
        XCTAssertEqual(model.sessions.first?.phase, .working)
        XCTAssertFalse(model.grantedSessions.contains(key))

        async let blocked = bridge(event("PermissionRequest", tool: "Bash"))
        let shownAgain = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shownAgain)
        model.decide(model.pending[0].id, .block)
        let blockedOutput = await blocked
        XCTAssertEqual((try? JSONValue.parse(blockedOutput.stdout))?.at("hookSpecificOutput", "decision", "interrupt")?.boolValue, true)
    }

    func testOpenInTerminalMakesNoDecision() async throws {
        async let passed = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        model.decide(model.pending[0].id, .passToTerminal)
        let output = await passed
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "", "no decision: the agent shows its own prompt")
        XCTAssertEqual(jumps, [key])
        XCTAssertEqual(model.sessions.first?.phase, .needsAttention, "the agent is still waiting on the user")
    }

    // MARK: Questions

    func testQuestionWizardAnswersArriveAsUpdatedInput() async throws {
        let question = """
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp/demo-project","tool_name":"AskUserQuestion",
         "tool_input":{"questions":[
           {"question":"Which database?","header":"DB","multiSelect":false,"options":[{"label":"Postgres","description":"server"},{"label":"SQLite"}]},
           {"question":"Which features?","header":"Feat","multiSelect":true,"options":[{"label":"Auth"},{"label":"Billing"},{"label":"Search"}]}]}}
        """
        // Even a blanket grant must not pre-answer a question.
        async let grantBridge = bridge(event("PermissionRequest", tool: "Bash"))
        let granted = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(granted)
        model.decide(model.pending[0].id, .allowAllSession)
        _ = await grantBridge

        async let asked = bridge(question)
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        let request = try XCTUnwrap(model.pending.first)
        XCTAssertTrue(request.isQuestion)
        XCTAssertEqual(request.questions.map(\.text), ["Which database?", "Which features?"])
        XCTAssertEqual(request.questions[0].options.map(\.label), ["Postgres", "SQLite"])
        XCTAssertEqual(request.questions[0].options[0].detail, "server")
        XCTAssertEqual(request.questions.map(\.multiSelect), [false, true])
        XCTAssertEqual(model.sessions.first?.activity.verb, "has a question")
        XCTAssertEqual(notifier.notes.last?.kind, .question)
        XCTAssertEqual(notifier.notes.last?.body, "Which database?")

        let selections = [
            QuestionAnswers.answer(for: request.questions[0], selected: ["SQLite"], custom: ""),
            QuestionAnswers.answer(for: request.questions[1], selected: ["Search", "Auth"], custom: ""),
        ]
        XCTAssertEqual(selections, [["SQLite"], ["Auth", "Search"]], "multi-select answers keep option order")
        model.decide(request.id, .answer(selections))

        let output = await asked
        let decision = try XCTUnwrap(JSONValue.parse(output.stdout).at("hookSpecificOutput", "decision"))
        XCTAssertEqual(decision["behavior"]?.stringValue, "allow")
        XCTAssertEqual(decision["updatedInput"]?["answers"]?["Which database?"]?.stringValue, "SQLite")
        XCTAssertEqual(decision["updatedInput"]?["answers"]?["Which features?"]?.stringValue, "Auth, Search")
        XCTAssertEqual(decision["updatedInput"]?["questions"]?.arrayValue?.count, 2)
    }

    func testWizardAnswerRules() {
        let single = AgentQuestion(id: 0, text: "q", header: nil, options: [.init(label: "A", detail: nil), .init(label: "B", detail: nil)], multiSelect: false)
        let multi = AgentQuestion(id: 1, text: "q", header: nil, options: single.options, multiSelect: true)
        XCTAssertEqual(QuestionAnswers.answer(for: single, selected: ["B"], custom: ""), ["B"])
        XCTAssertEqual(QuestionAnswers.answer(for: single, selected: ["B"], custom: "  my own  "), ["my own"], "free text replaces a single choice")
        XCTAssertEqual(QuestionAnswers.answer(for: multi, selected: ["B", "A"], custom: "C"), ["A", "B", "C"])
        XCTAssertEqual(QuestionAnswers.answer(for: multi, selected: [], custom: "   "), [])
    }

    // MARK: Requests that go away on their own

    func testWithdrawnRequestDisappears() async throws {
        let model = self.model!
        async let killed = bridge(event("PermissionRequest", tool: "Bash")) { pid in
            // The agent gives up (user answered in the terminal, or pressed Esc).
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { kill(pid, SIGTERM) }
        }
        let shown = await eventually { model.pending.count == 1 }
        XCTAssertTrue(shown)
        let output = await killed
        XCTAssertEqual(output.status, 0)
        let withdrawn = await eventually { model.pending.isEmpty }
        XCTAssertTrue(withdrawn, "the card must not outlive the request")
        XCTAssertEqual(model.sessions.first?.phase, .working)
        XCTAssertEqual(model.badge.pending, 0)
    }

    func testQuitMidRequestReleasesTheAgent() async throws {
        async let waiting = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        model.stop()   // app quits (or crashes) while the agent is blocked on us
        let output = await waiting
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout + output.stderr, "", "no decision was made; the agent falls back to its own prompt")
        XCTAssertLessThan(output.duration, 5)

        // Relaunch: a fresh instance takes over the same socket path and serves new requests.
        let relaunched = AppModel(paths: scratch.paths, home: scratch.file("home"), log: .inMemory())
        XCTAssertTrue(relaunched.start(usage: false))
        defer { relaunched.stop() }
        async let next = bridge(event("PermissionRequest", tool: "Bash"))
        let shownAgain = await eventually { relaunched.pending.count == 1 }
        XCTAssertTrue(shownAgain)
        relaunched.decide(relaunched.pending[0].id, .allowOnce)
        let nextOutput = await next
        XCTAssertEqual(behavior(nextOutput), "allow")
    }

    func testPendingRequestsNeverExpireOnTheirOwn() async throws {
        async let waiting = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        // Unrelated activity and time passing must not resolve or drop the card.
        _ = await bridge(event("Notification", session: "other", extra: ",\"message\":\"hello\""))
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(model.pending.count, 1)
        model.dismiss(key)
        XCTAssertEqual(model.pending.count, 1, "a session with a pending request cannot be dismissed")
        model.decide(model.pending[0].id, .deny)
        _ = await waiting
    }

    // MARK: Settings and instances

    func testNotificationsFollowSettings() async throws {
        model.settings.setNotifications(false, for: .idle)
        _ = await bridge(event("Stop"))
        let idle = await eventually { self.model.sessions.first?.phase == .waiting }
        XCTAssertTrue(idle)
        XCTAssertTrue(notifier.notes.isEmpty)
        XCTAssertFalse(NikoSettings.load(paths: scratch.paths).notificationsEnabled(for: .idle), "settings are persisted")
        model.settings.setNotifications(true, for: .idle)
        _ = await bridge(event("UserPromptSubmit"))
        _ = await bridge(event("Stop"))
        let notified = await eventually { self.notifier.notes.count == 1 }
        XCTAssertTrue(notified)
    }

    // MARK: Sounds (SPEC §4: none by default)

    func testSoundsAreSilentUntilSwitchedOn() async throws {
        let sounds = RecordingSoundPlayer()
        model.soundPlayer = sounds
        _ = await bridge(event("UserPromptSubmit"))
        _ = await bridge(event("Stop"))
        let idle = await eventually { self.model.sessions.first?.phase == .waiting }
        XCTAssertTrue(idle)
        XCTAssertTrue(sounds.played.isEmpty, "nothing plays out of the box")

        model.settings.soundsEnabled = true
        _ = await bridge(event("UserPromptSubmit"))
        _ = await bridge(event("Stop"))
        let finished = await eventually { sounds.played == [.completed] }
        XCTAssertTrue(finished, "\(sounds.played): 'started' stays off until it is ticked, 'completed' is on")

        model.settings.setSound(true, for: .started)
        model.settings.setSound(false, for: .completed)
        sounds.played = []
        _ = await bridge(event("UserPromptSubmit"))
        _ = await bridge(event("Stop"))
        let started = await eventually { sounds.played == [.started] }
        XCTAssertTrue(started, "\(sounds.played)")
        XCTAssertTrue(NikoSettings.load(paths: scratch.paths).soundsEnabled)
    }

    func testAttentionErrorAndLimitCues() async throws {
        let sounds = RecordingSoundPlayer()
        model.soundPlayer = sounds
        model.settings.soundsEnabled = true

        async let waiting = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        XCTAssertEqual(sounds.played, [.attention])
        model.decide(model.pending[0].id, .deny)
        _ = await waiting

        _ = await bridge(event("StopFailure", extra: ",\"error\":\"overloaded\""))
        let failed = await eventually { sounds.played.contains(.error) }
        XCTAssertTrue(failed)
        XCTAssertEqual(model.sessions.first?.activity, Activity(verb: "hit an error", detail: "overloaded"))
        XCTAssertEqual(model.completion?.failed, true, "an error has something to say, so it is said on a card")
        XCTAssertEqual(model.completion?.reply, "overloaded")
        model.settings.completionStyle = .notice
        _ = await bridge(event("UserPromptSubmit"))
        _ = await bridge(event("StopFailure", extra: ",\"error\":\"overloaded\""))
        let noticed = await eventually { self.model.toast?.kind == .failed }
        XCTAssertTrue(noticed)
        XCTAssertNil(model.completion)

        // One warning when a window crosses 90 %, none while it stays there.
        var usage = UsageSnapshot()
        usage.rateLimits = [RateLimitWindow(id: "five_hour", usedPercent: 60, resetsAt: nil)]
        model.usage = usage
        usage.rateLimits[0].usedPercent = 93
        model.usage = usage
        usage.rateLimits[0].usedPercent = 96
        model.usage = usage
        XCTAssertEqual(sounds.played.filter { $0 == .limit }.count, 1)
    }

    func testRepeatedCuesAreThrottled() {
        let sounds = RecordingSoundPlayer()
        model.soundPlayer = sounds
        model.settings.soundsEnabled = true
        let t0 = Date()
        model.play(.attention, now: t0)
        model.play(.attention, now: t0.addingTimeInterval(0.4))
        model.play(.completed, now: t0.addingTimeInterval(0.5))
        model.play(.attention, now: t0.addingTimeInterval(2))
        XCTAssertEqual(sounds.played, [.attention, .completed, .attention])
    }

    // MARK: Island state

    func testIslandOpensForARequestAndClosesWhenItIsSettled() async throws {
        XCTAssertFalse(model.isExpanded)
        async let waiting = bridge(event("PermissionRequest", tool: "Bash"))
        let opened = await eventually { self.model.isExpanded }
        XCTAssertTrue(opened, "a request opens the island")
        XCTAssertEqual(model.expandReason, .attention)
        XCTAssertEqual(model.focusedRequest?.id, model.pending.first?.id)
        model.expand(.hover)
        XCTAssertEqual(model.expandReason, .attention, "a hover never downgrades an open island")
        model.decide(model.pending[0].id, .allowOnce)
        _ = await waiting
        XCTAssertFalse(model.isExpanded, "opened for the request, so it closes with it")

        // Opened by the user: deciding does not close it.
        model.expand(.click)
        async let second = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        XCTAssertEqual(model.expandReason, .attention)
        model.collapse()
        XCTAssertEqual(model.pending.count, 1, "putting the island away decides nothing")
        model.toggleExpanded()
        XCTAssertEqual(model.expandReason, .click)
        model.decide(model.pending[0].id, .deny)
        _ = await second
        XCTAssertTrue(model.isExpanded)
    }

    func testAttentionCanBeToldNotToOpenTheIsland() async throws {
        model.settings.expandOnAttention = false
        async let waiting = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        XCTAssertFalse(model.isExpanded)
        XCTAssertEqual(IslandGlance(model: model).tone, .attention)
        XCTAssertEqual(IslandGlance(model: model).text, "demo-project needs you")
        model.decide(model.pending[0].id, .deny)
        _ = await waiting
    }

    func testFocusMovesBetweenQueuedRequests() async throws {
        async let first = bridge(event("PermissionRequest", session: "s1", tool: "Bash"))
        let one = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(one)
        async let second = bridge(event("PermissionRequest", session: "s2", tool: "Edit"))
        let two = await eventually { self.model.pending.count == 2 }
        XCTAssertTrue(two)
        XCTAssertEqual(model.focusedRequest?.event.sessionID, "s1", "oldest first")
        model.focusedRequestID = model.pending[1].id
        XCTAssertEqual(model.focusedRequest?.event.sessionID, "s2")
        model.decide(model.pending[1].id, .deny)
        XCTAssertEqual(model.focusedRequest?.event.sessionID, "s1", "focus falls back to what is still waiting")
        XCTAssertTrue(model.isExpanded, "still one request open")
        model.decide(model.pending[0].id, .deny)
        _ = await (first, second)
        XCTAssertNil(model.focusedRequest)
    }

    func testCompletionToastAndGlance() async throws {
        XCTAssertEqual(IslandGlance(model: model).tone, .idle)
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"ship the fix\""))
        _ = await bridge(event("PreToolUse", tool: "Bash"))
        let working = await eventually { IslandGlance(model: self.model).tone == .working }
        XCTAssertTrue(working)
        XCTAssertEqual(IslandGlance(model: model).text, "running make test")
        _ = await bridge(event("Stop"))
        let toasted = await eventually { self.model.toast != nil }
        XCTAssertTrue(toasted)
        XCTAssertEqual(model.toast, AppModel.Toast(key: key, title: "demo-project · ship fix", kind: .completed))
        XCTAssertEqual(IslandGlance(model: model).tone, .done)
        model.expand(.click)
        XCTAssertNil(model.toast, "opening the island replaces the notice")
        model.collapse()
        XCTAssertEqual(IslandGlance(model: model).tone, .waiting)

        model.settings.showCompletionToast = false
        _ = await bridge(event("UserPromptSubmit"))
        _ = await bridge(event("Stop"))
        let idle = await eventually { self.model.sessions.first?.phase == .waiting }
        XCTAssertTrue(idle)
        XCTAssertNil(model.toast)
    }

    // MARK: A finished turn, said on a card

    private let closing = ",\"last_assistant_message\":\"Fixed the **race** in `Hub.swift`.\\n\\nTests pass.\""

    /// One whole turn; returns once the session is waiting again.
    private func turn(prompt: String = "ship the fix", closing words: String? = nil) async {
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"\(prompt)\""))
        let working = await eventually { self.model.sessions.first { $0.key == self.key }?.phase == .working }
        XCTAssertTrue(working)
        _ = await bridge(event("Stop", extra: words ?? closing))
        let waiting = await eventually { self.model.sessions.first { $0.key == self.key }?.phase == .waiting }
        XCTAssertTrue(waiting)
    }

    func testAFinishedTurnComesDownAsACardWithTheAgentsLastWords() async throws {
        XCTAssertEqual(model.settings.completionStyle, .card)
        await turn()
        let card = try XCTUnwrap(model.completion)
        XCTAssertEqual(card.key, key)
        XCTAssertEqual(card.reply, "Fixed the **race** in `Hub.swift`.\n\nTests pass.")
        XCTAssertEqual(card.project, "demo-project")
        XCTAssertEqual(card.title, "ship the fix")
        XCTAssertFalse(card.failed)
        XCTAssertNil(model.toast, "the card says it; a notice as well would say it twice")
        XCTAssertFalse(model.isExpanded, "a card is not the island opening")
        // The agent's light markup is drawn, not shown as asterisks and backticks.
        XCTAssertEqual(String(ReplyText.attributed(card.reply ?? "").characters), "Fixed the race in Hub.swift.\n\nTests pass.")
        XCTAssertEqual(model.sessions.first?.replyLine, "Fixed the race in Hub.swift. Tests pass.")
        XCTAssertEqual(ReplyText.flattened(String(repeating: "word ", count: 100), limit: 40).count, 40)

        // A click goes to the session and puts the card away.
        model.openCompletion()
        XCTAssertNil(model.completion)
        XCTAssertEqual(jumps, [key])

        // Asking for more makes the card old news, and the old words are not this turn's.
        await turn()
        XCTAssertNotNil(model.completion)
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"and the docs\""))
        let cleared = await eventually { self.model.completion == nil }
        XCTAssertTrue(cleared)
        XCTAssertNil(model.sessions.first?.lastReply)

        // Opening the island puts it away too: the list says the same and more.
        _ = await bridge(event("Stop", extra: closing))
        let again = await eventually { self.model.completion != nil }
        XCTAssertTrue(again)
        model.expand(.click)
        XCTAssertNil(model.completion)
        model.collapse()

        // The ✕, and a pointer resting on the card.
        await turn()
        model.holdCompletion(true)
        model.holdCompletion(false)
        XCTAssertNotNil(model.completion)
        model.dismissCompletion()
        XCTAssertNil(model.completion)
        XCTAssertTrue(jumps.count == 1, "putting a card away goes nowhere")
    }

    func testACardIsOnlyShownWhereItHelps() async throws {
        // Chosen as a short notice.
        model.settings.completionStyle = .notice
        await turn()
        XCTAssertNil(model.completion)
        XCTAssertEqual(model.toast?.kind, .completed)

        // Chosen as nothing.
        model.settings.completionStyle = .off
        await turn()
        XCTAssertNil(model.completion)
        XCTAssertNil(model.toast)

        // Nothing to say: the short notice does.
        model.settings.completionStyle = .card
        await turn(closing: "")
        XCTAssertNil(model.completion)
        XCTAssertEqual(model.toast?.kind, .completed)

        // The user is already looking at that session.
        model.isFrontmost = { $0.key == self.key }
        await turn()
        XCTAssertNil(model.completion)
        XCTAssertNotNil(model.toast)
        model.isFrontmost = { _ in false }

        // No island on screen to show it on.
        model.islandIsVisible = { false }
        await turn()
        XCTAssertNil(model.completion)
        model.islandIsVisible = { true }

        // The island is open: the row itself says it.
        model.expand(.click)
        await turn()
        XCTAssertNil(model.completion)
        XCTAssertNil(model.toast)
        model.collapse()

        // Something is waiting for a decision: that comes first.
        model.settings.expandOnAttention = false
        async let waiting = bridge(event("PermissionRequest", session: "s2", tool: "Bash"))
        let asked = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(asked)
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"ship the fix\""))
        _ = await bridge(event("Stop", extra: closing))
        let stopped = await eventually { self.model.sessions.first { $0.key == self.key }?.phase == .waiting }
        XCTAssertTrue(stopped)
        XCTAssertNil(model.completion)
        model.decide(model.pending[0].id, .deny)
        _ = await waiting

        // Back to normal, the card is back.
        await turn()
        XCTAssertNotNil(model.completion)
    }

    func testACardWaitsAMomentForWordsThatComeFromTheTranscript() async throws {
        // With sessions being read from disk, a hook's "finished" is ahead of the transcript by a moment.
        model.stop()
        XCTAssertTrue(model.start(usage: false, scout: true))
        model.completionSettleDelay = 0.4
        let transcript = ",\"transcript_path\":\"/tmp/demo-project/s1.jsonl\""
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"ship the fix\"" + transcript))
        _ = await bridge(event("Stop", extra: transcript))
        let stopped = await eventually { self.model.sessions.first?.phase == .waiting }
        XCTAssertTrue(stopped)
        XCTAssertNil(model.completion, "nothing to say yet")
        XCTAssertNil(model.toast, "and no notice that a card would then have to replace")
        // The transcript catches up inside the wait.
        model.mergeTranscripts([TranscriptSnapshot(key: key, path: "/tmp/demo-project/s1.jsonl", cwd: "/tmp/demo-project", firstPrompt: "ship the fix",
                                                   lastPrompt: "ship the fix", lastReply: "Shipped.", phase: .waiting, activity: .waiting, updatedAt: Date())])
        let shown = await eventually { self.model.completion != nil }
        XCTAssertTrue(shown)
        XCTAssertEqual(model.completion?.reply, "Shipped.")

        // Asked something new before the wait is over: there is nothing finished to show.
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"and the docs\"" + transcript))
        _ = await bridge(event("Stop", extra: transcript))
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"wait, the tests first\"" + transcript))
        let working = await eventually { self.model.sessions.first?.phase == .working }
        XCTAssertTrue(working)
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertNil(model.completion)

        // Words that come with the event need no waiting at all.
        model.completionSettleDelay = 30
        _ = await bridge(event("Stop", extra: closing + transcript))
        let atOnce = await eventually(timeout: 3) { self.model.completion != nil }
        XCTAssertTrue(atOnce)
    }

    // MARK: Back at the screen

    func testWhatEndedWhileNobodyWasThereIsSaidOnceOnReturn() async throws {
        model.isAway = true
        await turn(prompt: "ship the fix")
        _ = await bridge(event("UserPromptSubmit", session: "s2", extra: ",\"prompt\":\"write the docs\""))
        _ = await bridge(event("StopFailure", session: "s2", extra: ",\"error\":\"overloaded\""))
        _ = await bridge(event("UserPromptSubmit", session: "s3", extra: ",\"prompt\":\"tidy up\""))
        _ = await bridge(event("Stop", session: "s3", extra: closing))
        // One of them is asked for more before anybody is back: it has not finished any more.
        _ = await bridge(event("UserPromptSubmit", session: "s3", extra: ",\"prompt\":\"and the tests\""))
        let settled = await eventually { self.model.sessions.count == 3 && self.model.sessions.filter { $0.phase == .waiting }.count == 2 }
        XCTAssertTrue(settled)
        XCTAssertNil(model.completion)
        XCTAssertNil(model.recap, "nothing is said to an empty room")

        model.isAway = false
        let recap = try XCTUnwrap(model.recap)
        XCTAssertEqual(recap.items.map(\.key.sessionID), ["s1", "s2"])
        XCTAssertEqual(recap.items.map(\.failed), [false, true])
        XCTAssertEqual(recap.items.first?.title, "ship the fix")
        XCTAssertEqual(recap.items.first?.project, "demo-project")
        XCTAssertNil(model.completion, "one card for all of it, not one each")

        // A line of it goes to that session; the rest goes with it.
        model.openRecap(SessionKey(source: "claude", sessionID: "s2"))
        XCTAssertNil(model.recap)
        XCTAssertEqual(jumps.map(\.sessionID), ["s2"])

        // Nothing ended: nothing to say. And coming back twice says it once.
        model.isAway = true
        model.isAway = false
        XCTAssertNil(model.recap)

        // Opening the island puts it away; "nothing" as the way to hear of finished turns means no recap either.
        model.isAway = true
        await turn()
        model.isAway = false
        XCTAssertNotNil(model.recap)
        model.holdRecap(true)
        model.holdRecap(false)
        model.expand(.click)
        XCTAssertNil(model.recap)
        model.collapse()
        model.settings.completionStyle = .off
        model.isAway = true
        await turn()
        model.isAway = false
        XCTAssertNil(model.recap)
    }

    // MARK: A line to the phone

    private final class Outbox: @unchecked Sendable {
        private let lock = NSLock()
        private var _sent: [JSONValue] = []
        private var _hosts: [String] = []
        var sent: [JSONValue] { lock.lock(); defer { lock.unlock() }; return _sent }
        var hosts: [String] { lock.lock(); defer { lock.unlock() }; return _hosts }
        func take(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            _hosts.append(request.url?.host ?? "?")
            if let body = request.httpBody, let json = try? JSONValue.parse(body) { _sent.append(json) }
        }
    }

    func testThePhoneIsOnlyTextedWhenAskedAndOnlyAsMuchAsAsked() async throws {
        let outbox = Outbox()
        model.makePushClient = { PushClient(transport: { request in outbox.take(request); return (Data(), 200) }, key: { "device-key" }) }
        model.settings.expandOnAttention = false

        // Out of the box: nothing, whatever happens.
        XCTAssertFalse(model.settings.pushEnabled)
        model.isAway = true
        await turn()
        XCTAssertTrue(outbox.sent.isEmpty)

        // Switched on but without a key: still nothing.
        model.settings.pushEnabled = true
        await turn()
        XCTAssertTrue(outbox.sent.isEmpty)

        // With a key, and nobody at the screen: one line per moment, saying who, where and what kind. Not what.
        model.hasPushKey = true
        async let waiting = bridge(event("PermissionRequest", tool: "Bash", command: "git push --force"))
        let asked = await eventually { outbox.sent.count == 1 }
        XCTAssertTrue(asked)
        XCTAssertEqual(outbox.sent[0]["title"]?.stringValue, "Claude Code · demo-project")
        XCTAssertEqual(outbox.sent[0]["body"]?.stringValue, "Needs your decision")
        XCTAssertEqual(outbox.sent[0]["device_key"]?.stringValue, "device-key")
        XCTAssertEqual(outbox.hosts, ["api.day.app"])
        XCTAssertFalse(outbox.sent[0].serialized(.compact).contains("git push"), "what is being asked stays on this Mac")
        model.decide(model.pending[0].id, .deny)
        _ = await waiting

        // "Say what it is about" adds the tool and the command, or the first line of the reply.
        model.settings.pushDetails = true
        async let second = bridge(event("PermissionRequest", session: "s2", tool: "Bash", command: "git push --force"))
        let detailed = await eventually { outbox.sent.count == 2 }
        XCTAssertTrue(detailed)
        XCTAssertEqual(outbox.sent[1]["body"]?.stringValue, "Needs your decision: Bash: git push --force")
        model.decide(model.pending[0].id, .deny)
        _ = await second
        await turn()
        let finished = await eventually { outbox.sent.count == 3 }
        XCTAssertTrue(finished)
        XCTAssertEqual(outbox.sent[2]["body"]?.stringValue, "Fixed the race in Hub.swift. Tests pass.")
        model.settings.pushDetails = false

        // Not for finished turns, if that is too much.
        model.settings.pushWhenFinished = false
        await turn()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(outbox.sent.count, 3)
        model.settings.pushWhenFinished = true

        // At the Mac the island is how you are told...
        model.isAway = false
        model.dismissRecap()
        await turn()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(outbox.sent.count, 3)
        // ...unless the phone is wanted there too. (A different session: the same line about the same one is not sent twice in half a minute.)
        model.settings.pushOnlyWhenAway = false
        _ = await bridge(event("UserPromptSubmit", session: "s4", extra: ",\"prompt\":\"one more\""))
        _ = await bridge(event("Stop", session: "s4", extra: closing))
        let atDesk = await eventually { outbox.sent.count == 4 }
        XCTAssertTrue(atDesk)
        XCTAssertEqual(outbox.sent[3]["body"]?.stringValue, "Finished")

        // Quiet hours hold lines back as they hold sounds back.
        let minute = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        model.settings.quietFrom = minute / 30 * 30
        model.settings.quietUntil = (minute / 30 * 30 + 60) % 1440
        model.settings.quietHoursEnabled = true
        _ = await bridge(event("UserPromptSubmit", session: "s5", extra: ",\"prompt\":\"late one\""))
        _ = await bridge(event("Stop", session: "s5", extra: closing))
        let late = await eventually { self.model.sessions.first { $0.key.sessionID == "s5" }?.phase == .waiting }
        XCTAssertTrue(late)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(outbox.sent.count, 4)
        let sounds = RecordingSoundPlayer()
        model.soundPlayer = sounds
        model.settings.soundsEnabled = true
        model.play(.completed)
        XCTAssertTrue(sounds.played.isEmpty, "quiet hours are quiet")
        model.settings.quietHoursEnabled = false
        model.play(.completed)
        XCTAssertEqual(sounds.played, [.completed])

        // The test line goes out whatever the other switches say, and how it went is kept for Settings.
        model.sendTestPush()
        let tested = await eventually { outbox.sent.count == 5 && self.model.pushStatus == .sent }
        XCTAssertTrue(tested)
        XCTAssertEqual(outbox.sent[4]["title"]?.stringValue, "Niko Island")
    }

    // MARK: Claude Code looks for itself

    func testClaudeCodeIsAskedToLookOnlyWhenSwitchedOnAndNotTooOften() async throws {
        final class Asked: @unchecked Sendable {
            private let lock = NSLock()
            private var _count = 0
            var outcome = ClaudeCodeUsage.Outcome.fresh
            var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
            func ask() -> ClaudeCodeUsage.Outcome { lock.lock(); defer { lock.unlock() }; _count += 1; return outcome }
        }
        let asked = Asked()
        model.claudeAsker = { _, _ in asked.ask() }
        let start = Date()

        model.askClaudeCode(force: true)
        XCTAssertEqual(asked.count, 0, "off until switched on, whatever is pressed")

        // Switching it on asks at once.
        model.settings.claudeAsksItself = true
        let first = await eventually { asked.count == 1 && self.model.claudeLookup == .fresh && !self.model.claudeIsLooking }
        XCTAssertTrue(first)

        // Not again for five minutes; and after that only while a Claude Code session is listed.
        model.askClaudeCode(now: start.addingTimeInterval(200))
        model.askClaudeCode(now: start.addingTimeInterval(400))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(asked.count, 1, "nobody is using Claude Code: the figures can wait")
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"ship the fix\""))
        let listed = await eventually { self.model.sessions.contains { $0.source == "claude" } }
        XCTAssertTrue(listed)
        model.askClaudeCode(now: start.addingTimeInterval(200))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(asked.count, 1, "too soon")
        model.askClaudeCode(now: start.addingTimeInterval(400))
        let second = await eventually { asked.count == 2 && !self.model.claudeIsLooking }
        XCTAssertTrue(second)

        // "Check now" asks after twenty seconds, session or not, and how it went is kept for the page that shows it.
        asked.outcome = .unchanged
        model.claudeLookedAt = Date().addingTimeInterval(-25)
        model.refreshProviderLimits()
        let third = await eventually { asked.count == 3 && self.model.claudeLookup == .unchanged }
        XCTAssertTrue(third)
        model.refreshProviderLimits()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(asked.count, 3, "pressed again at once: not asked again")

        model.settings.claudeAsksItself = false
        XCTAssertNil(model.claudeLookup)
        model.claudeLookedAt = nil
        model.askClaudeCode(force: true)
        XCTAssertEqual(asked.count, 3)
    }

    // MARK: A banner that can be answered, a key that goes where you are needed

    func testARequestCanBeAnsweredFromItsBannerAndAKeyGoesToWhatNeedsYou() async throws {
        model.settings.expandOnAttention = false
        XCTAssertFalse(model.jumpToWhatNeedsMe(), "nothing needs anybody")

        async let first = bridge(event("PermissionRequest", tool: "Bash", command: "git push"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        // The key opens the island on the request, and decides nothing.
        XCTAssertTrue(model.jumpToWhatNeedsMe())
        XCTAssertTrue(model.isExpanded)
        XCTAssertEqual(model.focusedRequest?.id, model.pending.first?.id)
        XCTAssertEqual(model.pending.count, 1)
        // "Allow once" on the banner answers that session's request.
        XCTAssertFalse(model.decide(forSession: SessionKey(source: "claude", sessionID: "someone-else"), .allow))
        XCTAssertTrue(model.decide(forSession: key, .allow))
        let allowed = await first
        XCTAssertEqual(behavior(allowed), "allow")
        XCTAssertFalse(model.decide(forSession: key, .deny), "the request has gone: nothing happens")

        async let second = bridge(event("PermissionRequest", tool: "Bash"))
        let again = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(again)
        XCTAssertTrue(model.decide(forSession: key, .deny))
        let denied = await second
        XCTAssertEqual(behavior(denied), "deny")

        // A question is not answered from a banner.
        let question = """
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp/demo-project","tool_name":"AskUserQuestion",
         "tool_input":{"questions":[{"question":"Which database?","header":"DB","multiSelect":false,"options":[{"label":"Postgres"},{"label":"SQLite"}]}]}}
        """
        async let asking = bridge(question)
        let asked = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(asked)
        XCTAssertFalse(model.decide(forSession: key, .allow))
        XCTAssertEqual(model.pending.count, 1)
        model.decide(model.pending[0].id, .passToTerminal)
        _ = await asking

        // With no request, the key goes to the session that stopped last.
        model.collapse()
        _ = await bridge(event("UserPromptSubmit", session: "older", extra: ",\"prompt\":\"one\""))
        _ = await bridge(event("Stop", session: "older"))
        _ = await bridge(event("UserPromptSubmit", session: "newer", extra: ",\"prompt\":\"two\""))
        _ = await bridge(event("Stop", session: "newer"))
        let stopped = await eventually { self.model.sessions.filter { $0.phase == .waiting }.count >= 2 }
        XCTAssertTrue(stopped)
        jumps = []
        // The session whose question was handed to its terminal still needs an answer there: it comes first.
        XCTAssertTrue(model.jumpToWhatNeedsMe())
        XCTAssertEqual(jumps.map(\.sessionID), ["s1"])
        model.dismiss(key)
        XCTAssertTrue(model.jumpToWhatNeedsMe())
        XCTAssertEqual(jumps.map(\.sessionID), ["s1", "newer"])
        XCTAssertFalse(NikoSettings().jumpHotkey, "a global key is not claimed unasked")
        XCTAssertEqual(Hotkey.Key.jump.display, "⌃⌥J")
    }

    func testARequestLeftWaitingAlsoGoesToThePhone() async throws {
        let outbox = Outbox()
        model.makePushClient = { PushClient(transport: { request in outbox.take(request); return (Data(), 200) }, key: { "device-key" }) }
        model.settings.expandOnAttention = false
        model.settings.pushEnabled = true
        model.hasPushKey = true
        XCTAssertTrue(model.settings.pushOnlyWhenAway)
        async let waiting = bridge(event("PermissionRequest", tool: "Bash", command: "git push"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(outbox.sent.isEmpty, "at the Mac, the island is how you are told")
        let asked = model.pending[0].receivedAt

        // Left alone for the wait the user chose: whoever it is for is evidently not looking at this screen.
        model.settings.reminderMinutes = 5
        model.remindAboutWaiting(now: asked.addingTimeInterval(301))
        let escalated = await eventually { outbox.sent.count == 1 }
        XCTAssertTrue(escalated)
        XCTAssertEqual(outbox.sent[0]["body"]?.stringValue, "Needs your decision")
        model.remindAboutWaiting(now: asked.addingTimeInterval(400))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(outbox.sent.count, 1, "one line per reminder, not one per tick")
        model.remindAboutWaiting(now: asked.addingTimeInterval(610))
        let twice = await eventually { outbox.sent.count == 2 }
        XCTAssertTrue(twice)
        model.decide(model.pending[0].id, .deny)
        _ = await waiting
    }

    // MARK: A limit that opens again

    func testALimitThatWasUsedUpIsAnnouncedOnceWhenItResets() async throws {
        let sounds = RecordingSoundPlayer()
        model.soundPlayer = sounds
        model.settings.soundsEnabled = true
        let now = Date()
        func usage(fiveHour: Double, weekly: Double, fiveHourResets: TimeInterval = 600, weeklyResets: TimeInterval = 86_400) -> UsageSnapshot {
            var snapshot = UsageSnapshot()
            var claude = UsageSnapshot.AgentUsage(id: "claude")
            claude.limits = [RateLimitWindow(id: "five_hour", usedPercent: fiveHour, resetsAt: now.addingTimeInterval(fiveHourResets)),
                             RateLimitWindow(id: "seven_day", usedPercent: weekly, resetsAt: now.addingTimeInterval(weeklyResets))]
            snapshot.agents = [UsageSnapshot.AgentUsage(id: "all"), claude]
            return snapshot
        }
        // Not full: nothing to wait for, nothing announced later.
        model.usage = usage(fiveHour: 80, weekly: 18)
        model.noteLimitResets(now: now.addingTimeInterval(700))
        XCTAssertNil(model.toast)

        // Used up. Before the reset: silence. At the reset: once.
        model.usage = usage(fiveHour: 100, weekly: 18)
        model.noteLimitResets(now: now.addingTimeInterval(300))
        XCTAssertNil(model.toast)
        sounds.played = []
        model.noteLimitResets(now: now.addingTimeInterval(601))
        XCTAssertEqual(model.toast?.kind, .limitReset)
        XCTAssertEqual(model.toast?.title, "Claude Code's limit has reset")
        XCTAssertEqual(model.toast?.key.source, "claude")
        XCTAssertEqual(IslandGlance(model: model).tone, .done)
        XCTAssertEqual(sounds.played, [.completed])
        model.dismissToast()
        model.noteLimitResets(now: now.addingTimeInterval(700))
        XCTAssertNil(model.toast, "said once")

        // Two windows used up: the agent can only work again when both have opened.
        model.usage = usage(fiveHour: 100, weekly: 100, fiveHourResets: 900, weeklyResets: 1800)
        model.noteLimitResets(now: now.addingTimeInterval(901))
        XCTAssertNil(model.toast, "the week is still full")
        model.noteLimitResets(now: now.addingTimeInterval(1801))
        XCTAssertEqual(model.toast?.kind, .limitReset)
        model.dismissToast()

        // Nobody at the screen: it is said when somebody is back.
        model.usage = usage(fiveHour: 100, weekly: 18, fiveHourResets: 2400)
        model.isAway = true
        sounds.played = []
        model.noteLimitResets(now: now.addingTimeInterval(2401))
        XCTAssertNil(model.toast)
        XCTAssertTrue(sounds.played.isEmpty)
        model.isAway = false
        XCTAssertEqual(model.toast?.kind, .limitReset)
        model.dismissToast()

        // A reset that passed while the Mac slept for hours is not news any more.
        model.usage = usage(fiveHour: 100, weekly: 18, fiveHourResets: 3000)
        model.noteLimitResets(now: now.addingTimeInterval(3000 + 7200))
        XCTAssertNil(model.toast)

        // And to the phone, where that is wanted.
        let outbox = Outbox()
        model.makePushClient = { PushClient(transport: { request in outbox.take(request); return (Data(), 200) }, key: { "device-key" }) }
        model.settings.pushEnabled = true
        model.settings.pushOnlyWhenAway = false
        model.hasPushKey = true
        model.usage = usage(fiveHour: 100, weekly: 18, fiveHourResets: 4000)
        model.noteLimitResets(now: now.addingTimeInterval(4001))
        let sent = await eventually { outbox.sent.count == 1 }
        XCTAssertTrue(sent)
        XCTAssertEqual(outbox.sent[0]["title"]?.stringValue, "Claude Code")
        XCTAssertEqual(outbox.sent[0]["body"]?.stringValue, "Its limit has reset. It can work again.")
    }

    // MARK: Answering from the island

    func testAFollowUpGoesToTheTerminalOnlyWhenThereIsAWayIn() async throws {
        final class Typed: @unchecked Sendable {
            private let lock = NSLock()
            private var _lines: [String] = []
            var accepts = true
            var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
            func take(_ line: String) -> Bool { lock.lock(); defer { lock.unlock() }; _lines.append(line); return accepts }
        }
        let typed = Typed()
        model.replySender = { _, line in typed.take(line) }
        terminalEnvironment = ["TMUX": "/private/tmp/tmux-501/default,4242,0", "TMUX_PANE": "%3", "TERM_PROGRAM": "tmux"]
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"ship the fix\""))
        let working = await eventually { self.model.sessions.first?.phase == .working }
        XCTAssertTrue(working)
        XCTAssertFalse(model.canReply(to: key), "off unless switched on")
        model.settings.replyFromIsland = true
        XCTAssertFalse(model.canReply(to: key), "an agent at work is not waiting for words")
        model.reply(to: key, "hello")
        XCTAssertTrue(typed.lines.isEmpty)

        _ = await bridge(event("Stop", extra: closing))
        let waiting = await eventually { self.model.completion != nil }
        XCTAssertTrue(waiting)
        XCTAssertTrue(model.canReply(to: key))
        model.reply(to: key, "  now run\nthe tests ")
        let sent = await eventually { self.model.replies[self.key] == .sent }
        XCTAssertTrue(sent)
        XCTAssertEqual(typed.lines, ["now run the tests"], "one line, as typed")
        XCTAssertNil(model.completion, "answered: the card has done its job")
        model.reply(to: key, "   ")
        XCTAssertEqual(typed.lines.count, 1, "nothing typed, nothing sent")

        // The terminal turned it down (a shell is at the prompt, say): the island says so and sends nothing else.
        typed.accepts = false
        model.reply(to: key, "again")
        let failed = await eventually { self.model.replies[self.key] == .failed }
        XCTAssertTrue(failed)

        // A session without a terminal that can be named has no field at all.
        terminalEnvironment = ["TERM_PROGRAM": "ghostty"]
        _ = await bridge(event("UserPromptSubmit", session: "s2", extra: ",\"prompt\":\"other\""))
        _ = await bridge(event("Stop", session: "s2", extra: closing))
        let other = SessionKey(source: "claude", sessionID: "s2")
        let there = await eventually { self.model.sessions.first { $0.key == other }?.phase == .waiting }
        XCTAssertTrue(there)
        XCTAssertFalse(model.canReply(to: other))
        model.reply(to: other, "hello")
        XCTAssertEqual(typed.lines.count, 2)
    }

    func testTheListCanBeArrangedByProjectOrByAgent() {
        func snapshot(_ source: String, _ id: String, cwd: String, phase: Session.Phase) -> TranscriptSnapshot {
            TranscriptSnapshot(key: SessionKey(source: source, sessionID: id), path: "/dev/null", cwd: cwd, firstPrompt: id, lastPrompt: id,
                               phase: phase, activity: phase == .working ? .thinking : .waiting, updatedAt: Date())
        }
        model.mergeTranscripts([snapshot("claude", "a", cwd: "/tmp/atlas", phase: .working), snapshot("codex", "b", cwd: "/tmp/shop", phase: .working),
                                snapshot("codex", "c", cwd: "/tmp/atlas", phase: .waiting), snapshot("claude", "d", cwd: "/tmp/shop", phase: .waiting)])
        let listed = model.sessions
        XCTAssertEqual(listed.count, 4)

        let plain = SessionGroups.make(listed, by: .none)
        XCTAssertEqual(plain.count, 1)
        XCTAssertNil(plain[0].title, "as it comes: no headings")
        XCTAssertEqual(plain[0].sessions.map(\.key), listed.map(\.key))

        let byProject = SessionGroups.make(listed, by: .project)
        XCTAssertEqual(Set(byProject.compactMap(\.title)), ["atlas", "shop"])
        XCTAssertEqual(byProject.first?.sessions.first?.key, listed.first?.key, "the group of the first row comes first")
        XCTAssertEqual(byProject.flatMap(\.sessions).count, 4)
        XCTAssertTrue(byProject.allSatisfy { group in Set(group.sessions.map(\.cwd)).count == 1 })

        let byAgent = SessionGroups.make(listed, by: .agent)
        XCTAssertEqual(Set(byAgent.compactMap(\.title)), ["Claude Code", "Codex"])
        XCTAssertEqual(Set(byAgent.compactMap(\.source)), ["claude", "codex"])
        // One group is no grouping: the heading would only repeat every row.
        XCTAssertNil(SessionGroups.make(listed.filter { $0.source == "codex" }, by: .agent).first?.title)
        XCTAssertTrue(SessionGroups.make([], by: .project).isEmpty)

        XCTAssertEqual(listed.first { $0.key.sessionID == "a" }?.resumeCommand, "claude --resume a")
        XCTAssertEqual(listed.first { $0.key.sessionID == "b" }?.resumeCommand, "codex resume b")
    }

    func testNobodyAtTheScreenMeansNoSoundsAndNoCards() async throws {
        let sounds = RecordingSoundPlayer()
        model.soundPlayer = sounds
        model.settings.soundsEnabled = true
        XCTAssertTrue(model.settings.quietWhenAway)
        model.isAway = true
        await turn()
        XCTAssertNil(model.completion)
        XCTAssertNil(model.toast)
        XCTAssertTrue(sounds.played.isEmpty, "\(sounds.played)")
        // A request still waits, silently, and is there when the user is back.
        model.settings.expandOnAttention = false
        async let waiting = bridge(event("PermissionRequest", tool: "Bash"))
        let asked = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(asked)
        XCTAssertTrue(sounds.played.isEmpty)
        model.isAway = false
        model.decide(model.pending[0].id, .allowOnce)
        _ = await waiting

        // Told to carry on regardless.
        model.settings.quietWhenAway = false
        model.isAway = true
        await turn()
        XCTAssertNotNil(model.completion)
        XCTAssertEqual(sounds.played, [.completed])
    }

    // MARK: Allow and deny from the keyboard

    func testKeysOnlyAnswerARequestThatIsOnScreen() async throws {
        model.settings.expandOnAttention = false
        async let first = bridge(event("PermissionRequest", tool: "Bash", command: "rm -rf build"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        XCTAssertFalse(model.settings.decisionHotkeys)
        XCTAssertFalse(model.decideByKey(.allow), "off unless switched on")
        XCTAssertFalse(model.isExpanded)
        XCTAssertEqual(model.pending.count, 1)

        model.settings.decisionHotkeys = true
        // With the island closed the first press only shows what is being asked.
        XCTAssertFalse(model.decideByKey(.allow))
        XCTAssertTrue(model.isExpanded)
        XCTAssertEqual(model.pending.count, 1, "nothing is allowed unseen")
        XCTAssertEqual(model.focusedRequest?.id, model.pending.first?.id)
        // Now it is on screen: the key answers it.
        XCTAssertTrue(model.decideByKey(.allow))
        let allowed = await first
        XCTAssertEqual(behavior(allowed), "allow")
        XCTAssertTrue(model.pending.isEmpty)

        // Looking at usage is not looking at the request.
        async let second = bridge(event("PermissionRequest", tool: "Bash"))
        let again = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(again)
        model.expand(.click)
        model.route = .usage
        XCTAssertFalse(model.decideByKey(.deny))
        XCTAssertEqual(model.route, .sessions)
        XCTAssertEqual(model.pending.count, 1)
        XCTAssertTrue(model.decideByKey(.deny))
        let denied = await second
        XCTAssertEqual(behavior(denied), "deny")

        // A question is answered with its answers, never with a key.
        let question = """
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp/demo-project","tool_name":"AskUserQuestion",
         "tool_input":{"questions":[{"question":"Which database?","header":"DB","multiSelect":false,"options":[{"label":"Postgres"},{"label":"SQLite"}]}]}}
        """
        async let asking = bridge(question)
        let asked = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(asked)
        model.expand(.click)
        XCTAssertFalse(model.decideByKey(.allow))
        XCTAssertFalse(model.decideByKey(.deny))
        XCTAssertEqual(model.pending.count, 1)
        model.decide(model.pending[0].id, .passToTerminal)
        _ = await asking
        // Nothing waiting: the keys do nothing at all.
        XCTAssertFalse(model.decideByKey(.allow))
    }

    // MARK: A request left waiting

    func testARequestLeftWaitingIsBroughtUpAgainAFewTimes() async throws {
        let sounds = RecordingSoundPlayer()
        model.soundPlayer = sounds
        model.settings.soundsEnabled = true
        model.settings.expandOnAttention = false
        async let waiting = bridge(event("PermissionRequest", tool: "Bash"))
        let shown = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(shown)
        let asked = model.pending[0].receivedAt
        XCTAssertEqual(sounds.played, [.attention])
        XCTAssertEqual(attentionRequests, 1)

        model.remindAboutWaiting(now: asked.addingTimeInterval(3600))
        XCTAssertEqual(sounds.played, [.attention], "never, unless asked for")

        model.settings.reminderMinutes = 5
        model.remindAboutWaiting(now: asked.addingTimeInterval(200))
        XCTAssertEqual(sounds.played.count, 1, "not yet")
        // Nobody at the screen: the reminder waits for them.
        model.isAway = true
        model.remindAboutWaiting(now: asked.addingTimeInterval(400))
        XCTAssertEqual(sounds.played.count, 1)
        model.isAway = false
        model.remindAboutWaiting(now: asked.addingTimeInterval(401))
        XCTAssertEqual(sounds.played.count, 2)
        XCTAssertEqual(attentionRequests, 2)
        model.remindAboutWaiting(now: asked.addingTimeInterval(500))
        XCTAssertEqual(sounds.played.count, 2, "the wait starts again from the reminder")
        model.remindAboutWaiting(now: asked.addingTimeInterval(710))
        model.remindAboutWaiting(now: asked.addingTimeInterval(1020))
        XCTAssertEqual(sounds.played.count, 4)
        model.remindAboutWaiting(now: asked.addingTimeInterval(9000))
        XCTAssertEqual(sounds.played.count, 4, "three reminders, then it lets be")
        XCTAssertEqual(model.pending.count, 1, "a reminder decides nothing")

        // With "open for requests" on, a reminder opens the island again.
        model.decide(model.pending[0].id, .deny)
        _ = await waiting
        model.settings.expandOnAttention = true
        async let second = bridge(event("PermissionRequest", tool: "Bash"))
        let again = await eventually { self.model.pending.count == 1 }
        XCTAssertTrue(again)
        model.collapse()
        XCTAssertFalse(model.isExpanded)
        model.remindAboutWaiting(now: model.pending[0].receivedAt.addingTimeInterval(301))
        XCTAssertTrue(model.isExpanded)
        model.decide(model.pending[0].id, .deny)
        _ = await second
    }

    // MARK: Rows

    func testRowsCarryTheBranchTheListAndTheModel() async throws {
        let repo = scratch.file("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("ref: refs/heads/feature/card\n".utf8).write(to: repo.appendingPathComponent(".git/HEAD"))
        let live = SessionKey(source: "codex", sessionID: "cx")
        var snapshot = TranscriptSnapshot(key: live, path: "/dev/null", cwd: repo.path, host: .codexDesktop, firstPrompt: "Add a card",
                                          lastPrompt: "Add a card", lastReply: nil, phase: .working, activity: .thinking, updatedAt: Date())
        snapshot.progress = TaskProgress(done: 1, total: 4, current: "Draw the card")
        snapshot.model = "gpt-6-astra"
        model.mergeTranscripts([snapshot])
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.progress, TaskProgress(done: 1, total: 4, current: "Draw the card"))
        XCTAssertEqual(session.modelLabel, "gpt-6-astra")

        model.refreshBranches()
        let found = await eventually { self.model.branches[repo.path] == "feature/card" }
        XCTAssertTrue(found)
        // Switched off, the branch is neither read nor kept.
        model.settings.setChip(.branch, shown: false)
        model.refreshBranches()
        XCTAssertTrue(model.branches.isEmpty)

        // A card for a finished turn carries the list as it stood.
        snapshot.phase = .waiting
        snapshot.activity = .waiting
        snapshot.lastReply = "Card drawn."
        snapshot.progress = TaskProgress(done: 4, total: 4)
        model.mergeTranscripts([snapshot])
        XCTAssertEqual(model.completion?.progress, TaskProgress(done: 4, total: 4))
        XCTAssertEqual(model.completion?.reply, "Card drawn.")
    }

    func testRowsShowTheConversationAndItsHost() async throws {
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"Add retries to the uploader\\nsecond line\""))
        _ = await bridge(event("UserPromptSubmit", extra: ",\"prompt\":\"and keep the old timeout\""))
        let two = await eventually { self.model.sessions.first?.lastPrompt == "and keep the old timeout" }
        XCTAssertTrue(two)
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.projectName, "demo-project")
        XCTAssertEqual(session.headline, "Add retries to the uploader")
        XCTAssertEqual(session.followUp, "and keep the old timeout")
    }

    func testDenyListedBundleIsNotAdmitted() async throws {
        model.settings.requireDeveloperEvidence = true
        let ancestors = ProcessInspector.ancestors(of: getpid()).compactMap(\.bundleID)
        guard let bundle = ancestors.first else { throw XCTSkip("test runner has no app bundle in its ancestry") }
        model.settings.deniedBundleIDs = [bundle]
        _ = await bridge(event("SessionStart"))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.hub.counters.admitted, 0)
        model.settings.deniedBundleIDs = []
        _ = await bridge(event("SessionStart"))
        let admitted = await eventually { self.model.sessions.count == 1 }
        XCTAssertTrue(admitted)
    }

    func testSecondInstanceBacksOff() {
        let second = AppModel(paths: scratch.paths, home: scratch.file("home"), log: .inMemory())
        XCTAssertFalse(second.start(usage: false))
        XCTAssertEqual(second.startFailure, .anotherInstanceRunning)
        XCTAssertNil(model.startFailure)
    }

    func testHTTPIngressOnlyRunsWhenEnabled() async throws {
        XCTAssertEqual(model.httpPort, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.ingressToken.path))
        model.settings.httpPort = 0
        model.settings.httpIngressEnabled = true
        XCTAssertGreaterThan(model.httpPort, 0)
        let token = try HTTPIngressServer.loadOrCreateToken(paths: scratch.paths)
        let port = model.httpPort
        let body = "{\"source\":\"opencode\",\"hook_event_name\":\"SessionStart\",\"session_id\":\"oc\",\"cwd\":\"/tmp\",\"_niko\":{\"pid\":\(getpid())}}"
        let response = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: httpPost(port: port, token: token, body: body)?.status) }
        }
        XCTAssertEqual(response, 200)
        let arrived = await eventually { self.model.sessions.contains { $0.source == "opencode" } }
        XCTAssertTrue(arrived)
        model.settings.httpIngressEnabled = false
        XCTAssertEqual(model.httpPort, 0)
    }

    func testUsageEnginePublishesToTheModel() async throws {
        model.stop()
        let stamp = ISO8601DateFormatter().string(from: Date())
        scratch.write("home/.claude/projects/-demo/s.jsonl",
                      "{\"cwd\":\"/demo\",\"sessionId\":\"u1\",\"type\":\"assistant\",\"message\":{\"id\":\"msg_u\",\"model\":\"claude-opus-4-5-20251101\",\"usage\":{\"input_tokens\":3,\"output_tokens\":21}},\"requestId\":\"r\",\"timestamp\":\"\(stamp)\"}\n")
        let withUsage = AppModel(paths: scratch.paths, home: scratch.file("home"), log: .inMemory())
        XCTAssertTrue(withUsage.start(usage: true))
        defer { withUsage.stop() }
        let counted = await eventually(timeout: 10) { withUsage.usage.todayTokens == 24 }
        XCTAssertTrue(counted, "tokens: \(withUsage.usage.todayTokens)")
        XCTAssertEqual(withUsage.usage.today.first?.agent, "claude")
        XCTAssertFalse(withUsage.settings.pricingRefreshEnabled, "network refresh is opt-in")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.pricingCache.path), "and nothing was downloaded")
    }

    // MARK: Soak (REVIEW "100 concurrent fake sessions: UI stays responsive, no fd leak")

    func testHundredConcurrentSessionsKeepMainActorResponsive() async throws {
        let path = scratch.paths.socket.path
        let baseline = openFileDescriptorCount()
        let sessions = 100, eventsPerSession = 12
        let next = Counter(), failures = Counter()
        let workers = (0..<16).map { _ in
            Thread {
                while true {
                    let index = next.increment() - 1
                    guard index < sessions else { return }
                    for step in 0..<eventsPerSession {
                        guard let client = SocketClient(path: path) else { failures.increment(); continue }
                        let name = step == 0 ? "SessionStart" : (step % 2 == 0 ? "PostToolUse" : "PreToolUse")
                        client.send(eventJSON(name, session: "soak-\(index)", tool: "Read"))
                        if !client.finish() { failures.increment() }
                    }
                }
            }
        }
        // Heartbeat: how long does the main actor ever go without getting a turn?
        var worstGap: TimeInterval = 0
        var last = Date()
        let deadline = Date().addingTimeInterval(60)
        workers.forEach { $0.start() }
        while !workers.allSatisfy(\.isFinished) || model.hub.counters.admitted < sessions * eventsPerSession {
            try await Task.sleep(nanoseconds: 2_000_000)
            let now = Date()
            worstGap = max(worstGap, now.timeIntervalSince(last))
            last = now
            if now > deadline { break }
        }
        let settled = await eventually(timeout: 20) { self.model.sessions.count == sessions }
        XCTAssertTrue(settled, "sessions: \(model.sessions.count)")
        XCTAssertEqual(failures.value, 0)
        XCTAssertEqual(model.hub.counters.admitted, sessions * eventsPerSession)
        XCTAssertEqual(model.hub.counters.dropped, 0)
        // Shared CI runners have a third of the cores and noisy neighbours; the
        // bound there only has to catch a real stall, not a slow machine.
        let allowed = ProcessInfo.processInfo.environment["CI"] == nil ? 0.25 : 1.5
        XCTAssertLessThan(worstGap, allowed, "main actor stalled for \(worstGap)s")
        XCTAssertEqual(model.badge.active, sessions)
        let released = await eventually { openFileDescriptorCount() <= baseline }
        XCTAssertTrue(released, "fd count \(openFileDescriptorCount()) vs baseline \(baseline)")
    }

    // MARK: Views render

    func testSessionsFoundOnDiskAreListedAndAnnouncedOnlyWhenLive() {
        let recorder = RecordingSoundPlayer()
        model.soundPlayer = recorder
        model.settings.soundsEnabled = true
        let key = SessionKey(source: "codex", sessionID: "desk")
        let written = Date().addingTimeInterval(-10)        // when the transcript was last touched
        func snapshot(_ phase: Session.Phase, reply: String? = nil) -> TranscriptSnapshot {
            TranscriptSnapshot(key: key, path: "/dev/null", cwd: "/tmp/shot", host: .codexDesktop, firstPrompt: "Add a share sheet",
                               lastPrompt: "Add a share sheet", lastReply: reply, phase: phase,
                               activity: phase == .working ? .thinking : .waiting, updatedAt: written)
        }
        // The first reading after launch: listed, nothing announced.
        model.mergeTranscripts([snapshot(.waiting)])
        XCTAssertEqual(model.sessions.map(\.key), [key])
        XCTAssertEqual(model.sessions.first?.origin, .transcript)
        XCTAssertTrue(recorder.played.isEmpty)
        XCTAssertNil(model.toast)
        // From then on a turn finishing is news.
        model.mergeTranscripts([snapshot(.working)])
        model.mergeTranscripts([snapshot(.waiting, reply: "Done.")])
        XCTAssertEqual(recorder.played, [.completed])
        XCTAssertEqual(model.completion?.key, key)
        XCTAssertEqual(model.completion?.reply, "Done.", "read from the transcript, so there is nothing to wait for")
        XCTAssertEqual(model.sessions.first?.replyLine, "Done.")
        // Dismissed: gone until the transcript has something new to say.
        model.dismiss(key)
        model.mergeTranscripts([snapshot(.waiting, reply: "Done.")])
        XCTAssertTrue(model.sessions.isEmpty)
        var later = snapshot(.working)
        later.updatedAt = Date().addingTimeInterval(5)
        model.mergeTranscripts([later])
        XCTAssertEqual(model.sessions.map(\.key), [key])
        // The transcript leaving the window takes the session with it.
        model.mergeTranscripts([])
        XCTAssertTrue(model.sessions.isEmpty)
    }

    func testProviderLimitsAreAskedOnlyWhenSwitchedOn() async throws {
        final class Calls: @unchecked Sendable {
            private let lock = NSLock()
            private var hosts: [String] = []
            func note(_ host: String) { lock.lock(); hosts.append(host); lock.unlock() }
            var all: [String] { lock.lock(); defer { lock.unlock() }; return hosts }
        }
        let calls = Calls()
        let paths = model.paths
        let answer = Data(#"{"five_hour":{"utilization":37,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":{"utilization":61,"resets_at":"2099-01-03T00:00:00Z"}}"#.utf8)
        model.makeLimitsClient = { onChange in
            ProviderLimitsClient(
                paths: paths,
                secrets: .init(claudeLogin: { .found(.init(token: "test-token", expiresAt: Date().addingTimeInterval(3600), plan: "max")) }, glmKey: { nil }),
                transport: { request in
                    calls.note(request.url?.host ?? "?")
                    return (answer, 200)
                }, onChange: onChange)
        }
        XCTAssertFalse(model.settings.claudeLimitsLookup, "off unless the user says so")
        XCTAssertFalse(model.settings.glmLimitsLookup)
        model.reconcileProviderLimits()
        XCTAssertNil(model.limitsClient, "nothing is even created while both switches are off")

        model.settings.claudeLimitsLookup = true
        let client = try XCTUnwrap(model.limitsClient)
        await client.refresh(force: true)
        let deadline = Date().addingTimeInterval(5)
        while model.providerLookups["claude"] == nil, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let result = try XCTUnwrap(model.providerLookups["claude"])
        XCTAssertEqual(result.state, .ok)
        XCTAssertEqual(result.limits?.windows.map(\.usedPercent), [37, 61])
        XCTAssertEqual(result.limits?.plan, "max")
        XCTAssertEqual(Set(calls.all), ["api.anthropic.com"], "one provider, one host")
        // What is kept between runs holds percentages and times, never the sign-in.
        let cached = try String(contentsOf: paths.cache.appendingPathComponent("provider-limits.json"), encoding: .utf8)
        XCTAssertFalse(cached.contains("test-token"))
        XCTAssertTrue(cached.contains("five_hour"))

        model.settings.claudeLimitsLookup = false
        XCTAssertNil(model.providerLookups["claude"], "switched off: the answer goes too")
    }

    func testResetsAreSpentInTheAgentsOwnApp() {
        // The island never spends a quota reset; it can only say which agents have one to spend.
        XCTAssertEqual(AgentRegistry.all.filter(\.quotaResetInApp).map(\.id), ["zcode"])
        XCTAssertFalse(AgentRegistry.all.first { $0.id == "zcode" }?.apps.isEmpty ?? true, "there is an app to bring forward")
    }

    func testAppearanceAndTimingSettingsHaveSaneDefaultsAndStick() {
        let settings = NikoSettings()
        XCTAssertEqual(settings.islandWidth.points, 640)
        XCTAssertEqual(settings.accent, .mint)
        XCTAssertEqual(settings.hoverOpenDelayMS, 160)
        XCTAssertEqual(settings.hoverCloseDelayMS, 150, "the island lets go soon after the pointer has")
        XCTAssertEqual(NikoSettings(raw: ["hoverCloseDelayMS": .int(450)]).hoverCloseDelayMS, 400, "an older choice lands on the nearest one offered now")
        XCTAssertEqual(NikoSettings(raw: ["hoverCloseDelayMS": .int(1500)]).hoverCloseDelayMS, 900)
        XCTAssertEqual(settings.textSize, .regular)
        XCTAssertLessThan(NikoSettings.TextSize.small.scale, NikoSettings.TextSize.regular.scale)
        XCTAssertLessThan(NikoSettings.TextSize.regular.scale, 1, "regular is a little smaller than the type 0.3.0 drew")
        XCTAssertEqual(settings.motion, .standard)
        XCTAssertLessThan(NikoSettings.Motion.brisk.factor, NikoSettings.Motion.calm.factor)
        XCTAssertEqual(settings.toastSeconds, 5)
        XCTAssertEqual(settings.visibleRows, 6)
        XCTAssertEqual(settings.language, "system")
        XCTAssertEqual(settings.islandDisplay, "auto")
        XCTAssertTrue(settings.discoverSessions && settings.showMascots && settings.hotkeyEnabled)
        XCTAssertEqual(NikoSettings.RowChip.allCases.filter(settings.showsChip), [.elapsed, .agent, .host, .branch])

        model.settings.accent = .violet
        model.settings.islandWidth = .wide
        model.settings.setChip(.host, shown: false)
        model.settings.setMascot("crab", for: "claude")
        model.settings.language = "zh-Hans"
        let saved = NikoSettings.load(paths: model.paths)
        XCTAssertEqual(saved.accent, .violet)
        XCTAssertEqual(saved.islandWidth.points, 720)
        XCTAssertFalse(saved.showsChip(.host))
        XCTAssertEqual(saved.mascotChoices, ["claude": "crab"])
        XCTAssertEqual(saved.language, "zh-Hans")
        model.settings.textSize = .large
        model.settings.motion = .brisk
        let look = IslandLook(settings: model.settings)
        XCTAssertEqual(look.textScale, NikoSettings.TextSize.large.scale)
        XCTAssertEqual(look.motion, 0.7)
        XCTAssertEqual(look.chips, [.elapsed, .agent, .branch])
        XCTAssertEqual(look.replyLines, 1)
        XCTAssertEqual(Mascots.sprite(for: "claude", choices: look.mascots).name, "crab")
        XCTAssertEqual(Mascots.sprite(for: "codex", choices: look.mascots).name, "whale")
        model.settings.setMascot(nil, for: "claude")
        XCTAssertTrue(model.settings.mascotChoices.isEmpty)
        XCTAssertEqual(NikoSettings(raw: ["language": .string("klingon"), "visibleRows": .int(500)]).language, "system")
        XCTAssertEqual(NikoSettings(raw: ["visibleRows": .int(500)]).visibleRows, 20)
    }

    func testRunningAgentsAreRecognisedByAppAndByProcessName() {
        XCTAssertEqual(AgentPresence.running(apps: ["com.openai.codex", "com.apple.finder"], processes: ["zsh", "claude", "zcode-cli"]),
                       ["claude", "codex", "zcode"])
        XCTAssertEqual(AgentPresence.running(apps: [], processes: ["node", "CursorUIViewServ"]), [], "look-alikes are not agents")
        XCTAssertEqual(AgentPresence.running(apps: ["com.todesktop.230313mzl4w4u92"], processes: []), ["cursor"])
        XCTAssertTrue(AgentPresence.runningProcessNames().contains { !$0.isEmpty }, "the process table can be read")
    }

    func testEverySceneRenders() throws {
        for scene in PreviewRenderer.Scene.allCases {
            let url = scratch.file("render/\(scene.rawValue).png")
            guard PreviewRenderer.render(scene, to: url, scale: 1) else {
                if ProcessInfo.processInfo.environment["CI"] != nil { throw XCTSkip("no window server for ImageRenderer") }
                return XCTFail("render failed for \(scene)")
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 3000, "\(scene) rendered an empty image")
        }
        XCTAssertTrue(PreviewRenderer.render(.sessions, to: scratch.file("render/plain.png"), scale: 1, metrics: .plain))
        XCTAssertTrue(PreviewRenderer.renderDemo(to: scratch.file("render/demo.gif")))
        XCTAssertTrue(PreviewRenderer.renderMascots(to: scratch.file("render/mascots")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.file("render/mascots").path).filter { $0.hasSuffix(".gif") }.count,
                       Mascots.all.count)

        let list = PreviewRenderer.demoModel(.sessions)
        XCTAssertEqual(list.sessions.count, 6, "five announced by hooks, one known only from its transcript")
        XCTAssertTrue(list.isExpanded)
        XCTAssertEqual(list.sessions.first?.phase, .needsAttention, "sessions needing attention sort first")
        XCTAssertEqual(Set(list.sessions.compactMap(\.hostName)), ["iTerm2", "Ghostty", "Terminal", "Cursor", "WezTerm", "Codex"])
        let desktop = try XCTUnwrap(list.sessions.first { $0.origin == .transcript })
        XCTAssertEqual(desktop.subagents, 2)
        XCTAssertEqual(desktop.hostLabel, "Desktop", "the agent's own app is not named twice")
        XCTAssertEqual(list.sessions.first { $0.customTitle != nil }?.headline, "Install guide")
        let usage = PreviewRenderer.demoModel(.usage)
        XCTAssertEqual(usage.usage.agents.map(\.id), ["all", "claude", "codex"])
        XCTAssertEqual(usage.usage.agent("claude")?.limitsSource, .provider)
        XCTAssertGreaterThan(usage.usage.agent("claude")?.month.tokens ?? 0, usage.usage.agent("claude")?.week.tokens ?? 0)
        XCTAssertEqual(PreviewRenderer.demoModel(.empty).runningAgents, ["claude", "codex", "zcode"])
        let permission = PreviewRenderer.demoModel(.permission)
        XCTAssertEqual(permission.pending.count, 1)
        XCTAssertFalse(PreviewRenderer.demoModel(.attention).isExpanded)
    }
}
