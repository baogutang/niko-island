import XCTest
@testable import NikoCore

final class ShimTests: XCTestCase {
    var scratch: Scratch!
    var paths: NikoPaths { scratch.paths }
    var fakeHome: URL { scratch.file("home") }

    override func setUpWithError() throws {
        scratch = Scratch()
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
    }

    override func tearDown() { scratch = nil }

    /// A stand-in "bridge" that records its arguments and stdin, then exits with `status`.
    private func fakeBridge(named name: String = "fake-bridge", status: Int32 = 0) throws -> String {
        let record = scratch.file("\(name).record").path
        let script = "#!/bin/sh\nprintf '%s|' \"$@\" > \(ShellQuote.single(record))\ncat >> \(ShellQuote.single(record))\necho out\nexit \(status)\n"
        let url = scratch.write("bin/\(name)", script)
        chmod(url.path, 0o755)
        return url.path
    }

    /// PATH with a stub `mdfind` that logs each call and prints `result`.
    private func stubPath(mdfindResult: String) throws -> String {
        let dir = scratch.file("stubs")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = scratch.file("mdfind.calls").path
        let script = "#!/bin/sh\necho called >> \(ShellQuote.single(log))\nprintf '%s' \(ShellQuote.single(mdfindResult))\n"
        let url = dir.appendingPathComponent("mdfind")
        try Data(script.utf8).write(to: url)
        chmod(url.path, 0o755)
        return dir.path + ":/usr/bin:/bin"
    }

    private var mdfindCalls: Int {
        (scratch.read("mdfind.calls") ?? "").split(separator: "\n").count
    }

    private func runShim(stdin: String = "payload", args: [String] = ["--source", "claude"],
                         env: [String: String]) -> ProcessOutput {
        var environment = ["HOME": fakeHome.path]
        for (key, value) in env { environment[key] = value }
        return runProcess("/bin/sh", [paths.bridgeShim.path] + args, stdin: Data(stdin.utf8),
                          environment: environment, inheritEnvironment: false)
    }

    private var installedAppPresent: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Niko Island.app/Contents/Helpers/niko-bridge")
    }

    func testGeneratedScriptsAreSyntacticallyValid() throws {
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: "/tmp/x y/niko-island")
        XCTAssertEqual(runProcess("/bin/sh", ["-n", paths.bridgeShim.path]).status, 0)
        XCTAssertEqual(runProcess("/bin/dash", ["-n", paths.bridgeShim.path]).status, 0)
        XCTAssertEqual(runProcess("/bin/bash", ["-n", paths.statuslineScript.path]).status, 0)
        XCTAssertEqual(runProcess("/bin/sh", ["-n", paths.bin.appendingPathComponent("niko-island").path]).status, 0)
        XCTAssertEqual(mode(of: paths.bridgeShim), 0o755)
        XCTAssertEqual(mode(of: paths.statuslineScript), 0o755)
        let defaults = NikoPaths(root: URL(fileURLWithPath: "/Users/x/.niko-island"), isDefaultLocation: true)
        XCTAssertTrue(Shims.bridgeShim(paths: defaults).contains("dir=\"$HOME/.niko-island/bin\""))
    }

    func testOverrideVariablePassesStdinArgumentsAndOutput() throws {
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil)
        let fake = try fakeBridge()
        let output = runShim(stdin: "{\"a\":1}", args: ["--source", "claude", "--x"], env: ["NIKO_BRIDGE_BIN": fake])
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "out\n")
        XCTAssertEqual(scratch.read("fake-bridge.record"), "--source|claude|--x|{\"a\":1}")
    }

    func testOnlyDenyStatusIsPassedThrough() throws {
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil)
        for (status, expected) in [(Int32(0), Int32(0)), (2, 2), (1, 0), (3, 0), (126, 0), (139, 0), (255, 0)] {
            let fake = try fakeBridge(named: "fake-\(status)", status: status)
            XCTAssertEqual(runShim(env: ["NIKO_BRIDGE_BIN": fake]).status, expected, "bridge exit \(status)")
        }
    }

    func testCorruptBinaryIsSilentSuccess() throws {
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil)
        let broken = scratch.write("bin/broken", "\u{7f}ELF definitely not a mach-o")
        chmod(broken.path, 0o755)
        let output = runShim(env: ["NIKO_BRIDGE_BIN": broken.path])
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "")
    }

    func testCacheFileIsUsedBeforeSpotlight() throws {
        try XCTSkipIf(installedAppPresent, "a real install would win over the cache")
        let fake = try fakeBridge()
        try Shims.install(paths: paths, bridgeBinary: fake, appExecutable: nil)
        let output = runShim(env: ["PATH": try stubPath(mdfindResult: "")])
        XCTAssertEqual(output.stdout, "out\n")
        XCTAssertEqual(mdfindCalls, 0)
    }

    func testMissingAppExitsZeroAndRemembersTheMiss() throws {
        try XCTSkipIf(installedAppPresent, "a real install is present")
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil)
        let path = try stubPath(mdfindResult: "")
        let first = runShim(env: ["PATH": path])
        XCTAssertEqual(first.status, 0)
        XCTAssertEqual(first.stdout + first.stderr, "")
        XCTAssertEqual(mdfindCalls, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.bridgeMiss.path))
        XCTAssertEqual(runShim(env: ["PATH": path]).status, 0)
        XCTAssertEqual(mdfindCalls, 1, "no second Spotlight query within the hour")
    }

    func testStaleCacheFallsBackToSpotlightAndRefreshesCache() throws {
        try XCTSkipIf(installedAppPresent, "a real install is present")
        try Shims.install(paths: paths, bridgeBinary: "/nonexistent/niko-bridge", appExecutable: nil)
        let app = scratch.file("Found/Niko Island.app")
        let helper = app.appendingPathComponent("Contents/Helpers/niko-bridge")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: try fakeBridge(), toPath: helper.path)
        let output = runShim(env: ["PATH": try stubPath(mdfindResult: app.path + "\n/somewhere/else.app\n")])
        XCTAssertEqual(output.stdout, "out\n")
        XCTAssertEqual(mdfindCalls, 1)
        XCTAssertEqual(scratch.read("ni/bin/.bridge-cache"), helper.path + "\n")
    }

    func testShimWorksWhenRuntimeDirectoryIsGone() throws {
        try XCTSkipIf(installedAppPresent, "a real install is present")
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil)
        let orphan = scratch.file("orphan-shim")
        try FileManager.default.copyItem(at: paths.bridgeShim, to: orphan)
        try FileManager.default.removeItem(at: paths.root)
        let output = runProcess("/bin/sh", [orphan.path, "--source", "claude"], stdin: Data("x".utf8),
                                environment: ["HOME": fakeHome.path, "PATH": try stubPath(mdfindResult: "")], inheritEnvironment: false)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout + output.stderr, "")
    }

    func testStatuslinePrintsUserSectionAndCachesRateLimits() throws {
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil,
                          statuslineUserSection: "printf 'model=%s' \"$(printf '%s' \"$input\" | sed 's/.*display_name\":\"\\([^\"]*\\)\".*/\\1/')\"")
        let payload = "{\"model\":{\"display_name\":\"Opus\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":9}}}"
        let output = runProcess("/bin/bash", [paths.statuslineScript.path], stdin: Data(payload.utf8),
                                environment: ["HOME": fakeHome.path, "NIKO_BRIDGE_BIN": bridgeBinaryPath,
                                              "NIKO_ISLAND_HOME": paths.root.path], inheritEnvironment: false)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, "model=Opus")
        XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: self.paths.rateLimitCache.path) }, "cache written in the background")
        let cache = try JSONValue.parse(Data(contentsOf: paths.rateLimitCache))
        XCTAssertEqual(cache.at("rate_limits", "five_hour", "used_percentage")?.intValue, 9)
    }

    func testStatuslineUserSectionSurvivesReinstall() throws {
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil)
        var script = try String(contentsOf: paths.statuslineScript, encoding: .utf8)
        XCTAssertEqual(Shims.extractUserSection(from: script), Shims.defaultUserSection)
        let custom = "echo \"my $line\"\n# with 'quotes' and \\backslashes\necho second"
        script = script.replacingOccurrences(of: Shims.defaultUserSection, with: custom)
        try Data(script.utf8).write(to: paths.statuslineScript)

        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil, statuslineUserSection: "echo SHOULD-NOT-WIN")
        let rewritten = try String(contentsOf: paths.statuslineScript, encoding: .utf8)
        XCTAssertEqual(Shims.extractUserSection(from: rewritten), custom)
        XCTAssertFalse(rewritten.contains("SHOULD-NOT-WIN"))
        XCTAssertEqual(runProcess("/bin/bash", ["-n", paths.statuslineScript.path]).status, 0)
    }

    func testStatuslineChainsPreviousCommandWithStdin() throws {
        let section = Shims.chainedUserSection(originalCommand: "tr a-z A-Z")
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil, statuslineUserSection: section)
        let output = runProcess("/bin/bash", [paths.statuslineScript.path], stdin: Data("hello".utf8),
                                environment: ["HOME": fakeHome.path, "NIKO_BRIDGE_BIN": "/nonexistent"], inheritEnvironment: false)
        XCTAssertEqual(output.stdout, "HELLO")
        XCTAssertEqual(output.status, 0)
    }

    func testStatuslineWorksWithoutTheApp() throws {
        try XCTSkipIf(installedAppPresent, "a real install is present")
        try Shims.install(paths: paths, bridgeBinary: nil, appExecutable: nil, statuslineUserSection: "echo still-here")
        let output = runProcess("/bin/bash", [paths.statuslineScript.path], stdin: Data("{}".utf8),
                                environment: ["HOME": fakeHome.path, "PATH": try stubPath(mdfindResult: "")], inheritEnvironment: false)
        XCTAssertEqual(output.stdout, "still-here\n")
        XCTAssertEqual(output.status, 0)
    }

    func testRemoveDeletesOnlyOurFiles() throws {
        try Shims.install(paths: paths, bridgeBinary: "/x", appExecutable: "/y")
        scratch.write("ni/bin/users-own-tool", "#!/bin/sh\n")
        Shims.remove(paths: paths)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.bin.path), ["users-own-tool"])
    }
}

/// The complete loop of BUILD-PLAN M2: fake agent → hook command → shim →
/// bridge → socket → decision → bridge stdout → fake agent.
final class HookCommandEndToEndTests: XCTestCase {
    private func runHook(_ command: String, stdin: String, island: TestIsland, extra: [String: String] = [:]) -> ProcessOutput {
        var env = ["HOME": island.scratch.file("home").path, "NIKO_BRIDGE_BIN": bridgeBinaryPath,
                   "NIKO_ISLAND_HOME": island.paths.root.path]
        for (key, value) in extra { env[key] = value }
        // Exactly how an agent runs a hook: the configured string goes to a shell.
        return runProcess("/bin/sh", ["-c", command], stdin: Data(stdin.utf8), environment: env, inheritEnvironment: false)
    }

    func testFakeAgentGetsDecisionThroughTheWholeChain() throws {
        let island = try TestIsland { event in
            event.toolName == "Bash" ? decisionReply("deny", reason: "no shell today") : decisionReply("approve")
        }
        try Shims.install(paths: island.paths, bridgeBinary: nil, appExecutable: nil)
        let command = Shims.hookCommand(paths: island.paths, source: "claude")
        XCTAssertTrue(command.contains(NikoVersion.hookMarker), "installer marker must be in the command")
        XCTAssertTrue(command.hasSuffix("; exit 0'"))

        let request = { (tool: String) in
            "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"e2e\",\"cwd\":\"/tmp\",\"tool_name\":\"\(tool)\",\"tool_input\":{}}"
        }
        let denied = runHook(command, stdin: request("Bash"), island: island)
        XCTAssertEqual(denied.status, 0)
        XCTAssertEqual(try JSONValue.parse(denied.stdout).at("hookSpecificOutput", "decision", "message")?.stringValue, "no shell today")
        let allowed = runHook(command, stdin: request("Edit"), island: island)
        XCTAssertEqual(try JSONValue.parse(allowed.stdout).at("hookSpecificOutput", "decision", "behavior")?.stringValue, "allow")

        let plain = runHook(command, stdin: "{\"hook_event_name\":\"Stop\",\"session_id\":\"e2e\",\"cwd\":\"/tmp\"}", island: island)
        XCTAssertEqual(plain.status, 0)
        XCTAssertEqual(plain.stdout, "")
        XCTAssertEqual(island.collector.wait(count: 3).map(\.event.name), ["PermissionRequest", "PermissionRequest", "Stop"])
    }

    func testHookIsNoOpAfterShimsAreDeleted() throws {
        let island = try TestIsland()
        try Shims.install(paths: island.paths, bridgeBinary: nil, appExecutable: nil)
        let command = Shims.hookCommand(paths: island.paths, source: "claude")
        Shims.remove(paths: island.paths)
        let output = runHook(command, stdin: "{\"hook_event_name\":\"Stop\",\"session_id\":\"x\"}", island: island)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout + output.stderr, "")
        try FileManager.default.removeItem(at: island.paths.root)
        XCTAssertEqual(runHook(command, stdin: "{}", island: island).status, 0, "even with ~/.niko-island gone")
    }

    func testExitCodeWrapperPropagatesOnlyDeny() throws {
        let island = try TestIsland { _ in decisionReply("deny", reason: "stop") }
        try Shims.install(paths: island.paths, bridgeBinary: nil, appExecutable: nil)
        let command = Shims.hookCommand(paths: island.paths, source: "generic", extraArguments: ["--blocking", "--reply", "exit-code"], propagateDeny: true)
        let output = runHook(command, stdin: "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"x\",\"cwd\":\"/tmp\"}", island: island)
        XCTAssertEqual(output.status, 2)
        XCTAssertEqual(output.stderr, "stop\n")
        Shims.remove(paths: island.paths)
        XCTAssertEqual(runHook(command, stdin: "{}", island: island).status, 0)
    }

    func testHookCommandSurvivesAwkwardInstallPath() throws {
        let scratch = Scratch()
        let odd = NikoPaths(root: scratch.file("it's a \"path\" $HOME/ni"))
        try FileManager.default.createDirectory(at: odd.root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Shims.install(paths: odd, bridgeBinary: nil, appExecutable: nil)
        let record = scratch.file("ran").path
        let fake = scratch.write("fake", "#!/bin/sh\ncat > \(ShellQuote.single(record))\n")
        chmod(fake.path, 0o755)
        let output = runProcess("/bin/sh", ["-c", Shims.hookCommand(paths: odd, source: "claude")], stdin: Data("hi".utf8),
                                environment: ["HOME": scratch.url.path, "NIKO_BRIDGE_BIN": fake.path], inheritEnvironment: false)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stderr, "")
        XCTAssertEqual(scratch.read("ran"), "hi")
    }
}
