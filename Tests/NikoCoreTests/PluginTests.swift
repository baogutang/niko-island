import XCTest
@testable import NikoCore

/// Runs the generated OpenCode-family plugin under Node against the real
/// loopback ingress. Skipped when Node is not installed.
final class OpenCodePluginTests: XCTestCase {
    private func nodePath() -> String? {
        let which = runProcess("/usr/bin/env", ["which", "node"])
        let path = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return which.status == 0 && !path.isEmpty ? path : nil
    }

    private let driver = """
    import { NikoIsland } from "./niko.mjs";
    const directory = process.argv[2];
    const calls = [];
    const client = { question: { reply: async (payload) => { calls.push(payload); } } };
    const hooks = await NikoIsland({ client, directory });
    await hooks.event({ event: { type: "session.created", properties: { info: { id: "oc-1" } } } });
    await hooks["chat.message"]({ sessionID: "oc-1" });
    await hooks["tool.execute.before"]({ tool: "bash", sessionID: "oc-1" }, { args: { command: "ls", big: "x".repeat(20000) } });
    await hooks["tool.execute.after"]({ tool: "bash", sessionID: "oc-1" });
    const output = { status: "ask" };
    await hooks["permission.ask"]({ id: "perm-1", type: "bash", sessionID: "oc-1", title: "Run ls", metadata: { command: "ls" } }, output);
    await hooks.event({ event: { type: "question.asked", properties: { id: "q-1", sessionID: "oc-1",
      questions: [{ question: "Pick", options: [{ label: "A" }, { label: "B" }], multiple: true }] } } });
    await hooks.event({ event: { type: "session.idle", properties: { sessionID: "oc-1" } } });
    await hooks.event({ event: { type: "something.unknown", properties: {} } });
    console.log(JSON.stringify({ status: output.status, replies: calls }));
    """

    private func runPlugin(node: String, scratch: Scratch, paths: NikoPaths) throws -> (output: ProcessOutput, json: JSONValue?) {
        let agent = try XCTUnwrap(AgentRegistry.descriptor("opencode"))
        scratch.write("plugin/niko.mjs", PluginTemplates.openCodePlugin(agent: agent, paths: paths))
        scratch.write("plugin/driver.mjs", driver)
        let output = runProcess(node, [scratch.file("plugin/driver.mjs").path, "/tmp"], timeout: 30)
        return (output, try? JSONValue.parse(output.stdout))
    }

    func testPluginTranslatesEventsAndDecisions() throws {
        let node = try XCTUnwrap(nodePath().map(Optional.some) ?? { throw XCTSkip("node not installed") }())
        let scratch = Scratch()
        let hub = IngressHub(log: .inMemory())
        let collector = Collector()
        hub.setHandler { delivery in
            collector.add(delivery)
            guard let replier = delivery.replier else { return }
            if delivery.event.toolName == "AskUserQuestion" {
                var input = delivery.event.toolInput ?? JSONObject()
                input["answers"] = .array([.array([.string("A"), .string("B")])])
                replier.send(decisionReply("approve", updatedInput: input))
            } else {
                replier.send(decisionReply("deny", reason: "not now"))
            }
        }
        let server = HTTPIngressServer(paths: scratch.paths, hub: hub, preferredPort: 0)
        try server.start()
        defer { server.stop() }

        let result = try runPlugin(node: node, scratch: scratch, paths: scratch.paths)
        XCTAssertEqual(result.output.status, 0, result.output.stderr)
        XCTAssertEqual(result.json?["status"]?.stringValue, "deny")
        XCTAssertEqual(result.json?["replies"]?[0]?["requestID"]?.stringValue, "q-1")
        XCTAssertEqual(result.json?["replies"]?[0]?["answers"], .array([.array([.string("A"), .string("B")])]))

        let events = collector.wait(count: 7).map(\.event)
        XCTAssertEqual(events.map(\.name), ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                            "PermissionRequest", "PermissionRequest", "Stop"])
        XCTAssertTrue(events.allSatisfy { $0.source == "opencode" && $0.sessionID == "oc-1" && $0.cwd == "/tmp" })
        XCTAssertEqual(events[2].toolName, "bash")
        XCTAssertLessThan(events[2].toolInput?["big"]?.stringValue?.count ?? .max, 5000, "status events are slimmed")
        XCTAssertEqual(events[4].toolInput?["_request_id"]?.stringValue, "perm-1")
        XCTAssertEqual(events[5].toolName, "AskUserQuestion")
        XCTAssertEqual(events[5].toolInput?["questions"]?[0]?["text"]?.stringValue, "Pick")
        XCTAssertEqual(events[5].toolInput?["questions"]?[0]?["options"], .array([.string("A"), .string("B")]))
        XCTAssertEqual(events[5].toolInput?["questions"]?[0]?["multiSelect"]?.boolValue, true)
        XCTAssertNotNil(events[0].terminal.pid)
    }

    func testPluginIsInertWhenTheAppIsNotRunning() throws {
        let node = try XCTUnwrap(nodePath().map(Optional.some) ?? { throw XCTSkip("node not installed") }())
        let scratch = Scratch()
        let result = try runPlugin(node: node, scratch: scratch, paths: scratch.paths)
        XCTAssertEqual(result.output.status, 0, result.output.stderr)
        XCTAssertEqual(result.json?["status"]?.stringValue, "ask", "the agent keeps its own prompt")
        XCTAssertEqual(result.json?["replies"], .array([]))
        XCTAssertLessThan(result.output.duration, 10)
    }

    func testPluginSurvivesAStaleTokenOrPort() throws {
        let node = try XCTUnwrap(nodePath().map(Optional.some) ?? { throw XCTSkip("node not installed") }())
        let scratch = Scratch()
        let hub = IngressHub(log: .inMemory())
        let server = HTTPIngressServer(paths: scratch.paths, hub: hub, preferredPort: 0)
        try server.start()
        defer { server.stop() }
        try Data("0000000000000000000000000000000000000000000000000000000000000000\n".utf8).write(to: scratch.paths.ingressToken)
        let result = try runPlugin(node: node, scratch: scratch, paths: scratch.paths)
        XCTAssertEqual(result.output.status, 0, result.output.stderr)
        XCTAssertEqual(result.json?["status"]?.stringValue, "ask")
        XCTAssertEqual(hub.counters.received, 0)
    }
}

final class HookMergeTests: XCTestCase {
    func testStripLeavesForeignStructureAlone() throws {
        let root = try XCTUnwrap(JSONValue.parse("""
        {"hooks":{"A":[],"B":[{"hooks":[]}],"C":[{"matcher":"x","hooks":[{"type":"command","command":"theirs"}]}],"D":"str","E":[42]},"other":1}
        """).objectValue)
        let stripped = HookMerge.strip(root)
        XCTAssertEqual(stripped.removed, 0)
        XCTAssertEqual(stripped.root, root)
        XCTAssertFalse(HookMerge.containsOurs(root))
    }

    func testInstallThenStripIsIdentityForOrdinaryConfigs() throws {
        let root = try XCTUnwrap(JSONValue.parse(claudeFixture).objectValue)
        let installed = try HookMerge.install(into: root, specs: AgentRegistry.claudeEvents) { _ in "run niko-bridge" }
        XCTAssertNotEqual(installed, root)
        XCTAssertEqual(HookMerge.strip(installed).removed, AgentRegistry.claudeEvents.count)
        XCTAssertEqual(HookMerge.strip(installed).root, root)
        XCTAssertEqual(try HookMerge.install(into: installed, specs: AgentRegistry.claudeEvents) { _ in "run niko-bridge" }, installed,
                       "installing twice does not duplicate")
    }

    func testStatusLineInstallAndRemoveShapes() throws {
        let command = "run niko-statusline"
        guard case .installed(let fresh, let none) = HookMerge.installStatusLine(into: JSONObject(), command: command) else { return XCTFail() }
        XCTAssertEqual(none, .null)
        XCTAssertEqual(HookMerge.removeStatusLine(from: fresh, restoring: .null), JSONObject())

        let foreign = JSONObject(["statusLine": .object(["type": .string("command"), "command": .string("mine"), "padding": .int(2)])])
        guard case .installed(let wrapped, let displaced) = HookMerge.installStatusLine(into: foreign, command: command) else { return XCTFail() }
        XCTAssertEqual(displaced, foreign["statusLine"])
        XCTAssertEqual(wrapped["statusLine"]?["padding"]?.intValue, 2)
        XCTAssertEqual(HookMerge.removeStatusLine(from: wrapped, restoring: displaced), foreign)
        guard case .installed(_, let again) = HookMerge.installStatusLine(into: wrapped, command: command) else { return XCTFail() }
        XCTAssertNil(again, "already ours: nothing new is displaced")

        XCTAssertEqual(HookMerge.installStatusLine(into: JSONObject(["statusLine": .string("weird")]), command: command),
                       .skipped("statusLine is not an object"))
        XCTAssertEqual(HookMerge.removeStatusLine(from: foreign, restoring: .null), foreign, "a foreign status line is never removed")
    }

    func testSupportFilesStayInSync() throws {
        // TestSupport.swift is duplicated across the two test targets; keep the copies identical.
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let other = here.deletingLastPathComponent().appendingPathComponent("NikoAppTests/TestSupport.swift")
        XCTAssertEqual(try String(contentsOf: here.appendingPathComponent("TestSupport.swift"), encoding: .utf8),
                       try String(contentsOf: other, encoding: .utf8))
    }
}
