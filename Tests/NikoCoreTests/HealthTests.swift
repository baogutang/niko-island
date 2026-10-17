import XCTest
@testable import NikoCore

/// Other islands' leftovers, and the small things the health card and the island now say better.
/// Fixtures follow the shapes found on a real Mac (Claude-style groups, Cursor's flat lists, ZCode's
/// `hooks.events`); the commands are those Vibe Island and Ping Island write.
final class ForeignHooksTests: XCTestCase {
    private let vibe = #"'/Users/me/.vibe-island/bin/vibe-island-bridge' --source claude"#
    private let ping = #"/Users/me/.ping-island/bin/ping-island-bridge --source codex"#
    private let ours = #"/bin/sh -c '[ -x \"$HOME/.niko-island/bin/niko-bridge\" ] && \"$HOME/.niko-island/bin/niko-bridge\" --source claude; exit 0'"#

    private var island: ForeignHooks.Island { ForeignHooks.known.first { $0.id == "vibe-island" }! }

    private func claudeSettings(statusLine: String? = nil) -> String {
        var text = #"{"model":"opus","hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"VIBE"}]},"#
            + #"{"matcher":"*","hooks":[{"type":"command","command":"OURS"}]}],"#
            + #""Stop":[{"hooks":[{"type":"command","command":"VIBE"},{"type":"command","command":"OURS"}]}],"#
            + #""Notification":[{"hooks":[{"type":"command","command":"VIBE"}]}],"SessionEnd":[]}"#
        if let statusLine { text += #","statusLine":{"type":"command","command":""# + statusLine + #""}"# }
        return text + "}"
    }

    private func escaped(_ command: String) -> String { command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

    private func write(_ scratch: Scratch) {
        scratch.write("home/.claude/settings.json", claudeSettings().replacingOccurrences(of: "VIBE", with: escaped(vibe)).replacingOccurrences(of: "OURS", with: escaped(ours)))
        scratch.write("home/.cursor/hooks.json", #"{"version":1,"hooks":{"beforeShellExecution":[{"command":"VIBE"},{"command":"OURS"}],"stop":[{"command":"VIBE"}]}}"#
            .replacingOccurrences(of: "VIBE", with: escaped(vibe)).replacingOccurrences(of: "OURS", with: escaped(ours)))
        scratch.write("home/.zcode/cli/config.json", #"{"hooks":{"enabled":true,"events":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"VIBE","async":false}]},{"matcher":".*","hooks":[{"type":"command","command":"OURS"}]}]}},"mcp":{"servers":[]}}"#
            .replacingOccurrences(of: "VIBE", with: escaped(vibe)).replacingOccurrences(of: "OURS", with: escaped(ours)))
        scratch.write("home/.codex/hooks.json", #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"PING"},{"type":"command","command":"OURS"}]}]}}"#
            .replacingOccurrences(of: "PING", with: escaped(ping)).replacingOccurrences(of: "OURS", with: escaped(ours)))
    }

    private func json(_ scratch: Scratch, _ file: String) throws -> JSONObject {
        try XCTUnwrap(JSONValue.parse(Data(XCTUnwrap(scratch.read("home/" + file)).utf8)).objectValue)
    }

    private func commands(_ value: JSONValue) -> [String] {
        switch value {
        case .object(let object): return object.members.flatMap { $0.key == "command" ? [$0.value.stringValue ?? ""] : commands($0.value) }
        case .array(let items): return items.flatMap(commands)
        default: return []
        }
    }

    func testLeftoversAreFoundPerIslandAndPerFile() {
        let scratch = Scratch()
        write(scratch)
        let findings = ForeignHooks.scan(home: scratch.file("home"), paths: scratch.paths) { _ in false }
        XCTAssertEqual(findings.map(\.id), ["vibe-island", "ping-island"])
        let vibe = findings[0]
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: vibe.places.map { ($0.file, $0.hooks) }),
                       [".claude/settings.json": 3, ".cursor/hooks.json": 2, ".zcode/cli/config.json": 1])
        XCTAssertEqual(vibe.hooks, 6)
        XCTAssertFalse(vibe.installed)
        XCTAssertEqual(findings[1].places.map(\.file), [".codex/hooks.json"])
        // Whether its app is still there is the caller's to say.
        XCTAssertTrue(ForeignHooks.scan(home: scratch.file("home"), paths: scratch.paths) { $0.id == "vibe-island" }[0].installed)
    }

    func testCleaningTakesOutOnlyTheIslandsHooksAndKeepsBackups() throws {
        let scratch = Scratch()
        write(scratch)
        let originals = [".claude/settings.json", ".cursor/hooks.json", ".zcode/cli/config.json"].map { scratch.read("home/" + $0) }
        let cleaned = ForeignHooks.clean(island, home: scratch.file("home"), paths: scratch.paths, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(cleaned.hooks, 6)
        XCTAssertEqual(Set(cleaned.files), [".claude/settings.json", ".cursor/hooks.json", ".zcode/cli/config.json"])
        XCTAssertTrue(cleaned.failures.isEmpty)

        let claude = try json(scratch, ".claude/settings.json")
        XCTAssertEqual(commands(.object(claude)), [ours, ours], "ours stay, in their places")
        XCTAssertEqual(claude["model"]?.stringValue, "opus", "everything else is left as it was")
        XCTAssertNil(claude["hooks"]?["Notification"], "an event that held only its hook goes")
        XCTAssertEqual(claude["hooks"]?["PreToolUse"]?.arrayValue?.count, 1, "a matcher group that held only its hook goes")
        XCTAssertEqual(claude["hooks"]?["SessionEnd"]?.arrayValue?.count, 0, "a list that was already empty is not touched")
        let cursor = JSONValue.object(try json(scratch, ".cursor/hooks.json"))
        XCTAssertEqual(commands(cursor.at("hooks", "beforeShellExecution") ?? .null), [ours])
        XCTAssertNil(cursor.at("hooks", "stop"))
        let zcode = try json(scratch, ".zcode/cli/config.json")
        XCTAssertEqual(zcode["hooks"]?["enabled"]?.boolValue, true)
        XCTAssertEqual(commands(zcode["hooks"] ?? .null), [ours])
        XCTAssertNotNil(zcode["mcp"], "other sections are left alone")
        XCTAssertTrue(commands(try json(scratch, ".codex/hooks.json")["hooks"] ?? .null).contains(ping), "another island's are not touched")

        // Each file changed has a byte-for-byte backup next to it.
        for (file, original) in zip([".claude/settings.json", ".cursor/hooks.json", ".zcode/cli/config.json"], originals) {
            let backup = try XCTUnwrap(cleaned.backups.first { $0.contains("/" + file + Installer.backupInfix) })
            XCTAssertEqual(try String(contentsOfFile: backup, encoding: .utf8), original)
        }
        // Nothing left: a second clean-up changes nothing.
        XCTAssertTrue(ForeignHooks.scan(home: scratch.file("home"), paths: scratch.paths) { _ in false }.allSatisfy { $0.id != "vibe-island" })
        XCTAssertEqual(ForeignHooks.clean(island, home: scratch.file("home"), paths: scratch.paths).hooks, 0)
    }

    func testTwoCleanUpsInTheSameSecondKeepTheOriginal() throws {
        let scratch = Scratch()
        write(scratch)
        let original = scratch.read("home/.codex/hooks.json")
        scratch.write("home/.codex/hooks.json", #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"VIBE"},{"type":"command","command":"PING"}]}]}}"#
            .replacingOccurrences(of: "VIBE", with: escaped(vibe)).replacingOccurrences(of: "PING", with: escaped(ping)))
        let before = scratch.read("home/.codex/hooks.json")
        XCTAssertNotEqual(before, original)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ForeignHooks.clean(island, home: scratch.file("home"), paths: scratch.paths, now: now)
        let second = ForeignHooks.clean(ForeignHooks.known.first { $0.id == "ping-island" }!, home: scratch.file("home"), paths: scratch.paths, now: now)
        let backups = (first.backups + second.backups).filter { $0.contains(".codex/hooks.json") }
        XCTAssertEqual(Set(backups).count, 2, "the second backup does not overwrite the first")
        XCTAssertEqual(try String(contentsOfFile: try XCTUnwrap(first.backups.first { $0.contains(".codex") }), encoding: .utf8), before)
    }

    func testTheStatusLineIsUnchainedFromAnIslandThatIsGone() throws {
        let scratch = Scratch()
        let statusline = "/Users/me/.vibe-island/bin/vibe-island-statusline"
        // Our wrapper, installed after Vibe Island's status line, chains to it, and would put it back on uninstall.
        try FileManager.default.createDirectory(at: scratch.paths.bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch.paths.cache, withIntermediateDirectories: true)
        let chained = Shims.statuslineScript(paths: scratch.paths, userSection: Shims.chainedUserSection(originalCommand: statusline))
        try Data(chained.utf8).write(to: scratch.paths.statuslineScript)
        try Data(#"{"command":"\#(statusline)","type":"command"}"#.utf8).write(to: scratch.paths.statuslineOriginal)
        scratch.write("home/.claude/settings.json", #"{"statusLine":{"type":"command","command":"/bin/sh -c 'exec niko-statusline'"}}"#)

        let finding = try XCTUnwrap(ForeignHooks.scan(home: scratch.file("home"), paths: scratch.paths) { _ in false }.first)
        XCTAssertTrue(finding.statusLine)
        XCTAssertEqual(finding.hooks, 0)
        let cleaned = ForeignHooks.clean(island, home: scratch.file("home"), paths: scratch.paths)
        XCTAssertTrue(cleaned.statusLine)
        let script = try String(contentsOf: scratch.paths.statuslineScript, encoding: .utf8)
        XCTAssertFalse(script.contains("vibe-island"))
        XCTAssertTrue(script.contains("statusline-cache"), "our part of the status line stays")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.statuslineOriginal.path), "uninstalling will not bring it back")
        XCTAssertEqual(scratch.read("home/.claude/settings.json"), #"{"statusLine":{"type":"command","command":"/bin/sh -c 'exec niko-statusline'"}}"#,
                       "Claude Code's setting points at ours and stays")

        // Set straight into Claude Code instead, its status line is taken out there.
        scratch.write("home/.claude/settings.json", #"{"model":"opus","statusLine":{"type":"command","command":"\#(statusline)"}}"#)
        XCTAssertTrue(ForeignHooks.clean(island, home: scratch.file("home"), paths: scratch.paths).statusLine)
        XCTAssertNil(try json(scratch, ".claude/settings.json")["statusLine"])
        XCTAssertEqual(try json(scratch, ".claude/settings.json")["model"]?.stringValue, "opus")
    }
}

final class SmallerFixesTests: XCTestCase {
    func testAShellCommandIsDescribedByWhatItDoes() {
        XCTAssertEqual(Activity.commandGist("SP=/private/tmp/x; cd $SP && sips -c 80 620 a.png --out b.png"), "sips -c 80 620 a.png --out b.png")
        XCTAssertEqual(Activity.commandGist("cd /Users/me/project && swift test 2>&1 | grep -E \"error\""), "swift test 2>&1 | grep -E \"error\"")
        XCTAssertEqual(Activity.commandGist("FOO=1 BAR=2 make build"), "make build")
        XCTAssertEqual(Activity.commandGist("export PATH=/x:$PATH; npm run dev"), "npm run dev")
        XCTAssertEqual(Activity.commandGist("sudo -E env -i nohup ./serve --port 8080"), "./serve --port 8080")
        XCTAssertEqual(Activity.commandGist("git status\ngit diff"), "git status")
        XCTAssertEqual(Activity.commandGist("cd /tmp"), "cd /tmp", "a command that only sets the scene is shown as it is")
        // Claude Code writes what each command is for; that is what the island says.
        let described = Activity.forTool("Bash", input: ["command": .string("SP=/tmp; cd $SP && swift build"), "description": .string("Build the app")])
        XCTAssertEqual(described, Activity(verb: "running", detail: "Build the app"))
        XCTAssertEqual(Activity.forTool("Bash", input: ["command": .string("SP=/tmp; cd $SP && swift build")]).detail, "swift build")
        XCTAssertEqual(Activity.forTool("Bash", input: ["command": .string("ls"), "description": .string("  ")]).detail, "ls")
        // A one-word description ("run", as ZCode writes) says less than the command; a Chinese one has no spaces.
        XCTAssertEqual(Activity.forTool("Bash", input: ["command": .string("swift test"), "description": .string("run")]).detail, "swift test")
        XCTAssertEqual(Activity.forTool("Bash", input: ["command": .string("swift test"), "description": .string("运行全部测试")]).detail, "运行全部测试")
    }

    func testAnAgentsOwnWorkspaceIsNotAProject() {
        let home = NikoPaths.userHome().path
        XCTAssertTrue(AutoNamer.isAgentWorkspace(home + "/.zcode/workspace/default"))
        XCTAssertTrue(AutoNamer.isAgentWorkspace(home))
        XCTAssertFalse(AutoNamer.isAgentWorkspace(home + "/projects/app"))
        XCTAssertFalse(AutoNamer.isAgentWorkspace("/tmp/demo"))
        XCTAssertNil(AutoNamer.projectName(cwd: home + "/.zcode/workspace/default"))
        XCTAssertEqual(AutoNamer.projectName(cwd: "/tmp/niko-demo-project"), "niko-demo-project")
        XCTAssertEqual(AutoNamer.title(cwd: home + "/.zcode/workspace/default", prompt: "Watch the AP queue", source: "zcode"), "ZCode · Watch AP queue")
    }

    func testAnOldReadingOfAPlanIsMarkedAsOld() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(LimitFreshness.isStale(nil, now: now))
        XCTAssertFalse(LimitFreshness.isStale(now.addingTimeInterval(-600), now: now))
        XCTAssertTrue(LimitFreshness.isStale(now.addingTimeInterval(-15 * 3600), now: now))
        var claude = UsageSnapshot.AgentUsage(id: "claude")
        claude.limits = [RateLimitWindow(id: "seven_day", usedPercent: 24, resetsAt: now.addingTimeInterval(8 * 3600), windowMinutes: 10080)]
        claude.limitsCapturedAt = now.addingTimeInterval(-15 * 3600)
        var snapshot = UsageSnapshot()
        snapshot.agents = [UsageSnapshot.AgentUsage(id: "all"), claude]
        XCTAssertEqual(QuotaGlance.make(usage: snapshot, recentAgents: ["claude"], now: now)?.stale, true)
        snapshot.agents[1].limitsCapturedAt = now.addingTimeInterval(-60)
        XCTAssertEqual(QuotaGlance.make(usage: snapshot, recentAgents: ["claude"], now: now)?.stale, false)
    }

    func testWindowsThatAreAllButUnusedAreCountedNotListed() {
        let zero = ["cursor_total", "cursor_auto", "cursor_api"].map { RateLimitWindow(id: $0, usedPercent: 0) }
        XCTAssertEqual(LimitRows.shown(zero).map(\.id), ["cursor_total"])
        XCTAssertEqual(LimitRows.quiet(zero), 2)
        let mixed = [RateLimitWindow(id: "five_hour", usedPercent: 0), RateLimitWindow(id: "seven_day", usedPercent: 24)]
        XCTAssertEqual(LimitRows.shown(mixed).map(\.id), ["seven_day"])
        XCTAssertEqual(LimitRows.quiet(mixed), 1)
        let used = [RateLimitWindow(id: "five_hour", usedPercent: 40), RateLimitWindow(id: "seven_day", usedPercent: 24)]
        XCTAssertEqual(LimitRows.shown(used).count, 2)
        XCTAssertNil(LimitRows.quiet(used))
        XCTAssertEqual(LimitRows.shown([RateLimitWindow(id: "primary", usedPercent: 0)]).count, 1)
    }

    func testWhenEachAgentWasLastHeardSurvivesARestart() {
        let scratch = Scratch()
        try? FileManager.default.createDirectory(at: scratch.paths.cache, withIntermediateDirectories: true)
        XCTAssertEqual(LastHeard.load(paths: scratch.paths), [:])
        let heard = ["codex": Date(timeIntervalSince1970: 1_800_000_000), "zcode": Date(timeIntervalSince1970: 1_800_000_500)]
        LastHeard.save(heard, paths: scratch.paths)
        XCTAssertEqual(LastHeard.load(paths: scratch.paths), heard)
        XCTAssertEqual(mode(of: LastHeard.file(scratch.paths)), 0o600)
    }

    func testStatusDoesNotListFilesThatAreMeantToBeGone() {
        let scratch = Scratch()
        scratch.write("home/.gemini/settings.json", #"{"hooks":{}}"#)
        let line = Diagnostics.agentSummary(home: scratch.file("home")).first { $0.hasPrefix("Gemini CLI") } ?? ""
        XCTAssertTrue(line.contains(".gemini/settings.json"))
        XCTAssertFalse(line.contains("plugins/niko"), "where an older version put its files is not reported as missing")
    }
}
