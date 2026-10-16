import XCTest
@testable import NikoCore
@testable import NikoIslandApp

@MainActor
final class PermissionCenterTests: XCTestCase {
    private func center(notifications: Consent, automation: Consent, installed: Set<AutomationTarget> = [.iterm2]) -> PermissionCenter {
        let center = PermissionCenter()
        center.readNotifications = { notifications }
        center.readAutomation = { _, ask in ask ? .granted : automation }
        center.isInstalled = { installed.contains($0) }
        return center
    }

    func testRefreshReadsOnlyTheTerminalsThisMacHas() async {
        let center = center(notifications: .granted, automation: .notAsked)
        await center.refresh()
        XCTAssertEqual(center.notifications, .granted)
        XCTAssertEqual(center.installedTargets, [.iterm2])
        XCTAssertEqual(center.consent(for: .automation(.iterm2)), .notAsked)
        XCTAssertNil(center.automation[.terminal])
        XCTAssertFalse(center.hasProblem)
    }

    func testARefusedJumpIsAProblemUntilMacOSSaysOtherwise() async {
        let center = center(notifications: .granted, automation: .granted)
        center.recordRefusal(.iterm2)
        XCTAssertEqual(center.consent(for: .automation(.iterm2)), .denied)
        XCTAssertTrue(center.hasProblem)
        XCTAssertEqual(center.refusals, [.iterm2])
        await center.refresh()
        XCTAssertFalse(center.hasProblem, "switching it on in System Settings clears the warning")
    }

    func testAskingShowsTheSystemPromptOnlyThroughTheExplicitRequest() async {
        var asked: [Bool] = []
        let center = PermissionCenter()
        center.isInstalled = { $0 == .terminal }
        center.readNotifications = { .notAsked }
        center.readAutomation = { _, ask in await MainActor.run { asked.append(ask) }; return ask ? .granted : .notAsked }
        await center.refresh()
        XCTAssertEqual(asked, [false], "refreshing never prompts")
        await center.request(.automation(.terminal))
        XCTAssertEqual(asked, [false, true])
        XCTAssertEqual(center.consent(for: .automation(.terminal)), .granted)
    }

    func testGuideDocksBesideSystemSettings() {
        let size = PermissionGuideController.size
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let below = PermissionGuideController.placement(size: size, settings: CGRect(x: 300, y: 300, width: 780, height: 560), visible: visible)
        XCTAssertEqual(below.maxY, 288)
        XCTAssertTrue(visible.contains(below))
        let beside = PermissionGuideController.placement(size: size, settings: CGRect(x: 120, y: 40, width: 760, height: 840), visible: visible)
        XCTAssertEqual(beside.minX, 892)
        let none = PermissionGuideController.placement(size: size, settings: nil, visible: visible)
        XCTAssertEqual(none.midX, visible.midX, accuracy: 1)
    }
}
