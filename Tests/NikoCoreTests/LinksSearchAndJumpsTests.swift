import XCTest
@testable import NikoCore

/// 0.11: links into the app, finding a session, more exact jumps, a sign-in for one's own
/// push server, putting removed hooks back, the warning level and the months of usage.
final class LinksSearchAndJumpsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(source: String = "claude", cwd: String? = "/Users/me/Projects/niko island", id: String = "a1-b2",
                         terminal: TerminalContext = TerminalContext()) -> Session {
        Session(key: SessionKey(source: source, sessionID: id), cwd: cwd, transcriptPath: nil, title: "t", startedAt: now, lastEventAt: now,
                phaseSince: now, activity: .waiting, phase: .waiting, terminal: terminal, ancestors: [], firstPrompt: nil)
    }

    // MARK: nikoisland:// links

    func testLinksOnlyDoHarmlessThings() throws {
        func link(_ text: String) -> IslandLink? { URL(string: text).flatMap(IslandLink.init) }
        XCTAssertEqual(link("nikoisland://quiet?minutes=45"), .quiet(minutes: 45))
        XCTAssertEqual(link("nikoisland://quiet?hours=1.5"), .quiet(minutes: 90))
        XCTAssertEqual(link("nikoisland://quiet"), .quiet(minutes: nil))
        XCTAssertEqual(link("nikoisland://quiet?hours=1e308"), .quiet(minutes: 1440), "clamp before converting a huge finite number")
        XCTAssertNil(link("nikoisland://quiet?hours=1e309"))
        XCTAssertEqual(link("nikoisland://quiet?minutes=100000"), .quiet(minutes: 1440), "at most a day")
        XCTAssertEqual(link("nikoisland://quiet/off"), .quietOff)
        XCTAssertEqual(link("nikoisland://quiet?minutes=0"), .quietOff)
        XCTAssertNil(link("nikoisland://quiet?minutes=-5"))
        XCTAssertNil(link("nikoisland://quiet?minutes=soon"))
        XCTAssertEqual(link("NikoIsland://Open"), .open)
        XCTAssertEqual(link("nikoisland://switcher"), .switcher)
        XCTAssertEqual(link("nikoisland://settings/usage"), .settings(page: "usage"))
        XCTAssertEqual(link("nikoisland://settings"), .settings(page: nil))
        // Nothing that answers a request, and nothing of another scheme.
        XCTAssertNil(link("nikoisland://allow"))
        XCTAssertNil(link("nikoisland://approve?id=1"))
        XCTAssertNil(link("https://quiet"))
    }

    // MARK: Finding a session

    func testTypedLettersFindSessionsTheWayPeopleTypeThem() {
        XCTAssertNotNil(QuickFind.score("niko", fields: ["niko-island"]))
        XCTAssertNotNil(QuickFind.score("nkis", fields: ["niko-island"]), "letters in order, apart")
        XCTAssertNil(QuickFind.score("xyz", fields: ["niko-island", "Claude Code"]))
        XCTAssertNotNil(QuickFind.score("CAFE", fields: ["café menu"]), "case and accents do not matter")
        XCTAssertNotNil(QuickFind.score("登录", fields: ["修复登录页的样式"]), "any script")
        XCTAssertEqual(QuickFind.score("", fields: ["anything"]), 0)
        // Every word has to be found, each in any field.
        XCTAssertNotNil(QuickFind.score("island codex", fields: ["niko-island", "Codex"]))
        XCTAssertNil(QuickFind.score("island gemini", fields: ["niko-island", "Codex"]))
        // Whole words beat scattered letters; the start beats the middle; the first field counts a little more.
        let whole = QuickFind.score("api", fields: ["api-server"]) ?? 0
        let middle = QuickFind.score("api", fields: ["rapid"]) ?? 0
        let scattered = QuickFind.score("api", fields: ["a pixel island"]) ?? 0
        XCTAssertGreaterThan(whole, middle)
        XCTAssertGreaterThan(middle, scattered)
        XCTAssertGreaterThan(QuickFind.score("web", fields: ["web", "x"]) ?? 0, QuickFind.score("web", fields: ["x", "web"]) ?? 0)
    }

    // MARK: Jumps

    func testWezTermAndKittyAreAddressedExactly() {
        var wez = TerminalContext()
        wez.termProgram = "WezTerm"
        wez.weztermPane = "12"
        wez.weztermSocket = "/Users/me/.local/share/wezterm/gui-sock-4242"
        let target = JumpTarget(terminal: wez)
        XCTAssertEqual(target.bundleID, "com.github.wez.wezterm")
        XCTAssertEqual(TerminalJump.weztermListQuery(for: target), ["cli", "--no-auto-start", "list", "--format", "json"])
        let listing = #"[{"window_id":0,"tab_id":3,"pane_id":11},{"window_id":0,"tab_id":5,"pane_id":12}]"#
        XCTAssertEqual(TerminalJump.weztermTab(ofPane: "12", listing: listing), "5")
        XCTAssertNil(TerminalJump.weztermTab(ofPane: "99", listing: listing))
        XCTAssertNil(TerminalJump.weztermTab(ofPane: "12", listing: "not json"))
        XCTAssertEqual(TerminalJump.weztermCommands(for: target, tab: "5"), [
            ["cli", "--no-auto-start", "activate-tab", "--tab-id", "5"],
            ["cli", "--no-auto-start", "activate-pane", "--pane-id", "12"],
        ])
        XCTAssertEqual(TerminalJump.weztermEnvironment(for: target), ["WEZTERM_UNIX_SOCKET": "/Users/me/.local/share/wezterm/gui-sock-4242"])
        wez.weztermPane = "12; rm -rf ~"
        XCTAssertNil(JumpTarget(terminal: wez).weztermPane, "a pane is a number")
        XCTAssertTrue(TerminalJump.weztermCommands(for: JumpTarget(terminal: wez), tab: nil).isEmpty)

        var kitty = TerminalContext()
        kitty.termProgram = "kitty"
        kitty.kittyWindow = "3"
        XCTAssertNil(TerminalJump.kittyCommand(for: JumpTarget(terminal: kitty)), "no remote control address: nothing to talk to")
        kitty.kittyListenOn = "tcp:localhost:12345"
        XCTAssertNil(TerminalJump.kittyCommand(for: JumpTarget(terminal: kitty)), "only a unix socket")
        kitty.kittyListenOn = "unix:/tmp/kitty-501"
        XCTAssertEqual(TerminalJump.kittyCommand(for: JumpTarget(terminal: kitty)),
                       ["@", "--to", "unix:/tmp/kitty-501", "focus-window", "--match", "id:3"])
        XCTAssertEqual(JumpTarget(terminal: kitty).bundleID, "net.kovidgoyal.kitty")

        // The bridge reads them from the terminal it runs in, and they survive the trip to the app.
        let context = BridgeRunner.terminalContext(environment: ["WEZTERM_PANE": "7", "WEZTERM_UNIX_SOCKET": "/tmp/w", "KITTY_WINDOW_ID": "2",
                                                           "KITTY_LISTEN_ON": "unix:/tmp/k"], chain: [])
        XCTAssertEqual(context.weztermPane, "7")
        XCTAssertEqual(context.kittyListenOn, "unix:/tmp/k")
        XCTAssertEqual(TerminalContext(json: context.json), context)
    }

    func testJumpRulesFillInTheSessionAndRefuseWebLinks() {
        let rule = JumpRule(match: "Claude Code", url: "vscode://file{cwd}")
        XCTAssertTrue(rule.matches(session()))
        XCTAssertFalse(rule.matches(session(source: "codex")))
        XCTAssertEqual(rule.link(for: session())?.absoluteString, "vscode://file/Users/me/Projects/niko%20island")
        XCTAssertNil(rule.link(for: session(cwd: nil)), "a rule that needs a folder does nothing without one")
        let all = JumpRule(match: "*", url: "myapp://open?project={project}&id={session}&agent={agent}")
        XCTAssertEqual(all.link(for: session())?.absoluteString, "myapp://open?project=niko%20island&id=a1-b2&agent=claude")
        // A value cannot break out of its place in the link.
        XCTAssertEqual(all.link(for: session(id: "x&y=1"))?.absoluteString, "myapp://open?project=niko%20island&id=x%26y%3D1&agent=claude")
        for refused in ["https://example.com/{cwd}", "file://{cwd}", "javascript:alert(1)", "no scheme", ""] {
            XCTAssertNil(JumpRule(match: "*", url: refused).link(for: session()), refused)
            XCTAssertFalse(JumpRule(match: "*", url: refused).isUsable, refused)
        }
        XCTAssertTrue(JumpRule(match: "VS Code", url: "vscode://file{cwd}").isUsable)
        XCTAssertFalse(JumpRule(match: " ", url: "vscode://file{cwd}").isUsable)
        // The first rule that makes a link wins.
        let rules = [JumpRule(match: "claude", url: "first://open{cwd}"), JumpRule(match: "claude", url: "second://{agent}")]
        XCTAssertEqual(JumpRule.link(for: session(), rules: rules)?.absoluteString, "first://open/Users/me/Projects/niko%20island")
        XCTAssertEqual(JumpRule.link(for: session(cwd: nil), rules: rules)?.absoluteString, "second://claude")
        XCTAssertNil(JumpRule.link(for: session(source: "gemini"), rules: rules))

        var settings = NikoSettings()
        settings.jumpRules = [rule]
        XCTAssertEqual(NikoSettings(raw: settings.raw).jumpRules, [rule])
    }

    // MARK: A sign-in for one's own push server

    func testASignInOnlyGoesToTheUsersOwnServer() throws {
        let message = PushMessage(title: "t", body: "b")
        let own = try XCTUnwrap(PushRequest.make(server: "https://bark.example.org", service: .bark, key: "k", signIn: "me:secret", message: message))
        XCTAssertEqual(own.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("me:secret".utf8).base64EncodedString())
        let token = try XCTUnwrap(PushRequest.make(server: "https://ntfy.example.org", service: .ntfy, key: "topic", signIn: "tk_abc", message: message))
        XCTAssertEqual(token.value(forHTTPHeaderField: "Authorization"), "Bearer tk_abc")
        let publicServer = try XCTUnwrap(PushRequest.make(server: " ", service: .bark, key: "k", signIn: "me:secret", message: message))
        XCTAssertNil(publicServer.value(forHTTPHeaderField: "Authorization"), "never to the service's public server")
        XCTAssertEqual(publicServer.url?.host, "api.day.app")

        // Typed into the address, it is taken out of it (and kept in the Keychain by the app).
        let split = try XCTUnwrap(PushRequest.splitSignIn("https://me:p%40ss@push.example.org/bark"))
        XCTAssertEqual(split.server, "https://push.example.org/bark")
        XCTAssertEqual(split.signIn, "me:p@ss")
        XCTAssertNil(PushRequest.splitSignIn("https://push.example.org"))
    }

    func testTheClientAddsTheSignInOnlyForAServerOfOnesOwn() async {
        final class Seen: @unchecked Sendable { var headers: [String?] = [] }
        let seen = Seen()
        let client = PushClient(transport: { request in
            seen.headers.append(request.value(forHTTPHeaderField: "Authorization"))
            return (Data(), 200)
        }, key: { "k" }, signIn: { "me:secret" })
        _ = await client.send(PushMessage(title: "a", body: "b"), server: "", service: .bark)
        _ = await client.send(PushMessage(title: "a", body: "b"), server: "https://bark.example.org", service: .bark)
        XCTAssertEqual(seen.headers.count, 2)
        XCTAssertNil(seen.headers[0])
        XCTAssertNotNil(seen.headers[1])
    }

    // MARK: Warning level and months

    func testTheWarningLevelIsTheUsersChoice() {
        var watch = QuotaWatch()
        let resets = now.addingTimeInterval(4 * 3600)
        func read(_ used: Double, minutes: Double, at level: Double) -> [QuotaWatch.Alert] {
            let time = now.addingTimeInterval(minutes * 60)
            return watch.record(agent: "claude", window: RateLimitWindow(id: "five_hour", usedPercent: used, resetsAt: resets, windowMinutes: 300),
                                at: time, now: time, nearlyFullAt: level)
        }
        XCTAssertEqual(read(10, minutes: 0, at: 70), [], "a baseline")
        XCTAssertEqual(read(12, minutes: 60, at: 70), [])
        let warned = read(71, minutes: 120, at: 70)
        XCTAssertTrue(warned.contains { if case .nearlyFull = $0 { return true } else { return false } }, "\(warned)")
        XCTAssertFalse(read(80, minutes: 125, at: 70).contains { if case .nearlyFull = $0 { return true } else { return false } }, "once per cycle")
        XCTAssertEqual(NikoSettings().limitWarningPercent, 90)
        var settings = NikoSettings()
        settings.limitWarningPercent = 33
        XCTAssertEqual(settings.limitWarningPercent, 90, "only the offered levels")
        settings.limitWarningPercent = 80
        XCTAssertEqual(settings.limitWarningPercent, 80)
    }

    func testUsageIsAddedUpByMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let october = Date(timeIntervalSince1970: 1_791_000_000)   // 2026-10-03
        let months = UsageSnapshot.monthIDs(endingAt: october, calendar: calendar)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.first, "2025-11")
        XCTAssertEqual(months.last, "2026-10")

        let scratch = Scratch()
        let store = try UsageStore(path: scratch.file("usage.sqlite").path, timeZone: TimeZone(identifier: "UTC")!)
        defer { store.close() }
        let records = [(october.timeIntervalSince1970, "claude", 100), (october.timeIntervalSince1970 - 40 * 86_400, "claude", 30),
                       (october.timeIntervalSince1970 - 40 * 86_400, "codex", 5), (october.timeIntervalSince1970 - 400 * 86_400, "claude", 9)]
            .enumerated().map { index, item in
                UsageRecord(identityKey: "m\(index)", timestamp: item.0, agent: item.1, model: "m", input: item.2, output: 0)
            }
        try store.commit(records: records, pricing: Pricing(), file: nil)
        let monthly = try store.monthlyTotalsByAgent(fromDay: "2025-11-01")
        XCTAssertEqual(monthly["claude"]?["2026-10"]?.tokens, 100)
        XCTAssertEqual(monthly["claude"]?["2026-08"]?.tokens, 30)
        XCTAssertEqual(monthly["codex"]?["2026-08"]?.tokens, 5)
        XCTAssertNil(monthly["claude"]?["2025-08"], "before the twelve months")
    }
}

// MARK: - Putting removed hooks back

extension InstallerTests {
    func testTheInstallerRemembersWhichAgentsTheUserConnected() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        XCTAssertTrue(ConnectedAgents.load(paths: scratch.paths).isEmpty)
        func run(_ action: InstallAction) -> InstallResult {
            var options = InstallOptions(home: home, paths: scratch.paths)
            options.agentIDs = ["claude"]
            options.bridgeBinary = bridgeBinaryPath
            return Installer(options: options).run(action)
        }
        let installed = run(.install)
        XCTAssertTrue(installed.succeeded, installed.error ?? "")
        XCTAssertEqual(ConnectedAgents.load(paths: scratch.paths), ["claude"])
        let report = try Installer(options: InstallOptions(home: home, paths: scratch.paths)).scan(.uninstall)
        XCTAssertEqual(Installer.wiredAgents(in: report), ["claude"])

        // Another tool rewrites the file and drops our entries: still on the list, no longer wired.
        scratch.write(settingsPath, "{\"model\":\"opus\"}")
        let after = try Installer(options: InstallOptions(home: home, paths: scratch.paths)).scan(.uninstall)
        XCTAssertTrue(Installer.wiredAgents(in: after).isEmpty)
        XCTAssertEqual(ConnectedAgents.load(paths: scratch.paths), ["claude"], "what the user connected is remembered")

        // Removing it on purpose takes it off the list: it is never put back.
        let removed = run(.uninstall)
        XCTAssertTrue(removed.succeeded, removed.error ?? "")
        XCTAssertTrue(ConnectedAgents.load(paths: scratch.paths).isEmpty)
    }
}
