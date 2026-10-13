import AppKit
import NikoCore
import UserNotifications

/// Brings the terminal tab that hosts a session to the front.
enum TerminalJumper {
    static func jump(to session: Session) {
        let target = JumpTarget(terminal: session.terminal, ancestors: session.ancestors)
        let ancestors = session.ancestors
        DispatchQueue.global(qos: .userInitiated).async {
            var clientTTY: String?
            if target.tmuxPane != nil, let tmux = TerminalJump.locateTmux(ancestors: ancestors) {
                for arguments in TerminalJump.tmuxCommands(for: target) { _ = run(tmux, arguments) }
                if let query = TerminalJump.tmuxClientQuery(for: target) {
                    clientTTY = run(tmux, query)?.split(separator: "\n").first.map(String.init)
                }
            }
            var selected = false
            if let script = TerminalJump.appleScript(for: target, clientTTY: clientTTY) {
                // osascript keeps the Apple Events round trip off our main thread.
                // The first use triggers the system's Automation consent prompt.
                selected = run("/usr/bin/osascript", ["-e", script])?.contains("found") ?? false
            }
            guard !selected, let bundleID = target.bundleID else { return }
            DispatchQueue.main.async {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?
                    .activate(options: [.activateAllWindows])
            }
        }
    }

    /// Bundle id of the frontmost app, to avoid notifying about a session the user is looking at.
    @MainActor
    static func isFrontmost(_ session: Session) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return JumpTarget(terminal: session.terminal, ancestors: session.ancestors).bundleID == front
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Local notifications. Only available inside a real app bundle.
@MainActor
final class SystemNotifier: NSObject, AttentionNotifying, UNUserNotificationCenterDelegate {
    private weak var model: AppModel?
    private let center: UNUserNotificationCenter?
    private var askedForPermission = false

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
            && Bundle.main.bundleURL.pathExtension == "app"
            && !UserDefaults.standard.bool(forKey: "NikoNotificationsDisabled")
    }

    init(model: AppModel) {
        self.model = model
        self.center = SystemNotifier.isAvailable ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
    }

    private func identifier(_ key: SessionKey) -> String { "session:" + key.description }

    func notify(kind: NikoSettings.EventKind, session: Session, body: String) {
        guard let model else { return }
        guard model.settings.notificationsEnabled(for: kind), let center else { return }
        // No banner for a session whose terminal is already in front of the user.
        guard !TerminalJumper.isFrontmost(session) else { return }

        let text: String
        switch kind {
        case .permission: text = body.isEmpty ? L("Needs your permission") : L("Wants to use %@", body)
        case .question: text = body.isEmpty ? L("Has a question for you") : body
        case .idle: text = L("Finished and waiting for you")
        }
        let payload = Payload(identifier: identifier(session.key), title: session.title,
                              subtitle: AgentRegistry.displayName(for: session.source), body: text,
                              source: session.key.source, session: session.key.sessionID)
        if askedForPermission {
            SystemNotifier.post(payload)
        } else {
            askedForPermission = true
            center.requestAuthorization(options: [.alert]) { granted, _ in
                if granted { SystemNotifier.post(payload) }
            }
        }
    }

    private struct Payload: Sendable {
        let identifier, title, subtitle, body, source, session: String
    }

    nonisolated private static func post(_ payload: Payload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.userInfo = ["source": payload.source, "session": payload.session]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil))
    }

    func clear(session: SessionKey) {
        center?.removeDeliveredNotifications(withIdentifiers: [identifier(session)])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let source = info["source"] as? String
        let session = info["session"] as? String
        completionHandler()
        guard let source, let session else { return }
        Task { @MainActor in
            self.model?.jump(to: SessionKey(source: source, sessionID: session))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
