import XCTest
@testable import NikoCore

/// Limits that only the provider knows: what its answers look like, and the
/// rules the lookups keep (opt-in, one host each, no sign-in on disk, no
/// renewing of anybody's sign-in).
final class ProviderLimitsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testAnthropicsAnswerIsReadInBothItsForms() throws {
        // As Claude Code itself caches it: named windows next to a list saying the same.
        let named = Data(#"""
        {"five_hour":{"utilization":100,"resets_at":"2026-09-23T11:09:59.650759+00:00","limit_dollars":null},
         "seven_day":{"utilization":45,"resets_at":"2026-09-26T13:59:59.650792+00:00"},
         "seven_day_opus":null,"seven_day_sonnet":null,"extra_usage":{"is_enabled":false,"utilization":0},
         "limits":[{"kind":"session","percent":100,"resets_at":"2026-09-23T11:09:59+00:00","is_active":true},
                   {"kind":"weekly","percent":45,"resets_at":"2026-09-26T13:59:59+00:00","is_active":true}]}
        """#.utf8)
        let limits = try XCTUnwrap(ClaudeUsageAPI.parse(named, now: now))
        XCTAssertEqual(limits.windows.map(\.id), ["five_hour", "seven_day"], "the list does not add the same windows again")
        XCTAssertEqual(limits.windows.map(\.usedPercent), [100, 45])
        XCTAssertEqual(limits.windows.map(\.minutes), [300, 10080])
        XCTAssertEqual(limits.source, .provider)
        XCTAssertEqual(limits.capturedAt, now)
        XCTAssertNotNil(limits.windows[0].resetsAt)

        // Only the list.
        let listed = Data(#"{"five_hour":null,"limits":[{"kind":"session","percent":12.5,"resets_at":"2026-09-23T11:09:59Z","is_active":true},{"kind":"weekly","percent":3,"resets_at":null,"is_active":true},{"kind":"old","percent":90,"is_active":false}]}"#.utf8)
        let fromList = try XCTUnwrap(ClaudeUsageAPI.parse(listed, now: now))
        XCTAssertEqual(fromList.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(fromList.windows.map(\.usedPercent), [12.5, 3])
        XCTAssertNil(fromList.windows[1].resetsAt)

        // A week per model: the list's figure is the newer one, a share for one surface is not the model's week,
        // paid extra use counts only where it is switched on, and a window with no name here is still shown.
        let scoped = Data(#"""
        {"five_hour":{"utilization":10,"resets_at":"2026-09-23T11:09:59Z"},"seven_day":{"utilization":20,"resets_at":"2026-09-26T13:59:59Z"},
         "seven_day_opus":{"utilization":33,"resets_at":"2026-09-26T13:59:59Z"},"seven_day_oauth_apps":{"utilization":4,"resets_at":null},
         "extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":1250,"utilization":25,"currency":"USD"},
         "limits":[{"kind":"weekly_scoped","group":"weekly","percent":41,"resets_at":"2026-09-26T13:59:59Z","scope":{"model":{"display_name":"Opus"},"surface":null}},
                   {"kind":"weekly_scoped","group":"weekly","percent":7,"resets_at":null,"scope":{"model":{"display_name":"Sonnet"}}},
                   {"kind":"weekly_scoped","group":"weekly","percent":99,"scope":{"model":{"display_name":"Sonnet"},"surface":"design"}},
                   {"kind":"weekly_scoped","group":"weekly","percent":50,"scope":{}}]}
        """#.utf8)
        let perModel = try XCTUnwrap(ClaudeUsageAPI.parse(scoped, now: now))
        XCTAssertEqual(perModel.windows.map(\.id), ["five_hour", "seven_day", "seven_day_oauth_apps", "seven_day_opus", "seven_day_sonnet", "extra_usage"])
        XCTAssertEqual(perModel.windows.map(\.usedPercent), [10, 20, 4, 41, 7, 25])
        XCTAssertTrue(perModel.windows.dropLast().allSatisfy { $0.minutes == 300 || $0.minutes == 10080 })

        XCTAssertNil(ClaudeUsageAPI.parse(Data("{}".utf8)))
        XCTAssertNil(ClaudeUsageAPI.parse(Data("<html>".utf8)))
        XCTAssertEqual(ClaudeUsageAPI.request(token: "t").url?.host, "api.anthropic.com")
        XCTAssertEqual(ClaudeUsageAPI.request(token: "t").value(forHTTPHeaderField: "Authorization"), "Bearer t")
    }

    func testCodingPlanAnswerIsReadWhateverItCallsItsWindows() throws {
        let tokens = Data(#"""
        {"code":200,"success":true,"data":{"level":"pro","limits":[
          {"type":"TIME_LIMIT","unit":5,"number":1,"usage":1000,"currentValue":123,"remaining":877,"percentage":12},
          {"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":52,"nextResetTime":1790400000000},
          {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":40,"nextResetTime":1790010000000}]}}
        """#.utf8)
        let limits = try XCTUnwrap(GLMQuotaAPI.parse(tokens, now: now))
        XCTAssertEqual(limits.windows.map(\.id), ["five_hour", "seven_day", "tools_month"], "the windows people watch come first")
        XCTAssertEqual(limits.windows.map(\.usedPercent), [40, 52, 12])
        XCTAssertEqual(limits.windows[0].resetsAt, Date(timeIntervalSince1970: 1_790_010_000))
        XCTAssertEqual(limits.windows[0].minutes, 300)
        XCTAssertEqual(limits.windows[1].minutes, 10080)
        XCTAssertEqual(limits.plan, "pro")
        XCTAssertNil(limits.resetsLeft, "no answer seen so far says how many resets are left")

        // The newer name for the same thing, and a window nobody has used yet.
        let credits = Data(#"{"code":200,"data":{"level":"lite","limits":[{"type":"CREDIT_LIMIT","unit":3,"number":5,"percentage":0},{"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":200,"currentValue":4}]}}"#.utf8)
        let fromCredits = try XCTUnwrap(GLMQuotaAPI.parse(credits, now: now))
        XCTAssertEqual(fromCredits.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(fromCredits.windows.map(\.usedPercent), [0, 2])
        XCTAssertNil(fromCredits.windows[0].resetsAt)

        // The week has been sent as "unit 6, number 7" as well as "unit 6, number 1": the unit is what says "week".
        let sevens = Data(#"{"data":{"limits":[{"type":"TOKENS_LIMIT","unit":6,"number":7,"percentage":61,"nextResetTime":1790400000000},{"type":"tokens_limit","unit":3,"number":5,"percentage":5}]}}"#.utf8)
        let week = try XCTUnwrap(GLMQuotaAPI.parse(sevens, now: now))
        XCTAssertEqual(week.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(week.windows.map(\.minutes), [300, 10080])
        // No unit at all: the window that resets first (or has not started counting) is the short one.
        let bare = Data(#"{"data":{"limits":[{"type":"TOKENS_LIMIT","percentage":70,"nextResetTime":1790400000000},{"type":"TOKENS_LIMIT","percentage":8,"nextResetTime":1790010000000}]}}"#.utf8)
        let guessed = try XCTUnwrap(GLMQuotaAPI.parse(bare, now: now))
        XCTAssertEqual(guessed.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(guessed.windows.map(\.usedPercent), [8, 70])

        XCTAssertNil(GLMQuotaAPI.parse(Data(#"{"code":401,"msg":"token expired"}"#.utf8)))
        XCTAssertEqual(GLMQuotaAPI.url(.bigmodel).host, "open.bigmodel.cn")
        XCTAssertEqual(GLMQuotaAPI.url(.zai).host, "api.z.ai")
        XCTAssertEqual(GLMQuotaAPI.request(key: "k", region: .zai).value(forHTTPHeaderField: "Authorization"), "k")
        XCTAssertTrue(GLMQuotaAPI.Region.allCases.allSatisfy { ProviderLimitsClient.hosts.contains($0.host) })
    }

    func testRegionFollowsWhatZCodeIsSetTo() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        XCTAssertNil(GLMQuotaAPI.regionZCodeUses(home: home))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".zcode/v2"), withIntermediateDirectories: true)
        try Data(#"{"providerFamilyDomain":"bigmodel","locale":"zh"}"#.utf8).write(to: home.appendingPathComponent(".zcode/v2/setting.json"))
        XCTAssertEqual(GLMQuotaAPI.regionZCodeUses(home: home), .bigmodel)
        try Data(#"{"providerFamilyDomain":"zai"}"#.utf8).write(to: home.appendingPathComponent(".zcode/v2/setting.json"))
        XCTAssertEqual(GLMQuotaAPI.regionZCodeUses(home: home), .zai)
    }

    func testClaudeCodesSignInIsReadForItsTokenAndDateOnly() throws {
        let stored = Data(#"{"claudeAiOauth":{"accessToken":"at","refreshToken":"rt","expiresAt":1790000600000,"scopes":["user:inference"],"subscriptionType":"pro"}}"#.utf8)
        let login = try XCTUnwrap(ClaudeCodeLogin.parse(stored))
        XCTAssertEqual(login.token, "at")
        XCTAssertEqual(login.expiresAt, Date(timeIntervalSince1970: 1_790_000_600))
        XCTAssertEqual(login.plan, "pro")
        XCTAssertNil(ClaudeCodeLogin.parse(Data(#"{"claudeAiOauth":{"refreshToken":"rt"}}"#.utf8)))
        XCTAssertNil(ClaudeCodeLogin.parse(Data("not json".utf8)))
        // With no Keychain entry and no file there is simply no sign-in. (This asks the real Keychain a
        // question it answers without showing anything when the item is not there or not ours.)
        let scratch = Scratch()
        try FileManager.default.createDirectory(at: scratch.file("home/.claude"), withIntermediateDirectories: true)
        try stored.write(to: scratch.file("home/.claude/.credentials.json"))
        XCTAssertNotNil(ClaudeCodeLogin.parse(try Data(contentsOf: scratch.file("home/.claude/.credentials.json"))))
    }

    func testTheAnswerAsClaudeCodeItselfKeepsItIsReadWithoutASignIn() throws {
        // The shape of a real answer, as Claude Code caches it in ~/.claude.json: windows under code names next to
        // the ones with a meaning, a list whose weekly entry is called "weekly_all", and extra usage that is off.
        let answer = #"""
        {"five_hour":{"utilization":12,"resets_at":"2099-01-01T05:00:00.000000+00:00","limit_dollars":null,"locked_reason":null},
         "seven_day":{"utilization":34,"resets_at":"2099-01-06T00:00:00.000000+00:00","limit_dollars":null},
         "seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,"tangelo":null,"iguana_necktie":null,
         "nimbus_quill":{"utilization":0,"resets_at":null,"limit_dollars":null},
         "extra_usage":{"is_enabled":false,"monthly_limit":5000,"used_credits":0,"utilization":0,"currency":"USD"},
         "limits":[{"kind":"session","group":"session","percent":12,"severity":"ok","resets_at":"2099-01-01T05:00:00+00:00","scope":null,"is_active":true},
                   {"kind":"weekly_all","group":"weekly","percent":34,"severity":"ok","resets_at":"2099-01-06T00:00:00+00:00","scope":null,"is_active":false}],
         "seven_day_breakdown":{"as_of":"2098-12-31T00:00:00Z","rows":[{"key":"opus","display_name":"Opus","percent":20}]}}
        """#
        let parsed = try XCTUnwrap(ClaudeUsageAPI.parse(Data(answer.utf8), now: now))
        XCTAssertEqual(parsed.windows.map(\.id), ["five_hour", "seven_day"], "a window under a code name says nothing a person can use")
        XCTAssertEqual(parsed.windows.map(\.usedPercent), [12, 34])
        // Only the list: the weekly entry is "weekly_all", and "not the one that bites right now" is still a limit.
        let listOnly = #"{"limits":[{"kind":"session","group":"session","percent":50,"resets_at":null,"is_active":false},{"kind":"weekly_all","group":"weekly","percent":70,"resets_at":null,"is_active":false}]}"#
        XCTAssertEqual(ClaudeUsageAPI.parse(Data(listOnly.utf8), now: now)?.windows.map(\.id), ["five_hour", "seven_day"])

        let scratch = Scratch()
        let home = scratch.file("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        XCTAssertNil(ClaudeUsageAPI.cached(home: home))
        let fetched = now.addingTimeInterval(-7200)
        let file = #"{"numStartups":3,"projects":{"/x":{"history":["secret prompt"]}},"oauthAccount":{"emailAddress":"x@example.org"},"cachedUsageUtilization":{"accountUuid":"u","fetchedAtMs":\#(Int(fetched.timeIntervalSince1970 * 1000)),"utilization":\#(answer)}}"#
        try Data(file.utf8).write(to: home.appendingPathComponent(".claude.json"))
        let cached = try XCTUnwrap(ClaudeUsageAPI.cached(home: home))
        XCTAssertEqual(cached.source, .agentCache)
        XCTAssertEqual(cached.capturedAt, fetched, "as old as the last time Claude Code looked, and said so")
        XCTAssertEqual(cached.windows.map(\.id), ["five_hour", "seven_day"])
        // A fresher answer from anywhere wins a window; an old cache whose windows have reset says nothing.
        let asked = ProviderLimits(windows: [RateLimitWindow(id: "five_hour", usedPercent: 60, resetsAt: now.addingTimeInterval(600))], capturedAt: now, source: .provider)
        let merged = try XCTUnwrap(ProviderLimits.merged([cached, asked], now: now))
        XCTAssertEqual(merged.windows.first { $0.id == "five_hour" }?.usedPercent, 60)
        XCTAssertEqual(merged.windows.first { $0.id == "seven_day" }?.usedPercent, 34)
        XCTAssertTrue(cached.current(now: Date(timeIntervalSince1970: 4_200_000_000)).windows.isEmpty)
        try Data(#"{"cachedUsageUtilization":{"fetchedAtMs":1,"utilization":{}}}"#.utf8).write(to: home.appendingPathComponent(".claude.json"))
        XCTAssertNil(ClaudeUsageAPI.cached(home: home))
    }

    func testChatGPTsAnswerAboutACodexPlanIsRead() throws {
        // A plan with only a weekly window, as seen: the second window is null.
        let weekly = Data(#"""
        {"plan_type":"pro","rate_limit":{"allowed":true,"limit_reached":false,
          "primary_window":{"used_percent":30,"limit_window_seconds":604800,"reset_after_seconds":580000,"reset_at":1790580000},
          "secondary_window":null},
         "credits":{"has_credits":false,"unlimited":false,"balance":"0"},"rate_limit_reset_credits":{"available_count":0}}
        """#.utf8)
        let limits = try XCTUnwrap(CodexUsageAPI.parse(weekly, now: now))
        XCTAssertEqual(limits.windows.map(\.id), ["primary"], "named as Codex's own files name them, so both sources fill the same rows")
        XCTAssertEqual(limits.windows[0].usedPercent, 30)
        XCTAssertEqual(limits.windows[0].minutes, 10080)
        XCTAssertEqual(limits.windows[0].resetsAt, Date(timeIntervalSince1970: 1_790_580_000))
        XCTAssertEqual(limits.plan, "pro")
        XCTAssertEqual(limits.source, .provider)

        let both = Data(#"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_after_seconds":600},"secondary_window":{"used_percent":140,"limit_window_seconds":604800,"reset_at":1790580000}}}"#.utf8)
        let two = try XCTUnwrap(CodexUsageAPI.parse(both, now: now))
        XCTAssertEqual(two.windows.map(\.minutes), [300, 10080])
        XCTAssertEqual(two.windows.map(\.usedPercent), [12, 100])
        XCTAssertEqual(two.windows[0].resetsAt, now.addingTimeInterval(600))
        XCTAssertNil(CodexUsageAPI.parse(Data(#"{"detail":"Unauthorized"}"#.utf8)))
        XCTAssertNil(CodexUsageAPI.parse(Data("<html>".utf8)))

        // Saved resets are counted from the list: used ones and ones past their date do not count.
        let saved = Data(#"{"credits":[{"status":"available","expires_at":"2099-01-01T00:00:00Z"},{"status":"available","expires_at":null},{"status":"available","expires_at":"2020-01-01T00:00:00Z"},{"status":"redeemed","expires_at":"2099-01-01T00:00:00Z"}],"available_count":9}"#.utf8)
        XCTAssertEqual(CodexUsageAPI.savedResets(saved, now: now), 2)
        XCTAssertEqual(CodexUsageAPI.savedResets(Data(#"{"credits":[],"available_count":0}"#.utf8), now: now), 0)
        XCTAssertNil(CodexUsageAPI.savedResets(Data(#"{"detail":"no"}"#.utf8), now: now))

        let request = CodexUsageAPI.request(CodexUsageAPI.usage, login: .init(token: "t", account: "acct"))
        XCTAssertEqual(request.url?.host, "chatgpt.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("niko-island/"), true, "asked under this app's own name, not as somebody else's client")
        XCTAssertEqual(CodexUsageAPI.savedResets.host, "chatgpt.com")
    }

    func testCodexsSignInCountsOnlyWhenItIsAChatGPTPlan() throws {
        let plan = Data(#"{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"i","access_token":"at","refresh_token":"rt","account_id":"acct"},"last_refresh":"2026-10-05T03:46:50Z"}"#.utf8)
        XCTAssertEqual(CodexLogin.parse(plan), CodexLogin.Login(token: "at", account: "acct"))
        // Older files do not name the mode.
        XCTAssertEqual(CodexLogin.parse(Data(#"{"tokens":{"access_token":"at"}}"#.utf8))?.token, "at")
        // An API key has no plan to ask about.
        XCTAssertNil(CodexLogin.parse(Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x","tokens":{"access_token":"at"}}"#.utf8)))
        XCTAssertNil(CodexLogin.parse(Data(#"{"auth_mode":"chatgpt","tokens":{}}"#.utf8)))
        XCTAssertNil(CodexLogin.parse(Data("nope".utf8)))

        let scratch = Scratch()
        let home = scratch.file("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try plan.write(to: home.appendingPathComponent(".codex/auth.json"))
        XCTAssertEqual(CodexLogin.read(home: home), .found(.init(token: "at", account: "acct")), "the file is read first: it asks nobody")
        // The name Codex files a Keychain sign-in under: "cli|" and 16 hex digits of its folder's path.
        let account = CodexLogin.keychainAccount(folder: home.appendingPathComponent(".codex"))
        XCTAssertTrue(account.hasPrefix("cli|"))
        XCTAssertEqual(account.count, 20)
        XCTAssertEqual(account, CodexLogin.keychainAccount(folder: home.appendingPathComponent(".codex")))
        XCTAssertNotEqual(account, CodexLogin.keychainAccount(folder: home.appendingPathComponent(".codex-other")))
    }

    // MARK: The client

    private final class Wire: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []
        private var _answers: [(Data, Int)] = []
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
        func queue(_ body: String, _ status: Int = 200) { lock.lock(); _answers.append((Data(body.utf8), status)); lock.unlock() }
        func send(_ request: URLRequest) throws -> (Data, Int) {
            lock.lock(); defer { lock.unlock() }
            _requests.append(request)
            guard !_answers.isEmpty else { throw URLError(.notConnectedToInternet) }
            return _answers.removeFirst()
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: Date
        init(_ now: Date) { _now = now }
        var now: Date { lock.lock(); defer { lock.unlock() }; return _now }
        func advance(_ seconds: TimeInterval) { lock.lock(); _now += seconds; lock.unlock() }
    }

    private let claudeAnswer = #"{"five_hour":{"utilization":37,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":{"utilization":61,"resets_at":"2099-01-03T00:00:00Z"}}"#
    private let glmAnswer = #"{"code":200,"data":{"level":"max","limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":9,"nextResetTime":4070908800000}]}}"#

    /// A sign-in that can be replaced mid-test, the way the agent replaces its own.
    private final class Stored<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Value
        init(_ value: Value) { _value = value }
        var value: Value {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
    }

    private func client(paths: NikoPaths, wire: Wire, clock: Clock, login: ClaudeCodeLogin.Outcome = .missing, key: String? = nil,
                        stored: Stored<ClaudeCodeLogin.Outcome>? = nil, codex: Stored<CodexLogin.Outcome>? = nil) -> ProviderLimitsClient {
        ProviderLimitsClient(paths: paths, secrets: .init(claudeLogin: { stored?.value ?? login }, glmKey: { key }, codexLogin: { codex?.value ?? .missing }),
                             transport: { try wire.send($0) }, clock: { clock.now }) { _ in }
    }

    /// The client also asks by itself when it is switched on; whichever call got there first, wait for its answer.
    private func settle(_ client: ProviderLimitsClient, _ provider: String) async {
        for _ in 0..<400 {
            if await client.current()[provider] != nil { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testNothingIsAskedUnlessSwitchedOnAndThenOnlyAtAPoliteRate() async throws {
        let scratch = Scratch()
        let paths = NikoPaths(root: scratch.file("ni"))
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        let wire = Wire(), clock = Clock(now)
        let fresh = ClaudeCodeLogin.Login(token: "secret-token", expiresAt: now.addingTimeInterval(3600), plan: "max")
        let asker = client(paths: paths, wire: wire, clock: clock, login: .found(fresh), key: "secret-key")

        await asker.refresh(force: true)
        XCTAssertTrue(wire.requests.isEmpty, "both switches are off")

        wire.queue(claudeAnswer)
        await asker.configure(.init(claude: true))
        await asker.refresh(force: true)
        await settle(asker, "claude")
        var results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .ok)
        XCTAssertEqual(results["claude"]?.limits?.windows.map(\.usedPercent), [37, 61])
        XCTAssertEqual(results["claude"]?.limits?.plan, "max", "the plan comes with the sign-in when the answer does not name it")
        XCTAssertNil(results["zcode"])
        XCTAssertEqual(wire.requests.map { $0.url?.host }, ["api.anthropic.com"])
        XCTAssertEqual(wire.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")

        // Too soon to ask again, even when pressed.
        clock.advance(10)
        await asker.refresh(force: true)
        XCTAssertEqual(wire.requests.count, 1)
        // On its own it waits five minutes.
        clock.advance(200)
        await asker.refresh()
        XCTAssertEqual(wire.requests.count, 1)

        // The other provider, with the user's key, to the service that was chosen.
        wire.queue(glmAnswer)
        await asker.configure(.init(claude: true, glm: true, glmRegion: .zai))
        await asker.refresh()
        await settle(asker, "zcode")
        results = await asker.current()
        XCTAssertEqual(results["zcode"]?.state, .ok)
        XCTAssertEqual(results["zcode"]?.limits?.plan, "max")
        XCTAssertEqual(wire.requests.last?.url?.host, "api.z.ai")
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "secret-key")

        // What is kept between runs: numbers. No sign-in, no key.
        let cached = try String(contentsOf: paths.cache.appendingPathComponent("provider-limits.json"), encoding: .utf8)
        XCTAssertFalse(cached.contains("secret"))
        XCTAssertTrue(cached.contains("five_hour"))
        let reopened = client(paths: paths, wire: Wire(), clock: clock)
        let remembered = await reopened.current()
        XCTAssertEqual(remembered["claude"]?.limits?.windows.count, 2, "the last answer is shown again after a restart")

        // Switching off forgets the answer, and stops asking.
        await asker.configure(.init())
        let after = await asker.current()
        XCTAssertTrue(after.isEmpty)
        clock.advance(4000)
        await asker.refresh(force: true)
        XCTAssertEqual(wire.requests.count, 2)
    }

    /// Once a provider has answered, it is asked again only while its agent is at work.
    func testAnAnsweredProviderWaitsForItsAgentToWork() async throws {
        let scratch = Scratch()
        let paths = NikoPaths(root: scratch.file("ni"))
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        let wire = Wire(), clock = Clock(now)
        let fresh = ClaudeCodeLogin.Login(token: "t", expiresAt: now.addingTimeInterval(86_400), plan: "pro")
        let asker = client(paths: paths, wire: wire, clock: clock, login: .found(fresh))
        await asker.noteActivity(["codex": now])
        wire.queue(claudeAnswer)
        await asker.configure(.init(claude: true))
        await asker.refresh(force: true)
        await settle(asker, "claude")
        XCTAssertEqual(wire.requests.count, 1, "with no answer yet it asks, whoever is at work")

        clock.advance(600)
        await asker.refresh()
        XCTAssertEqual(wire.requests.count, 1, "Claude Code has not been heard from: its numbers cannot have moved")
        await asker.refresh(force: true)
        XCTAssertEqual(wire.requests.count, 2, "Check now always asks")

        wire.queue(claudeAnswer)
        clock.advance(600)
        await asker.noteActivity(["claude": clock.now])
        await asker.refresh()
        XCTAssertEqual(wire.requests.count, 3)
        // Two hours later without a word from it, it stops again.
        clock.advance(ProviderLimitsClient.activeWindow + 1)
        await asker.refresh()
        XCTAssertEqual(wire.requests.count, 3)
    }

    func testASignInPastItsDateIsOfferedOnceAndNeverRenewed() async throws {
        let scratch = Scratch()
        let paths = NikoPaths(root: scratch.file("ni"))
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        let wire = Wire(), clock = Clock(now)
        let stored = Stored(ClaudeCodeLogin.Outcome.found(.init(token: "old", expiresAt: now.addingTimeInterval(-60), plan: "pro")))
        let asker = client(paths: paths, wire: wire, clock: clock, stored: stored)
        // The date is Claude Code's note to itself; whether the sign-in still works is Anthropic's call. It says no
        // (and has been seen to say so as "too many requests" as well as "unauthorized").
        wire.queue(#"{"error":{"type":"rate_limit_error"}}"#, 429)
        await asker.configure(.init(claude: true))
        await asker.refresh(force: true)
        await settle(asker, "claude")
        var results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .loginExpired)
        XCTAssertEqual(wire.requests.count, 1)

        // The same sign-in is not offered again, however long we wait or however often "Check now" is pressed.
        for _ in 0..<3 {
            clock.advance(400)
            await asker.refresh(force: true)
        }
        results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .loginExpired)
        XCTAssertEqual(wire.requests.count, 1, "one refusal is enough")

        // Claude Code ran and put a new one there: that one is asked with.
        stored.value = .found(.init(token: "new", expiresAt: clock.now.addingTimeInterval(3600), plan: "pro"))
        wire.queue(claudeAnswer)
        clock.advance(400)
        await asker.refresh()
        results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .ok)
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new")

        // A date that was wrong does not stand in the way of an answer.
        let lucky = client(paths: NikoPaths(root: scratch.file("ni2")), wire: wire, clock: clock,
                           login: .found(.init(token: "dated", expiresAt: clock.now.addingTimeInterval(-60), plan: nil)))
        try FileManager.default.createDirectory(at: scratch.file("ni2/cache"), withIntermediateDirectories: true)
        wire.queue(claudeAnswer)
        await lucky.configure(.init(claude: true))
        await lucky.refresh(force: true)
        await settle(lucky, "claude")
        let answered = await lucky.current()
        XCTAssertEqual(answered["claude"]?.state, .ok)

        let source = try String(contentsOf: repositoryRoot.appendingPathComponent("Sources/NikoCore/Usage/ProviderLookups.swift"), encoding: .utf8)
        for forbidden in ["refresh_token", "refreshToken\"]", "oauth/token", "SecItemUpdate"] {
            XCTAssertFalse(source.contains(forbidden), "renewing or rewriting another app's sign-in is not our business: \(forbidden)")
        }
    }

    func testCodexIsAskedWithItsOwnSignInAndSavedResetsComeAlong() async throws {
        let scratch = Scratch()
        let paths = NikoPaths(root: scratch.file("ni"))
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        let wire = Wire(), clock = Clock(now)
        let codex = Stored(CodexLogin.Outcome.found(.init(token: "codex-secret", account: "acct")))
        let asker = client(paths: paths, wire: wire, clock: clock, codex: codex)
        let usage = #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":30,"limit_window_seconds":604800,"reset_at":4070908800},"secondary_window":null}}"#

        await asker.refresh(force: true)
        XCTAssertTrue(wire.requests.isEmpty, "off until switched on")

        wire.queue(usage)
        wire.queue(#"{"credits":[{"status":"available","expires_at":null},{"status":"available","expires_at":"2099-01-01T00:00:00Z"}]}"#)
        await asker.configure(.init(codex: true))
        await asker.refresh(force: true)
        await settle(asker, "codex")
        var results = await asker.current()
        XCTAssertEqual(results["codex"]?.state, .ok)
        XCTAssertEqual(results["codex"]?.limits?.windows.map(\.id), ["primary"])
        XCTAssertEqual(results["codex"]?.limits?.resetsLeft, 2)
        XCTAssertEqual(wire.requests.map { $0.url?.path }, ["/backend-api/wham/usage", "/backend-api/wham/rate-limit-reset-credits"])
        XCTAssertTrue(wire.requests.allSatisfy { $0.url?.host == "chatgpt.com" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer codex-secret" })
        let cached = try String(contentsOf: paths.cache.appendingPathComponent("provider-limits.json"), encoding: .utf8)
        XCTAssertFalse(cached.contains("secret"))
        XCTAssertFalse(cached.contains("acct"))

        // The second question going unanswered costs nothing but the count.
        clock.advance(400)
        wire.queue(usage)
        wire.queue("{}", 500)
        await asker.refresh()
        results = await asker.current()
        XCTAssertEqual(results["codex"]?.state, .ok)
        XCTAssertNil(results["codex"]?.limits?.resetsLeft)

        // Turned down: Codex renews its own sign-in, we do not, and we do not knock again with the same one.
        clock.advance(400)
        wire.queue(#"{"detail":"Unauthorized"}"#, 401)
        await asker.refresh()
        results = await asker.current()
        XCTAssertEqual(results["codex"]?.state, .loginExpired)
        XCTAssertEqual(results["codex"]?.limits?.windows.count, 1, "the last good answer stays on screen")
        let asked = wire.requests.count
        clock.advance(400)
        await asker.refresh(force: true)
        XCTAssertEqual(wire.requests.count, asked)
        codex.value = .found(.init(token: "renewed", account: "acct"))
        wire.queue(usage)
        wire.queue(#"{"credits":[]}"#)
        clock.advance(400)
        await asker.refresh()
        results = await asker.current()
        XCTAssertEqual(results["codex"]?.state, .ok)
        XCTAssertEqual(results["codex"]?.limits?.resetsLeft, 0)

        // No ChatGPT plan signed in: nothing to ask with, nothing asked.
        codex.value = .missing
        clock.advance(400)
        let before = wire.requests.count
        await asker.refresh()
        results = await asker.current()
        XCTAssertEqual(results["codex"]?.state, .noLogin)
        XCTAssertEqual(wire.requests.count, before)
    }

    func testFailuresAreNamedAndDoNotEraseWhatWasKnown() async throws {
        let scratch = Scratch()
        let paths = NikoPaths(root: scratch.file("ni"))
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        let wire = Wire(), clock = Clock(now)
        let login = ClaudeCodeLogin.Login(token: "t", expiresAt: nil, plan: nil)
        let asker = client(paths: paths, wire: wire, clock: clock, login: .found(login), key: nil)
        wire.queue(claudeAnswer)
        await asker.configure(.init(claude: true, glm: true))
        await asker.refresh(force: true)
        await settle(asker, "claude")
        var results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .ok)
        XCTAssertEqual(results["zcode"]?.state, .noKey, "no key, no request")
        XCTAssertEqual(wire.requests.count, 1)

        for (body, status, expected) in [("{}", 429, ProviderLimitsClient.State.rateLimited), ("nope", 200, .unreadable), ("", 503, .unreachable)] {
            clock.advance(400)
            wire.queue(body, status)
            await asker.refresh()
            results = await asker.current()
            XCTAssertEqual(results["claude"]?.state, expected)
            XCTAssertEqual(results["claude"]?.limits?.windows.count, 2, "\(expected): the last good answer stays on screen")
        }
        // The network being away is a state, not a crash.
        clock.advance(400)
        await asker.refresh()
        results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .unreachable)

        // A sign-in Anthropic turns down is not offered a second time.
        clock.advance(400)
        wire.queue("{}", 401)
        await asker.refresh()
        results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .unauthorized)
        let asked = wire.requests.count
        clock.advance(400)
        await asker.refresh()
        results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .unauthorized)
        XCTAssertEqual(wire.requests.count, asked)
        XCTAssertEqual(results["claude"]?.limits?.windows.count, 2)

        // "Deny" at the Keychain stands until the user asks again.
        let refused = client(paths: NikoPaths(root: scratch.file("ni2")), wire: wire, clock: clock, login: .denied)
        try FileManager.default.createDirectory(at: scratch.file("ni2/cache"), withIntermediateDirectories: true)
        await refused.configure(.init(claude: true))
        await refused.refresh()
        await settle(refused, "claude")
        let denied = await refused.current()
        XCTAssertEqual(denied["claude"]?.state, .denied)
    }

    func testLimitsFromSeveralSourcesMergeByWhoLookedLast() {
        let old = ProviderLimits(windows: [RateLimitWindow(id: "five_hour", usedPercent: 10, resetsAt: now.addingTimeInterval(600)),
                                           RateLimitWindow(id: "seven_day", usedPercent: 20, resetsAt: now.addingTimeInterval(6000))],
                                 capturedAt: now.addingTimeInterval(-500), plan: "pro", source: .statusLine)
        let new = ProviderLimits(windows: [RateLimitWindow(id: "five_hour", usedPercent: 100, resetsAt: now.addingTimeInterval(600))],
                                 capturedAt: now.addingTimeInterval(-5), source: .limitReached)
        let gone = ProviderLimits(windows: [RateLimitWindow(id: "extra", usedPercent: 5, resetsAt: now.addingTimeInterval(-1))], capturedAt: now)
        let merged = ProviderLimits.merged([old, gone, new], now: now)
        XCTAssertEqual(merged?.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(merged?.windows.first?.usedPercent, 100, "the newer word on the same window")
        XCTAssertEqual(merged?.source, .limitReached)
        XCTAssertEqual(merged?.plan, "pro")
        XCTAssertNil(ProviderLimits.merged([gone], now: now))
        // Round trip, as stored.
        var stored = new
        stored.resetsLeft = 7
        XCTAssertEqual(ProviderLimits(json: stored.json), stored)
    }

    // MARK: Kimi, MiniMax, Gemini

    func testKimisAnswerIsReadInNumbersOrText() throws {
        let answer = #"{"usage":{"limit":"100","remaining":"74","resetTime":"2099-01-05T00:00:00Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":200,"remaining":80,"resetTime":4070908800}}]}"#
        let limits = try XCTUnwrap(KimiUsageAPI.parse(Data(answer.utf8)))
        XCTAssertEqual(limits.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(limits.windows[0].usedPercent, 60, accuracy: 0.01)
        XCTAssertEqual(limits.windows[0].minutes, 300)
        XCTAssertEqual(limits.windows[0].resetsAt, Date(timeIntervalSince1970: 4_070_908_800))
        XCTAssertEqual(limits.windows[1].usedPercent, 26, accuracy: 0.01)
        XCTAssertEqual(limits.windows[1].resetsAt, Date(timeIntervalSince1970: 4_070_908_800 + 4 * 86_400))
        // A window of another length keeps its own name; nothing usable is no answer.
        let hourly = #"{"limits":[{"window":{"duration":1,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":10,"remaining":10}}]}"#
        XCTAssertEqual(KimiUsageAPI.parse(Data(hourly.utf8))?.windows.first?.minutes, 60)
        XCTAssertNil(KimiUsageAPI.parse(Data(#"{"limits":[],"usage":{"limit":0}}"#.utf8)))
        XCTAssertEqual(KimiUsageAPI.request(key: "k").url?.host, "api.kimi.com")
    }

    func testMiniMaxsAnswerCountsOnlyTheCodingModelsAndARealWeek() {
        let answer = #"{"model_remains":[{"model_name":"video","current_interval_remaining_percent":10},{"model_name":"general","current_interval_remaining_percent":72.5,"end_time":4070908800000,"current_weekly_status":1,"current_weekly_remaining_percent":40,"weekly_end_time":4071513600000}],"base_resp":{"status_code":0,"status_msg":"success"}}"#
        guard case .limits(let limits) = MiniMaxQuotaAPI.parse(Data(answer.utf8)) else { return XCTFail("expected limits") }
        XCTAssertEqual(limits.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(limits.windows[0].usedPercent, 27.5, accuracy: 0.01)
        XCTAssertEqual(limits.windows[1].usedPercent, 60, accuracy: 0.01)
        XCTAssertEqual(limits.windows[1].resetsAt, Date(timeIntervalSince1970: 4_071_513_600))
        // Status 3: this plan has no weekly limit, whatever the percentage says.
        let noWeek = answer.replacingOccurrences(of: #""current_weekly_status":1"#, with: #""current_weekly_status":3"#)
        guard case .limits(let short) = MiniMaxQuotaAPI.parse(Data(noWeek.utf8)) else { return XCTFail("expected limits") }
        XCTAssertEqual(short.windows.map(\.id), ["five_hour"])
        XCTAssertEqual(MiniMaxQuotaAPI.parse(Data(#"{"base_resp":{"status_code":1004,"status_msg":"login fail"}}"#.utf8)), .refused)
        XCTAssertEqual(MiniMaxQuotaAPI.parse(Data("<html>".utf8)), .unreadable)
        XCTAssertEqual(MiniMaxQuotaAPI.url(.cn).host, "api.minimaxi.com")
        XCTAssertEqual(MiniMaxQuotaAPI.url(.global).host, "api.minimax.io")
    }

    func testGeminiQuotasAreGroupedByModelFamily() throws {
        let answer = #"{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":0.8,"resetTime":"2099-01-02T00:00:00Z"},{"modelId":"gemini-3-pro-preview","remainingFraction":0.25,"resetTime":"2099-01-02T01:00:00Z"},{"modelId":"gemini-2.5-flash","remainingFraction":1},{"modelId":"gemini-2.5-flash-lite","remainingFraction":"0.5"}]}"#
        let limits = try XCTUnwrap(GeminiQuotaAPI.parse(Data(answer.utf8)))
        XCTAssertEqual(limits.windows.map(\.id), ["daily_pro", "daily_flash", "daily_flash_lite"])
        XCTAssertEqual(limits.windows[0].usedPercent, 75, accuracy: 0.01, "the family's tightest bucket")
        XCTAssertEqual(limits.windows[0].resetsAt, ISOTime.parse("2099-01-02T01:00:00Z").map(Date.init(timeIntervalSince1970:)))
        XCTAssertEqual(limits.windows[1].usedPercent, 0, accuracy: 0.01)
        XCTAssertEqual(limits.windows[2].usedPercent, 50, accuracy: 0.01)
        XCTAssertNil(GeminiQuotaAPI.parse(Data(#"{"buckets":[]}"#.utf8)))

        XCTAssertEqual(GeminiQuotaAPI.project(Data(#"{"cloudaicompanionProject":"proj-1","currentTier":{"name":"Free"}}"#.utf8)).id, "proj-1")
        XCTAssertEqual(GeminiQuotaAPI.project(Data(#"{"cloudaicompanionProject":{"id":"proj-2"}}"#.utf8)).id, "proj-2")
        let request = GeminiQuotaAPI.quotaRequest(token: "t", project: "proj-1")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody.flatMap { try? JSONValue.parse($0) }, .object(["project": .string("proj-1")]))
    }

    func testGeminiCLIsSignInIsReadInEitherForm() throws {
        let file = try XCTUnwrap(GeminiLogin.parse(Data(#"{"access_token":"a1","refresh_token":"r1","expiry_date":4070908800000}"#.utf8)))
        XCTAssertEqual(file, GeminiLogin.Login(token: "a1", expiresAt: Date(timeIntervalSince1970: 4_070_908_800)))
        let keychain = try XCTUnwrap(GeminiLogin.parse(Data(#"{"token":{"accessToken":"a2","refreshToken":"r2","expiresAt":4070908800000},"updatedAt":1}"#.utf8)))
        XCTAssertEqual(keychain.token, "a2")
        XCTAssertNil(GeminiLogin.parse(Data(#"{"refresh_token":"only"}"#.utf8)), "a refresh token alone is of no use: it is never spent here")
    }

    func testTheNewPlansAreAskedOnlyTheirOwnWay() async throws {
        let scratch = Scratch()
        let wire = Wire()
        let clock = Clock(Date(timeIntervalSince1970: 4_000_000_000))
        let gemini = Stored<GeminiLogin.Outcome>(.found(.init(token: "g-token", expiresAt: clock.now - 60)))
        let client = ProviderLimitsClient(
            paths: scratch.paths,
            secrets: .init(claudeLogin: { .missing }, glmKey: { nil }, kimiKey: { nil }, minimaxKey: { "mm-key" },
                           geminiLogin: { gemini.value }),
            transport: { try wire.send($0) }, clock: { clock.now }) { _ in }

        // No key, and a sign-in that has run out: nothing goes out.
        await client.configure(.init(kimi: true, gemini: true))
        await client.refresh(force: true)
        await settle(client, ProviderLimitsClient.gemini)
        var results = await client.current()
        XCTAssertEqual(results[ProviderLimitsClient.kimi]?.state, .noKey)
        XCTAssertEqual(results[ProviderLimitsClient.gemini]?.state, .loginExpired)
        XCTAssertTrue(wire.requests.isEmpty, "an expired token is never sent, and never renewed")

        // A good sign-in: which project, then that project's buckets.
        gemini.value = .found(.init(token: "g-token", expiresAt: clock.now + 3600))
        wire.queue(#"{"cloudaicompanionProject":"proj-9","currentTier":{"name":"Free"}}"#)
        wire.queue(#"{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":0.4}]}"#)
        clock.advance(400)
        await client.refresh(force: true)
        results = await client.current()
        XCTAssertEqual(results[ProviderLimitsClient.gemini]?.state, .ok)
        XCTAssertEqual(results[ProviderLimitsClient.gemini]?.limits?.plan, "Free")
        XCTAssertEqual(results[ProviderLimitsClient.gemini]?.limits?.windows.first?.usedPercent ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual(wire.requests.map { $0.url?.absoluteString ?? "" },
                       ["https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
                        "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"])
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer g-token")

        // MiniMax turns the key down in the body of a 200.
        await client.configure(.init(minimax: true, minimaxRegion: .global))
        wire.queue(#"{"base_resp":{"status_code":1004,"status_msg":"login fail"}}"#)
        clock.advance(400)
        await client.refresh(force: true)
        await settle(client, ProviderLimitsClient.minimax)
        results = await client.current()
        XCTAssertEqual(results[ProviderLimitsClient.minimax]?.state, .unauthorized)
        XCTAssertEqual(wire.requests.last?.url?.host, "api.minimax.io")
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer mm-key")
        XCTAssertNil(results[ProviderLimitsClient.gemini], "switched off: forgotten")
        for request in wire.requests { XCTAssertTrue(ProviderLimitsClient.hosts.contains(request.url?.host ?? ""), "\(request)") }
        await client.configure(.init())
    }

    /// SPEC §5: the network is the price list and, when switched on, the providers and the update check. Nothing else.
    func testCursorsSpendingPageIsRead() throws {
        let answer = #"""
        {"billingCycleStart":"2026-08-18T08:09:13.000Z","billingCycleEnd":"2026-09-18T08:09:13.000Z","membershipType":"pro",
         "limitType":"user","isUnlimited":false,
         "individualUsage":{"plan":{"enabled":true,"used":1516,"limit":2000,"remaining":484,
           "breakdown":{"included":1516,"bonus":0,"total":1516},"autoPercentUsed":3.3,"apiPercentUsed":0.71,"totalPercentUsed":3.06},
           "onDemand":{"enabled":true,"used":500,"limit":2000,"remaining":1500}},"teamUsage":{}}
        """#
        let limits = try XCTUnwrap(CursorQuotaAPI.parse(Data(answer.utf8), now: now))
        XCTAssertEqual(limits.plan, "pro")
        XCTAssertEqual(limits.windows.map(\.id), ["cursor_total", "cursor_auto", "cursor_api", "cursor_on_demand"])
        XCTAssertEqual(limits.windows.map { Int($0.usedPercent.rounded()) }, [3, 3, 1, 25])
        XCTAssertEqual(limits.windows.first?.windowMinutes, 44_640)
        XCTAssertEqual(limits.windows.first?.resetsAt, ISOTime.flexible(.string("2026-09-18T08:09:13.000Z")).map(Date.init(timeIntervalSince1970:)))
        XCTAssertNil(CursorQuotaAPI.parse(Data(#"{"isUnlimited":true}"#.utf8)), "an unlimited plan has nothing to show")
        // No percentages: the dollars used of the limit say it.
        let plain = try XCTUnwrap(CursorQuotaAPI.parse(Data(#"{"individualUsage":{"plan":{"enabled":true,"used":500,"limit":2000}}}"#.utf8)))
        XCTAssertEqual(plain.windows.first?.usedPercent, 25)
    }

    func testCursorsSignInIsReadFromItsOwnDatabase() throws {
        func token(_ claims: String) -> String {
            let body = Data(claims.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            return "eyJhbGciOiJIUzI1NiJ9.\(body).c2ln"
        }
        let login = try XCTUnwrap(CursorLogin.login(token: token(#"{"sub":"auth0|user_01ABC","exp":4102444800}"#)))
        XCTAssertEqual(login.userID, "user_01ABC")
        XCTAssertEqual(login.expiresAt, Date(timeIntervalSince1970: 4_102_444_800))
        XCTAssertEqual(CursorQuotaAPI.request(login: login).value(forHTTPHeaderField: "Cookie"),
                       "WorkosCursorSessionToken=user_01ABC%3A%3A" + login.token)
        XCTAssertNil(CursorLogin.login(token: "not-a-token"))
        XCTAssertNil(CursorLogin.login(token: token(#"{"sub":"auth0|user;evil=1"}"#)), "only a plain id goes into the cookie")

        let scratch = Scratch()
        let home = scratch.file("home")
        let path = CursorLogin.databasePath(home: home)
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        XCTAssertEqual(CursorLogin.read(home: home), .missing)
        let db = try SQLiteDB(path: path)
        try db.execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
        try db.run("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', ?)", [.text(token(#"{"sub":"github|user_9"}"#))])
        db.close()
        guard case .found(let found) = CursorLogin.read(home: home) else { return XCTFail("the sign-in is found") }
        XCTAssertEqual(found.userID, "user_9")
        XCTAssertTrue(ProviderLimitsClient.hosts.contains("cursor.com"))
    }

    /// The answer Kiro 1.3's own usage panel reads (shape checked live, numbers made up).
    func testKirosCreditsAreRead() throws {
        let answer = #"""
        {"daysUntilReset":null,"limits":null,"nextDateReset":1.7624448E9,"overageConfiguration":{"overageStatus":"DISABLED"},
         "subscriptionInfo":{"overageCapability":"OVERAGE_INCAPABLE","subscriptionManagementTarget":"MANAGE","subscriptionTitle":"KIRO PRO","type":"Q_DEVELOPER_STANDALONE_PRO","upgradeCapability":"UPGRADE_CAPABLE"},
         "usageBreakdownList":[{"bonuses":[{"bonusCode":"WELCOME","status":"ACTIVE","currentUsage":50,"usageLimit":500,"expiresAt":1.7630E9}],
           "currency":"USD","currentOverages":0,"currentUsage":20,"currentUsageWithPrecision":20.4,"displayName":"Credit","displayNamePlural":"Credits",
           "freeTrialInfo":{"freeTrialStatus":"ACTIVE","currentUsage":10,"usageLimit":100,"freeTrialExpiry":1.7625E9},
           "nextDateReset":1.7624448E9,"resourceType":"CREDIT","unit":"INVOCATIONS","usageLimit":1000,"usageLimitWithPrecision":1000}],
         "userInfo":{"email":null,"userId":"u"}}
        """#
        let limits = try XCTUnwrap(KiroQuotaAPI.parse(Data(answer.utf8), now: now))
        XCTAssertEqual(limits.plan, "KIRO PRO")
        XCTAssertEqual(limits.windows.map(\.id), ["kiro_credits", "kiro_trial", "kiro_bonus"])
        XCTAssertEqual(limits.windows.map { ($0.usedPercent * 100).rounded() / 100 }, [2.04, 10, 10])
        XCTAssertEqual(limits.windows.first?.resetsAt, Date(timeIntervalSince1970: 1_762_444_800))
        XCTAssertNil(KiroQuotaAPI.parse(Data(#"{"usageBreakdownList":[]}"#.utf8)))
    }

    func testKirosSignInIsReadOnlyWhileGood() throws {
        let scratch = Scratch()
        let home = scratch.file("home")
        XCTAssertEqual(KiroLogin.read(home: home), .missing)
        scratch.write("home/.aws/sso/cache/kiro-auth-token.json",
                      #"{"accessToken":"tok","refreshToken":"r","expiresAt":"2099-01-01T00:00:00.000Z","authMethod":"IdC","provider":"Enterprise","region":"us-east-1"}"#)
        XCTAssertEqual(KiroLogin.read(home: home), .missing, "no profile, nothing to ask about")
        scratch.write("home/Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent/profile.json",
                      #"{"arn":"arn:aws:codewhisperer:eu-central-1:123456789012:profile/ABC","name":"x"}"#)
        guard case .found(let login) = KiroLogin.read(home: home) else { return XCTFail("found") }
        XCTAssertEqual(login.region, "eu-central-1", "the profile's region picks the service")
        XCTAssertEqual(login.tokenType, "SSO_OIDC")
        let request = try XCTUnwrap(KiroQuotaAPI.request(login: login))
        XCTAssertEqual(request.url?.host, "management.eu-central-1.kiro.dev")
        XCTAssertTrue(ProviderLimitsClient.hosts.contains(request.url?.host ?? ""))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "TokenType"), "SSO_OIDC")
        XCTAssertTrue(request.url?.query?.contains("origin=AI_EDITOR") ?? false)
        scratch.write("home/.aws/sso/cache/kiro-auth-token.json",
                      #"{"accessToken":"tok","expiresAt":"2020-01-01T00:00:00.000Z","authMethod":"IdC"}"#)
        XCTAssertEqual(KiroLogin.read(home: home), .expired, "never renewed here")
    }

    func testKirosSpendingIsCountedFromItsSessions() throws {
        let scratch = Scratch()
        func iso(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }
        let at = Date()
        let lines = [
            #"{"id":"1","timestamp":"\#(iso(at.addingTimeInterval(-600)))","payload":{"type":"usage_summary","promptTurnSummaries":[{"unit":"credit","unitPlural":"credits","usage":6.25}],"status":"success"}}"#,
            #"{"id":"2","timestamp":"\#(iso(at.addingTimeInterval(-3 * 86_400)))","payload":{"type":"usage_summary","promptTurnSummaries":[{"unit":"credit","usage":1.5},{"unit":"credit","usage":0.5}]}}"#,
            #"{"id":"3","timestamp":"\#(iso(at))","payload":{"type":"assistant","content":"usage_summary is a word here"}}"#,
        ]
        scratch.write("home/.kiro/sessions/w/sess_a/messages.jsonl", lines.joined(separator: "\n") + "\n")
        let credits = try XCTUnwrap(KiroCredits(home: scratch.file("home")).totals(now: at))
        XCTAssertEqual(credits.fiveHours, 6.25)
        XCTAssertEqual(credits.week, 8.25)
        XCTAssertEqual(credits.month, 8.25)
        XCTAssertEqual(credits.days.count, 7)
        XCTAssertEqual(credits.days.last, 6.25)
    }

    func testOnlyFourFilesCanReachTheNetwork() throws {
        let sources = repositoryRoot.appendingPathComponent("Sources")
        var offenders: [String] = []
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in walker where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("URLSession") || text.contains("NWConnection(") || text.contains("CFStream") {
                offenders.append(file.lastPathComponent)
            }
        }
        // The price list, the provider lookups, and a line to the user's own phone: each off until switched on.
        // And, approved by the owner, a daily question to GitHub about a new version.
        XCTAssertEqual(offenders.sorted(), ["Pricing.swift", "ProviderLookups.swift", "Push.swift", "Updates.swift"])
        XCTAssertFalse(NikoSettings().updateChecks)
        XCTAssertFalse(NikoSettings().kimiLimitsLookup)
        XCTAssertFalse(NikoSettings().minimaxLimitsLookup)
        XCTAssertFalse(NikoSettings().geminiLimitsLookup)
        XCTAssertFalse(NikoSettings().claudeLimitsLookup)
        XCTAssertFalse(NikoSettings().glmLimitsLookup)
        XCTAssertFalse(NikoSettings().codexLimitsLookup)
        XCTAssertFalse(NikoSettings().pricingRefreshEnabled)
        XCTAssertFalse(NikoSettings().pushEnabled)
    }
}
