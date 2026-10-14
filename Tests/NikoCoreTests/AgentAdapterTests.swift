import XCTest
@testable import NikoCore

/// The adapters added in 0.9.0, each against the format its agent documents
/// (or, where the reference is thin, the registration CodeIsland ships).
final class AgentAdapterTests: XCTestCase {
    var scratch: Scratch!
    var home: URL { scratch.file("home") }

    override func setUp() {
        scratch = Scratch()
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() { scratch = nil }

    @discardableResult
    private func run(_ action: InstallAction, agents: [String]? = nil, at offset: TimeInterval = 0) -> InstallResult {
        var options = InstallOptions(home: home, paths: scratch.paths)
        options.agentIDs = agents
        options.bridgeBinary = bridgeBinaryPath
        options.now = Date(timeIntervalSince1970: 1_760_000_000 + offset)
        return Installer(options: options).run(action)
    }

    private func makeDirectory(_ relative: String) throws {
        try FileManager.default.createDirectory(at: scratch.file("home/" + relative), withIntermediateDirectories: true)
    }

    private func json(_ relative: String) throws -> JSONValue {
        try JSONValue.parse(Data(XCTUnwrap(scratch.read(relative)).utf8))
    }

    private func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: scratch.file(relative).path)
    }

    // MARK: Kimi Code (TOML)

    private let kimiConfig = """
    default_model = "kimi-k2"

    [models.kimi-k2]
    provider = "kimi"
    max_context_size = 262144

    # my own hook
    [[hooks]]
    event = "Stop"
    command = "afplay /System/Library/Sounds/Glass.aiff"

    """

    func testKimiCodeGetsOneMarkedBlockAndGivesItBack() throws {
        try makeDirectory(".kimi-code")
        scratch.write("home/.kimi-code/config.toml", kimiConfig)
        let result = run(.install, agents: ["kimi"])
        XCTAssertTrue(result.applied, result.error ?? "")
        let installed = try XCTUnwrap(scratch.read("home/.kimi-code/config.toml"))
        XCTAssertTrue(installed.hasPrefix(kimiConfig), "the user's settings stay where they were, untouched")
        XCTAssertEqual(installed.components(separatedBy: TOMLHooks.beginMarker).count - 1, 1)
        XCTAssertEqual(installed.components(separatedBy: "[[hooks]]").count - 1, 1 + AgentRegistry.kimiEvents.count)

        // Kimi Code refuses a config with a key it does not know, or an event it does not have.
        let allowedEvents: Set<String> = [
            "UserPromptSubmit", "UserPromptQueued", "PreToolUse", "Stop", "TurnStarted", "PostToolUse", "PostToolUseFailure",
            "PermissionRequest", "PermissionResult", "SessionStart", "SessionEnd", "SessionHeartbeat", "SubagentStart",
            "SubagentStop", "TaskStarted", "StopFailure", "Interrupt", "PreCompact", "PostCompact", "Notification",
        ]
        let block = String(installed.dropFirst(kimiConfig.count))
        for line in block.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            if line.hasPrefix("#") || line == "[[hooks]]" { continue }
            let key = line.prefix { $0 != " " }
            XCTAssertTrue(["event", "matcher", "command", "timeout"].contains(String(key)), line)
            if key == "event" {
                XCTAssertTrue(allowedEvents.contains(line.components(separatedBy: "\"")[1]), line)
            }
            if key == "timeout" { XCTAssertTrue((1...600).contains(Int(line.split(separator: " ").last ?? "") ?? 0), line) }
            if key == "command" {
                XCTAssertTrue(line.contains("niko-bridge") && line.contains("--source kimi") && line.contains("--observe"), line)
            }
        }
        XCTAssertEqual(run(.install, agents: ["kimi"], at: 60).plan.outcomes.first?.status, .unchanged, "a second install changes nothing")

        XCTAssertTrue(run(.uninstall, agents: ["kimi"], at: 120).applied)
        XCTAssertEqual(scratch.read("home/.kimi-code/config.toml"), kimiConfig, "byte for byte what the user had")
    }

    func testKimiCodeConfigThatCannotTakeHookTablesIsLeftAlone() throws {
        try makeDirectory(".kimi-code")
        for conflicting in ["hooks = []\n", "default_model = \"x\"\n[hooks]\nenabled = true\n", "\"hooks\".stop = \"x\"\n"] {
            scratch.write("home/.kimi-code/config.toml", conflicting)
            let result = run(.install, agents: ["kimi"])
            guard case .skipped(let why) = result.plan.outcomes.first?.status else { return XCTFail("expected a skip for \(conflicting)") }
            XCTAssertTrue(why.contains("left untouched"), why)
            XCTAssertEqual(scratch.read("home/.kimi-code/config.toml"), conflicting)
        }
        // A key called hooks inside some other table is not in the way.
        let fine = "[agent]\nhooks = true\n"
        scratch.write("home/.kimi-code/config.toml", fine)
        XCTAssertTrue(run(.install, agents: ["kimi"], at: 60).applied)
        XCTAssertTrue(run(.uninstall, agents: ["kimi"], at: 120).applied)
        XCTAssertEqual(scratch.read("home/.kimi-code/config.toml"), fine)
    }

    func testTablesOfOursAreFoundEvenWhenTheMarkersAreGone() {
        // A tool that rewrites the file may drop comments; the tables still carry the marker.
        let rewritten = """
        default_model = "x"

        [[hooks]]
        event = "Stop"
        command = "/bin/sh -c '[ -x ~/.niko-island/bin/niko-bridge ] && ~/.niko-island/bin/niko-bridge --source kimi; exit 0'"
        timeout = 10

        # the user's own, after ours
        [[hooks]]
        event = "PreToolUse"
        command = "./check.sh"
        """
        let stripped = TOMLHooks.strip(rewritten)
        XCTAssertEqual(stripped.removed, 1)
        XCTAssertFalse(stripped.text.contains("niko-bridge"))
        XCTAssertTrue(stripped.text.contains("# the user's own, after ours\n[[hooks]]\nevent = \"PreToolUse\""))
        XCTAssertEqual(TOMLHooks.strip("a = 1\n").removed, 0)
    }

    func testTOMLStringsAreEscaped() {
        XCTAssertEqual(TOMLHooks.quoted(#"say "hi" \ there"#), #""say \"hi\" \\ there""#)
        XCTAssertEqual(TOMLHooks.quoted("a\nb\tc\u{01}"), #""a\nb\tc\u0001""#)
        XCTAssertEqual(TOMLHooks.quoted("/Users/a b/.niko-island"), "\"/Users/a b/.niko-island\"")
    }

    // MARK: Copilot CLI

    func testCopilotCLIGetsItsOwnFormatWithClaudesEventNames() throws {
        try makeDirectory(".copilot")
        XCTAssertTrue(run(.install, agents: ["copilot"]).applied)
        let root = try json("home/.copilot/hooks/niko.json")
        XCTAssertEqual(root["version"], .int(1))
        let entry = try XCTUnwrap(root["hooks"]?["PreToolUse"]?[0])
        XCTAssertEqual(entry["type"]?.stringValue, "command")
        XCTAssertTrue(entry["bash"]?.stringValue?.contains("--source copilot --event PreToolUse") == true)
        XCTAssertEqual(entry["timeoutSec"], .int(10))
        XCTAssertNil(root["hooks"]?["PermissionRequest"], "status only")
        XCTAssertTrue(run(.uninstall, agents: ["copilot"], at: 60).applied)
        XCTAssertFalse(exists("home/.copilot/hooks/niko.json"))
    }

    // MARK: Kiro

    func testKiroGetsAGlobalHookFileAndTheOldEntriesGo() throws {
        try makeDirectory(".kiro")
        // What 0.8 and earlier wrote: Claude's format, into a file Kiro never read hooks from.
        let old = """
        {
          "chat.defaultModel": "auto",
          "hooks": {
            "Stop": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/bin/sh -c 'niko-bridge --source kiro; exit 0'" }] }]
          }
        }
        """
        scratch.write("home/.kiro/settings/cli.json", old)
        let result = run(.install, agents: ["kiro"])
        XCTAssertTrue(result.applied, result.error ?? "")
        let file = try json("home/.kiro/hooks/niko.json")
        XCTAssertEqual(file["version"]?.stringValue, "v1")
        let hooks = try XCTUnwrap(file["hooks"]?.arrayValue)
        XCTAssertEqual(hooks.compactMap { $0["trigger"]?.stringValue }, AgentRegistry.kiroEvents.map(\.event))
        XCTAssertEqual(hooks[0]["action"]?["type"]?.stringValue, "command")
        XCTAssertTrue(hooks[0]["action"]?["command"]?.stringValue?.contains("--event SessionStart") == true)
        XCTAssertEqual(hooks[0]["enabled"]?.boolValue, true)

        let cleaned = try json("home/.kiro/settings/cli.json")
        XCTAssertNil(cleaned["hooks"], "our old entries are gone")
        XCTAssertEqual(cleaned["chat.defaultModel"]?.stringValue, "auto", "the user's own settings stay")

        XCTAssertTrue(run(.uninstall, agents: ["kiro"], at: 60).applied)
        XCTAssertFalse(exists("home/.kiro/hooks/niko.json"))
        XCTAssertTrue(exists("home/.kiro/settings/cli.json"))
    }

    // MARK: MiniMax Code

    func testMiniMaxCodeGetsAPluginPackThatGoesCompletely() throws {
        XCTAssertEqual(run(.install, agents: ["minimax"]).plan.outcomes.first?.status, .notDetected, "never creates ~/.minimax")
        try makeDirectory(".minimax")
        XCTAssertTrue(run(.install, agents: ["minimax"]).applied)
        let manifest = try json("home/.minimax/plugins/niko/.claude-plugin/plugin.json")
        XCTAssertEqual(manifest["hooks"], .array([.string("hooks/hooks.json")]))
        XCTAssertEqual(manifest["name"]?.stringValue, "niko")
        let hooks = try json("home/.minimax/plugins/niko/hooks/hooks.json")
        XCTAssertNil(hooks["_comment"], "MiniMax Code checks the shape strictly")
        for member in try XCTUnwrap(hooks["hooks"]?.objectValue?.members) {
            let group = try XCTUnwrap(member.value[0])
            XCTAssertNil(group["matcher"], member.key)
            let timeout = try XCTUnwrap(group["hooks"]?[0]?["timeout"]?.doubleValue)
            XCTAssertTrue((1...10).contains(timeout), "\(member.key): a whole number of seconds from 1 to 10")
            XCTAssertTrue(group["hooks"]?[0]?["command"]?.stringValue?.contains("--observe") == true)
        }
        XCTAssertTrue(run(.uninstall, agents: ["minimax"], at: 60).applied)
        XCTAssertFalse(exists("home/.minimax/plugins/niko"), "the folders made for the pack go with it")
        XCTAssertTrue(exists("home/.minimax"))
    }

    // MARK: Devin

    func testDevinSharesItsConfigAndCanBeAnswered() throws {
        try makeDirectory(".config/devin")
        let original = "{\n  \"model\": \"swe-1\",\n  \"read_config_from\": {\n    \"claude\": true\n  }\n}\n"
        scratch.write("home/.config/devin/config.json", original)
        XCTAssertTrue(run(.install, agents: ["devin"]).applied)
        let root = try json("home/.config/devin/config.json")
        XCTAssertEqual(root["model"]?.stringValue, "swe-1")
        let permission = try XCTUnwrap(root["hooks"]?["PermissionRequest"]?[0])
        XCTAssertNil(permission["matcher"], "no matcher: every tool")
        XCTAssertEqual(permission["hooks"]?[0]?["timeout"], .int(HookSpec.approvalTimeout))
        XCTAssertTrue(permission["hooks"]?[0]?["command"]?.stringValue?.contains("--source devin --reply devin") == true)
        XCTAssertNotNil(root["hooks"]?["PostCompaction"])
        XCTAssertTrue(run(.uninstall, agents: ["devin"], at: 60).applied)
        XCTAssertEqual(scratch.read("home/.config/devin/config.json"), original)
    }

    func testDevinRepliesInItsOwnWords() throws {
        let permission = #"{"hook_event_name":"PermissionRequest","session_id":"d1","cwd":"/tmp","tool_name":"exec","tool_input":{"command":"ls"}}"#
        let allow = try TestIsland { _ in decisionReply("approve") }
        let allowed = allow.bridge(["--source", "devin", "--reply", "devin"], stdin: permission)
        XCTAssertEqual(allowed.status, 0)
        XCTAssertEqual(allowed.stdout, "{\"decision\":\"approve\"}\n")
        let deny = try TestIsland { _ in decisionReply("deny", reason: "not today") }
        let denied = deny.bridge(["--source", "devin", "--reply", "devin"], stdin: permission)
        XCTAssertEqual(denied.status, 2)
        XCTAssertEqual(denied.stdout, "{\"decision\":\"block\",\"reason\":\"not today\"}\n")
        XCTAssertEqual(denied.stderr, "not today\n")
        XCTAssertEqual(try XCTUnwrap(deny.collector.all.first?.event).source, "devin")
    }

    // MARK: Amp

    func testAmpPluginOnlyListens() throws {
        try makeDirectory(".config/amp")
        XCTAssertTrue(run(.install, agents: ["amp"]).applied)
        let plugin = try XCTUnwrap(scratch.read("home/.config/amp/plugins/niko.ts"))
        XCTAssertTrue(plugin.contains("niko-bridge"))
        XCTAssertTrue(plugin.contains("export default function (amp)"))
        XCTAssertFalse(plugin.contains("\"tool.call\""), "it never stands between Amp and a tool")
        XCTAssertTrue(NikoSettings.load(paths: scratch.paths).httpIngressEnabled)
        XCTAssertTrue(run(.uninstall, agents: ["amp"], at: 60).applied)
        XCTAssertFalse(exists("home/.config/amp/plugins/niko.ts"))
    }

    func testAmpPluginReportsThroughTheLoopbackIngress() throws {
        let which = runProcess("/usr/bin/env", ["which", "node"])
        let node = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard which.status == 0, !node.isEmpty else { throw XCTSkip("node not installed") }
        let hub = IngressHub(log: .inMemory())
        let collector = Collector()
        hub.setHandler { collector.add($0) }
        let server = HTTPIngressServer(paths: scratch.paths, hub: hub, preferredPort: 0)
        try server.start()
        defer { server.stop() }

        let agent = try XCTUnwrap(AgentRegistry.descriptor("amp"))
        scratch.write("amp/niko.mjs", PluginTemplates.ampPlugin(agent: agent, paths: scratch.paths))
        scratch.write("amp/driver.mjs", """
        import plugin from "./niko.mjs";
        const handlers = {};
        const amp = {
          on: (name, handler) => { handlers[name] = handler; return { unsubscribe() {} }; },
          system: { workspaceRoot: "file:///w/amp" },
          helpers: { filePathFromURI: (uri) => uri.replace("file://", "") },
        };
        plugin(amp);
        const thread = { id: "T-1" };
        await handlers["session.start"]({ thread });
        await handlers["agent.start"]({ thread, message: "Tidy the header", id: 1 });
        await handlers["tool.result"]({ thread, toolUseID: "u1", tool: "Bash", input: { cmd: "ls" }, status: "done" });
        await handlers["agent.end"]({ thread, id: 1, status: "done",
          messages: [{ role: "user", content: "x" }, { role: "assistant", content: [{ type: "text", text: "Done." }] }] });
        console.log(JSON.stringify(Object.keys(handlers).sort()));
        """)
        let output = runProcess(node, [scratch.file("amp/driver.mjs").path], timeout: 30)
        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertEqual(try JSONValue.parse(Data(output.stdout.utf8)),
                       .array(["agent.end", "agent.start", "session.start", "tool.result"].map { .string($0) }))
        let events = collector.wait(count: 4).map(\.event)
        XCTAssertEqual(events.map(\.name), ["SessionStart", "UserPromptSubmit", "PreToolUse", "Stop"])
        XCTAssertTrue(events.allSatisfy { $0.source == "amp" && $0.sessionID == "T-1" && $0.cwd == "/w/amp" })
        XCTAssertEqual(events[1].raw["prompt"]?.stringValue, "Tidy the header")
        XCTAssertEqual(events[2].toolName, "Bash")
        XCTAssertEqual(events[3].raw["last_assistant_message"]?.stringValue, "Done.")
    }

    // MARK: Qoder

    func testQoderFamilyWatchesPermissionPrompts() throws {
        for id in ["qoder", "qoder-cn", "qoderwork"] {
            let agent = try XCTUnwrap(AgentRegistry.descriptor(id))
            XCTAssertEqual(agent.bridgeArguments, ["--observe"], id)
            XCTAssertFalse(agent.approvals, id)
        }
        try makeDirectory(".qoder")
        XCTAssertTrue(run(.install, agents: ["qoder"]).applied)
        let root = try json("home/.qoder/settings.json")
        XCTAssertEqual(root["hooks"]?["PermissionRequest"]?[0]?["hooks"]?[0]?["timeout"], .int(HookSpec.quickTimeout))
    }

    // MARK: Bridge

    func testAWatchedPermissionPromptNeverHoldsTheAgent() throws {
        let island = try TestIsland { _ in decisionReply("approve") }
        let output = island.bridge(["--source", "kimi", "--observe"],
                                   stdin: #"{"hook_event_name":"PermissionRequest","session_id":"k1","cwd":"/tmp","tool_name":"Shell","tool_input":{"command":"ls"}}"#)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "", "no decision reaches an agent whose hook only watches")
        let event = try XCTUnwrap(island.collector.wait(count: 1).first?.event)
        XCTAssertEqual(event.name, HookEvent.notification)
        XCTAssertFalse(event.isBlocking)
        XCTAssertEqual(event.raw["native_event"]?.stringValue, "PermissionRequest")
        var store = SessionStore()
        store.apply(event)
        XCTAssertEqual(store.sessions[event.key]?.phase, .needsAttention)
        XCTAssertEqual(store.sessions[event.key]?.activity, Activity(verb: "needs permission", detail: "Shell"))
    }

    func testTheEventNameCanComeFromTheCommandLine() throws {
        let island = try TestIsland()
        // Copilot CLI's own camelCase format names neither the event nor the session in snake case.
        _ = island.bridge(["--source", "copilot", "--event", "preToolUse"],
                          stdin: #"{"sessionId":"c-1","timestamp":1760000000000,"cwd":"/w/c","toolName":"bash","toolArgs":"{\"command\":\"npm test\"}"}"#)
        // When the payload names it, that wins.
        _ = island.bridge(["--source", "kiro", "--event", "PreToolUse"], stdin: #"{"hook_event_name":"agentSpawn","session_id":"k-1","cwd":"/w/k"}"#)
        let events = island.collector.wait(count: 2).map(\.event)
        let copilot = try XCTUnwrap(events.first { $0.source == "copilot" })
        XCTAssertEqual(copilot.name, HookEvent.preToolUse)
        XCTAssertEqual(copilot.sessionID, "c-1")
        XCTAssertEqual(Activity.forTool(copilot.toolName, input: copilot.toolInput), Activity(verb: "running", detail: "npm test"))
        let kiro = try XCTUnwrap(events.first { $0.source == "kiro" })
        XCTAssertEqual(kiro.name, HookEvent.sessionStart)
    }

    func testHooksBorrowedFromClaudeCodeAreTold() {
        typealias A = BorrowedHooks.Ancestor
        let none: (pid_t) -> [String] = { _ in [] }
        XCTAssertEqual(BorrowedHooks.borrower(in: [A(pid: 9, path: "/bin/sh"), A(pid: 8, path: "/usr/local/bin/devin")], arguments: none)?.agent, "devin")
        XCTAssertNil(BorrowedHooks.borrower(in: [A(pid: 9, path: "/bin/sh"), A(pid: 8, path: "/Users/a/.local/bin/claude"),
                                                 A(pid: 7, path: "/usr/local/bin/devin")], arguments: none),
                     "Claude Code run by Devin is still Claude Code")
        let node: (pid_t) -> [String] = { pid in
            pid == 5 ? ["node", "/opt/homebrew/lib/node_modules/@github/copilot/index.js"]
                     : ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"]
        }
        XCTAssertEqual(BorrowedHooks.borrower(in: [A(pid: 5, path: "/opt/homebrew/bin/node")], arguments: node)?.agent, "copilot")
        XCTAssertNil(BorrowedHooks.borrower(in: [A(pid: 6, path: "/opt/homebrew/bin/node")], arguments: node))
        XCTAssertNil(BorrowedHooks.borrower(in: [A(pid: 9, path: "/bin/zsh"), A(pid: 1, path: "/Applications/Terminal.app/x")], arguments: none))

        let devin = BorrowedHooks.borrowers[0]
        scratch.write("home/.config/devin/config.json", #"{"model":"x"}"#)
        XCTAssertFalse(BorrowedHooks.ownHooksInstalled(devin, home: home.path))
        scratch.write("home/.config/devin/config.json", #"{"hooks":{"Stop":[{"hooks":[{"command":"niko-bridge --source devin"}]}]}}"#)
        XCTAssertTrue(BorrowedHooks.ownHooksInstalled(devin, home: home.path))
    }

    func testProcessArgumentsAreReadWithoutTheEnvironment() {
        let arguments = ProcessInspector.arguments(of: getpid())
        XCTAssertEqual(arguments.first.map { ($0 as NSString).lastPathComponent }, (CommandLine.arguments[0] as NSString).lastPathComponent)
        XCTAssertEqual(arguments.count, CommandLine.arguments.count)
        XCTAssertFalse(arguments.contains { $0.hasPrefix("PATH=") })
        XCTAssertEqual(ProcessInspector.arguments(of: -1), [])
    }

    // MARK: Events

    func testNamesOutsideClaudesSetMeanSomething() throws {
        func event(_ source: String, _ text: String) throws -> AgentEvent {
            try AgentEvent(json: JSONValue.parse(Data(text.utf8)), defaultSource: source)
        }
        XCTAssertEqual(try event("zcode", #"{"hook_event_name":"PostToolUseFailure","session_id":"z"}"#).name, HookEvent.postToolUse)
        XCTAssertEqual(try event("devin", #"{"hook_event_name":"PostCompaction","session_id":"d"}"#).name, HookEvent.postCompact)
        XCTAssertEqual(try event("kimi", #"{"hook_event_name":"Interrupt","session_id":"k"}"#).name, HookEvent.stop)
        XCTAssertEqual(try event("kimi", #"{"hook_event_name":"PermissionResult","session_id":"k"}"#).name, HookEvent.postToolUse)
        let failed = try event("copilot", #"{"hook_event_name":"errorOccurred","sessionId":"c","error":{"message":"rate limited"}}"#)
        XCTAssertEqual(failed.name, HookEvent.stopFailure)
        XCTAssertEqual(failed.sessionID, "c")
        XCTAssertEqual(failed.raw["message"]?.stringValue, "rate limited")

        // An event the island has no meaning for keeps the row as it was.
        var store = SessionStore()
        store.apply(try event("kimi", #"{"hook_event_name":"PreToolUse","session_id":"k","tool_name":"Shell","tool_input":{"command":"make"}}"#))
        store.apply(try event("kimi", #"{"hook_event_name":"SessionHeartbeat","session_id":"k"}"#))
        XCTAssertEqual(store.sessions[SessionKey(source: "kimi", sessionID: "k")]?.activity, Activity(verb: "running", detail: "make"))
    }
}
