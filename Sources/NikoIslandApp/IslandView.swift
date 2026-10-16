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
    @Environment(\.look) private var look
    @Environment(\.isStaticPreview) private var isStaticPreview
    @Namespace private var space

    var body: some View {
        let recap = model.isExpanded ? nil : model.recap
        let card = model.isExpanded || recap != nil ? nil : model.completion
        let showsCard = card != nil || recap != nil
        let housing = metrics.hasNotch && !model.isExpanded && !showsCard
        let corner = (model.isExpanded ? 30 : (showsCard ? 24 : 13)) * (housing ? 1 : look.islandRadiusScale)
        let shape = IslandShape(ear: model.isExpanded ? 11 : (showsCard ? 9 : 6), radius: corner)
        // Opening settles with the lightest overshoot; closing is quicker and has none,
        // so the island is out of the way the moment it is not wanted.
        let spring = model.isExpanded || showsCard ? Motion.open(look.motion) : Motion.close(look.motion)
        let lifted = model.isExpanded || showsCard
        let tone = IslandGlance(model: model).tone
        let closed = !model.isExpanded && !showsCard && model.settings.islandGlow
        return VStack(spacing: 0) {
            if model.isExpanded {
                ExpandedIsland(model: model, metrics: metrics)
                    .transition(.islandContent(delay: 0.07))
            } else if let recap {
                RecapCard(model: model, recap: recap, metrics: metrics)
                    .transition(.islandContent(delay: 0.06))
            } else if let card {
                CompletionCard(model: model, completion: card, metrics: metrics)
                    .transition(.islandContent(delay: 0.06))
            } else {
                CollapsedIsland(model: model, metrics: metrics)
                    .transition(.islandContent(delay: 0.04))
            }
        }
        // Pulled down while closed, the island stretches after the fingers.
        .padding(.bottom, model.isExpanded ? 0 : Rubber.band(max(0, model.pull), limit: 22))
        .frame(width: model.isExpanded ? CGFloat(model.settings.islandWidth.points) : nil)
        .background(IslandSurface(shape: shape, style: look.style, housing: housing))
        .overlay {
            // A hairline of light along the island's edge, so it holds its shape against a dark desktop.
            if !housing {
                shape.stroke(LinearGradient(colors: [Color.white.opacity(0.02), Color.white.opacity(0.09)], startPoint: .top, endPoint: .bottom),
                             lineWidth: 1.5)
            }
        }
        .overlay(alignment: .bottom) {
            if closed, tone == .working, !isStaticPreview { ActivitySheen(color: look.accent) }
        }
        .clipShape(shape)
        .contentShape(shape)
        .background {
            if closed, let glow = Self.glow(tone, accent: look.accent) {
                IslandGlow(shape: shape, color: glow.color, breathing: glow.breathing, strength: glow.strength)
                    .id(tone)
            }
        }
        // Pushed up while open, it gives a little, as if pressed back into the edge.
        .scaleEffect(x: 1, y: model.isExpanded ? 1 - Rubber.band(max(0, -model.pull), limit: 40) / 520 : 1, anchor: .top)
        // Two shadows, as light has: a soft ambient one far out and a firmer one close in.
        .shadow(color: .black.opacity(lifted ? 0.32 : 0), radius: 34, y: 18)
        .shadow(color: .black.opacity(lifted ? 0.28 : 0), radius: 8, y: 4)
        .environment(\.islandNamespace, isStaticPreview ? nil : space)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: IslandFrameKey.self, value: proxy.frame(in: .named("island-canvas")))
        })
        .animation(isStaticPreview ? nil : spring, value: model.isExpanded)
        .animation(isStaticPreview ? nil : spring, value: model.toast)
        .animation(isStaticPreview ? nil : Motion.land(look.motion), value: model.completion)
        .animation(isStaticPreview ? nil : Motion.land(look.motion), value: model.recap)
        .animation(isStaticPreview ? nil : spring, value: model.badge)
    }
}

extension IslandBody {
    /// The colour beneath the closed island for what it is saying, if any.
    static func glow(_ tone: IslandGlance.Tone, accent: Color) -> (color: Color, breathing: Bool, strength: Double)? {
        switch tone {
        case .attention: return (Theme.amber, true, 0.9)
        case .working: return (accent, false, 0.3)
        case .done: return (accent, false, 0.6)
        case .failed: return (Theme.coral, false, 0.6)
        case .warning: return (Theme.amber, false, 0.45)
        case .idle, .waiting: return nil
        }
    }
}

/// Resistance that grows with distance: a pull of x points moves the thing less and less,
/// never more than `limit` (the curve scroll views rubber-band with).
enum Rubber {
    static func band(_ x: CGFloat, limit: CGFloat) -> CGFloat {
        guard x > 0, limit > 0 else { return 0 }
        return limit * (1 - 1 / (x * 0.55 / limit + 1))
    }
}

// MARK: - Collapsed

/// What the collapsed island says at a glance.
struct IslandGlance: Equatable {
    enum Tone { case idle, working, waiting, attention, done, failed, warning }
    var source: String?
    /// The session the glance is about, when it is about one.
    var key: SessionKey?
    var text: String
    var tone: Tone
    var count: Int

    @MainActor
    init(model: AppModel) {
        if let toast = model.toast {
            source = toast.key.source
            key = toast.key.sessionID.isEmpty ? nil : toast.key
            text = toast.title
            tone = toast.kind == .failed ? .failed : (toast.kind == .limitWarning || toast.kind == .notice) ? .warning : .done
            count = 0
        } else if let request = model.pending.first {
            let session = model.sessions.first { $0.key == request.sessionKey }
            let project = AutoNamer.projectName(cwd: request.event.cwd) ?? AgentRegistry.displayName(for: request.event.source)
            source = request.event.source
            key = request.sessionKey
            text = L("%@ needs you", session.map { AutoNamer.projectName(cwd: $0.cwd) ?? project } ?? project)
            tone = .attention
            count = model.pending.count
        } else if let working = model.sessions.first(where: { $0.phase == .working }) {
            source = working.source
            key = working.key
            let detail = working.activity.detail.map { " " + $0 } ?? ""
            text = working.activity.localizedVerb + detail
            tone = .working
            count = model.sessions.filter { $0.phase == .working }.count
        } else if let waiting = model.sessions.first {
            source = waiting.source
            key = waiting.key
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

    /// How the creature on the closed island feels.
    var mood: CreatureMood {
        switch tone {
        case .idle: return .idle
        case .working: return .working
        case .waiting, .warning: return .waiting
        case .attention: return .attention
        case .done: return .happy
        case .failed: return .failed
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
        case .warning: return Theme.amber
        }
    }
}

struct CollapsedIsland: View {
    @ObservedObject var model: AppModel
    var metrics: IslandMetrics
    @Environment(\.look) private var look
    @Environment(\.islandNamespace) private var namespace

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
                            .font(look.body(11.5, .semibold))
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
            MascotView(source: source, size: 17, animated: glance.tone != .idle && glance.tone != .waiting,
                       mood: glance.mood, seed: glance.key?.description)
                .travels(glance.key.map { "creature/" + $0.description } ?? "creature/none", in: namespace)
        } else {
            // Nothing is going on: it stays still, so a quiet island costs nothing.
            MascotView(sprite: Mascots.island, size: 17, mood: .idle).opacity(0.8)
                .travels("creature/island", in: namespace)
        }
    }

    @ViewBuilder
    private func marker(_ glance: IslandGlance) -> some View {
        switch glance.tone {
        case .attention:
            HStack(spacing: 3) {
                Image(systemName: "bell.fill").font(.system(size: 9, weight: .bold))
                    .symbolEffect(.bounce, value: glance.count)
                if glance.count > 1 { Text("\(glance.count)").font(look.mono(10, .bold)).contentTransition(.numericText()) }
            }
            .foregroundStyle(Theme.amber)
        case .working:
            if glance.count > 1 {
                Text("\(glance.count)").font(look.mono(10, .bold)).foregroundStyle(look.accent).contentTransition(.numericText())
            } else {
                Circle().fill(look.accent).frame(width: 6, height: 6)
            }
        case .waiting:
            Circle().fill(Theme.amber).frame(width: 6, height: 6)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(look.accent)
        case .failed:
            Image(systemName: "exclamationmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.coral)
        case .warning:
            Image(systemName: "gauge.with.dots.needle.67percent").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.amber)
        case .idle:
            Circle().fill(Theme.quaternary).frame(width: 5, height: 5)
        }
    }
}

// MARK: - Expanded

struct ExpandedIsland: View {
    @Environment(\.look) private var look
    @ObservedObject var model: AppModel
    var metrics: IslandMetrics
    @Environment(\.isStaticPreview) private var isStaticPreview

    /// Plan limits for the agent at the top of the list (the one that needs you, else the latest), when any source has them.
    private var glance: QuotaGlance? {
        guard model.settings.quotaGlance else { return nil }
        var order: [String] = []
        // In the usage view, the agent being looked at comes first.
        if model.route == .usage, model.usageAgent != "all" { order.append(model.usageAgent) }
        for source in model.sessions.map(\.source) where !order.contains(source) { order.append(source) }
        return QuotaGlance.make(usage: model.usage, recentAgents: order, now: isStaticPreview ? PreviewClock.now : Date())
    }

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
                case .sessions: SessionsPane(model: model).transition(.rise)
                case .usage: UsageView(model: model).transition(.rise)
                }
            }
            .animation(Motion.smooth(look.motion), value: model.route)
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
            if let glance {
                QuotaGlanceView(glance: glance, active: model.route == .usage) {
                    withAnimation(Motion.smooth(look.motion)) { model.route = model.route == .usage ? .sessions : .usage }
                }
            } else {
                Text(NikoVersion.displayName).font(look.body(12, .bold)).foregroundStyle(Theme.primary)
            }
            if !metrics.hasNotch {
                Text(summary).font(look.body(11.5)).foregroundStyle(model.pending.isEmpty ? Theme.tertiary : Theme.amber)
            }
            if let update = model.availableUpdate {
                Button {
                    model.settingsPage = "about"
                    model.onOpenSettings?()
                } label: {
                    Chip(text: L("%@ is out", update.version), tint: look.accent)
                }
                .buttonStyle(.plain)
                .help(L("A newer version can be installed from Settings → About."))
            }
            Spacer(minLength: 0)
            if model.sessions.count > 3 {
                IconButton(symbol: "magnifyingglass", label: L("Find a session")) {
                    model.collapse()
                    model.onOpenSwitcher?()
                }
            }
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
    @Environment(\.look) private var look
    @ObservedObject var model: AppModel
    @Environment(\.isStaticPreview) private var isStaticPreview
    @State private var listHeight: CGFloat = 0
    @State private var hovered: SessionKey?
    @Namespace private var hoverSpace

    /// Height of the list before it scrolls: the number of rows the user asked for.
    private var maxListHeight: CGFloat {
        CGFloat(model.settings.visibleRows) * (model.settings.rowDensity == .compact ? 52 : 68)
    }

    var body: some View {
        content.animation(isStaticPreview ? nil : Motion.smooth(look.motion), value: model.focusedRequestID)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .other(let message)? = model.startFailure {
                notice(L("Niko Island could not start listening"), detail: message)
            }
            if let request = model.focusedRequest {
                RequestDetailView(model: model, request: request).id(request.id)
                    .transition(.rise)
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
                .onPreferenceChange(ListHeightKey.self) { height in
                    // The list grows and shrinks to its rows on the same spring as everything else.
                    withAnimation(listHeight == 0 ? nil : Motion.smooth(look.motion)) { listHeight = height }
                }
                .onHover { inside in
                    if !inside { withAnimation(Motion.snappy(look.motion)) { hovered = nil } }
                }
            }
        }
    }

    private func rowStack(_ rows: [Session], now: Date) -> some View {
        let groups = SessionGroups.make(rows, by: model.settings.sessionGrouping)
        // A row you are typing a reply into keeps its card.
        let typing = Set(rows.map(\.key).filter { model.replies[$0] != nil || model.canReply(to: $0) })
        let full = model.settings.compactOlderRows ? RowTiers.full(rows, alwaysFull: typing, now: now) : Set(rows.map(\.key))
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(groups) { group in
                if let title = group.title {
                    HStack(spacing: 6) {
                        if let source = group.source { MascotView(source: source, size: 12) }
                        Text(title.uppercased()).font(look.mono(10, .semibold)).foregroundStyle(Theme.tertiary).lineLimit(1)
                        Text("\(group.sessions.count)").font(look.mono(10)).foregroundStyle(Theme.tertiary.opacity(0.7))
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    .padding(.top, group.id == groups.first?.id ? 2 : 10)
                    .padding(.bottom, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.sessions) { session in
                    SessionRowView(model: model, session: session, now: now, showsProject: model.settings.sessionGrouping != .project,
                                   compact: !full.contains(session.key),
                                   hovered: isStaticPreview ? nil : $hovered, hoverSpace: isStaticPreview ? nil : hoverSpace)
                        .cascade(rows.firstIndex { $0.key == session.key } ?? 0)
                        .transition(.row)
                }
            }
        }
        .animation(isStaticPreview ? nil : Motion.smooth(look.motion), value: rows.map(\.key))
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
                MascotView(sprite: Mascots.island, size: 48, animated: true, mood: .idle)
            } else {
                HStack(spacing: 10) {
                    ForEach(running.prefix(6), id: \.self) { MascotView(source: $0, size: 38, animated: true, mood: .idle) }
                }
            }
            Text(running.isEmpty ? L("No agents running yet.") : L("All quiet."))
                .font(look.title(16)).foregroundStyle(Theme.primary)
            Group {
                if running.isEmpty {
                    Text(wired.isEmpty ? L("Nothing is connected yet. Connecting changes nothing until you say so.")
                         : L("Start an agent and it will show up here."))
                } else {
                    Text(L("%@ open, with nothing happening in the last %lld minutes.",
                           Localization.list(names), model.settings.sessionRetentionMinutes))
                }
            }
            .font(look.body(12.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if !unconnected.isEmpty {
                Button(L("Connect %@…", Localization.list(unconnected.map { AgentRegistry.displayName(for: $0) }))) {
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
                Text(title).font(look.body(12.5, .semibold)).foregroundStyle(Theme.primary)
                Text(detail).font(look.body(11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: look.radius(12), style: .continuous).fill(Theme.amber.opacity(0.12)))
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


/// The list in sections: by project, by agent, or as it comes.
struct SessionGroups {
    struct Group: Identifiable {
        var id: String
        /// nil for the one group of an ungrouped list.
        var title: String?
        /// The agent, when that is what the group is.
        var source: String?
        var sessions: [Session]
    }

    /// Groups keep the order in which their first session appears, so what
    /// needs attention stays at the top; a list with one group gets no heading.
    static func make(_ sessions: [Session], by grouping: NikoSettings.SessionGrouping) -> [Group] {
        guard grouping != .none else { return sessions.isEmpty ? [] : [Group(id: "all", title: nil, source: nil, sessions: sessions)] }
        var order: [String] = []
        var groups: [String: Group] = [:]
        for session in sessions {
            let id = grouping == .project ? (session.cwd ?? "agent:" + session.source) : session.source
            if groups[id] == nil {
                order.append(id)
                groups[id] = Group(id: id, title: grouping == .project ? session.projectName : AgentRegistry.displayName(for: session.source),
                                   source: grouping == .agent ? session.source : nil, sessions: [])
            }
            groups[id]?.sessions.append(session)
        }
        let made = order.compactMap { groups[$0] }
        if made.count == 1, var only = made.first {
            only.title = nil
            return [only]
        }
        return made
    }
}

/// "Claude  5h 31% 2h39m │ 7d 76% 1d" along the top of the open island; a click opens Usage.
struct QuotaGlanceView: View {
    var glance: QuotaGlance
    var active: Bool
    var action: () -> Void
    @Environment(\.look) private var look
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(AgentRegistry.displayName(for: glance.agent)).font(look.body(11.5, .semibold)).foregroundStyle(Theme.primary)
                ForEach(Array(glance.entries.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { Rectangle().fill(Theme.hairline).frame(width: 1, height: 11) }
                    HStack(spacing: 4) {
                        Text(entry.label).foregroundStyle(Theme.tertiary)
                        Text("\(entry.percent)%").fontWeight(.semibold).foregroundStyle(color(entry.level))
                        if let left = entry.resetsIn { Text(left).foregroundStyle(Theme.tertiary) }
                    }
                    .font(look.mono(11))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(active ? 0.12 : hovering ? 0.07 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(Motion.snappy(look.motion)) { hovering = inside } }
        .help(L("Plan limits of %@: open Usage", AgentRegistry.displayName(for: glance.agent)))
        .accessibilityLabel(glance.entries.map { L("%@ window %lld percent used", $0.label, $0.percent) }.joined(separator: ", "))
    }

    private func color(_ level: QuotaGlance.Level) -> Color {
        switch level {
        case .calm: return Theme.mint
        case .warm: return Theme.amber
        case .hot: return Theme.coral
        }
    }
}
