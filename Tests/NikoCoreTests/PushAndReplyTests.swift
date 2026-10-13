import XCTest
@testable import NikoCore

/// A line to the user's own phone, and a follow-up typed into a terminal: what
/// is sent, where it may go, and when it is refused.
final class PushAndReplyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let message = PushMessage(title: "Claude Code · atlas-api", body: "Needs your decision")

    // MARK: Push

    func testALineGoesOutAsJSONAndNothingOfItIsInTheAddress() throws {
        let bark = try XCTUnwrap(PushRequest.make(server: "", service: .bark, key: " device-secret ", message: message))
        XCTAssertEqual(bark.url?.absoluteString, "https://api.day.app/push")
        XCTAssertEqual(bark.httpMethod, "POST")
        XCTAssertEqual(bark.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("niko-island/"), true)
        let sent = try JSONValue.parse(try XCTUnwrap(bark.httpBody))
        XCTAssertEqual(sent["device_key"]?.stringValue, "device-secret")
        XCTAssertEqual(sent["title"]?.stringValue, "Claude Code · atlas-api")
        XCTAssertEqual(sent["body"]?.stringValue, "Needs your decision")
        XCTAssertFalse(bark.url?.absoluteString.contains("secret") ?? true)

        let ntfy = try XCTUnwrap(PushRequest.make(server: "https://ntfy.example.org/", service: .ntfy, key: "my-topic", message: message))
        XCTAssertEqual(ntfy.url?.absoluteString, "https://ntfy.example.org")
        let published = try JSONValue.parse(try XCTUnwrap(ntfy.httpBody))
        XCTAssertEqual(published["topic"]?.stringValue, "my-topic")
        XCTAssertEqual(published["message"]?.stringValue, "Needs your decision")
        XCTAssertEqual(PushRequest.endpoint(server: "", service: .ntfy)?.absoluteString, "https://ntfy.sh")
        XCTAssertEqual(PushRequest.endpoint(server: "https://bark.example.org/base/?x=1#y", service: .bark)?.absoluteString, "https://bark.example.org/base/push")

        XCTAssertNil(PushRequest.make(server: "", service: .bark, key: "   ", message: message), "no key, no request")
    }

    func testPlainHTTPIsOnlyForThisMacAndTheLocalNetwork() {
        for allowed in ["http://localhost:8080", "http://127.0.0.1:8080", "http://192.168.1.20:8080", "http://10.0.0.5", "http://172.20.1.1", "http://nas.local:8080"] {
            XCTAssertNotNil(PushRequest.endpoint(server: allowed, service: .bark), allowed)
        }
        for refused in ["http://api.day.app", "http://example.org", "http://172.32.0.1", "http://192.169.1.1", "ftp://example.org", "example.org",
                        "https://user:pass@example.org", "javascript:alert(1)", "http://1.2.3", "https://"] {
            XCTAssertNil(PushRequest.endpoint(server: refused, service: .bark), refused)
        }
    }

    private final class Wire: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []
        var status = 200
        var fails = false
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
        func send(_ request: URLRequest) throws -> (Data, Int) {
            lock.lock(); defer { lock.unlock() }
            _requests.append(request)
            if fails { throw URLError(.notConnectedToInternet) }
            return (Data(), status)
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: Date
        init(_ now: Date) { _now = now }
        var now: Date { lock.lock(); defer { lock.unlock() }; return _now }
        func advance(_ seconds: TimeInterval) { lock.lock(); _now += seconds; lock.unlock() }
    }

    func testTheClientSaysHowItWentAndDoesNotRepeatItself() async {
        let wire = Wire(), clock = Clock(now)
        let client = PushClient(transport: { try wire.send($0) }, key: { "k" }, clock: { clock.now })
        var outcome = await client.send(message, server: "", service: .bark, subject: "claude/s1/permission")
        XCTAssertEqual(outcome, .sent)
        XCTAssertEqual(wire.requests.count, 1)
        // The same thing about the same session within half a minute is one line, not two.
        outcome = await client.send(message, server: "", service: .bark, subject: "claude/s1/permission")
        XCTAssertEqual(outcome, .sent)
        XCTAssertEqual(wire.requests.count, 1)
        _ = await client.send(message, server: "", service: .bark, subject: "claude/s2/permission")
        XCTAssertEqual(wire.requests.count, 2, "another session is another line")
        clock.advance(31)
        _ = await client.send(message, server: "", service: .bark, subject: "claude/s1/permission")
        XCTAssertEqual(wire.requests.count, 3)

        wire.status = 400
        outcome = await client.send(message, server: "", service: .bark)
        XCTAssertEqual(outcome, .refused(400))
        wire.fails = true
        outcome = await client.send(message, server: "", service: .bark)
        XCTAssertEqual(outcome, .unreachable)
        let before = wire.requests.count
        outcome = await client.send(message, server: "http://example.org", service: .bark)
        XCTAssertEqual(outcome, .notSetUp, "an address that is not allowed is never contacted")
        XCTAssertEqual(wire.requests.count, before)
        let keyless = PushClient(transport: { try wire.send($0) }, key: { nil }, clock: { clock.now })
        outcome = await keyless.send(message, server: "", service: .bark)
        XCTAssertEqual(outcome, .notSetUp)
        XCTAssertEqual(wire.requests.count, before)
    }

    // MARK: Quiet hours and the list

    func testQuietHoursMayRunOverMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ hour: Int, _ minute: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: hour, minute: minute))! }
        var settings = NikoSettings()
        XCTAssertFalse(settings.quietHoursEnabled)
        XCTAssertEqual(settings.quietFrom, 22 * 60)
        XCTAssertEqual(settings.quietUntil, 8 * 60)
        XCTAssertFalse(settings.isQuiet(at: at(23), calendar: calendar), "off until switched on")
        settings.quietHoursEnabled = true
        XCTAssertTrue(settings.isQuiet(at: at(23), calendar: calendar))
        XCTAssertTrue(settings.isQuiet(at: at(3), calendar: calendar))
        XCTAssertTrue(settings.isQuiet(at: at(7, 59), calendar: calendar))
        XCTAssertFalse(settings.isQuiet(at: at(8), calendar: calendar))
        XCTAssertFalse(settings.isQuiet(at: at(21, 59), calendar: calendar))
        XCTAssertTrue(settings.isQuiet(at: at(22), calendar: calendar))
        // A stretch inside one day.
        settings.quietFrom = 13 * 60
        settings.quietUntil = 14 * 60 + 30
        XCTAssertTrue(settings.isQuiet(at: at(13, 30), calendar: calendar))
        XCTAssertFalse(settings.isQuiet(at: at(14, 30), calendar: calendar))
        XCTAssertFalse(settings.isQuiet(at: at(3), calendar: calendar))
        // From and until at the same time is no stretch at all; times land on the half hour.
        settings.quietUntil = 13 * 60
        XCTAssertFalse(settings.isQuiet(at: at(13), calendar: calendar))
        settings.quietFrom = 9 * 60 + 47
        XCTAssertEqual(settings.quietFrom, 9 * 60 + 30)
        settings.quietUntil = 5000
        XCTAssertEqual(settings.quietUntil, 23 * 60 + 30)

        XCTAssertEqual(settings.sessionGrouping, .none)
        XCTAssertFalse(settings.replyFromIsland)
        XCTAssertFalse(settings.pushEnabled)
        XCTAssertTrue(settings.pushOnlyWhenAway)
        XCTAssertFalse(settings.pushDetails, "what a request is about stays on this Mac unless asked otherwise")
        XCTAssertEqual(settings.pushService, "bark")
        settings.pushService = "carrier-pigeon"
        XCTAssertEqual(settings.pushService, "bark")
    }

    // MARK: A follow-up into a terminal

    private func session(source: String = "claude", terminal: TerminalContext) -> Session {
        Session(key: SessionKey(source: source, sessionID: "s1"), cwd: "/tmp/proj", transcriptPath: nil, title: "t", startedAt: now, lastEventAt: now,
                phaseSince: now, activity: .waiting, phase: .waiting, terminal: terminal, ancestors: [], firstPrompt: nil)
    }

    func testAReplyOnlyGoesWhereTheTerminalCanBeNamedExactly() {
        var tmux = TerminalContext()
        tmux.tmux = "/private/tmp/tmux-501/default,4242,0"
        tmux.tmuxPane = "%7"
        tmux.termProgram = "tmux"
        XCTAssertEqual(TerminalReply.channel(for: session(terminal: tmux)), .tmux(socket: "/private/tmp/tmux-501/default", pane: "%7"))
        tmux.tmuxPane = "%7; kill-server"
        XCTAssertNil(TerminalReply.channel(for: session(terminal: tmux)), "a pane is a percent sign and a number, nothing else")

        var iterm = TerminalContext()
        iterm.termProgram = "iTerm.app"
        iterm.itermSessionID = "w0t1p0:8F1C2A6E-0000-4000-8000-000000000001"
        XCTAssertEqual(TerminalReply.channel(for: session(terminal: iterm)), .iterm(guid: "8F1C2A6E-0000-4000-8000-000000000001"))

        var apple = TerminalContext()
        apple.termProgram = "Apple_Terminal"
        apple.tty = "ttys004"
        XCTAssertEqual(TerminalReply.channel(for: session(terminal: apple)), .terminal(tty: "/dev/ttys004"))
        apple.tty = "ttys004\"; do shell script \"x"
        XCTAssertNil(TerminalReply.channel(for: session(terminal: apple)))

        var ghostty = TerminalContext()
        ghostty.termProgram = "ghostty"
        ghostty.tty = "ttys009"
        XCTAssertNil(TerminalReply.channel(for: session(terminal: ghostty)), "an emulator that cannot be told which tab is not typed into")
        XCTAssertNil(TerminalReply.channel(for: session(terminal: TerminalContext())), "a desktop app has no such way in")
    }

    func testWhatIsTypedIsOneLineAndWhatRunsThereMustBeTheAgent() {
        XCTAssertEqual(TerminalReply.clean("  run the tests\nthen commit\t\u{1B}[31m "), "run the tests then commit [31m")
        XCTAssertNil(TerminalReply.clean(" \n\t "))
        XCTAssertEqual(TerminalReply.clean(String(repeating: "a", count: 5000))?.count, TerminalReply.limit)

        // `ps -o stat=,comm= -t ttys004`: the lines whose state has a plus are in the foreground.
        let atAgent = "Ss   -zsh\nS+   claude\nS+   /usr/local/bin/node\n"
        XCTAssertEqual(TerminalReply.foreground(psOutput: atAgent), ["claude", "/usr/local/bin/node"])
        XCTAssertTrue(TerminalReply.isAgentWaiting(foreground: TerminalReply.foreground(psOutput: atAgent), source: "claude"))
        // The agent has gone and the shell is back: what is typed now would be run as a command.
        let atShell = "Ss+  -zsh\n"
        XCTAssertFalse(TerminalReply.isAgentWaiting(foreground: TerminalReply.foreground(psOutput: atShell), source: "claude"))
        XCTAssertFalse(TerminalReply.isAgentWaiting(foreground: ["claude", "bash"], source: "claude"), "a shell among them is enough to refuse")
        XCTAssertFalse(TerminalReply.isAgentWaiting(foreground: ["vim"], source: "claude"))
        XCTAssertFalse(TerminalReply.isAgentWaiting(foreground: [], source: "claude"))
        XCTAssertTrue(TerminalReply.isAgentWaiting(foreground: ["codex"], source: "codex"))
        XCTAssertFalse(TerminalReply.isAgentWaiting(foreground: ["ssh"], source: "codex"))

        XCTAssertEqual(TerminalReply.tmuxProbe(socket: "/s", pane: "%7"), ["-S", "/s", "display-message", "-p", "-t", "%7", "#{pane_current_command}"])
        XCTAssertEqual(TerminalReply.tmuxSend(socket: nil, pane: "%7", text: "-n; rm -rf /"),
                       [["send-keys", "-t", "%7", "-l", "--", "-n; rm -rf /"], ["send-keys", "-t", "%7", "Enter"]],
                       "typed as text, never read as options or keys")

        // Whatever is typed stays inside the quotes of the script.
        let nasty = "say \"hi\" \\ and\ndo shell script \"x\""
        let script = try? XCTUnwrap(TerminalReply.appleScript(for: .terminal(tty: "/dev/ttys004"), text: nasty))
        XCTAssertEqual(script?.contains("do script \"say \\\"hi\\\" \\\\ and do shell script \\\"x\\\"\" in aTab"), true)
        XCTAssertEqual(TerminalReply.appleScript(for: .iterm(guid: "G"), text: "ok")?.contains("write text \"ok\""), true)
        XCTAssertEqual(TerminalReply.appleScript(for: .iterm(guid: "G"), text: "ok")?.contains("activate"), false, "a reply brings nothing to the front")
        XCTAssertNil(TerminalReply.appleScript(for: .tmux(socket: nil, pane: "%1"), text: "ok"))
    }
}
