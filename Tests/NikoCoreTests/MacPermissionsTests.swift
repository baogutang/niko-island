import XCTest
@testable import NikoCore

final class MacPermissionsTests: XCTestCase {
    func testAutomationAnswersMapToConsent() {
        XCTAssertEqual(MacPermissions.automationConsent(status: 0), .granted)
        XCTAssertEqual(MacPermissions.automationConsent(status: -1743), .denied)
        XCTAssertEqual(MacPermissions.automationConsent(status: -1744), .notAsked)
        XCTAssertEqual(MacPermissions.automationConsent(status: -600), .unknown, "a terminal that is not running cannot answer")
    }

    func testOsascriptRefusalIsRecognisedInAnyLanguage() {
        XCTAssertTrue(MacPermissions.isAutomationDenial("26:31: execution error: Not authorized to send Apple events to iTerm. (-1743)"))
        XCTAssertTrue(MacPermissions.isAutomationDenial("26:31: execution error: 未获得授权将 Apple 事件发送给 iTerm。 (-1743)"))
        XCTAssertFalse(MacPermissions.isAutomationDenial("26:31: execution error: iTerm got an error: Can’t get session id \"x\". (-1728)"))
        XCTAssertFalse(MacPermissions.isAutomationDenial(""))
    }

    func testEachPermissionOpensItsOwnPane() {
        XCTAssertEqual(MacPermission.automation(.iterm2).settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        XCTAssertTrue(MacPermission.notifications.settingsURL.absoluteString.hasSuffix("?id=\(NikoVersion.bundleIdentifier)"))
        XCTAssertEqual(AutomationTarget(bundleID: "com.googlecode.iterm2"), .iterm2)
        XCTAssertEqual(AutomationTarget(bundleID: "com.apple.Terminal"), .terminal)
        XCTAssertNil(AutomationTarget(bundleID: "com.mitchellh.ghostty"), "Ghostty is not driven by AppleScript")
    }
}
