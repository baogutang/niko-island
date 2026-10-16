import Foundation

/// The macOS permissions Niko Island can use, and how to read and fix each one.
///
/// Neither is a list an app can be dragged into: Automation is asked for per terminal the
/// first time we send it an Apple event, and notifications by the system's own prompt. What
/// the app can do is notice a "no", say what it costs, and open the right place to change it.
public enum MacPermission: Hashable, Sendable {
    case notifications
    case automation(AutomationTarget)

    /// System Settings, opened at the pane that holds this switch.
    public var settingsURL: URL {
        switch self {
        case .notifications:
            return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(NikoVersion.bundleIdentifier)")!
        case .automation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        }
    }
}

/// Terminals we drive with AppleScript to bring a session's own tab to the front.
public enum AutomationTarget: String, CaseIterable, Hashable, Sendable {
    case terminal, iterm2

    public var bundleID: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2: return "com.googlecode.iterm2"
        }
    }

    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2: return "iTerm2"
        }
    }

    public init?(bundleID: String) {
        guard let match = Self.allCases.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = match
    }
}

public enum Consent: Hashable, Sendable {
    case granted
    case denied
    /// macOS has not asked yet; it will the first time it matters.
    case notAsked
    /// Cannot be told right now: Automation is only answered while the terminal is running.
    case unknown
}

public enum MacPermissions {
    /// Reads `AEDeterminePermissionToAutomateTarget`'s answer.
    public static func automationConsent(status: Int32) -> Consent {
        switch status {
        case 0: return .granted
        case -1743: return .denied        // errAEEventNotPermitted
        case -1744: return .notAsked      // errAEEventWouldRequireUserConsent
        default: return .unknown          // procNotFound (-600) and the like: the terminal is not running
        }
    }

    /// Whether `osascript`'s error output says the user turned Automation down for that terminal.
    /// The message is localised; the error number at its end is not.
    public static func isAutomationDenial(_ errorOutput: String) -> Bool {
        errorOutput.contains("(-1743)") || errorOutput.localizedCaseInsensitiveContains("not authorized to send apple events")
    }
}
