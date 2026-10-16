import AppKit
import NikoCore
import SwiftUI

/// Opens System Settings where a permission lives and docks a short guide beside its window,
/// watching until the switch is on. The guide never steals focus from System Settings.
@MainActor
final class PermissionGuideController {
    static let shared = PermissionGuideController()

    private var panel: NSPanel?
    private let model = PermissionGuideModel()
    private var timer: Timer?
    private var grantedAt: Date?
    private var lastSettingsFrame: CGRect?
    private var checking = false
    /// Who reads consent while the guide is up; the app's own center unless a test supplies one.
    var center: PermissionCenter?
    /// Opens a System Settings link; replaced in tests so they never launch System Settings.
    var openSettings: (URL) -> Void = { NSWorkspace.shared.open($0) }

    var isPresented: Bool { panel != nil }
    var presented: MacPermission? { panel == nil ? nil : model.permission }

    static let size = CGSize(width: 460, height: 176)

    func present(_ permission: MacPermission, reason: String? = nil) {
        model.permission = permission
        model.reason = reason
        model.consent = center?.consent(for: permission) ?? .unknown
        grantedAt = nil
        openSettings(permission.settingsURL)
        if panel == nil { panel = makePanel() }
        reposition(animated: false)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel?.animator().alphaValue = 1
        }
        startTimer()
    }

    func dismiss() {
        timer?.invalidate(); timer = nil
        let old = panel
        panel = nil
        old?.orderOut(nil); old?.contentView = nil; old?.close()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.setAccessibilityLabel(L("Permission guide"))
        let view = PermissionGuideView(model: model,
            close: { [weak self] in self?.dismiss() },
            reopen: { [weak self] in if let self { self.openSettings(self.model.permission.settingsURL) } })
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: Self.size)
        panel.contentView = host
        return panel
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard panel != nil else { timer?.invalidate(); timer = nil; return }
        reposition(animated: true)
        if let grantedAt, Date().timeIntervalSince(grantedAt) > 1.6 { dismiss(); return }
        guard !checking, let center else { return }
        checking = true
        let permission = model.permission
        Task { [weak self] in
            let consent: Consent
            switch permission {
            case .notifications: consent = await center.readNotifications()
            case .automation(let target): consent = await center.readAutomation(target, false)
            }
            guard let self else { return }
            self.checking = false
            guard self.panel != nil, self.model.permission == permission else { return }
            if consent == .granted, self.model.consent != .granted {
                self.grantedAt = Date()
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                await center.refresh()
            }
            withAnimation(Motion.smooth()) { self.model.consent = consent }
        }
    }

    private func reposition(animated: Bool) {
        guard let panel else { return }
        let settings = Self.settingsWindowFrame()
        guard settings != lastSettingsFrame || !panel.isVisible else { return }
        lastSettingsFrame = settings
        let screen = (settings.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = Self.placement(size: Self.size, settings: settings, visible: screen)
        if animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Under the settings window near its right-hand pane, else beside it, else over its lower edge.
    nonisolated static func placement(size: CGSize, settings: CGRect?, visible: CGRect) -> CGRect {
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, visible.minX + 8), visible.maxX - size.width - 8) }
        guard let settings else {
            return CGRect(x: clampX(visible.midX - size.width / 2), y: visible.minY + 80, width: size.width, height: size.height)
        }
        let gap: CGFloat = 12
        let x = clampX(settings.midX - size.width / 2 + settings.width * 0.12)
        let below = settings.minY - gap - size.height
        if below >= visible.minY + 8 { return CGRect(x: x, y: below, width: size.width, height: size.height) }
        let y = min(max(settings.minY + 24, visible.minY + 8), visible.maxY - size.height - 8)
        if settings.maxX + gap + size.width <= visible.maxX - 8 {
            return CGRect(x: settings.maxX + gap, y: y, width: size.width, height: size.height)
        }
        if settings.minX - gap - size.width >= visible.minX + 8 {
            return CGRect(x: settings.minX - gap - size.width, y: y, width: size.width, height: size.height)
        }
        return CGRect(x: x, y: max(visible.minY + 8, settings.minY + 16), width: size.width, height: size.height)
    }

    /// The largest on-screen System Settings window, in AppKit coordinates. Reading window
    /// bounds needs no permission.
    static func settingsWindowFrame() -> CGRect? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        var best: CGRect?
        for info in list {
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(owner),
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 200, rect.height > 200 else { continue }
            if best.map({ rect.width * rect.height > $0.width * $0.height }) ?? true { best = rect }
        }
        return best.map { CGRect(x: $0.minX, y: primaryTop - $0.maxY, width: $0.width, height: $0.height) }
    }
}

@MainActor
final class PermissionGuideModel: ObservableObject {
    @Published var permission: MacPermission = .notifications
    @Published var reason: String?
    @Published var consent: Consent = .unknown
}

/// Steps for one permission, in the island's own dark look.
struct PermissionGuideView: View {
    @ObservedObject var model: PermissionGuideModel
    var close: () -> Void
    var reopen: () -> Void
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var granted: Bool { model.consent == .granted }

    /// The installed app's own icon; drawn in code when running outside a bundle (previews, tests).
    private var appIcon: NSImage {
        if Bundle.main.bundleURL.pathExtension == "app" { return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) }
        return IconRenderer.image(points: 48) ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            icons
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title).font(Theme.body(14, .semibold)).foregroundStyle(Theme.primary)
                    Spacer(minLength: 0)
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.secondary)
                            .frame(width: 20, height: 20).background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain).accessibilityLabel(L("Close"))
                }
                if let reason = model.reason {
                    Text(reason).font(Theme.body(11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1)").font(Theme.body(10, .bold)).foregroundStyle(.black)
                            .frame(width: 16, height: 16).background(Circle().fill(Theme.mint))
                        Text(text).font(Theme.body(12)).foregroundStyle(Theme.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    status
                    Spacer(minLength: 0)
                    if !granted {
                        Button(L("Open Settings"), action: reopen).buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .frame(width: PermissionGuideController.size.width, height: PermissionGuideController.size.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.window.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardStroke))
        .onAppear { pulse = true }
    }

    private var title: String {
        switch model.permission {
        case .notifications: return L("Allow notifications")
        case .automation(let target): return L("Allow Niko Island to control %@", target.displayName)
        }
    }

    private var steps: [String] {
        switch model.permission {
        case .notifications:
            return [L("Turn on Allow notifications for Niko Island"),
                    L("Choose Alerts: a permission request can then be answered on the banner")]
        case .automation(let target):
            return [L("Find Niko Island in the Automation list"),
                    L("Turn on %@ underneath it", target.displayName)]
        }
    }

    /// Niko Island → the thing it needs, with a gentle pulse until the switch is on.
    private var icons: some View {
        VStack(spacing: 6) {
            Image(nsImage: appIcon).resizable().frame(width: 48, height: 48)
            Image(systemName: granted ? "checkmark.circle.fill" : "arrow.down")
                .font(.system(size: granted ? 16 : 12, weight: .bold))
                .foregroundStyle(granted ? Theme.mint : Theme.secondary)
                .offset(y: granted || reduceMotion ? 0 : (pulse ? 2 : -2))
                .animation(granted || reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            target.frame(width: 40, height: 40).opacity(granted ? 1 : 0.9)
        }
        .frame(width: 64)
    }

    /// The terminal's own icon when it is installed, otherwise a symbol on a tile like an app icon.
    @ViewBuilder private var target: some View {
        if case .automation(let target) = model.permission,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            let symbol: String = { if case .notifications = model.permission { return "bell.badge.fill" }; return "apple.terminal.fill" }()
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.primary))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
                .padding(2)
        }
    }

    @ViewBuilder private var status: some View {
        if granted {
            Label(L("Allowed. You are set."), systemImage: "checkmark.circle.fill")
                .font(Theme.body(11.5, .medium)).foregroundStyle(Theme.mint)
        } else {
            HStack(spacing: 6) {
                if isStaticPreview {
                    Circle().fill(Theme.amber).frame(width: 7, height: 7)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(L("Waiting for the switch…")).font(Theme.body(11.5)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// Settings → General: each permission, what it is for, how it stands and the one thing to do about it.
struct PermissionsCard: View {
    @ObservedObject var center: PermissionCenter
    @Environment(\.isStaticPreview) private var isStaticPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Permissions").uppercased()).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            VStack(alignment: .leading, spacing: 0) {
                let targets = center.installedTargets
                row(.notifications, title: L("Notifications"), detail: notificationDetail, divider: !targets.isEmpty)
                ForEach(Array(targets.enumerated()), id: \.element) { index, target in
                    row(.automation(target), title: L("Control %@", target.displayName),
                        detail: automationDetail(target), divider: index < targets.count - 1)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(center.hasProblem ? Theme.coral.opacity(0.45) : Theme.cardStroke))
        }
        .task {
            guard !isStaticPreview else { return }
            while !Task.isCancelled {
                await center.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var notificationDetail: String {
        switch center.notifications {
        case .granted: return L("Banners for requests, questions and finished turns.")
        case .denied: return L("Turned off in System Settings, so no banner appears.")
        case .notAsked: return L("macOS asks the first time a banner is due.")
        case .unknown: return L("Only the installed app can show notifications.")
        }
    }

    private func automationDetail(_ target: AutomationTarget) -> String {
        switch center.consent(for: .automation(target)) {
        case .granted: return L("Clicking a session brings its own %@ tab to the front.", target.displayName)
        case .denied: return L("Turned down: a session only brings %@ forward, not its tab.", target.displayName)
        case .notAsked: return L("macOS asks the first time you go to a session in %@.", target.displayName)
        case .unknown: return L("Checked while %@ is open.", target.displayName)
        }
    }

    private func row(_ permission: MacPermission, title: String, detail: String, divider: Bool) -> some View {
        let consent = center.consent(for: permission)
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.body(13.5, .semibold)).foregroundStyle(Theme.primary)
                    Text(detail).font(Theme.body(11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                switch consent {
                case .granted:
                    Chip(text: L("Allowed"), tint: Theme.mint, mono: false)
                case .denied:
                    Chip(text: L("Off"), tint: Theme.coral, mono: false)
                    Button(L("Fix…")) { PermissionGuideController.shared.present(permission) }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                case .notAsked:
                    Button(L("Allow…")) { Task { await center.request(permission) } }
                        .buttonStyle(PillButtonStyle())
                case .unknown:
                    EmptyView()
                }
            }
            .padding(.vertical, 12)
            if divider { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }
}
