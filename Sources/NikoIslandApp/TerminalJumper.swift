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
            // No tab to select (an IDE, a desktop app, another emulator): bring the app forward.
            guard !selected, let bundleID = target.bundleID ?? session.host?.bundleID else { return }
            let thread = TerminalJump.threadURL(for: session)
            DispatchQueue.main.async {
                // A desktop app that can be told which conversation to show is told.
                if let thread, NSWorkspace.shared.open(thread) { return }
                if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    running.activate(options: [.activateAllWindows])
                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }

    /// Bundle id of the frontmost app, to avoid notifying about a session the user is looking at.
    @MainActor
    static func isFrontmost(_ session: Session) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return session.hostBundleID == front
    }

    /// Sends a follow-up into the session's terminal. Returns false when there
    /// is no way in, or when what sits at that terminal is not the agent.
    static func reply(_ text: String, to session: Session) async -> Bool {
        guard let channel = TerminalReply.channel(for: session) else { return false }
        let ancestors = session.ancestors
        let source = session.source
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: send(text, through: channel, source: source, ancestors: ancestors))
            }
        }
    }

    private static func send(_ text: String, through channel: TerminalReply.Channel, source: String, ancestors: [ProcessNode]) -> Bool {
        func waiting(onTTY tty: String) -> Bool {
            let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            guard let listing = run("/bin/ps", ["-o", "stat=,comm=", "-t", name]) else { return false }
            return TerminalReply.isAgentWaiting(foreground: TerminalReply.foreground(psOutput: listing), source: source)
        }
        switch channel {
        case .tmux(let socket, let pane):
            guard let tmux = TerminalJump.locateTmux(ancestors: ancestors),
                  let command = run(tmux, TerminalReply.tmuxProbe(socket: socket, pane: pane)),
                  TerminalReply.isAgentWaiting(foreground: [command], source: source) else { return false }
            for arguments in TerminalReply.tmuxSend(socket: socket, pane: pane, text: text) {
                guard run(tmux, arguments) != nil else { return false }
            }
            return true
        case .iterm(let guid):
            guard let tty = run("/usr/bin/osascript", ["-e", TerminalReply.itermTTYScript(guid: guid)])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !tty.isEmpty, waiting(onTTY: tty),
                  let script = TerminalReply.appleScript(for: channel, text: text) else { return false }
            return run("/usr/bin/osascript", ["-e", script])?.contains("sent") ?? false
        case .terminal(let tty):
            guard waiting(onTTY: tty), let script = TerminalReply.appleScript(for: channel, text: text) else { return false }
            return run("/usr/bin/osascript", ["-e", script])?.contains("sent") ?? false
        }
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
        // A request for permission can be answered on its banner; a question cannot (it needs its answers).
        let allow = UNNotificationAction(identifier: SystemNotifier.allowAction, title: L("Allow once"), options: [])
        let deny = UNNotificationAction(identifier: SystemNotifier.denyAction, title: L("Deny"), options: [.destructive])
        center?.setNotificationCategories([UNNotificationCategory(identifier: SystemNotifier.permissionCategory, actions: [allow, deny],
                                                                  intentIdentifiers: [], options: [])])
    }

    static let permissionCategory = "niko.permission"
    static let allowAction = "niko.allow"
    static let denyAction = "niko.deny"

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
                              source: session.key.source, session: session.key.sessionID,
                              category: kind == .permission ? SystemNotifier.permissionCategory : "")
        if askedForPermission {
            SystemNotifier.post(payload)
        } else {
            askedForPermission = true
            center.requestAuthorization(options: [.alert], completionHandler: SystemNotifier.afterAuthorization(post: payload))
        }
    }

    /// What runs once macOS has answered the permission question. macOS calls it on a queue of
    /// its own, so it must not belong to the main actor: a closure written inside this
    /// main-actor class would, and Swift stops the app when such a closure runs off the main
    /// thread (that was 0.8.0 quitting at the first notification). Made here, outside any actor.
    nonisolated static func afterAuthorization(post payload: Payload) -> @Sendable (Bool, (any Error)?) -> Void {
        { granted, _ in
            if granted { post(payload) }
        }
    }

    struct Payload: Sendable {
        let identifier, title, subtitle, body, source, session, category: String
    }

    nonisolated private static func post(_ payload: Payload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.userInfo = ["source": payload.source, "session": payload.session]
        if !payload.category.isEmpty { content.categoryIdentifier = payload.category }
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
        let action = response.actionIdentifier
        completionHandler()
        guard let source, let session else { return }
        Task { @MainActor in
            let key = SessionKey(source: source, sessionID: session)
            switch action {
            case SystemNotifier.allowAction: self.model?.decide(forSession: key, .allow)
            case SystemNotifier.denyAction: self.model?.decide(forSession: key, .deny)
            default: self.model?.jump(to: key)
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
