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

    private func client(paths: NikoPaths, wire: Wire, clock: Clock, login: ClaudeCodeLogin.Outcome = .missing, key: String? = nil) -> ProviderLimitsClient {
        ProviderLimitsClient(paths: paths, secrets: .init(claudeLogin: { login }, glmKey: { key }),
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

    func testASignInThatHasRunOutIsNotSentAndNeverRenewed() async throws {
        let scratch = Scratch()
        let paths = NikoPaths(root: scratch.file("ni"))
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        let wire = Wire(), clock = Clock(now)
        let stale = ClaudeCodeLogin.Login(token: "old", expiresAt: now.addingTimeInterval(-60), plan: "pro")
        let asker = client(paths: paths, wire: wire, clock: clock, login: .found(stale))
        await asker.configure(.init(claude: true))
        await asker.refresh(force: true)
        await settle(asker, "claude")
        let results = await asker.current()
        XCTAssertEqual(results["claude"]?.state, .loginExpired)
        XCTAssertTrue(wire.requests.isEmpty, "an expired sign-in goes nowhere, and nothing here asks for a new one")
        let source = try String(contentsOf: repositoryRoot.appendingPathComponent("Sources/NikoCore/Usage/ProviderLookups.swift"), encoding: .utf8)
        for forbidden in ["refresh_token", "refreshToken\"]", "oauth/token", "SecItemUpdate"] {
            XCTAssertFalse(source.contains(forbidden), "renewing or rewriting another app's sign-in is not our business: \(forbidden)")
        }
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

        for (body, status, expected) in [("{}", 429, ProviderLimitsClient.State.rateLimited), ("nope", 200, .unreadable), ("{}", 401, .unauthorized), ("", 503, .unreachable)] {
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

    /// SPEC §5: the network is the price list and, when switched on, the providers. Nothing else.
    func testOnlyTwoFilesCanReachTheNetwork() throws {
        let sources = repositoryRoot.appendingPathComponent("Sources")
        var offenders: [String] = []
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in walker where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("URLSession") || text.contains("NWConnection(") || text.contains("CFStream") {
                offenders.append(file.lastPathComponent)
            }
        }
        XCTAssertEqual(offenders.sorted(), ["Pricing.swift", "ProviderLookups.swift"])
        XCTAssertFalse(NikoSettings().claudeLimitsLookup)
        XCTAssertFalse(NikoSettings().glmLimitsLookup)
        XCTAssertFalse(NikoSettings().pricingRefreshEnabled)
    }
}
