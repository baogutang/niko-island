import XCTest
@testable import NikoCore

let claudeFixture = """
{
  "env": {
    "EXAMPLE_FLAG": "1"
  },
  "permissions": {
    "allow": [
      "Bash(npm test:*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/bin/audit-shell.sh",
            "timeout": 3
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "afplay /System/Library/Sounds/Glass.aiff"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  },
  "model": "opus"
}

"""

final class InstallerTests: XCTestCase {
    var scratch: Scratch!
    var home: URL { scratch.file("home") }
    let settingsPath = "home/.claude/settings.json"

    override func setUp() {
        scratch = Scratch()
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() { scratch = nil }

    private func options(agents: [String]? = nil, at offset: TimeInterval = 0) -> InstallOptions {
        var options = InstallOptions(home: home, paths: scratch.paths)
        options.agentIDs = agents
        options.bridgeBinary = bridgeBinaryPath
        options.now = Date(timeIntervalSince1970: 1_760_000_000 + offset)
        return options
    }

    @discardableResult
    private func run(_ action: InstallAction, agents: [String]? = nil, at offset: TimeInterval = 0,
                     configure: (inout InstallOptions) -> Void = { _ in }) -> InstallResult {
        var options = options(agents: agents, at: offset)
        configure(&options)
        return Installer(options: options).run(action)
    }

    private func settings() throws -> JSONObject {
        try XCTUnwrap(JSONValue.parse(Data(contentsOf: scratch.file(settingsPath))).objectValue)
    }

    private func backups(_ relative: String = ".claude/settings.json") -> [String] {
        Installer(options: options()).backups(for: relative)
    }

    private func ourCommands(in root: JSONObject) -> [(event: String, hook: JSONValue, group: JSONValue)] {
        var out: [(String, JSONValue, JSONValue)] = []
        for member in root["hooks"]?.objectValue?.members ?? [] {
            for group in member.value.arrayValue ?? [] {
                for hook in group["hooks"]?.arrayValue ?? [] where HookMerge.isOurs(command: hook["command"]?.stringValue ?? "") {
                    out.append((member.key, hook, group))
                }
            }
        }
        return out
    }

    // MARK: Claude Code wiring

    /// A ~/.claude that holds only skills (Cursor and skill installers make one) is not Claude Code.
    func testClaudeDirectoryAloneIsNotClaudeCode() throws {
        let claude = try XCTUnwrap(AgentRegistry.descriptor("claude"))
        scratch.write("home/.claude/skills/review/SKILL.md", "# review")
        var report = try ScanProbe.run(home: home, agents: [claude])
        XCTAssertEqual(report.agents["claude"]?.directory, .present)
        // This Mac may well have `claude` on its PATH; the scan of a Mac without it has no binary.
        report.agents["claude"]?.binary = nil
        XCTAssertFalse(report.isInstalled(claude))
        XCTAssertTrue(report.isInstalled(claude, apps: ["com.anthropic.claudefordesktop"]), "the desktop app has Claude Code in it")
        let scanned = report
        let skipped = run(.install, agents: ["claude"]) { $0.detectedOnly = true; $0.dryRun = true; $0.scanOverride = { scanned } }
        XCTAssertEqual(skipped.plan.outcomes.first?.status, .notDetected)
        XCTAssertTrue(skipped.plan.changes.isEmpty)
        XCTAssertFalse(run(.install, agents: ["claude"]) { $0.dryRun = true; $0.scanOverride = { scanned } }.plan.changes.isEmpty,
                       "an agent asked for by name is still connected")
        report.agents["claude"]?.binary = "/usr/local/bin/claude"
        XCTAssertTrue(report.isInstalled(claude), "its command on the PATH counts")

        for marker in [".claude.json", ".claude/projects/-w/1.jsonl", ".local/share/claude/versions/2.1.3"] {
            let other = Scratch()
            other.write("home/.claude/skills/x/SKILL.md", "x")
            other.write("home/" + marker, "{}")
            report = try ScanProbe.run(home: other.file("home"), agents: [claude])
            XCTAssertTrue(report.isInstalled(claude), marker)
        }
        // Agents without markers keep the plain rule.
        let codex = try XCTUnwrap(AgentRegistry.descriptor("codex"))
        scratch.write("home/.codex/config.toml", "")
        XCTAssertTrue(try ScanProbe.run(home: home, agents: [codex]).isInstalled(codex))
    }

    func testNativeClaudeCodeIsKnownByItsPath() {
        XCTAssertEqual(AgentPresence.alias(forPath: "/Users/a/.local/share/claude/versions/2.1.295"), "claude")
        XCTAssertNil(AgentPresence.alias(forPath: "/usr/local/bin/2to3"))
    }

    func testDryRunChangesNothing() throws {
        scratch.write(settingsPath, claudeFixture)
        let result = run(.install) { $0.dryRun = true }
        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(result.applied)
        XCTAssertEqual(result.plan.changes.map(\.relativePath), [".claude/settings.json"])
        XCTAssertEqual(result.plan.changes.first?.kind, .modify)
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture)
        XCTAssertTrue(backups().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.root.path), "dry run must not even create our runtime dir")
        XCTAssertTrue(result.report(home: home.path).contains("Dry run: nothing was changed."))
    }

    func testInstallWiresEveryEventWithMarkerAndTimeouts() throws {
        scratch.write(settingsPath, claudeFixture)
        let result = run(.install)
        XCTAssertTrue(result.succeeded, result.error ?? "")
        XCTAssertTrue(result.applied)
        let root = try settings()
        let ours = ourCommands(in: root)
        XCTAssertEqual(Set(ours.map(\.event)), Set(HookEvent.canonical + [HookEvent.postCompact, HookEvent.stopFailure]))
        XCTAssertEqual(ours.count, 12)
        for entry in ours {
            let command = try XCTUnwrap(entry.hook["command"]?.stringValue)
            XCTAssertTrue(command.contains("niko-bridge"), "every entry of ours carries the marker")
            XCTAssertTrue(command.hasPrefix("/bin/sh -c '[ -x "))
            XCTAssertTrue(command.hasSuffix("--source claude; exit 0'"))
            XCTAssertEqual(entry.hook["type"]?.stringValue, "command")
            switch entry.event {
            case "PermissionRequest":
                XCTAssertEqual(entry.hook["timeout"]?.intValue, 86400)
                XCTAssertEqual(entry.group["matcher"]?.stringValue, "*")
            case "PreCompact", "PostCompact":
                XCTAssertEqual(entry.group["matcher"]?.stringValue, "manual|auto")
            default:
                XCTAssertEqual(entry.group["matcher"]?.stringValue, "*")
                XCTAssertEqual(entry.hook["timeout"]?.intValue, 10)
            }
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scratch.paths.bridgeShim.path))
        XCTAssertEqual(scratch.read("ni/bin/.bridge-cache"), bridgeBinaryPath + "\n")
    }

    func testForeignConfigurationIsPreservedExactly() throws {
        let url = scratch.write(settingsPath, claudeFixture)
        chmod(url.path, 0o640)
        XCTAssertTrue(run(.install).succeeded)
        let before = try XCTUnwrap(JSONValue.parse(claudeFixture).objectValue)
        let after = try settings()
        XCTAssertEqual(after.keys, before.keys, "top-level key order untouched")
        for key in ["env", "permissions", "model"] { XCTAssertEqual(after[key], before[key], key) }

        // Foreign hooks: still first, byte-for-byte the same values (timeouts and matchers not weakened).
        let foreignPre = try XCTUnwrap(before["hooks"]?["PreToolUse"]?[0])
        XCTAssertEqual(after["hooks"]?["PreToolUse"]?[0], foreignPre)
        XCTAssertEqual(after["hooks"]?["PreToolUse"]?.arrayValue?.count, 2)
        XCTAssertEqual(after["hooks"]?["Stop"]?[0], before["hooks"]?["Stop"]?[0])
        XCTAssertEqual(Array(after["hooks"]?.objectValue?.keys.prefix(2) ?? []), ["PreToolUse", "Stop"])
        XCTAssertEqual(HookMerge.strip(after).root["hooks"], before["hooks"])

        // The status line is wrapped, its other keys kept, the original remembered and chained.
        XCTAssertEqual(after["statusLine"]?["padding"]?.intValue, 0)
        XCTAssertTrue(after["statusLine"]?["command"]?.stringValue?.contains("niko-statusline") ?? false)
        let sidecar = try JSONValue.parse(Data(contentsOf: scratch.paths.statuslineOriginal))
        XCTAssertEqual(sidecar, before["statusLine"])
        XCTAssertTrue(try String(contentsOf: scratch.paths.statuslineScript, encoding: .utf8)
            .contains("printf '%s' \"$input\" | ~/.claude/statusline.sh"))

        // File mode kept; one backup holding the original bytes.
        XCTAssertEqual(mode(of: url), 0o640)
        let saved = backups()
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(saved[0].hasSuffix("settings.json.niko-backup-20251009-085320") || saved[0].contains(".niko-backup-"))
        XCTAssertEqual(try String(contentsOfFile: saved[0], encoding: .utf8), claudeFixture)
        XCTAssertEqual(mode(of: URL(fileURLWithPath: saved[0])), 0o640)
    }

    func testInstallIsIdempotent() throws {
        scratch.write(settingsPath, claudeFixture)
        XCTAssertTrue(run(.install).applied)
        let first = scratch.read(settingsPath)
        let second = run(.install, at: 60)
        XCTAssertTrue(second.succeeded)
        XCTAssertFalse(second.applied)
        XCTAssertTrue(second.plan.isNoOp)
        XCTAssertEqual(second.plan.outcomes, [AgentOutcome(id: "claude", status: .unchanged)])
        XCTAssertEqual(scratch.read(settingsPath), first)
        XCTAssertEqual(backups().count, 1, "a no-op install makes no backup")
    }

    func testReinstallReplacesOutdatedEntriesInsteadOfDuplicating() throws {
        // An older build's entries (different command text, same marker).
        let old = claudeFixture.replacingOccurrences(of: "\"model\": \"opus\"", with: "\"model\": \"opus\"")
        var root = try XCTUnwrap(JSONValue.parse(old).objectValue)
        root = try HookMerge.install(into: root, specs: [HookSpec("PreToolUse"), HookSpec("LegacyEvent")]) { _ in "/old/path/niko-bridge --source claude" }
        scratch.write(settingsPath, JSONValue.object(root).serialized(.pretty))
        XCTAssertTrue(run(.install).applied)
        let after = try settings()
        XCTAssertEqual(ourCommands(in: after).count, 12)
        XCTAssertNil(after["hooks"]?["LegacyEvent"], "an event that only held our old entry is cleaned up")
        XCTAssertFalse(JSONValue.object(after).serialized().contains("/old/path/niko-bridge"))
    }

    func testUninstallRestoresOriginalBytes() throws {
        scratch.write(settingsPath, claudeFixture)
        XCTAssertTrue(run(.install).applied)
        let result = run(.uninstall, at: 120)
        XCTAssertTrue(result.succeeded, result.error ?? "")
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture, "byte-identical to what the user had")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.bridgeShim.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.statuslineScript.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.statuslineOriginal.path))
        XCTAssertFalse(HookMerge.containsOurs(try settings()))
        XCTAssertTrue(run(.uninstall, at: 180).plan.isNoOp, "second uninstall has nothing to do")
    }

    func testUninstallKeepsEditsMadeAfterInstall() throws {
        scratch.write(settingsPath, claudeFixture)
        XCTAssertTrue(run(.install).applied)
        // The user keeps working on their config while we are installed.
        var root = try settings()
        root["model"] = .string("sonnet")
        root["newSetting"] = .bool(true)
        var hooks = try XCTUnwrap(root["hooks"]?.objectValue)
        var stop = try XCTUnwrap(hooks["Stop"]?.arrayValue)
        stop.append(HookMerge.group(spec: HookSpec("Stop", matcher: nil, timeout: nil), command: "say done"))
        hooks["Stop"] = .array(stop)
        hooks["SubagentStop"] = .array([.object(["hooks": .array([.object(["type": .string("command"), "command": .string("true")])])])]
            + (hooks["SubagentStop"]?.arrayValue ?? []))
        root["hooks"] = .object(hooks)
        scratch.write(settingsPath, JSONValue.object(root).serialized(.pretty))

        XCTAssertTrue(run(.uninstall, at: 300).succeeded)
        let after = try settings()
        XCTAssertFalse(HookMerge.containsOurs(after))
        XCTAssertEqual(after["model"]?.stringValue, "sonnet")
        XCTAssertEqual(after["newSetting"]?.boolValue, true)
        XCTAssertEqual(after["hooks"]?["Stop"]?.arrayValue?.count, 2)
        XCTAssertEqual(after["hooks"]?["Stop"]?[1]?["hooks"]?[0]?["command"]?.stringValue, "say done")
        XCTAssertEqual(after["hooks"]?["SubagentStop"]?.arrayValue?.count, 1, "their SubagentStop hook stays, ours goes")
        XCTAssertEqual(after["hooks"]?["PreToolUse"]?.arrayValue?.count, 1)
        XCTAssertNil(after["hooks"]?["PermissionRequest"])
        XCTAssertEqual(after["statusLine"], try JSONValue.parse(claudeFixture)["statusLine"], "original status line restored")
    }

    func testUninstallRemovesOnlyMarkerTaggedEntriesInsideSharedGroups() throws {
        let mixed = """
        {"hooks":{"PreToolUse":[{"matcher":"*","hooks":[
          {"type":"command","command":"echo mine"},
          {"type":"command","command":"/bin/sh -c '[ -x /x/niko-bridge ] && /x/niko-bridge --source claude; exit 0'","timeout":10},
          {"type":"command","command":"echo also-mine","timeout":99}]}],
         "Notification":[{"type":"command","command":"/x/niko-bridge --source claude"}],
         "UserPromptSubmit":[],
         "Weird":"not-an-array"},
         "statusLine":{"type":"command","command":"my-own-statusline"}}
        """
        scratch.write(settingsPath, mixed)
        let result = run(.uninstall)
        XCTAssertTrue(result.succeeded, result.error ?? "")
        let after = try settings()
        let hooks = try XCTUnwrap(after["hooks"]?["PreToolUse"]?[0]?["hooks"]?.arrayValue)
        XCTAssertEqual(hooks.compactMap { $0["command"]?.stringValue }, ["echo mine", "echo also-mine"])
        XCTAssertEqual(hooks[1]["timeout"]?.intValue, 99)
        XCTAssertNil(after["hooks"]?["Notification"], "flat entry of ours removed together with its now-empty event")
        XCTAssertEqual(after["hooks"]?["UserPromptSubmit"], .array([]), "foreign empty array is not ours to delete")
        XCTAssertEqual(after["hooks"]?["Weird"]?.stringValue, "not-an-array")
        XCTAssertEqual(after["statusLine"]?["command"]?.stringValue, "my-own-statusline", "a status line that is not ours is never touched")
    }

    func testStatusLineAddedThenRemovedWhenUserHadNone() throws {
        scratch.write(settingsPath, "{\n  \"model\": \"opus\"\n}\n")
        XCTAssertTrue(run(.install).applied)
        XCTAssertTrue(try settings()["statusLine"]?["command"]?.stringValue?.contains("niko-statusline") ?? false)
        XCTAssertEqual(scratch.read("ni/cache/statusline-original.json")?.trimmingCharacters(in: .whitespacesAndNewlines), "null")
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertEqual(scratch.read(settingsPath), "{\n  \"model\": \"opus\"\n}\n")
    }

    func testNoStatuslineOptionLeavesStatusLineAlone() throws {
        scratch.write(settingsPath, claudeFixture)
        XCTAssertTrue(run(.install) { $0.includeStatusLine = false }.applied)
        XCTAssertEqual(try settings()["statusLine"], try JSONValue.parse(claudeFixture)["statusLine"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.statuslineOriginal.path))
    }

    func testNewForeignStatusLineIsRechainedOnReinstall() throws {
        scratch.write(settingsPath, claudeFixture)
        XCTAssertTrue(run(.install).applied)
        var root = try settings()
        root["statusLine"] = .object(["type": .string("command"), "command": .string("brand-new-statusline --fancy")])
        scratch.write(settingsPath, JSONValue.object(root).serialized(.pretty))
        XCTAssertTrue(run(.install, at: 60).applied)
        let script = try String(contentsOf: scratch.paths.statuslineScript, encoding: .utf8)
        XCTAssertTrue(script.contains("| brand-new-statusline --fancy"))
        XCTAssertFalse(script.contains("~/.claude/statusline.sh"))
        XCTAssertEqual(try JSONValue.parse(Data(contentsOf: scratch.paths.statuslineOriginal))["command"]?.stringValue, "brand-new-statusline --fancy")
    }

    func testFormattingStylesSurviveRoundTrip() throws {
        for original in ["{\n    \"model\": \"opus\",\n    \"hooks\": {}\n}\n", "{\"model\":\"opus\",\"n\":1.50}", "{\n\t\"a\": [\n\t\t1\n\t]\n}"] {
            scratch.write(settingsPath, original)
            XCTAssertTrue(run(.install) { $0.includeStatusLine = false }.applied, original)
            let installed = try XCTUnwrap(scratch.read(settingsPath))
            if original.contains("\n    ") { XCTAssertTrue(installed.contains("\n        \"PreToolUse\": ["), "four-space indent kept") }
            if !original.contains("\n") { XCTAssertFalse(installed.contains("\n"), "compact stays compact") }
            XCTAssertTrue(installed.contains("1.50") || !original.contains("1.50"), "number spelling kept")
            XCTAssertTrue(run(.uninstall, at: 60).succeeded)
            XCTAssertEqual(scratch.read(settingsPath), original)
            backups().forEach { unlink($0) }
        }
    }

    // MARK: Refusals

    func testInvalidOrOddConfigsAreLeftUntouched() throws {
        let cases: [(String, String)] = [
            ("{ this is not json", "not valid JSON"),
            ("[1, 2, 3]", "not a JSON object"),
            ("{\"hooks\": [\"array\"]}", "\"hooks\" is not an object"),
            ("{\"hooks\": {\"Stop\": {\"oops\": 1}}}", "hooks.Stop is not an array"),
        ]
        for (content, reason) in cases {
            scratch.write(settingsPath, content)
            let result = run(.install)
            XCTAssertTrue(result.succeeded)
            XCTAssertFalse(result.applied, content)
            guard case .skipped(let why) = result.plan.outcomes.first?.status else { return XCTFail("expected skip for \(content)") }
            XCTAssertTrue(why.contains(reason), why)
            XCTAssertEqual(scratch.read(settingsPath), content)
            XCTAssertTrue(backups().isEmpty)
        }
    }

    func testUnreadableAndOversizeConfigsAreLeftUntouched() throws {
        let url = scratch.write(settingsPath, claudeFixture)
        chmod(url.path, 0o000)
        var result = run(.install)
        chmod(url.path, 0o600)
        guard case .skipped = result.plan.outcomes.first?.status else { return XCTFail("unreadable should be skipped") }
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture)

        let big = "{\"pad\":\"" + String(repeating: "x", count: ScanProbe.sizeCap + 10) + "\"}"
        scratch.write(settingsPath, big)
        result = run(.install)
        guard case .skipped(let why) = result.plan.outcomes.first?.status else { return XCTFail("oversize should be skipped") }
        XCTAssertTrue(why.contains("over the scan limit"))
        XCTAssertEqual(scratch.read(settingsPath)?.count, big.count)

        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)   // a directory where the file should be
        guard case .skipped = run(.install).plan.outcomes.first?.status else { return XCTFail("directory should be skipped") }
    }

    func testAgentNotInstalledMeansNothingIsCreated() throws {
        let result = run(.install)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.plan.outcomes, [AgentOutcome(id: "claude", status: .notDetected)])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.path), [], "we never create an agent's directory")
        XCTAssertTrue(result.report(home: home.path).contains("no supported agent directories"))
    }

    func testMissingSettingsFileIsCreatedPrivately() throws {
        try FileManager.default.createDirectory(at: scratch.file("home/.claude"), withIntermediateDirectories: true)
        let result = run(.install)
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.plan.changes.first?.kind, .create)
        XCTAssertEqual(mode(of: scratch.file(settingsPath)), 0o600)
        XCTAssertEqual(ourCommands(in: try settings()).count, 12)
        XCTAssertTrue(backups().isEmpty, "nothing to back up")
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertEqual(scratch.read(settingsPath), "{}\n")
    }

    func testEmptyAndBlankFilesAreTreatedAsEmptyObjects() throws {
        for blank in ["", "  \n"] {
            scratch.write(settingsPath, blank)
            XCTAssertTrue(run(.install).applied)
            XCTAssertEqual(ourCommands(in: try settings()).count, 12)
            XCTAssertEqual(try String(contentsOfFile: try XCTUnwrap(backups().first), encoding: .utf8), blank)
            backups().forEach { unlink($0) }
            Shims.remove(paths: scratch.paths)
        }
        scratch.write(settingsPath, "{\"hooks\":{},\"x\":{\"Stop\":[]}}")
        XCTAssertTrue(run(.install).applied, "an existing empty hooks object must not trip the safety check")
    }

    func testSymlinkedSettingsAreWrittenThroughTheLink() throws {
        let target = scratch.write("dotfiles/claude-settings.json", claudeFixture)
        try FileManager.default.createDirectory(at: scratch.file("home/.claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: scratch.file(settingsPath), withDestinationURL: target)
        XCTAssertTrue(run(.install).applied)
        var st = stat()
        lstat(scratch.file(settingsPath).path, &st)
        XCTAssertEqual(st.st_mode & S_IFMT, S_IFLNK, "the symlink itself is still a symlink")
        XCTAssertTrue(HookMerge.containsOurs(try XCTUnwrap(JSONValue.parse(Data(contentsOf: target)).objectValue)))
        XCTAssertEqual(backups().count, 1, "backup sits next to the link, not inside the dotfiles repo")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.file("dotfiles").path), ["claude-settings.json"])
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), claudeFixture)
    }

    // MARK: Failure handling

    func testPartialFailureRollsEverythingBack() throws {
        scratch.write(settingsPath, claudeFixture)
        let codexOriginal = "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"echo codex-user-hook\"}]}]}}"
        scratch.write("home/.codex/hooks.json", codexOriginal)
        let result = run(.install, agents: ["claude", "codex"]) { $0.failAfterWrites = 1 }
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.rolledBack)
        XCTAssertFalse(result.applied)
        XCTAssertTrue(result.error?.contains("restored") ?? false)
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture, "first file was written, then restored")
        XCTAssertEqual(scratch.read("home/.codex/hooks.json"), codexOriginal)
        XCTAssertTrue(backups().isEmpty, "a rolled-back run leaves no backup clutter")
        XCTAssertTrue(backups(".codex/hooks.json").isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.statuslineOriginal.path))
    }

    func testRollbackRemovesFilesAndDirectoriesItCreated() throws {
        try FileManager.default.createDirectory(at: scratch.file("home/.copilot"), withIntermediateDirectories: true)
        scratch.write(settingsPath, claudeFixture)
        let result = run(.install, agents: ["copilot", "claude"]) { $0.failAfterWrites = 1 }
        XCTAssertTrue(result.rolledBack)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.file("home/.copilot").path), [])
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture)
    }

    func testVerificationMismatchRollsBack() throws {
        scratch.write(settingsPath, claudeFixture)
        let path = scratch.file(settingsPath).path
        let result = run(.install) { options in
            options.beforeVerify = { try? Data("{\"tampered\":true}".utf8).write(to: URL(fileURLWithPath: path)) }
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.rolledBack)
        XCTAssertTrue(result.error?.contains("verification failed") ?? false)
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture)
    }

    func testFileChangedAfterScanIsNotOverwritten() throws {
        scratch.write(settingsPath, claudeFixture)
        let installer = Installer(options: options())
        let plan = installer.plan(.install, scan: try installer.scan(.install))
        let edited = claudeFixture.replacingOccurrences(of: "\"opus\"", with: "\"haiku\"")
        scratch.write(settingsPath, edited)   // the agent (or the user) saved in the meantime
        let result = installer.apply(plan)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.error?.contains("changed after it was scanned") ?? false)
        XCTAssertEqual(scratch.read(settingsPath), edited)
        XCTAssertTrue(backups().isEmpty)
    }

    func testScanFailureMeansNoMutation() throws {
        scratch.write(settingsPath, claudeFixture)
        for action in [InstallAction.install, .uninstall] {
            let result = run(action) { $0.scanOverride = { throw ScanError.incomplete("no end marker") } }
            XCTAssertTrue(result.error?.contains("nothing was changed") ?? false)
            XCTAssertFalse(result.applied)
            XCTAssertTrue(result.plan.changes.isEmpty)
        }
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.root.path))
    }

    // MARK: Backups

    func testBackupsArePrunedToTheNewestThree() throws {
        scratch.write(settingsPath, claudeFixture)
        for cycle in 0..<4 {
            XCTAssertTrue(run(.install, at: Double(cycle) * 100).applied)
            XCTAssertTrue(run(.uninstall, at: Double(cycle) * 100 + 50).succeeded)
        }
        XCTAssertEqual(backups().count, 3)
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture)
    }

    func testPurgeRemovesRuntimeDirectoryAndBackups() throws {
        scratch.write(settingsPath, claudeFixture)
        XCTAssertTrue(run(.install).applied)
        scratch.write("ni/data/usage/usage.sqlite", "pretend database")
        XCTAssertTrue(run(.uninstall, at: 60) { $0.purge = true }.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.root.path))
        XCTAssertTrue(backups().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.file("home/.claude").path), ["settings.json"])
        XCTAssertEqual(scratch.read(settingsPath), claudeFixture)
    }

    func testPlainUninstallKeepsUsageDataAndBackups() throws {
        scratch.write(settingsPath, claudeFixture)
        XCTAssertTrue(run(.install).applied)
        scratch.write("ni/data/usage/usage.sqlite", "pretend database")
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertEqual(scratch.read("ni/data/usage/usage.sqlite"), "pretend database")
        XCTAssertFalse(backups().isEmpty)
    }

    // MARK: Other adapters

    func testDefaultInstallOnlyTouchesStableAdapters() throws {
        scratch.write(settingsPath, claudeFixture)
        scratch.write("home/.codex/hooks.json", "{}")
        scratch.write("home/.cursor/hooks.json", "{}")
        try FileManager.default.createDirectory(at: scratch.file("home/.config/opencode"), withIntermediateDirectories: true)
        let result = run(.install)
        XCTAssertEqual(result.plan.outcomes.map(\.id), ["claude"])
        XCTAssertEqual(scratch.read("home/.codex/hooks.json"), "{}")
        XCTAssertEqual(scratch.read("home/.cursor/hooks.json"), "{}")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.file("home/.config/opencode").path), [])
        XCTAssertFalse(NikoSettings.load(paths: scratch.paths).httpIngressEnabled)
    }

    func testGenericSettingsAdapterMergesAndUninstalls() throws {
        let original = "{\n  \"hooks\": {\n    \"Stop\": [\n      {\n        \"hooks\": [\n          {\n            \"type\": \"command\",\n            \"command\": \"echo theirs\"\n          }\n        ]\n      }\n    ]\n  }\n}\n"
        scratch.write("home/.qwen/settings.json", original)
        XCTAssertTrue(run(.install, agents: ["qwen"]).applied)
        let root = try XCTUnwrap(JSONValue.parse(Data(contentsOf: scratch.file("home/.qwen/settings.json"))).objectValue)
        XCTAssertEqual(root["hooks"]?["Stop"]?.arrayValue?.count, 2)
        XCTAssertEqual(root["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["command"]?.stringValue, "echo theirs")
        XCTAssertTrue(root["hooks"]?["PreToolUse"]?[0]?["hooks"]?[0]?["command"]?.stringValue?.contains("--source qwen") ?? false)
        XCTAssertNil(root["hooks"]?["PermissionRequest"], "approvals are only wired where the agent documents the contract")
        XCTAssertNil(root["statusLine"])
        XCTAssertTrue(run(.uninstall, agents: ["qwen"], at: 60).succeeded)
        XCTAssertEqual(scratch.read("home/.qwen/settings.json"), original)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scratch.paths.bridgeShim.path), "partial uninstall keeps the shims for other agents")
    }

    // MARK: Agents with their own config dialect

    private func json(_ relative: String) throws -> JSONObject {
        try XCTUnwrap(JSONValue.parse(Data(contentsOf: scratch.file(relative))).objectValue, relative)
    }

    func testCodexGetsApprovalsWithoutMatchersAndAfterForeignEntries() throws {
        // Codex remembers trust per position in the file, so nothing of ours may be inserted before an existing entry.
        let original = #"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"theirs","timeout":30}]}]}}"#
        scratch.write("home/.codex/hooks.json", original)
        XCTAssertTrue(run(.install, agents: ["codex"]).applied)
        let hooks = try XCTUnwrap(json("home/.codex/hooks.json")["hooks"])
        XCTAssertEqual(hooks["PreToolUse"]?[0]?["hooks"]?[0]?["command"]?.stringValue, "theirs")
        let ours = try XCTUnwrap(hooks["PreToolUse"]?[1])
        XCTAssertNil(ours["matcher"], "no matcher: every tool")
        XCTAssertTrue(ours["hooks"]?[0]?["command"]?.stringValue?.contains("--source codex --reply json-strict") ?? false)
        XCTAssertEqual(hooks["PermissionRequest"]?[0]?["hooks"]?[0]?["timeout"]?.intValue, HookSpec.approvalTimeout)
        XCTAssertNil(hooks["SessionEnd"]?[0]?["hooks"]?[0]?["timeout"], "Codex caps SessionEnd hooks at three seconds")
        XCTAssertNil(hooks["Notification"], "not a Codex event")
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertEqual(scratch.read("home/.codex/hooks.json"), original)
    }

    func testZCodeHooksLiveUnderEventsAndNeedTheSwitch() throws {
        let original = #"{"mcp":{"servers":{}},"hooks":{"enabled":false,"timeoutMs":600000,"events":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"theirs","async":false}]}]}}}"#
        scratch.write("home/.zcode/cli/config.json", original)
        XCTAssertTrue(run(.install, agents: ["zcode"]).applied)
        let root = try json("home/.zcode/cli/config.json")
        XCTAssertEqual(root["hooks"]?["enabled"]?.boolValue, true, "hooks that are switched off would never run")
        XCTAssertEqual(root["hooks"]?["timeoutMs"]?.intValue, 600_000)
        XCTAssertNotNil(root["mcp"])
        let events = try XCTUnwrap(root["hooks"]?["events"])
        XCTAssertEqual(events["Stop"]?[0]?["hooks"]?[0]?["command"]?.stringValue, "theirs")
        let permission = try XCTUnwrap(events["PermissionRequest"]?[0])
        XCTAssertEqual(permission["matcher"]?.stringValue, ".*")
        XCTAssertEqual(permission["hooks"]?[0]?["type"]?.stringValue, "command")
        XCTAssertEqual(permission["hooks"]?[0]?["async"]?.boolValue, false)
        XCTAssertEqual(permission["hooks"]?[0]?["timeoutMs"]?.intValue, HookSpec.approvalTimeout * 1000)
        XCTAssertTrue(permission["hooks"]?[0]?["command"]?.stringValue?.contains("--source zcode --reply json-strict") ?? false)
        XCTAssertNotNil(events["PostToolUseFailure"])
        XCTAssertTrue(run(.install, agents: ["zcode"], at: 30).succeeded, "idempotent")
        XCTAssertEqual(try json("home/.zcode/cli/config.json")["hooks"]?["events"]?["Stop"]?.arrayValue?.count, 2)
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertEqual(scratch.read("home/.zcode/cli/config.json"), original, "the switch goes back to how the user had it")
    }

    func testCursorGetsFlatEntriesThatOnlyObserve() throws {
        let original = #"{"version":1,"hooks":{"stop":[{"command":"theirs"}],"beforeShellExecution":[{"command":"their-guard"}]}}"#
        scratch.write("home/.cursor/hooks.json", original)
        XCTAssertTrue(run(.install, agents: ["cursor"]).applied)
        let hooks = try XCTUnwrap(json("home/.cursor/hooks.json")["hooks"])
        XCTAssertEqual(hooks["stop"]?[0]?["command"]?.stringValue, "theirs")
        let ours = try XCTUnwrap(hooks["stop"]?[1])
        XCTAssertNil(ours["hooks"], "flat: the entry is the hook")
        XCTAssertNil(ours["type"])
        XCTAssertTrue(ours["command"]?.stringValue?.contains("--source cursor") ?? false)
        XCTAssertEqual(ours["timeout"]?.intValue, HookSpec.quickTimeout)
        // Cursor's permission hooks must answer with a decision. The island does not decide for Cursor, so it stays out of them.
        for event in ["beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "preToolUse", "subagentStart"] {
            XCTAssertFalse((hooks[event]?.arrayValue ?? []).contains { $0["command"]?.stringValue?.contains("niko-bridge") ?? false }, event)
        }
        XCTAssertNotNil(hooks["beforeSubmitPrompt"])
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertEqual(scratch.read("home/.cursor/hooks.json"), original)

        // A fresh file gets the version Cursor requires.
        scratch.write("home/.cursor/hooks.json", "")
        XCTAssertTrue(run(.install, agents: ["cursor"], at: 120).applied)
        XCTAssertEqual(try json("home/.cursor/hooks.json")["version"]?.intValue, 1)
    }

    func testWindsurfGeminiAndTraeUseTheirOwnSpelling() throws {
        scratch.write("home/.codeium/windsurf/hooks.json", #"{"hooks":{"pre_run_command":[{"command":"theirs","show_output":true}]}}"#)
        scratch.write("home/.gemini/settings.json", #"{"theme":"dark"}"#)
        scratch.write("home/.trae/hooks.json", "{}")
        XCTAssertTrue(run(.install, agents: ["windsurf", "gemini", "trae"]).applied)

        let windsurf = try XCTUnwrap(json("home/.codeium/windsurf/hooks.json")["hooks"])
        XCTAssertEqual(windsurf["pre_run_command"]?[0]?["show_output"]?.boolValue, true)
        XCTAssertEqual(windsurf["pre_run_command"]?[1]?["show_output"]?.boolValue, false)
        XCTAssertNil(windsurf["pre_run_command"]?[1]?["timeout"])
        XCTAssertNotNil(windsurf["post_cascade_response"])

        let gemini = try json("home/.gemini/settings.json")
        XCTAssertEqual(gemini["theme"]?.stringValue, "dark")
        let before = try XCTUnwrap(gemini["hooks"]?["BeforeTool"]?[0])
        XCTAssertNil(before["matcher"])
        XCTAssertEqual(before["hooks"]?[0]?["timeout"]?.intValue, 5000, "milliseconds")
        XCTAssertEqual(before["hooks"]?[0]?["name"]?.stringValue, "niko-island")
        XCTAssertNil(gemini["hooks"]?["PreToolUse"], "Gemini has its own event names")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.file("home/.gemini/config").path), "the 0.2.0 plugin directory is no longer written")

        let trae = try json("home/.trae/hooks.json")
        XCTAssertEqual(trae["version"]?.intValue, 1)
        XCTAssertNotNil(trae["hooks"]?["UserPromptSubmit"])

        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertEqual(scratch.read("home/.codeium/windsurf/hooks.json"), #"{"hooks":{"pre_run_command":[{"command":"theirs","show_output":true}]}}"#)
        XCTAssertEqual(scratch.read("home/.gemini/settings.json"), #"{"theme":"dark"}"#)
        XCTAssertEqual(scratch.read("home/.trae/hooks.json"), "{}")
    }

    func testLeftoversOfAnEarlierVersionAreRemoved() throws {
        // 0.2.0 wrote a plugin directory for Gemini CLI.
        scratch.write("home/.gemini/settings.json", "{}")
        scratch.write("home/.gemini/config/plugins/niko/hooks.json", #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"niko-bridge --source gemini"}]}]}}"#)
        scratch.write("home/.gemini/config/plugins/niko/plugin.json", #"{"name":"niko","description":"Niko Island status bridge (niko-bridge)."}"#)
        scratch.write("home/.gemini/config/plugins/other/plugin.json", #"{"name":"someone else's"}"#)
        XCTAssertTrue(run(.install, agents: ["gemini"]).applied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.file("home/.gemini/config/plugins/niko/hooks.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.file("home/.gemini/config/plugins/niko/plugin.json").path))
        XCTAssertNotNil(scratch.read("home/.gemini/config/plugins/other/plugin.json"))
        XCTAssertNotNil(try json("home/.gemini/settings.json")["hooks"]?["BeforeTool"])
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.file("home/.gemini/config/plugins/niko").path), "the empty directory goes too")
        XCTAssertEqual(scratch.read("home/.gemini/settings.json"), "{}")
    }

    func testRecommendedAgentsAreTheOnesWeCanVouchFor() {
        XCTAssertEqual(AgentRegistry.defaultIDs, ["claude"])
        let recommended = Set(AgentRegistry.recommendedIDs)
        XCTAssertTrue(recommended.isSuperset(of: ["claude", "codex", "zcode", "cursor", "windsurf", "gemini"]))
        XCTAssertFalse(recommended.contains("amp"), "format taken on trust: opt-in only")
        XCTAssertEqual(AgentRegistry.all.filter(\.approvals).map(\.id), ["claude", "codex", "zcode", "devin"])
        XCTAssertEqual(AgentRegistry.agent(forApp: "com.openai.codex")?.id, "codex")
        XCTAssertEqual(AgentRegistry.agent(forApp: "dev.zcode.app")?.id, "zcode")
        XCTAssertEqual(AgentRegistry.agent(forApp: "com.anthropic.claudefordesktop")?.id, "claude")
        // Ids are unique, and every agent the island can decide for says how to phrase the decision.
        XCTAssertEqual(Set(AgentRegistry.all.map(\.id)).count, AgentRegistry.all.count)
    }

    func testOwnedHookFileNeverClobbersAForeignFile() throws {
        try FileManager.default.createDirectory(at: scratch.file("home/.copilot"), withIntermediateDirectories: true)
        XCTAssertTrue(run(.install, agents: ["copilot"]).applied)
        let ours = try XCTUnwrap(scratch.read("home/.copilot/hooks/niko.json"))
        XCTAssertTrue(ours.contains("niko-bridge") && ours.contains("--source copilot"))
        XCTAssertNotNil(try JSONValue.parse(ours)["hooks"]?["Stop"])
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.file("home/.copilot/hooks/niko.json").path))

        scratch.write("home/.copilot/hooks/niko.json", "{\"note\":\"a user's own file that happens to have this name\"}")
        let blocked = run(.install, agents: ["copilot"], at: 120)
        guard case .skipped(let why) = blocked.plan.outcomes.first?.status else { return XCTFail("expected skip") }
        XCTAssertTrue(why.contains("not ours"))
        XCTAssertTrue(run(.uninstall, at: 180).succeeded)
        XCTAssertEqual(scratch.read("home/.copilot/hooks/niko.json"), "{\"note\":\"a user's own file that happens to have this name\"}")
    }

    func testOpenCodePluginEnablesLoopbackIngress() throws {
        try FileManager.default.createDirectory(at: scratch.file("home/.config/opencode"), withIntermediateDirectories: true)
        XCTAssertTrue(run(.install, agents: ["opencode"]).applied)
        let plugin = try XCTUnwrap(scratch.read("home/.config/opencode/plugins/niko.js"))
        XCTAssertTrue(plugin.contains("niko-bridge"))
        XCTAssertTrue(plugin.contains("export const NikoIsland"))
        XCTAssertTrue(NikoSettings.load(paths: scratch.paths).httpIngressEnabled)
        XCTAssertEqual(mode(of: scratch.paths.ingressToken), 0o600)
        XCTAssertTrue(run(.uninstall, at: 60).succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.file("home/.config/opencode/plugins/niko.js").path))
    }

    func testPlannedAgentsHaveNoAdapter() {
        XCTAssertTrue(Installer(options: options(agents: ["vibe", "droid"])).agents(for: .install).isEmpty)
        XCTAssertEqual(AgentRegistry.defaultIDs, ["claude"])
        XCTAssertEqual(Set(AgentRegistry.all.map(\.id)).count, AgentRegistry.all.count, "ids are unique")
    }

    // MARK: Resilience after the app is gone (REVIEW "socket absent → hooks no-op")

    func testInstalledHooksAreHarmlessOnceTheAppIsDeleted() throws {
        scratch.write(settingsPath, claudeFixture)
        XCTAssertTrue(run(.install) { $0.bridgeBinary = "/nonexistent/Niko Island.app/Contents/Helpers/niko-bridge" }.applied)
        let root = try settings()
        let stub = scratch.write("stubs/mdfind", "#!/bin/sh\nexit 0\n")
        chmod(stub.path, 0o755)
        let env = ["HOME": home.path, "PATH": scratch.file("stubs").path + ":/usr/bin:/bin"]
        let payload = Data("{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s\",\"tool_name\":\"Bash\"}".utf8)
        let installedAppPresent = FileManager.default.fileExists(atPath: "/Applications/Niko Island.app/Contents/Helpers/niko-bridge")

        // 1. App deleted, shims still there.  2. Shims deleted too.  3. Whole runtime dir deleted.
        for stage in 0..<3 {
            if stage == 1 { Shims.remove(paths: scratch.paths) }
            if stage == 2 { try FileManager.default.removeItem(at: scratch.paths.root) }
            for entry in ourCommands(in: root) {
                let command = try XCTUnwrap(entry.hook["command"]?.stringValue)
                let output = runProcess("/bin/sh", ["-c", command], stdin: payload, environment: env, inheritEnvironment: false)
                XCTAssertEqual(output.status, 0, "stage \(stage) \(entry.event)")
                if !installedAppPresent { XCTAssertEqual(output.stdout + output.stderr, "", "stage \(stage) \(entry.event)") }
            }
            let statusLine = try XCTUnwrap(root["statusLine"]?["command"]?.stringValue)
            XCTAssertEqual(runProcess("/bin/sh", ["-c", statusLine], stdin: Data("{}".utf8), environment: env, inheritEnvironment: false).status, 0)
        }
    }
}

final class ScanProbeTests: XCTestCase {
    func testReportsDirectoryAndFileStates() throws {
        let scratch = Scratch()
        scratch.write(".claude/settings.json", "{\"a\":\"ünï©ødé\"}\n")
        try FileManager.default.createDirectory(at: scratch.file(".codex"), withIntermediateDirectories: true)
        scratch.write(".cursor", "a file where a directory is expected")
        let agents = ["claude", "codex", "cursor", "gemini"].compactMap(AgentRegistry.descriptor)
        let report = try ScanProbe.run(home: scratch.url, agents: agents)
        XCTAssertEqual(report.home, scratch.url.path)
        XCTAssertEqual(report.uid, "\(getuid())")
        XCTAssertEqual(report.agents["claude"]?.directory, .present)
        XCTAssertEqual(report.file(".claude/settings.json", agent: "claude"), .present(Data("{\"a\":\"ünï©ødé\"}\n".utf8)))
        XCTAssertEqual(report.agents["codex"]?.directory, .present)
        XCTAssertEqual(report.file(".codex/hooks.json", agent: "codex"), .missing)
        XCTAssertEqual(report.agents["cursor"]?.directory, .unknown)
        XCTAssertEqual(report.agents["gemini"]?.directory, .missing)
        XCTAssertEqual(report.file(".gemini/settings.json", agent: "gemini"), .missing)
    }

    func testProbeIsReadOnlyAndPortable() throws {
        let scratch = Scratch()
        scratch.write(".claude/settings.json", "{}")
        let before = try FileManager.default.subpathsOfDirectory(atPath: scratch.url.path).sorted()
        _ = try ScanProbe.run(home: scratch.url, agents: AgentRegistry.installable, includeVersions: false)
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: scratch.url.path).sorted(), before)
        let script = scratch.write("probe.sh", ScanProbe.script(agents: AgentRegistry.installable, includeVersions: true))
        for shell in ["/bin/sh", "/bin/dash", "/bin/bash", "/bin/zsh"] {
            XCTAssertEqual(runProcess(shell, ["-n", script.path]).status, 0, shell)
        }
        let viaDash = runProcess("/bin/dash", [script.path], environment: ["HOME": scratch.url.path])
        XCTAssertEqual(viaDash.status, 0)
        XCTAssertNoThrow(try ScanProbe.parse(viaDash.stdout, expecting: AgentRegistry.installable))
    }

    func testRejectsIncompleteOrCorruptOutput() {
        let agents = [AgentRegistry.descriptor("claude")!]
        let good = "<<<NI:meta>>>\nprobe=1\nhome=/h\nuid=501\n<<<NI:agent:claude>>>\ndir=D\nfile=.claude/settings.json|F|2|e30=\n<<<NI:end>>>\n"
        XCTAssertNoThrow(try ScanProbe.parse(good, expecting: agents))
        let cases = [
            good.replacingOccurrences(of: "<<<NI:end>>>\n", with: ""),                 // truncated
            good.replacingOccurrences(of: "probe=1\n", with: ""),                       // no meta
            good.replacingOccurrences(of: "|F|2|e30=", with: "|F|3|e30="),              // size mismatch
            good.replacingOccurrences(of: "|F|2|e30=", with: "|F|2|!!!"),               // bad base64
            good.replacingOccurrences(of: "file=.claude/settings.json|F|2|e30=\n", with: ""),   // missing record
            good.replacingOccurrences(of: "<<<NI:agent:claude>>>", with: "<<<NI:agent:other>>>"),
            "",
        ]
        for output in cases { XCTAssertThrowsError(try ScanProbe.parse(output, expecting: agents), output) }
    }
}
