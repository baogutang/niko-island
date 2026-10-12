import NikoCore
import SwiftUI

struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    /// Square top corners when the panel hangs from the notch.
    var attachedToTop = false
    var onHeightChange: (CGFloat) -> Void = { _ in }

    static let maxListHeight: CGFloat = 430

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            Group {
                switch model.selectedTab {
                case .sessions: sessionsTab
                case .usage: UsageView(model: model)
                case .settings: SettingsView(model: model)
                }
            }
            .padding(12)
        }
        .frame(width: PanelController.width)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: attachedToTop ? 0 : 18, bottomLeadingRadius: 18,
                                   bottomTrailingRadius: 18, topTrailingRadius: attachedToTop ? 0 : 18, style: .continuous)
                .fill(Theme.panel)
        )
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: attachedToTop ? 0 : 18, bottomLeadingRadius: 18,
                                   bottomTrailingRadius: 18, topTrailingRadius: attachedToTop ? 0 : 18, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(PanelHeightKey.self) { height in onHeightChange(height) }
    }

    // MARK: Header

    private var summary: String {
        if !model.pending.isEmpty { return L("%lld waiting for your decision", model.pending.count) }
        if model.sessions.isEmpty { return L("No sessions") }
        return L("%lld sessions", model.sessions.count)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Capsule().fill(model.pending.isEmpty ? Theme.working : Theme.attention).frame(width: 18, height: 7)
            Text(NikoVersion.displayName).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
            Text(summary).font(.system(size: 11)).foregroundStyle(model.pending.isEmpty ? Theme.tertiary : Theme.attention)
            Spacer()
            tabButton(.sessions, "rectangle.stack", L("Sessions"))
            tabButton(.usage, "chart.bar", L("Usage"))
            tabButton(.settings, "gearshape", L("Settings"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func tabButton(_ tab: AppModel.Tab, _ symbol: String, _ label: String) -> some View {
        Button { model.selectedTab = tab } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.selectedTab == tab ? Theme.primary : Theme.tertiary)
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(model.selectedTab == tab ? Color.white.opacity(0.12) : .clear))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Sessions

    @ViewBuilder
    private var sessionsTab: some View {
        if case .other(let message)? = model.startFailure {
            notice(L("Niko Island could not start listening"), detail: message, symbol: "exclamationmark.triangle.fill")
        }
        if model.sessions.isEmpty && model.pending.isEmpty {
            emptyState
        } else {
            let content = TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    ForEach(model.pending) { request in
                        if request.isQuestion {
                            QuestionWizardView(model: model, request: request).id(request.id)
                        } else {
                            PermissionCardView(model: model, request: request)
                        }
                    }
                    ForEach(model.sessions) { session in
                        SessionCardView(model: model, session: session, now: context.date)
                    }
                }
            }
            // Short lists size themselves; long ones scroll inside a fixed frame.
            if model.sessions.count + model.pending.count * 3 > 7 {
                ScrollView { content }.frame(height: PanelView.maxListHeight)
            } else {
                content
            }
        }
    }

    private var emptyState: some View {
        let wired = model.maintenance.agents.contains { $0.wired }
        return VStack(spacing: 8) {
            Image(systemName: "moon.zzz").font(.system(size: 22)).foregroundStyle(Theme.tertiary)
            Text(L("No agents running yet.")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
            if wired {
                Text(L("Start an agent in any terminal and it will show up here."))
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
            } else {
                Text(L("Hooks are not installed yet. Nothing is changed until you say so."))
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
                Button(L("Set up hooks…")) { model.selectedTab = .settings }
                    .buttonStyle(PillButtonStyle(kind: .primary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func notice(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.waiting)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.waiting.opacity(0.12)))
        .padding(.bottom, 8)
    }
}
