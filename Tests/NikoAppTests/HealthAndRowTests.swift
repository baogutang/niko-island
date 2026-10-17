import AppKit
import XCTest
@testable import NikoCore
@testable import NikoIslandApp

/// The health card's findings, and the rows and header of the open island after the 0.15.2 review.
@MainActor
final class HealthAndRowTests: XCTestCase {
    private func model(_ scratch: Scratch) -> AppModel {
        try? FileManager.default.createDirectory(at: scratch.file("home"), withIntermediateDirectories: true)
        return AppModel(paths: scratch.paths, home: scratch.file("home"), log: .inMemory())
    }

    private func event(_ fields: [String: JSONValue], app: (program: String, bundle: String)? = nil) -> IngressDelivery? {
        var object = JSONObject()
        for key in fields.keys.sorted() { object[key] = fields[key] }
        if let app { object[AgentEvent.metaKey] = .object(["term_program": .string(app.program), "bundle_id": .string(app.bundle)]) }
        guard let event = try? AgentEvent(json: .object(object)) else { return nil }
        return IngressDelivery(event: event, evidence: AdmissionEvidence(channel: .unixSocket, peerUID: getuid()), replier: nil)
    }

    func testAnAgentsOwnAppIsDesktopNotItsNameAgain() throws {
        let scratch = Scratch()
        let model = model(scratch)
        // Hooks that run inside the Claude app and ZCode report the app as their terminal.
        for (source, id, app) in [("claude", "c", ("Claude", "com.anthropic.claudefordesktop")), ("zcode", "z", ("ZCode", "dev.zcode.app")),
                                  ("claude", "t", ("iTerm.app", "com.googlecode.iterm2"))] {
            model.handle(try XCTUnwrap(event(["source": .string(source), "hook_event_name": .string("UserPromptSubmit"),
                                              "session_id": .string(id), "cwd": .string("/tmp/demo")], app: app)))
        }
        let labels = Dictionary(uniqueKeysWithValues: model.sessions.map { ($0.key.sessionID, $0.hostLabel) })
        XCTAssertEqual(labels["c"], L("Desktop"), "not \"Claude\" next to \"Claude Code\"")
        XCTAssertEqual(labels["z"], L("Desktop"), "not \"ZCode\" next to \"ZCode\"")
        XCTAssertNotEqual(labels["t"], L("Desktop"), "a terminal is still named")
    }

    func testChipsGiveWayToTheHeadlineLeastTellingFirst() {
        let chips = [RowChip(id: "elapsed", text: "2m", keep: 100), RowChip(id: "agent", text: "Claude Code", keep: 60),
                     RowChip(id: "host", text: "Desktop", keep: 20), RowChip(id: "model", text: "opus-5-5", keep: 30),
                     RowChip(id: "cost", text: "$92.50", keep: 50), RowChip(id: "context", text: "context 459k", keep: 40)]
        XCTAssertEqual(RowChip.fit(chips, budget: 2000, scale: 1).map(\.id), chips.map(\.id), "with room, all stay")
        let fitted = RowChip.fit(chips, budget: 247, scale: 1)
        XCTAssertEqual(fitted.map(\.id), ["elapsed", "agent", "cost"], "host, then model, then context go; the order is kept")
        XCTAssertEqual(RowChip.fit(chips, budget: 10, scale: 1).map(\.id), ["elapsed"], "the most telling one stays")
    }

    func testTheHeaderReadsAnAgentListThatOnlyChangesWhenTheAgentsDo() throws {
        let scratch = Scratch()
        let model = model(scratch)
        for (source, id) in [("claude", "a"), ("codex", "b"), ("claude", "c")] {
            model.handle(try XCTUnwrap(event(["source": .string(source), "hook_event_name": .string("UserPromptSubmit"),
                                              "session_id": .string(id), "cwd": .string("/tmp/demo-" + id)])))
        }
        XCTAssertEqual(model.listedCount, 3)
        XCTAssertEqual(Set(model.listedAgents), ["claude", "codex"])
        let before = model.listedAgents
        // Another tool in a session at work: the list's agents are what they were (nothing to lay out again).
        model.handle(try XCTUnwrap(event(["source": .string("claude"), "hook_event_name": .string("PreToolUse"), "session_id": .string("a"),
                                          "cwd": .string("/tmp/demo-a"), "tool_name": .string("Bash")])))
        XCTAssertEqual(model.listedAgents, before)
        model.handle(try XCTUnwrap(event(["source": .string("codex"), "hook_event_name": .string("SessionEnd"), "session_id": .string("b")])))
        XCTAssertEqual(model.listedAgents, ["claude"])
        XCTAssertEqual(model.listedCount, 2)
    }

    func testAWatchFollowsWhatItReads() async throws {
        let scratch = Scratch()
        let model = model(scratch)
        var seen: [Bool] = []
        let watch = Watch({ model.wantsOnboarding }) { seen.append($0) }
        XCTAssertEqual(seen, [false], "told at once")
        model.wantsOnboarding = true
        for _ in 0..<50 where seen.count < 2 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(seen, [false, true])
        model.wantsOnboarding = true
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(seen, [false, true], "the same value again is not news")
        _ = watch
    }

    func testTheHealthCardSaysWhatIsWrongAndHowToFixIt() throws {
        let scratch = Scratch()
        let model = model(scratch)
        XCTAssertTrue(model.healthItems.isEmpty, "nothing found, nothing said")

        let vibe = try XCTUnwrap(ForeignHooks.known.first { $0.id == "vibe-island" })
        model.health.leftovers = [ForeignHooks.Finding(island: vibe, places: [.init(agent: "claude", file: ".claude/settings.json", hooks: 14),
                                                                              .init(agent: "codex", file: ".codex/hooks.json", hooks: 6)],
                                                       statusLine: true, installed: false)]
        model.maintenance.agents = [.init(id: "windsurf", name: "Windsurf", stability: .beta, wired: true, installed: false),
                                    .init(id: "claude", name: "Claude Code", stability: .stable, wired: true)]
        model.settings.glmLimitsLookup = true
        model.providerLookups = ["zcode": ProviderLimitsClient.Result(state: .noKey, checkedAt: Date())]
        var claude = UsageSnapshot.AgentUsage(id: "claude")
        claude.limits = [RateLimitWindow(id: "seven_day", usedPercent: 24)]
        claude.limitsCapturedAt = Date().addingTimeInterval(-15 * 3600)
        model.usage.agents = [UsageSnapshot.AgentUsage(id: "all"), claude]

        let items = model.healthItems
        XCTAssertEqual(items.map(\.id), ["island-vibe-island", "absent", "lookup-zcode", "claude-stale"])
        guard case .clean(let island)? = items[0].fix else { return XCTFail("leftovers are cleaned up") }
        XCTAssertEqual(island.id, "vibe-island")
        XCTAssertTrue(items[0].detail.contains("20"), "all of its hooks are counted: \(items[0].detail)")
        guard case .disconnect(let agents)? = items[1].fix else { return XCTFail("absent agents are disconnected") }
        XCTAssertEqual(agents, ["windsurf"])
        guard case .addKey? = items[2].fix else { return XCTFail("a missing key is added") }
        XCTAssertFalse(items[3].urgent, "a suggestion does not put a dot on the gear")

        // A suggestion the user takes is gone; a lookup switched off is no longer a problem.
        // (Switching it on asks Claude Code at once: a stand-in answers, the real one is never run.)
        model.claudeAsker = { _, _ in .unchanged }
        model.apply(.keepClaudeCurrent)
        model.apply(.turnOff("zcode"))
        XCTAssertFalse(model.settings.glmLimitsLookup)
        XCTAssertEqual(model.healthItems.map(\.id), ["island-vibe-island", "absent"])

        // An island whose app is still here is mentioned, not cleaned up.
        model.health.leftovers[0].installed = true
        XCTAssertNil(model.healthItems.first?.fix)
    }
}
