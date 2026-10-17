import XCTest
@testable import NikoCore

/// Pace, outlook and warnings for plan windows (the rules agent-hud-open uses).
final class QuotaWatchTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 4_000_000_000)

    private func window(_ used: Double, resetsIn hours: Double, minutes: Int = 300, at now: Date) -> RateLimitWindow {
        RateLimitWindow(id: "five_hour", usedPercent: used, resetsAt: now.addingTimeInterval(hours * 3600), windowMinutes: minutes)
    }

    func testLevelsFollowTheShareUsed() {
        XCTAssertEqual(QuotaLevel(used: 69.9), .ok)
        XCTAssertEqual(QuotaLevel(used: 70), .warning)
        XCTAssertEqual(QuotaLevel(used: 90), .critical)
    }

    func testThePaceIsTheLastHourOfAFiveHourWindow() {
        var watch = QuotaWatch()
        let resets = start.addingTimeInterval(4 * 3600)
        // Steady 10 points an hour for two hours, then 30 in the last hour.
        for minute in stride(from: 0, through: 120, by: 10) {
            _ = watch.record(agent: "claude", window: RateLimitWindow(id: "five_hour", usedPercent: Double(minute) / 6,
                                                                      resetsAt: resets, windowMinutes: 300),
                             at: start.addingTimeInterval(Double(minute) * 60), now: start.addingTimeInterval(Double(minute) * 60))
        }
        for minute in stride(from: 130, through: 180, by: 10) {
            let used = 20 + Double(minute - 120) / 2
            _ = watch.record(agent: "claude", window: RateLimitWindow(id: "five_hour", usedPercent: used, resetsAt: resets, windowMinutes: 300),
                             at: start.addingTimeInterval(Double(minute) * 60), now: start.addingTimeInterval(Double(minute) * 60))
        }
        let now = start.addingTimeInterval(180 * 60)
        let current = RateLimitWindow(id: "five_hour", usedPercent: 50, resetsAt: resets, windowMinutes: 300)
        let outlook = try! XCTUnwrap(watch.outlook(agent: "claude", window: current, now: now))
        XCTAssertEqual(outlook.pacePerHour, 30, accuracy: 0.01, "the last hour, not the whole series")
        XCTAssertFalse(outlook.runsOutBeforeReset, "50 points left at 30 an hour last 1h40m; the reset is an hour away")
        XCTAssertEqual(outlook.usedAtReset ?? 0, 80, accuracy: 0.01)
        XCTAssertEqual(outlook.runsOutAt!.timeIntervalSince(now), 100 / 60 * 3600, accuracy: 1)
    }

    func testTooShortASeriesOrAResetGivesNoPace() {
        let series = [QuotaWatch.Sample(time: start, used: 10), QuotaWatch.Sample(time: start.addingTimeInterval(600), used: 20)]
        XCTAssertNil(QuotaWatch.pace(series, minutes: 300), "ten minutes say nothing yet")
        let afterReset = [QuotaWatch.Sample(time: start, used: 80), QuotaWatch.Sample(time: start.addingTimeInterval(1800), used: 90),
                          QuotaWatch.Sample(time: start.addingTimeInterval(1900), used: 2), QuotaWatch.Sample(time: start.addingTimeInterval(3700), used: 12)]
        XCTAssertEqual(try XCTUnwrap(QuotaWatch.pace(afterReset, minutes: 300)), 20, accuracy: 0.01, "counted from the reset on")
        let weekly = [QuotaWatch.Sample(time: start, used: 10), QuotaWatch.Sample(time: start.addingTimeInterval(1800), used: 12)]
        XCTAssertNil(QuotaWatch.pace(weekly, minutes: 10080), "a week needs an hour of readings")
    }

    func testWarningsComeOncePerCycleAndNeverAtLaunch() {
        var watch = QuotaWatch()
        var now = start
        let resets = start.addingTimeInterval(4 * 3600)
        func read(_ used: Double, _ resetsAt: Date = resets) -> [QuotaWatch.Alert] {
            defer { now = now.addingTimeInterval(600) }
            return watch.record(agent: "codex", window: RateLimitWindow(id: "five_hour", usedPercent: used, resetsAt: resetsAt, windowMinutes: 300),
                                at: now, now: now)
        }
        XCTAssertEqual(read(92), [], "the first reading after launch is a baseline")
        XCTAssertEqual(read(93), [], "already over 90 when the app started: not news")

        var fresh = QuotaWatch()
        now = start
        func readFresh(_ used: Double) -> [QuotaWatch.Alert] {
            defer { now = now.addingTimeInterval(600) }
            return fresh.record(agent: "codex", window: RateLimitWindow(id: "five_hour", usedPercent: used, resetsAt: resets, windowMinutes: 300),
                                at: now, now: now)
        }
        XCTAssertEqual(readFresh(40), [])
        XCTAssertEqual(readFresh(45), [])
        // 15 points in 20 minutes: at that pace it runs out long before the reset.
        let forecast = readFresh(60)
        XCTAssertEqual(forecast.count, 1)
        if case .runsOutEarly(let agent, _, _) = forecast.first { XCTAssertEqual(agent, "codex") } else { XCTFail("\(forecast)") }
        XCTAssertEqual(readFresh(75), [], "said once in this cycle")
        let full = readFresh(91)
        XCTAssertEqual(full.count, 1)
        if case .nearlyFull = full.first {} else { XCTFail("\(full)") }
        XCTAssertEqual(readFresh(95), [])

        // A stale reading says nothing new.
        var stale = QuotaWatch()
        _ = stale.record(agent: "claude", window: window(85, resetsIn: 3, at: start), at: start, now: start)
        XCTAssertEqual(stale.record(agent: "claude", window: window(91, resetsIn: 3, at: start), at: start.addingTimeInterval(60),
                                    now: start.addingTimeInterval(3600)), [])
    }

    func testReadingsAreKeptBetweenLaunches() throws {
        let scratch = Scratch()
        var watch = QuotaWatch()
        _ = watch.record(agent: "claude", window: window(10, resetsIn: 4, at: start), at: start, now: start)
        _ = watch.record(agent: "claude", window: window(30, resetsIn: 4, at: start), at: start.addingTimeInterval(3600),
                         now: start.addingTimeInterval(3600))
        let file = scratch.file("cache/quota-history.json")
        watch.save(to: file)
        let back = QuotaWatch.load(from: file)
        XCTAssertEqual(back.samples, watch.samples)
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("token"), "numbers and times only")
        XCTAssertEqual(QuotaWatch.load(from: scratch.file("nothing.json")).samples, [:])
    }

    // MARK: Copilot

    func testCopilotsAllowancesAreRead() throws {
        let answer = #"{"copilot_plan":"individual","quota_reset_date_utc":"2099-02-01T00:00:00Z","quota_snapshots":{"chat":{"unlimited":false,"has_quota":true,"entitlement":50,"remaining":20,"percent_remaining":40,"quota_reset_at":4070908800},"completions":{"unlimited":true,"percent_remaining":100},"premium_interactions":{"unlimited":false,"has_quota":false,"entitlement":0,"percent_remaining":100}}}"#
        let limits = try XCTUnwrap(CopilotQuotaAPI.parse(Data(answer.utf8)))
        XCTAssertEqual(limits.windows.map(\.id), ["copilot_chat"], "unlimited and not-in-the-plan counters are left out")
        XCTAssertEqual(limits.windows[0].usedPercent, 60, accuracy: 0.01)
        XCTAssertEqual(limits.windows[0].resetsAt, Date(timeIntervalSince1970: 4_070_908_800))
        XCTAssertEqual(limits.plan, "individual")
        XCTAssertNil(CopilotQuotaAPI.parse(Data(#"{"quota_snapshots":{}}"#.utf8)))
        let request = CopilotQuotaAPI.request(token: "t")
        XCTAssertEqual(request.url?.host, "api.github.com")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("niko-island/") == true, "under this app's own name")
    }

    func testTheGitHubCLIsSignInIsFoundWhereGhKeepsIt() {
        let hosts = """
        github.example.com:
            oauth_token: not-this-one
        github.com:
            user: someone
            oauth_token: gho_abc
            git_protocol: https
        """
        XCTAssertEqual(GitHubLogin.token(inHosts: hosts), "gho_abc")
        XCTAssertNil(GitHubLogin.token(inHosts: "github.com:\n    user: someone\n"), "kept in the Keychain instead")
        XCTAssertEqual(GitHubLogin.unwrap("go-keyring-base64:" + Data("gho_xyz".utf8).base64EncodedString()), "gho_xyz")
        XCTAssertEqual(GitHubLogin.unwrap("gho_plain"), "gho_plain")
        let scratch = Scratch()
        scratch.write("home/.config/gh/hosts.yml", hosts)
        XCTAssertEqual(GitHubLogin.read(home: scratch.file("home"), environment: [:]), .found("gho_abc"))
        XCTAssertEqual(GitHubLogin.read(home: scratch.file("home"), environment: ["GH_TOKEN": "from-env"]), .found("from-env"))
    }

    // MARK: A call settled somewhere else

    func testAnEventSaysWhenARequestWasSettledElsewhere() throws {
        func event(_ text: String) throws -> AgentEvent { try AgentEvent(json: JSONValue.parse(Data(text.utf8)), defaultSource: "claude") }
        let request = try event(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"make"}}"#)
        XCTAssertTrue(try event(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"make"},"tool_response":{}}"#).settles(request))
        XCTAssertFalse(try event(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}"#).settles(request))
        XCTAssertFalse(try event(#"{"hook_event_name":"PostToolUse","session_id":"other","tool_name":"Bash","tool_input":{"command":"make"}}"#).settles(request))
        XCTAssertTrue(try event(#"{"hook_event_name":"Stop","session_id":"s"}"#).settles(request))
        XCTAssertFalse(try event(#"{"hook_event_name":"Notification","session_id":"s","message":"Claude needs your permission"}"#).settles(request))
        XCTAssertFalse(try event(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"make"}}"#).settles(request))
        // A long input arrives shortened in a status event; it is still the same call.
        let long = String(repeating: "x", count: 6000)
        let big = try event(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Write","tool_input":{"content":"\#(long)"}}"#)
        let after = try event(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Write","tool_input":{"content":"\#(String(long.prefix(4096)))…"}}"#)
        XCTAssertTrue(after.settles(big))
    }

    /// The shapes Claude Code 2.1 sends (read from its own code): a PermissionRequest has no
    /// `tool_use_id`; a question it ran carries `answers`; a subagent's events carry `agent_id`.
    func testAQuestionOrPlanAnsweredInTheAgentsOwnWindowLeavesTheIsland() throws {
        func event(_ text: String) throws -> AgentEvent { try AgentEvent(json: JSONValue.parse(Data(text.utf8)), defaultSource: "claude") }
        let questions = #"{"questions":[{"question":"Which style?","header":"Style","multiSelect":false,"options":[{"label":"A"},{"label":"B"}]}]}"#
        let asked = try event(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"AskUserQuestion","tool_input":\#(questions)}"#)
        // Answered in Claude's window: it runs with the answers added to what was asked.
        let answered = #"{"questions":[{"question":"Which style?","header":"Style","multiSelect":false,"options":[{"label":"A"},{"label":"B"}]}],"answers":{"Which style?":"B"},"annotations":{}}"#
        XCTAssertTrue(try event(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"AskUserQuestion","tool_use_id":"toolu_1","tool_input":\#(answered)}"#).settles(asked))
        XCTAssertTrue(try event(#"{"hook_event_name":"PostToolUseFailure","session_id":"s","tool_name":"AskUserQuestion","tool_use_id":"toolu_1","tool_input":\#(questions),"error":"rejected"}"#).settles(asked))
        XCTAssertFalse(try event(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[]}}"#).settles(asked),
                       "another question is not this one")

        // A plan approved in the app: the next tool starts.
        let plan = try event(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"ExitPlanMode","tool_input":{"plan":"1. Do it"}}"#)
        let next = try event(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_use_id":"toolu_2","tool_input":{"command":"make"}}"#)
        XCTAssertTrue(next.settles(plan, waited: 30))
        XCTAssertFalse(next.settles(plan, waited: 0.3), "calls started side by side are not an answer")
        // A subagent working on is no answer to the main thread, nor the other way round.
        let helper = try event(#"{"hook_event_name":"PreToolUse","session_id":"s","agent_id":"a1","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}"#)
        XCTAssertFalse(helper.settles(plan, waited: 30))
        let helperAsks = try event(#"{"hook_event_name":"PermissionRequest","session_id":"s","agent_id":"a1","tool_name":"Bash","tool_input":{"command":"rm x"}}"#)
        XCTAssertFalse(next.settles(helperAsks, waited: 30))
        XCTAssertTrue(helper.settles(helperAsks, waited: 30))
        // Idle again means nothing is waiting; a notice that it needs permission means it still is.
        XCTAssertTrue(try event(#"{"hook_event_name":"Notification","session_id":"s","notification_type":"idle_prompt","message":"Claude is waiting for your input"}"#).settles(plan))
        XCTAssertFalse(try event(#"{"hook_event_name":"Notification","session_id":"s","notification_type":"permission_prompt","message":"Claude needs your permission"}"#).settles(plan))
    }

    // MARK: Usage over time

    func testTokensAreCountedInStretchesOfTime() throws {
        let scratch = Scratch()
        let store = try UsageStore(path: scratch.file("usage.sqlite").path)
        let base = 900.0 * 4_444_444   // on a quarter hour
        let records = [(base + 10, "claude", 100), (base + 899, "claude", 50), (base + 900, "codex", 7), (base - 10, "claude", 1)]
            .enumerated().map { index, item in
                UsageRecord(identityKey: "e\(index)", timestamp: item.0, agent: item.1, model: "m", input: item.2, output: 0)
            }
        try store.commit(records: records, pricing: Pricing(), file: nil)
        let rows = try store.stretches(since: base, seconds: 900)
        let first = Int(base / 900)
        XCTAssertEqual(rows[first]?["claude"], 150)
        XCTAssertEqual(rows[first + 1]?["codex"], 7)
        XCTAssertNil(rows[first - 1], "before the start")
    }
}
