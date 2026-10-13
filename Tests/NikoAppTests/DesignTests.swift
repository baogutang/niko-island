import SwiftUI
import XCTest
@testable import NikoCore
@testable import NikoIslandApp

/// The pieces of the visual design that can be checked without looking at them.
@MainActor
final class DesignTests: XCTestCase {
    func testSpritesAreWellFormed() {
        XCTAssertEqual(Set(Mascots.all.map(\.name)).count, Mascots.all.count)
        for sprite in Mascots.all {
            XCTAssertEqual(sprite.frames.count, 2, sprite.name)
            XCTAssertEqual(sprite.frames[0].count, 12, sprite.name)
            for (index, frame) in sprite.frames.enumerated() {
                XCTAssertEqual(frame.count, sprite.rows, "\(sprite.name) frame \(index)")
                for row in frame {
                    XCTAssertEqual(row.count, 12, "\(sprite.name) frame \(index): \(row)")
                    for character in row where character != "." {
                        XCTAssertNotNil(sprite.palette[character], "\(sprite.name) uses “\(character)” without a colour")
                    }
                }
            }
            XCTAssertNotEqual(sprite.frames[0], sprite.frames[1], "\(sprite.name) should move")
            let filled = sprite.frames[0].joined().filter { $0 != "." }.count
            XCTAssertGreaterThan(filled, 30, "\(sprite.name) is more than a speck")
        }
    }

    func testEveryAgentHasACreatureAndATint() {
        for agent in AgentRegistry.installable {
            XCTAssertNotEqual(Mascots.sprite(for: agent.id).name, "island", "\(agent.id) falls back to the generic sprite")
        }
        XCTAssertEqual(Mascots.sprite(for: "something-unknown").name, "island")
        // The agents people are most likely to run side by side must be told apart at a glance.
        let common = ["claude", "codex", "cursor", "copilot", "gemini", "opencode"].map { Mascots.sprite(for: $0).name }
        XCTAssertEqual(Set(common).count, common.count)
        // Recoloured variants really differ from the creature they borrow.
        XCTAssertNotEqual(Mascots.sprite(for: "qwen").palette["a"], Mascots.sprite(for: "gemini").palette["a"])
        XCTAssertNotEqual(Mascots.sprite(for: "kiro").palette["a"], Mascots.sprite(for: "trae").palette["a"])
    }

    func testIslandShapeStaysInsideItsFrameAndFlaresAtTheTop() {
        let rect = CGRect(x: 0, y: 0, width: 640, height: 300)
        let path = IslandShape(ear: 10, radius: 30).path(in: rect)
        XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(path.boundingRect))
        XCTAssertEqual(path.boundingRect.width, 640, accuracy: 0.5, "full width at the screen edge")
        XCTAssertTrue(path.contains(CGPoint(x: 8, y: 1)), "at the very top the ear flares out towards the corner")
        XCTAssertFalse(path.contains(CGPoint(x: 8, y: 40)), "below the ear the body is inset")
        XCTAssertTrue(path.contains(CGPoint(x: 320, y: 150)))
        XCTAssertFalse(path.contains(CGPoint(x: 12, y: 298)), "bottom corners are rounded")
        // A tiny frame must not produce a degenerate path.
        let small = IslandShape(ear: 10, radius: 30).path(in: CGRect(x: 0, y: 0, width: 30, height: 12))
        XCTAssertFalse(small.boundingRect.isNull)
    }

    func testMetrics() {
        XCTAssertEqual(IslandMetrics.notched.collapsedWidth(contentWidth: 50), 186 + 2 * IslandMetrics.wing)
        XCTAssertEqual(IslandMetrics.plain.collapsedWidth(contentWidth: 20), 96)
        XCTAssertEqual(IslandMetrics.plain.collapsedWidth(contentWidth: 2000), 360)
        XCTAssertLessThan(IslandMetrics.expandedWidth, IslandMetrics.canvas.width)
        if let screen = NSScreen.screens.first {
            let metrics = IslandMetrics(screen: screen)
            XCTAssertGreaterThanOrEqual(metrics.bandHeight, 24)
            XCTAssertEqual(metrics.hasNotch, screen.safeAreaInsets.top > 0)
        }
    }

    func testAnswerRulesAndFormatting() {
        XCTAssertEqual(elapsedText(since: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 42)), "42s")
        XCTAssertEqual(elapsedText(since: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 125)), "2m")
        XCTAssertEqual(elapsedText(since: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 3 * 3600 + 300)), "3h 5m")
        XCTAssertEqual(tokenText(999), "999")
        XCTAssertEqual(tokenText(1_500), "1.5K")
        XCTAssertEqual(tokenText(7_700_000), "7.7M")
        XCTAssertEqual(costText(0.004), "<$0.01")
        XCTAssertEqual(costText(12.345), "$12.35")
        XCTAssertEqual(Set(SettingsPage.allCases.map(\.symbol)).count, SettingsPage.allCases.count)
    }
}
