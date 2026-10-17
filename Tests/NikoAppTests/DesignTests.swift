import SwiftUI
import XCTest
@testable import NikoCore
@testable import NikoIslandApp

/// The pieces of the visual design that can be checked without looking at them.
@MainActor
final class DesignTests: XCTestCase {
    func testPetsAreWellFormed() {
        XCTAssertEqual(Set(PixelPets.all.map(\.name)).count, PixelPets.all.count)
        for pet in PixelPets.all {
            let width = pet.columns
            XCTAssertGreaterThan(width, 0, pet.name)
            XCTAssertLessThanOrEqual(max(width, pet.rows.count), 18, "\(pet.name) stays small enough to read as pixels")
            for (name, rows) in [("base", pet.rows)] + pet.poses.map({ ($0.key, $0.value) }) {
                for row in rows {
                    XCTAssertEqual(row.count, width, "\(pet.name) \(name): \(row)")
                    for character in row where character != "." {
                        XCTAssertNotNil(pet.palette[character], "\(pet.name) uses “\(character)” without a colour")
                    }
                }
                XCTAssertEqual(rows.count, pet.rows.count, "\(pet.name): every pose has the same size")
            }
            if let eye = pet.eye { XCTAssertTrue(pet.rows.joined().contains(eye), "\(pet.name) has eyes to close") }
            XCTAssertGreaterThan(pet.rows.joined().filter { $0 != "." }.count, 20, "\(pet.name) is more than a speck")
        }
    }

    /// Clawd is drawn from Claude Code's own glyphs: nine cells by three, each cell two pixels by four.
    func testClawdIsBuiltFromClaudeCodesGlyphs() {
        let clawd = PixelPets.Clawd.pet
        XCTAssertEqual(clawd.palette["a"], PixelPets.Clawd.body)
        XCTAssertEqual(clawd.columns, 17)
        XCTAssertEqual(clawd.rows.count, 10, "three terminal rows, the feet using the top of theirs")
        XCTAssertEqual(clawd.rows.filter { $0.contains("e") }.count, 2, "open eyes are two pixels tall")
        XCTAssertEqual(clawd.poses["closed"]?.filter { $0.contains("e") }.count, 1, "shut, a line")
        XCTAssertNotEqual(clawd.poses["walk-left"], clawd.poses["walk-right"], "the feet move as he walks")
        XCTAssertNotEqual(clawd.poses["arms-up"], clawd.rows)
        XCTAssertEqual(PixelPets.Clawd.quarters("▛").3, false, "the eye is the quarter ▛ leaves out")
    }

    /// 0.14 and 0.15 lost the island off the top of the screen: an open page taller than
    /// its window made SwiftUI grow the window upwards. The window's size is ours alone.
    func testTheIslandNeverResizesItsWindow() {
        let model = AppModel(paths: NikoPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ni-design-\(UUID())")))
        let host = IslandWindowController.host(IslandView(model: model, metrics: .plain))
        XCTAssertEqual(host.sizingOptions, [], "the hosting view must not size the island's window")
        XCTAssertLessThan(IslandMetrics.contentLimit + 100, IslandMetrics.canvas.height, "a page fits with the header and margins")
    }

    /// Lays the island out in a window of the canvas's size and reports the island's frame on each pass.
    private func islandFrames(_ model: AppModel, then change: (() -> Void)? = nil) -> (settled: CGRect, afterChange: [CGRect]) {
        _ = NSApplication.shared
        var frames: [CGRect] = []
        let host = IslandWindowController.host(IslandView(model: model, metrics: .plain) { frames.append($0) })
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: IslandMetrics.canvas), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func settle() {
            for _ in 0..<12 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        settle()
        let settled = frames.last ?? .zero
        guard let change else { return (settled, []) }
        frames = []
        change()
        settle()
        return (settled, frames)
    }

    private func addSessions(_ model: AppModel, count: Int) {
        for index in 0..<count {
            let object: JSONObject = ["source": .string("claude"), "hook_event_name": .string("UserPromptSubmit"),
                                      "session_id": .string("more-\(index)"), "cwd": .string("/Users/dev/code/project-\(index)"),
                                      "prompt": .string("Task number \(index)")]
            guard let event = try? AgentEvent(json: .object(object)) else { continue }
            model.handle(IngressDelivery(event: event, evidence: AdmissionEvidence(channel: .unixSocket, peerUID: getuid()), replier: nil))
        }
    }

    func testTheOpenIslandStaysInsideItsWindow() {
        // A long list with the most rows, and a request on top of one: both used to run past the
        // window's bottom (0.14 and 0.15.0 grew the window upwards, 0.15.1 cut the island off).
        for scene in [PreviewRenderer.Scene.sessions, .permission, .question] {
            let model = PreviewRenderer.demoModel(scene)
            model.settings.visibleRows = NikoSettings.visibleRowChoices.max() ?? 12
            addSessions(model, count: 14)
            model.expand(.click)
            let island = islandFrames(model).settled
            XCTAssertGreaterThan(island.height, 300, "\(scene): the island was laid out")
            XCTAssertLessThanOrEqual(island.maxY, IslandMetrics.canvas.height - 40, "\(scene): the island ends inside its window, with room for its shadow")
        }
    }

    func testUsageOpensAtItsOwnHeight() {
        let model = PreviewRenderer.demoModel(.sessions)
        let frames = islandFrames(model) { model.route = .usage }.afterChange
        XCTAssertFalse(frames.isEmpty)
        // Measured after the fact, its first frame was the whole window's height.
        XCTAssertTrue(frames.allSatisfy { $0.maxY <= IslandMetrics.canvas.height - 40 }, "\(frames.map { Int($0.maxY) })")
    }

    func testAMoodLoopIsOneStripOfFramesSideBySide() throws {
        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return bytes
        }
        for (agent, mood) in [("claude", CreatureMood.working), ("kiro", .attention), ("codex", .happy)] {
            let strip = try XCTUnwrap(CreatureFrames.strip(Mascots.sprite(for: agent), mood: mood, points: 17, scale: 2))
            XCTAssertGreaterThan(strip.count, 2, "\(agent) \(mood)")
            XCTAssertEqual(strip.image.height, 34, "one row")
            XCTAssertEqual(strip.image.width, strip.count * 34, "frames side by side")
            XCTAssertEqual(strip.rect(strip.count - 1).maxX, 1, accuracy: 0.0001)
            let frames = (0..<strip.count).compactMap { strip.image.cropping(to: CGRect(x: $0 * 34, y: 0, width: 34, height: 34)) }.map(pixels)
            XCTAssertEqual(frames.count, strip.count)
            for (index, frame) in frames.enumerated() {
                XCTAssertTrue(stride(from: 3, to: frame.count, by: 4).contains { frame[$0] > 0 }, "\(agent) \(mood): frame \(index) is drawn")
            }
            XCTAssertGreaterThan(Set(frames).count, 1, "\(agent) \(mood): the creature moves")
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
        // Every agent's pet is its own: no two agents of different vendors share one.
        let vendors = ["claude", "codex", "kiro", "cursor", "zcode", "gemini", "copilot", "qwen", "trae", "windsurf", "opencode",
                       "grok", "factory", "devin", "amp", "kimi", "minimax", "qoder", "codebuddy", "mimocode"]
        XCTAssertEqual(Set(vendors.map { Mascots.sprite(for: $0).name }).count, vendors.count)
        XCTAssertEqual(Mascots.sprite(for: "claude").name, "clawd")
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

    func testAPullGivesLessTheFurtherItGoesAndNeverPastItsLimit() {
        XCTAssertEqual(Rubber.band(0, limit: 22), 0)
        var previous: CGFloat = 0
        for distance in stride(from: CGFloat(4), through: 400, by: 4) {
            let stretched = Rubber.band(distance, limit: 22)
            XCTAssertGreaterThan(stretched, previous, "it keeps following the finger")
            XCTAssertLessThan(stretched, 22, "but never past the limit")
            XCTAssertLessThan(stretched - previous, 4 * 0.55 + 0.001, "and gives less with every point")
            previous = stretched
        }
    }

    func testTheIslandsCornersAreContinuousAndItsEarsMeetTheSidesSmoothly() {
        let rect = CGRect(x: 0, y: 0, width: 640, height: 300)
        let path = IslandShape(ear: 10, radius: 30).path(in: rect)
        // A continuous corner starts further up the side than a circular one would (1.53 radii, not 1).
        XCTAssertTrue(path.contains(CGPoint(x: 10.5, y: 300 - 31)), "straight side above the corner")
        XCTAssertFalse(path.contains(CGPoint(x: 11, y: 296)), "rounded away at the bottom")
        XCTAssertTrue(path.contains(CGPoint(x: 40, y: 299)), "and flat along the bottom")
        // The closed island is short: the corners shrink to fit under the ears instead of overlapping them.
        let closed = IslandShape(ear: 8, radius: 14).path(in: CGRect(x: 0, y: 0, width: 200, height: 28))
        XCTAssertEqual(closed.boundingRect.height, 28, accuracy: 0.01)
        XCTAssertTrue(closed.contains(CGPoint(x: 100, y: 27)))
        XCTAssertFalse(closed.contains(CGPoint(x: 8.5, y: 27.5)))
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
