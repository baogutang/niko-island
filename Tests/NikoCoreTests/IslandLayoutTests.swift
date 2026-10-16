import XCTest
@testable import NikoCore

final class IslandLayoutTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func usage(_ agents: [(String, [RateLimitWindow])]) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.agents = agents.map { id, limits in
            var agent = UsageSnapshot.AgentUsage(id: id)
            agent.limits = limits
            return agent
        }
        return snapshot
    }

    func testGlanceShowsTheShortAndLongWindowOfTheAgentLastUsed() throws {
        let snapshot = usage([
            ("codex", [RateLimitWindow(id: "primary", usedPercent: 12, resetsAt: now.addingTimeInterval(3_600), windowMinutes: 300)]),
            ("claude", [RateLimitWindow(id: "seven_day", usedPercent: 76.4, resetsAt: now.addingTimeInterval(86_400 + 600)),
                        RateLimitWindow(id: "five_hour", usedPercent: 31, resetsAt: now.addingTimeInterval(2 * 3_600 + 39 * 60))]),
        ])
        let glance = try XCTUnwrap(QuotaGlance.make(usage: snapshot, recentAgents: ["claude", "codex"], now: now))
        XCTAssertEqual(glance.agent, "claude")
        XCTAssertEqual(glance.entries.map(\.label), ["5h", "7d"])
        XCTAssertEqual(glance.entries.map(\.percent), [31, 76])
        XCTAssertEqual(glance.entries.map(\.resetsIn), ["2h39m", "1d"])
        XCTAssertEqual(glance.entries.map(\.level), [.calm, .warm])
        // An agent without limits is skipped for the next one that has them.
        XCTAssertEqual(QuotaGlance.make(usage: snapshot, recentAgents: ["gemini", "codex"], now: now)?.agent, "codex")
    }

    func testWindowsThatAlreadyResetAreNotShown() {
        let snapshot = usage([("claude", [RateLimitWindow(id: "five_hour", usedPercent: 95, resetsAt: now.addingTimeInterval(-1))])])
        XCTAssertNil(QuotaGlance.make(usage: snapshot, recentAgents: ["claude"], now: now))
        XCTAssertEqual(QuotaGlance.entry(RateLimitWindow(id: "x", usedPercent: 93), now: now).level, .hot)
        XCTAssertEqual(QuotaGlance.remaining(30), "1m")
        XCTAssertEqual(QuotaGlance.remaining(2 * 3_600), "2h")
        XCTAssertEqual(QuotaGlance.remaining(3 * 86_400 + 100), "3d")
    }

    private func session(_ id: String, phase: Session.Phase, quietFor seconds: TimeInterval) -> Session {
        Session(key: SessionKey(source: "claude", sessionID: id), cwd: "/tmp/\(id)", transcriptPath: nil, title: "t",
                startedAt: now, lastEventAt: now, phaseSince: now.addingTimeInterval(-seconds),
                activity: .waiting, phase: phase, terminal: TerminalContext(), ancestors: [], firstPrompt: nil)
    }

    func testOlderQuietSessionsSitOnOneLine() {
        let rows = [session("top", phase: .waiting, quietFor: 3_600), session("busy", phase: .working, quietFor: 3_600),
                    session("asks", phase: .needsAttention, quietFor: 3_600), session("fresh", phase: .waiting, quietFor: 60),
                    session("old", phase: .waiting, quietFor: 3_600), session("typing", phase: .waiting, quietFor: 3_600)]
        let full = RowTiers.full(rows, alwaysFull: [SessionKey(source: "claude", sessionID: "typing")], now: now)
        XCTAssertEqual(full.map(\.sessionID).sorted(), ["asks", "busy", "fresh", "top", "typing"])
    }
}
