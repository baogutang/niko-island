import XCTest
@testable import NikoCore
@testable import NikoIslandApp

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

    private func bridge(_ stdin: String, _ arguments: [String] = ["--source", "claude"],
                        onStart: (@Sendable (Int32) -> Void)? = nil) async -> ProcessOutput {
        await runProcessAsync(bridgeBinaryPath, arguments, stdin: Data(stdin.utf8),
                              environment: ["NIKO_ISLAND_HOME": scratch.paths.root.path], onStart: onStart)
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
        XCTAssertEqual(attentionRequests, 1, "the panel is asked to show itself")
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
            QuestionWizardView.answer(for: request.questions[0], selected: ["SQLite"], custom: ""),
            QuestionWizardView.answer(for: request.questions[1], selected: ["Search", "Auth"], custom: ""),
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
        XCTAssertEqual(QuestionWizardView.answer(for: single, selected: ["B"], custom: ""), ["B"])
        XCTAssertEqual(QuestionWizardView.answer(for: single, selected: ["B"], custom: "  my own  "), ["my own"], "free text replaces a single choice")
        XCTAssertEqual(QuestionWizardView.answer(for: multi, selected: ["B", "A"], custom: "C"), ["A", "B", "C"])
        XCTAssertEqual(QuestionWizardView.answer(for: multi, selected: [], custom: "   "), [])
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
        model.settings.setSound(true, for: .idle)
        _ = await bridge(event("UserPromptSubmit"))
        _ = await bridge(event("Stop"))
        let notified = await eventually { self.notifier.notes.count == 1 }
        XCTAssertTrue(notified, "a sound-only preference still reaches the notifier")
        XCTAssertFalse(NikoSettings.load(paths: scratch.paths).notificationsEnabled(for: .idle), "settings are persisted")
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
        XCTAssertLessThan(worstGap, 0.25, "main actor stalled for \(worstGap)s")
        XCTAssertEqual(model.badge.active, sessions)
        let released = await eventually { openFileDescriptorCount() <= baseline }
        XCTAssertTrue(released, "fd count \(openFileDescriptorCount()) vs baseline \(baseline)")
    }

    // MARK: Views render

    func testEveryPanelSceneRenders() throws {
        for scene in PreviewRenderer.Scene.allCases {
            let url = scratch.file("render/\(scene.rawValue).png")
            guard PreviewRenderer.render(scene, to: url, scale: 1) else {
                if ProcessInfo.processInfo.environment["CI"] != nil { throw XCTSkip("no window server for ImageRenderer") }
                return XCTFail("render failed for \(scene)")
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 3000, "\(scene) rendered an empty image")
        }
        let demo = PreviewRenderer.demoModel(.sessions)
        XCTAssertEqual(demo.sessions.count, 3)
        XCTAssertEqual(demo.pending.count, 1)
        XCTAssertEqual(demo.sessions.first?.phase, .needsAttention, "sessions needing attention sort first")
    }
}
