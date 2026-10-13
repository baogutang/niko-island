import XCTest
@testable import NikoCore
@testable import NikoIslandApp

/// Drives the real `niko-island` executable the way a user would.
final class CLITests: XCTestCase {
    var scratch: Scratch!
    var home: URL { scratch.file("home") }
    var cli: String { buildProductsDirectory.appendingPathComponent("niko-island").path }

    let fixture = "{\n  \"model\": \"opus\",\n  \"hooks\": {\n    \"Stop\": [\n      {\n        \"hooks\": [\n          {\n            \"type\": \"command\",\n            \"command\": \"echo mine\"\n          }\n        ]\n      }\n    ]\n  }\n}\n"

    override func setUp() {
        scratch = Scratch()
        scratch.write("home/.claude/settings.json", fixture)
    }

    override func tearDown() { scratch = nil }

    private func niko(_ arguments: String...) -> ProcessOutput {
        runProcess(cli, arguments + (arguments.first.map { ["install", "uninstall", "scan", "status", "doctor", "diagnostics"].contains($0) } == true
                                     ? ["--home", home.path] : []),
                   environment: ["NIKO_ISLAND_HOME": scratch.paths.root.path])
    }

    func testVersionHelpAndUnknownCommand() {
        XCTAssertEqual(niko("--version").stdout, "niko-island \(NikoVersion.current)\n")
        let help = niko("--help")
        XCTAssertEqual(help.status, 0)
        for word in ["install", "uninstall", "--dry-run", "--purge", "scan", "doctor", "diagnostics"] {
            XCTAssertTrue(help.stdout.contains(word), word)
        }
        XCTAssertEqual(niko("frobnicate").status, 64)
        XCTAssertEqual(niko("install", "--agents", "nonexistent").status, 64)
        XCTAssertEqual(niko("install", "--agents", "kimi").status, 64, "planned agents have no adapter")
        XCTAssertEqual(niko("install", "--bogus-flag").status, 64)
        XCTAssertEqual(niko("install", "--purge").status, 64)
        XCTAssertEqual(scratch.read("home/.claude/settings.json"), fixture)
    }

    func testDryRunThenInstallThenUninstall() throws {
        let dry = niko("install", "--dry-run")
        XCTAssertEqual(dry.status, 0, dry.stderr)
        XCTAssertTrue(dry.stdout.contains("Claude Code: modify ~/.claude/settings.json"))
        XCTAssertTrue(dry.stdout.contains("Dry run: nothing was changed."))
        XCTAssertEqual(scratch.read("home/.claude/settings.json"), fixture)

        let install = niko("install")
        XCTAssertEqual(install.status, 0, install.stderr)
        XCTAssertTrue(install.stdout.contains("install complete."))
        XCTAssertTrue(install.stdout.contains("backup: ~/.claude/settings.json.niko-backup-"))
        let wired = try XCTUnwrap(JSONValue.parse(Data(contentsOf: scratch.file("home/.claude/settings.json"))).objectValue)
        XCTAssertTrue(HookMerge.containsOurs(wired))
        XCTAssertEqual(scratch.read("ni/bin/.bridge-cache"), bridgeBinaryPath + "\n", "bridge found next to the CLI binary")

        XCTAssertTrue(niko("status").stdout.contains("Claude Code [stable]: hooks installed"))
        XCTAssertTrue(niko("status").stdout.contains("app: not running"))
        XCTAssertTrue(niko("install").stdout.contains("already up to date"))

        let uninstall = niko("uninstall")
        XCTAssertEqual(uninstall.status, 0, uninstall.stderr)
        XCTAssertTrue(uninstall.stdout.contains("uninstall complete."))
        XCTAssertEqual(scratch.read("home/.claude/settings.json"), fixture)
        XCTAssertTrue(niko("scan").stdout.contains("Claude Code [stable]: not wired"))
        XCTAssertTrue(niko("uninstall").stdout.contains("Nothing to do."))
    }

    func testExperimentalAdaptersAreOptInAndAnnounced() throws {
        scratch.write("home/.codex/hooks.json", "{}")
        XCTAssertFalse(niko("install").stdout.contains("Codex"))
        XCTAssertEqual(scratch.read("home/.codex/hooks.json"), "{}")
        let all = niko("install", "--all")
        XCTAssertTrue(all.stdout.contains("Beta adapters selected"), all.stdout)
        XCTAssertTrue(all.stdout.contains("Experimental adapters selected"), all.stdout)
        XCTAssertTrue(all.stdout.contains("Codex: modify ~/.codex/hooks.json"), all.stdout)
        XCTAssertTrue(all.stdout.contains("Codex runs a new hook only after you trust it"), "what the user still has to do")
        XCTAssertTrue(niko("uninstall").stdout.contains("Codex: modify ~/.codex/hooks.json"))
        XCTAssertEqual(scratch.read("home/.codex/hooks.json"), "{}")

        // --recommended: what the app offers on first launch. Agents that are not installed are left alone.
        let recommended = niko("install", "--recommended")
        XCTAssertTrue(recommended.stdout.contains("Codex: modify ~/.codex/hooks.json"), recommended.stdout)
        XCTAssertFalse(recommended.stdout.contains("Experimental adapters selected"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.file("home/.cursor").path))
        XCTAssertEqual(niko("uninstall").status, 0)
        XCTAssertEqual(scratch.read("home/.codex/hooks.json"), "{}")
    }

    func testDoctorAndDiagnosticsAreRedacted() throws {
        XCTAssertEqual(niko("install").status, 0)
        scratch.write("ni/logs/niko-island.log", "2026-01-01T00:00:00Z INFO token=sk-ant-api03-LEAKLEAKLEAKLEAK and ghp_abcdefghijklmnopqrstuvwxyz0123456789\n")
        var settings = NikoSettings.load(paths: scratch.paths)
        settings.deniedBundleIDs = ["com.example.secretapp"]
        settings.save(paths: scratch.paths)

        let doctor = niko("doctor")
        XCTAssertEqual(doctor.status, 0, doctor.stdout)
        XCTAssertTrue(doctor.stdout.contains("No problems found."))

        let out = scratch.file("diag.txt").path
        XCTAssertEqual(niko("diagnostics", "--out", out).status, 0)
        let text = try String(contentsOfFile: out, encoding: .utf8)
        XCTAssertTrue(text.contains("Niko Island diagnostics"))
        XCTAssertTrue(text.contains("Claude Code [stable]: hooks installed"))
        XCTAssertFalse(text.contains("LEAKLEAK"))
        XCTAssertFalse(text.contains("ghp_abcdefghijklmnopqrstuvwxyz0123456789"))
        XCTAssertFalse(text.contains("echo mine"), "config contents are never exported")
        XCTAssertFalse(text.contains("com.example.secretapp"))
        XCTAssertFalse(text.contains(home.path), "home directory is abbreviated")
        if let token = scratch.read("ni/run/ingress-token") { XCTAssertFalse(text.contains(token.trimmingCharacters(in: .newlines))) }
    }

    func testUsageCommandReadsLocalTranscripts() {
        let stamp = ISO8601DateFormatter().string(from: Date())
        scratch.write("home/.claude/projects/-demo/s.jsonl",
                      "{\"cwd\":\"/demo\",\"sessionId\":\"u1\",\"type\":\"assistant\",\"message\":{\"id\":\"msg_u\",\"model\":\"claude-opus-4-5-20251101\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":2000}},\"requestId\":\"r\",\"timestamp\":\"\(stamp)\"}\n")
        let usage = runProcess(cli, ["usage", "--home", home.path], environment: ["NIKO_ISLAND_HOME": scratch.paths.root.path])
        XCTAssertEqual(usage.status, 0, usage.stderr)
        XCTAssertTrue(usage.stdout.contains("Today        $0.06   3.0K tokens"), usage.stdout)
        XCTAssertTrue(usage.stdout.contains("Claude Code / claude-opus-4-5-20251101"))
        XCTAssertTrue(usage.stdout.contains("Last 7 days  $0.06"))
        XCTAssertTrue(usage.stdout.contains("estimates"))
    }

    func testListenPrintsEventNamesButNoValues() {
        let root = scratch.paths.root.path
        let bridge = bridgeBinaryPath
        let output = runProcess(cli, ["internal", "listen", "2"], environment: ["NIKO_ISLAND_HOME": root]) { _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                let event = "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s\",\"cwd\":\"/tmp\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo TOP-SECRET-VALUE\"}}"
                runProcess(bridge, ["--source", "claude"], stdin: Data(event.utf8), environment: ["NIKO_ISLAND_HOME": root])
            }
        }
        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(output.stdout.contains("PreToolUse\tsource=claude\ttool=Bash\tblocking=false"), output.stdout)
        XCTAssertTrue(output.stdout.contains("input_keys=command"))
        XCTAssertFalse(output.stdout.contains("TOP-SECRET-VALUE"))
        XCTAssertTrue(output.stdout.contains("received=1 admitted=1 dropped=0"))
    }

    func testPricingStatusNeedsNoNetwork() {
        let status = niko("pricing", "status")
        XCTAssertEqual(status.status, 0)
        XCTAssertTrue(status.stdout.contains("models (repository)"), status.stdout)
        XCTAssertTrue(status.stdout.contains("automatic weekly refresh: off"))
        XCTAssertEqual(niko("pricing", "bogus").status, 64)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.pricingCache.path))
    }

    func testDumpedScriptsParseInEveryShell() throws {
        let directory = scratch.file("scripts")
        XCTAssertEqual(niko("internal", "dump-scripts", directory.path).status, 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertGreaterThanOrEqual(names.count, 14)
        for name in names {
            let path = directory.appendingPathComponent(name).path
            let shells = name.hasSuffix(".bash") ? ["/bin/bash"] : ["/bin/sh", "/bin/dash", "/bin/bash"]
            for shell in shells { XCTAssertEqual(runProcess(shell, ["-n", path]).status, 0, "\(shell) \(name)") }
        }
    }
}
