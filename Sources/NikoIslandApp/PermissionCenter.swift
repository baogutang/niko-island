import AppKit
import CoreServices
import NikoCore
import SwiftUI
import UserNotifications

/// What macOS currently allows Niko Island, read without ever showing a prompt, and the way
/// to change it: the right System Settings pane with a guide docked beside it.
@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var notifications: Consent = .notAsked
    @Published private(set) var automation: [AutomationTarget: Consent] = [:]
    /// Terminals that turned an Apple event down since launch, newest last.
    @Published private(set) var refusals: [AutomationTarget] = []

    /// Test seams: the real answers come from macOS.
    var readNotifications: @Sendable () async -> Consent = { await PermissionCenter.systemNotificationConsent(available: PermissionCenter.notificationsAvailable) }
    var readAutomation: @Sendable (AutomationTarget, Bool) async -> Consent = { target, ask in
        await PermissionCenter.systemAutomationConsent(target, ask: ask)
    }
    var isInstalled: (AutomationTarget) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }

    /// The terminals this Mac has; only those are worth a row.
    var installedTargets: [AutomationTarget] { AutomationTarget.allCases.filter(isInstalled) }

    func consent(for permission: MacPermission) -> Consent {
        switch permission {
        case .notifications: return notifications
        case .automation(let target): return automation[target] ?? .unknown
        }
    }

    /// Something the user said no to, that costs them a feature.
    var hasProblem: Bool {
        notifications == .denied || automation.values.contains(.denied)
    }

    func refresh() async {
        notifications = await readNotifications()
        for target in installedTargets { automation[target] = await readAutomation(target, false) }
    }

    /// Asks macOS to show its own prompt (only possible while it has not asked yet).
    func request(_ permission: MacPermission) async {
        switch permission {
        case .notifications:
            guard SystemNotifier.isAvailable else { return }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            notifications = await readNotifications()
        case .automation(let target):
            automation[target] = await readAutomation(target, true)
        }
    }

    /// Fixed answers for the rendered documentation pictures.
    func showForPreview(notifications: Consent, automation: [AutomationTarget: Consent]) {
        self.notifications = notifications
        self.automation = automation
        isInstalled = { automation[$0] != nil }
    }

    /// A jump or a reply was refused: remember it, so Settings and the guide can say why.
    func recordRefusal(_ target: AutomationTarget) {
        automation[target] = .denied
        refusals.removeAll { $0 == target }
        refusals.append(target)
    }

    // MARK: Reading macOS

    /// Read once: whether this process can use notifications at all (an installed app bundle).
    nonisolated static let notificationsAvailable = Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
        && !UserDefaults.standard.bool(forKey: "NikoNotificationsDisabled")

    nonisolated static func systemNotificationConsent(available: Bool) async -> Consent {
        guard available else { return .unknown }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        case .notDetermined: return .notAsked
        @unknown default: return .unknown
        }
    }

    /// `AEDeterminePermissionToAutomateTarget` can block on the user's answer, so it never runs on the main thread.
    nonisolated static func systemAutomationConsent(_ target: AutomationTarget, ask: Bool) async -> Consent {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let descriptor = NSAppleEventDescriptor(bundleIdentifier: target.bundleID)
                guard let address = descriptor.aeDesc else { continuation.resume(returning: .unknown); return }
                let status = AEDeterminePermissionToAutomateTarget(address, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
                continuation.resume(returning: MacPermissions.automationConsent(status: status))
            }
        }
    }
}
