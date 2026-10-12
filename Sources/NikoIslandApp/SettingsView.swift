import AppKit
import NikoCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var diagnosticsPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(L("Hooks")) { hooks }
            section(L("Notify me when")) {
                eventToggles { kind in
                    Binding(get: { model.settings.notificationsEnabled(for: kind) },
                            set: { model.settings.setNotifications($0, for: kind) })
                }
            }
            section(L("Play a sound when")) {
                eventToggles { kind in
                    Binding(get: { model.settings.soundEnabled(for: kind) },
                            set: { model.settings.setSound($0, for: kind) })
                }
            }
            section(L("Privacy")) { privacy }
            footer
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
            content()
        }
    }

    // MARK: Hooks

    @ViewBuilder
    private var hooks: some View {
        if let fix = model.maintenance.quarantineFix {
            VStack(alignment: .leading, spacing: 4) {
                Label(L("macOS is still holding this app in quarantine"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.waiting)
                Text(L("Hooks cannot start the bridge until the flag is cleared. Run this once in a terminal, then reopen the app:"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Text(fix).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.primary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.waiting.opacity(0.12)))
        }
        if model.maintenance.agents.isEmpty {
            Text(L("No supported agent was found in your home directory."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        ForEach(model.maintenance.agents) { agent in
            HStack(spacing: 8) {
                Image(systemName: AgentRegistry.symbol(for: agent.id)).font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(width: 18)
                Text(agent.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.primary)
                if agent.stability == .experimental {
                    Text(L("experimental")).font(.system(size: 10)).foregroundStyle(Theme.waiting)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.waiting.opacity(0.15)))
                }
                Spacer()
                Text(agent.wired ? L("connected") : L("not connected"))
                    .font(.system(size: 11)).foregroundStyle(agent.wired ? Theme.working : Theme.tertiary)
                Button(agent.wired ? L("Remove") : L("Connect")) {
                    model.runInstaller(agent.wired ? .uninstall : .install, agents: [agent.id])
                }
                .buttonStyle(PillButtonStyle(kind: agent.wired ? .neutral : .primary))
                .disabled(model.maintenance.busy)
            }
        }
        Text(L("Connecting adds entries tagged niko-bridge to the agent's config after a backup. Removing takes out only those entries."))
            .font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
        if let message = model.maintenance.message {
            Text(message)
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
        }
    }

    // MARK: Toggles

    private func label(for kind: NikoSettings.EventKind) -> String {
        switch kind {
        case .permission: return L("An agent asks for permission")
        case .question: return L("An agent asks a question")
        case .idle: return L("An agent finishes and waits for me")
        }
    }

    private func eventToggles(_ binding: @escaping (NikoSettings.EventKind) -> Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(NikoSettings.EventKind.allCases, id: \.self) { kind in
                Toggle(isOn: binding(kind)) {
                    Text(label(for: kind)).font(.system(size: 12)).foregroundStyle(Theme.primary)
                }
                .toggleStyle(CheckToggleStyle())
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { model.settings.pricingRefreshEnabled },
                                 set: { model.settings.pricingRefreshEnabled = $0 })) {
                Text(L("Refresh the model price list from the network (weekly)"))
                    .font(.system(size: 12)).foregroundStyle(Theme.primary)
            }
            .toggleStyle(CheckToggleStyle())
            Text(L("Off by default. It is the only network request this app can make; everything else stays on this Mac."))
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
            if model.httpPort > 0 {
                Text(L("Plugin ingress listening on 127.0.0.1:%lld", Int(model.httpPort)))
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(L("Export diagnostics")) {
                    if let url = model.exportDiagnostics() {
                        diagnosticsPath = url.path
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .buttonStyle(PillButtonStyle())
                Button(L("Releases")) {
                    if let url = URL(string: NikoVersion.releasesURL) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(PillButtonStyle())
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }.buttonStyle(PillButtonStyle(kind: .destructive))
            }
            Text(L("Version %@ · no telemetry, no account, MIT licensed", NikoVersion.current))
                .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
        }
    }
}
