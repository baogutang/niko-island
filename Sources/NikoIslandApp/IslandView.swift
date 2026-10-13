import NikoCore
import SwiftUI

/// Root of the island window: a transparent canvas with the island hanging
/// from the top centre. Collapsed it is a small black tab the height of the
/// menu bar; expanded it becomes the session surface.
struct IslandView: View {
    @ObservedObject var model: AppModel
    var metrics: IslandMetrics
    var onFrameChange: (CGRect) -> Void = { _ in }
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var visible: Bool {
        model.isExpanded || model.settings.showIslandWhenIdle || !model.sessions.isEmpty || !model.pending.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            if visible { IslandBody(model: model, metrics: metrics) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "island-canvas")
        .onPreferenceChange(IslandFrameKey.self) { onFrameChange($0) }
        .environment(\.colorScheme, .dark)
        .environment(\.look, IslandLook(settings: model.settings))
    }
}

/// The island itself: the black shape and whatever it currently holds.
struct IslandBody: View {
    @ObservedObject var model: AppModel
    var metrics: IslandMetrics
    @Environment(\.isStaticPreview) private var isStaticPreview

    var body: some View {
        let shape = IslandShape(ear: model.isExpanded ? 10 : 6, radius: model.isExpanded ? 30 : 13)
        let spring = Animation.spring(response: 0.36, dampingFraction: 0.84)
        return VStack(spacing: 0) {
            if model.isExpanded {
                ExpandedIsland(model: model, metrics: metrics)
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.08)))
            } else {
                CollapsedIsland(model: model, metrics: metrics)
                    .transition(.opacity.animation(.easeOut(duration: 0.1)))
            }
        }
        .frame(width: model.isExpanded ? CGFloat(model.settings.islandWidth.points) : nil)
        .background(shape.fill(Theme.island))
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(model.isExpanded ? 0.55 : 0), radius: 24, y: 14)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: IslandFrameKey.self, value: proxy.frame(in: .named("island-canvas")))
        })
        .animation(isStaticPreview ? nil : spring, value: model.isExpanded)
        .animation(isStaticPreview ? nil : spring, value: model.toast)
        .animation(isStaticPreview ? nil : spring, value: model.badge)
    }
}

// MARK: - Collapsed

/// What the collapsed island says at a glance.
struct IslandGlance: Equatable {
    enum Tone { case idle, working, waiting, attention, done, failed }
    var source: String?
    var text: String
    var tone: Tone
    var count: Int

    @MainActor
    init(model: AppModel) {
        if let toast = model.toast {
            source = toast.key.source
            text = toast.title
            tone = toast.kind == .completed ? .done : .failed
            count = 0
        } else if let request = model.pending.first {
            let session = model.sessions.first { $0.key == request.sessionKey }
            let project = AutoNamer.projectName(cwd: request.event.cwd) ?? AgentRegistry.displayName(for: request.event.source)
            source = request.event.source
            text = L("%@ needs you", session.map { AutoNamer.projectName(cwd: $0.cwd) ?? project } ?? project)
            tone = .attention
            count = model.pending.count
        } else if let working = model.sessions.first(where: { $0.phase == .working }) {
            source = working.source
            let detail = working.activity.detail.map { " " + $0 } ?? ""
            text = working.activity.localizedVerb + detail
            tone = .working
            count = model.sessions.filter { $0.phase == .working }.count
        } else if let waiting = model.sessions.first {
            source = waiting.source
            text = L("%lld waiting", model.sessions.count)
            tone = .waiting
            count = 0
        } else {
            source = nil
            text = NikoVersion.displayName
            tone = .idle
            count = 0
        }
    }

    func color(accent: Color) -> Color {
        switch tone {
        case .idle: return Theme.tertiary
        case .working: return Theme.primary.opacity(0.9)
        case .waiting: return Theme.amber
        case .attention: return Theme.amber
        case .done: return accent
        case .failed: return Theme.coral
        }
    }
}

struct CollapsedIsland: View {
    @ObservedObject var model: AppModel
    var metrics: IslandMetrics
    @Environment(\.look) private var look

    var body: some View {
        let glance = IslandGlance(model: model)
        Button { model.expand(.click) } label: {
            Group {
                if metrics.hasNotch {
                    // Beside the camera housing there is room for a creature on
                    // the left and a marker on the right; the middle is hardware.
                    HStack(spacing: 0) {
                        mascot(glance).frame(width: IslandMetrics.wing)
                        Color.clear.frame(width: metrics.notchWidth)
                        marker(glance).frame(width: IslandMetrics.wing)
                    }
                } else {
                    HStack(spacing: 7) {
                        mascot(glance)
                        Text(glance.text)
                            .font(Theme.body(11.5, .semibold))
                            .foregroundStyle(glance.color(accent: look.accent))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 230)
                            .fixedSize()
                        marker(glance)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(height: metrics.bandHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(glance.text)
    }

    @ViewBuilder
    private func mascot(_ glance: IslandGlance) -> some View {
        if let source = glance.source {
            MascotView(source: source, size: 17, animated: glance.tone == .working)
        } else {
            MascotView(sprite: Mascots.island, size: 17).opacity(0.75)
        }
    }

    @ViewBuilder
    private func marker(_ glance: IslandGlance) -> some View {
        switch glance.tone {
        case .attention:
            HStack(spacing: 3) {
                Image(systemName: "bell.fill").font(.system(size: 9, weight: .bold))
                if glance.count > 1 { Text("\(glance.count)").font(Theme.mono(10, .bold)) }
            }
            .foregroundStyle(Theme.amber)
        case .working:
            if glance.count > 1 {
                Text("\(glance.count)").font(Theme.mono(10, .bold)).foregroundStyle(look.accent)
            } else {
                Circle().fill(look.accent).frame(width: 6, height: 6)
            }
        case .waiting:
            Circle().fill(Theme.amber).frame(width: 6, height: 6)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(look.accent)
        case .failed:
            Image(systemName: "exclamationmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.coral)
        case .idle:
            Circle().fill(Theme.quaternary).frame(width: 5, height: 5)
        }
    }
}

// MARK: - Expanded

struct ExpandedIsland: View {
    @ObservedObject var model: AppModel
    var metrics: IslandMetrics
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var summary: String {
        if !model.pending.isEmpty { return L("%lld waiting for your decision", model.pending.count) }
        if model.sessions.isEmpty { return L("No sessions") }
        return L("%lld sessions", model.sessions.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch model.route {
                case .sessions: SessionsPane(model: model)
                case .usage: UsageView(model: model)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
    }

    /// Sits in the menu-bar band. On a notched display its middle is hidden by
    /// the camera housing, so everything lives at the two ends.
    private var header: some View {
        HStack(spacing: 8) {
            MascotView(sprite: Mascots.island, size: 16)
            Text(NikoVersion.displayName).font(Theme.body(12, .bold)).foregroundStyle(Theme.primary)
            if !metrics.hasNotch {
                Text(summary).font(Theme.body(11.5)).foregroundStyle(model.pending.isEmpty ? Theme.tertiary : Theme.amber)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "chart.bar.fill", active: model.route == .usage, label: L("Usage")) {
                model.route = model.route == .usage ? .sessions : .usage
            }
            IconButton(symbol: model.settings.soundsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                       label: model.settings.soundsEnabled ? L("Mute sounds") : L("Turn sounds on")) {
                model.settings.soundsEnabled.toggle()
            }
            IconButton(symbol: "gearshape.fill", label: L("Settings")) { model.onOpenSettings?() }
        }
        .padding(.horizontal, 20)
        .frame(height: max(metrics.bandHeight, 34))
    }
}

/// The session list, with the request that needs an answer opened up on top.
struct SessionsPane: View {
    @ObservedObject var model: AppModel
    @Environment(\.isStaticPreview) private var isStaticPreview
    @State private var listHeight: CGFloat = 0

    /// Height of the list before it scrolls: the number of rows the user asked for.
    private var maxListHeight: CGFloat {
        CGFloat(model.settings.visibleRows) * (model.settings.rowDensity == .compact ? 52 : 68)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .other(let message)? = model.startFailure {
                notice(L("Niko Island could not start listening"), detail: message)
            }
            if let request = model.focusedRequest {
                RequestDetailView(model: model, request: request).id(request.id)
            }
            let rows = model.sessions.filter { $0.key != model.focusedRequest?.sessionKey }
            if !rows.isEmpty {
                if model.focusedRequest != nil {
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 12)
                }
                list(rows)
            } else if model.focusedRequest == nil {
                emptyState
            }
        }
    }

    @ViewBuilder
    private func list(_ rows: [Session]) -> some View {
        if isStaticPreview {
            rowStack(rows, now: PreviewClock.now)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // Short lists size themselves; long ones scroll inside a capped frame.
                ScrollView(.vertical, showsIndicators: false) {
                    rowStack(rows, now: context.date)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                        })
                }
                .frame(height: min(max(listHeight, 44), maxListHeight))
                .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
            }
        }
    }

    private func rowStack(_ rows: [Session], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows) { session in
                SessionRowView(model: model, session: session, now: now)
            }
        }
    }

    /// Nothing to list. Say what the island can see instead of leaving it at that:
    /// which agents are open, and which of them are not connected yet.
    private var emptyState: some View {
        let running = model.runningAgents
        let wired = Set(model.maintenance.agents.filter(\.wired).map(\.id))
        let unconnected = running.filter { !wired.contains($0) && model.maintenance.agents.map(\.id).contains($0) }
        let names = running.map { AgentRegistry.displayName(for: $0) }
        return VStack(spacing: 9) {
            if running.isEmpty {
                MascotView(sprite: Mascots.island, size: 44, animated: true)
            } else {
                HStack(spacing: 10) {
                    ForEach(running.prefix(6), id: \.self) { MascotView(source: $0, size: 34, animated: true) }
                }
            }
            Text(running.isEmpty ? L("No agents running yet.") : L("All quiet."))
                .font(Theme.title(16)).foregroundStyle(Theme.primary)
            Group {
                if running.isEmpty {
                    Text(wired.isEmpty ? L("Nothing is connected yet. Connecting changes nothing until you say so.")
                         : L("Start an agent and it will show up here."))
                } else {
                    Text(L("%@ open, with nothing happening in the last %lld minutes.",
                           ListFormatter.localizedString(byJoining: names), model.settings.sessionRetentionMinutes))
                }
            }
            .font(Theme.body(12.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if !unconnected.isEmpty {
                Button(L("Connect %@…", ListFormatter.localizedString(byJoining: unconnected.map { AgentRegistry.displayName(for: $0) }))) {
                    model.settingsPage = "agents"
                    model.onOpenSettings?()
                }
                .buttonStyle(PillButtonStyle(kind: .primary, large: true))
                .padding(.top, 4)
            } else if wired.isEmpty {
                Button(L("Connect an agent…")) {
                    model.settingsPage = "agents"
                    model.onOpenSettings?()
                }
                .buttonStyle(PillButtonStyle(kind: .primary, large: true))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 30)
    }

    private func notice(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(12.5, .semibold)).foregroundStyle(Theme.primary)
                Text(detail).font(Theme.body(11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.amber.opacity(0.12)))
        .padding(.bottom, 10)
    }
}

struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Fixed "now" for documentation images, so they do not change on every run.
enum PreviewClock {
    static let now = Date(timeIntervalSince1970: 1_791_800_000)
}
