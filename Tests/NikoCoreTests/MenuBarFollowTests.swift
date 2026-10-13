import XCTest
@testable import NikoCore

/// The numbers here are what the window server reported on a 2560×1440
/// display while the menu bar was revealed and hidden inside a full-screen
/// Space (macOS 15): the bar's window slides from y = -68 to 0 in about ten
/// frames and is off screen while hidden.
final class MenuBarFollowTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    private func bar(y: CGFloat, on display: CGRect? = nil, height: CGFloat = 24) -> MenuBarProbe.Window {
        let display = display ?? self.display
        return .init(layer: MenuBarProbe.menuBarLayer, bounds: CGRect(x: display.minX, y: display.minY + y, width: display.width, height: height))
    }

    func testFindsTheMenuBarAtRestAndWhileItSlides() {
        XCTAssertEqual(MenuBarProbe.offset(onScreen: [bar(y: 0)], display: display), 0)
        for y in [-68, -56, -46, -41, -37, -23, -17, -12, -5] as [CGFloat] {
            XCTAssertEqual(MenuBarProbe.offset(onScreen: [bar(y: y)], display: display), y)
        }
        XCTAssertNil(MenuBarProbe.offset(onScreen: [], display: display), "hidden: its window is not on screen")
    }

    func testIgnoresEverythingThatIsNotThisDisplaysMenuBar() {
        let statusItem = MenuBarProbe.Window(layer: 25, bounds: CGRect(x: 0, y: 0, width: 2560, height: 24))
        let extra = MenuBarProbe.Window(layer: 24, bounds: CGRect(x: 1700, y: 0, width: 300, height: 24))
        let curtain = MenuBarProbe.Window(layer: 24, bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        XCTAssertNil(MenuBarProbe.offset(onScreen: [statusItem, extra, curtain], display: display))

        let second = CGRect(x: 2560, y: 180, width: 1920, height: 1080)
        XCTAssertNil(MenuBarProbe.offset(onScreen: [bar(y: 0)], display: second), "the other display's bar is not ours")
        XCTAssertEqual(MenuBarProbe.offset(onScreen: [bar(y: 0), bar(y: -30, on: second)], display: second), -30)
        // A notched display has a taller bar.
        XCTAssertEqual(MenuBarProbe.offset(onScreen: [bar(y: 0, height: 37)], display: display), 0)
        // Two Spaces mid-transition: the one that shows more wins.
        XCTAssertEqual(MenuBarProbe.offset(onScreen: [bar(y: -40), bar(y: 0)], display: display), 0)
    }

    private func place(desktop: Bool, bar: CGFloat?, trusted: Bool = true, missing: TimeInterval = 0, pinned: Bool = false,
                       policy: FullScreenPolicy = .followMenuBar, current: CGFloat = 0) -> IslandPlacement {
        IslandFollow.placement(.init(onDesktopSpace: desktop, barOffset: bar, barTrusted: trusted, barMissingFor: missing,
                                     pinned: pinned, policy: policy, hideDistance: 46, currentDesktopLift: current))
    }

    func testOnADesktopTheIslandRestsUnlessTheMenuBarHides() {
        XCTAssertEqual(place(desktop: true, bar: 0), .init(surface: .desktop, lift: 0))
        // An auto-hiding menu bar takes the island with it, step for step.
        XCTAssertEqual(place(desktop: true, bar: -17), .init(surface: .desktop, lift: 17))
        XCTAssertEqual(place(desktop: true, bar: -68), .init(surface: .desktop, lift: 46), "never further than out of sight")
        // Gone without sliding: a Space change is under way. Nothing moves until that is certain.
        XCTAssertEqual(place(desktop: true, bar: nil, missing: 0.1), .init(surface: .desktop, lift: 0))
        XCTAssertEqual(place(desktop: true, bar: nil, missing: 0.1, current: 46), .init(surface: .desktop, lift: 46))
        XCTAssertEqual(place(desktop: true, bar: nil, missing: IslandFollow.missingGrace + 0.01), .init(surface: .desktop, lift: 46))
    }

    func testOnADesktopItNeverHidesOnAGuess() {
        // The probe has never recognised a menu bar: do not trust "missing".
        XCTAssertEqual(place(desktop: true, bar: nil, trusted: false, missing: 10), .init(surface: .desktop, lift: 0))
        // Open or under the pointer.
        XCTAssertEqual(place(desktop: true, bar: nil, missing: 10, pinned: true), .init(surface: .desktop, lift: 0))
        // The user asked for it to stay.
        XCTAssertEqual(place(desktop: true, bar: nil, missing: 10, policy: .always), .init(surface: .desktop, lift: 0))
        XCTAssertEqual(place(desktop: true, bar: -30, policy: .never), .init(surface: .desktop, lift: 0))
    }

    func testInFullScreenItComesAndGoesWithTheMenuBar() {
        XCTAssertEqual(place(desktop: false, bar: nil), .init(surface: .hidden, lift: 46))
        // The first frames of the reveal are still above the island's own height.
        XCTAssertEqual(place(desktop: false, bar: -68), .init(surface: .hidden, lift: 46))
        XCTAssertEqual(place(desktop: false, bar: -42), .init(surface: .overlay, lift: 42))
        XCTAssertEqual(place(desktop: false, bar: -5), .init(surface: .overlay, lift: 5))
        XCTAssertEqual(place(desktop: false, bar: 0), .init(surface: .overlay, lift: 0))
    }

    func testFullScreenPoliciesAndPinning() {
        XCTAssertEqual(place(desktop: false, bar: nil, policy: .always), .init(surface: .overlay, lift: 0))
        XCTAssertEqual(place(desktop: false, bar: 0, policy: .never), .init(surface: .hidden, lift: 46))
        // An open island, or a request that needs a decision, stays put while the bar leaves.
        XCTAssertEqual(place(desktop: false, bar: nil, pinned: true), .init(surface: .overlay, lift: 0))
        XCTAssertEqual(place(desktop: false, bar: -60, pinned: true), .init(surface: .overlay, lift: 0))
        XCTAssertEqual(place(desktop: false, bar: nil, pinned: true, policy: .never), .init(surface: .overlay, lift: 0))
    }

    func testSettingsDefaultToFollowingTheMenuBar() {
        var settings = NikoSettings()
        XCTAssertEqual(settings.fullScreenPolicy, .followMenuBar)
        XCTAssertTrue(settings.attentionBreaksFullScreen)
        settings.fullScreenPolicy = .always
        settings.attentionBreaksFullScreen = false
        XCTAssertEqual(NikoSettings(raw: settings.raw).fullScreenPolicy, .always)
        XCTAssertFalse(NikoSettings(raw: settings.raw).attentionBreaksFullScreen)
        XCTAssertEqual(NikoSettings(raw: ["fullScreenPolicy": .string("nonsense")]).fullScreenPolicy, .followMenuBar)
    }
}
