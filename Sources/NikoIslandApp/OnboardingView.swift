import NikoCore
import SwiftUI

/// What the backdrop reads on every frame. Changing it re-renders nothing: the
/// pointer can move and confetti can be thrown without the page being laid out again.
@MainActor
final class BackdropStage {
    let began = Date()
    /// Where the pointer is, from -0.5 to 0.5 across the screen.
    var pointer = CGSize.zero
    var bursts: [Date] = []
    /// Throws the confetti (set by the layer that draws it).
    var onCelebrate: (() -> Void)?
    /// Frames the sea drew in the last second, for the development build's counter.
    var framesPerSecond = 0

    func celebrate() {
        bursts.append(Date())
        if bursts.count > 4 { bursts.removeFirst() }
        onCelebrate?()
    }
}

/// The welcome a new user sees once: a night sea across the whole screen, the
/// island dropping in where it will live, the agents found on this Mac ready
/// to connect with one click, and the few choices worth making up front.
///
/// Everything is laid out in units of `u` (one point on a 900-point-tall
/// screen), so a large display gets a large welcome that is drawn at that
/// size. Nothing with text in it is ever magnified.
struct OnboardingView: View {
    var model: AppModel
    var metrics: IslandMetrics = .plain
    var onFinish: () -> Void

    enum Step: Int, CaseIterable { case welcome, agents, tour, preferences, done }

    @State var step: Step = .welcome
    @State private var appeared = false
    /// The title and the creatures have made their entrance.
    @State private var revealed = false
    @State private var selected: Set<String> = []
    @State private var selectionSeeded = false
    @State private var connecting = false
    @State private var connectedNow: Set<String> = []
    @State private var stage = BackdropStage()
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var look: IslandLook { IslandLook(settings: model.settings) }
    private var shown: Bool { revealed || isStaticPreview }

    static func unit(for size: CGSize) -> CGFloat {
        min(1.6, max(0.72, min(size.height / 900, size.width / 1280)))
    }

    var body: some View {
        GeometryReader { proxy in
            let u = Self.unit(for: proxy.size)
            ZStack(alignment: .top) {
                SeaBackdrop(stage: stage, unit: u, accent: look.accent, islandBottom: metrics.bandHeight)
                DemoIsland(model: model, metrics: metrics, stage: demoStage)
                    .offset(y: appeared || isStaticPreview ? 0 : -(metrics.bandHeight + 40))
                    // The island drops into place and bites into the top edge with one small give.
                    .animation(.spring(response: 0.62, dampingFraction: 0.66).delay(0.25), value: appeared)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content(u)
                        .id(step)
                        // Pages slide and fade; they are never scaled, which would soften every letter on them mid-way.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 22 * u)).animation(Motion.fadeIn(0.42).delay(0.08)),
                            removal: .opacity.combined(with: .offset(y: -14 * u)).animation(Motion.fadeOut(0.18))))
                    Spacer(minLength: 0)
                    footer(u)
                        .padding(.bottom, 46 * u)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(1.25), value: revealed)
                }
                .padding(.horizontal, 40)
                .padding(.top, metrics.bandHeight + 70 * u)

                if UserDefaults.standard.bool(forKey: "NikoShowFrameRate") {
                    // Development only: how many frames the sea drew in the last second.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(stage.framesPerSecond) fps").font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8)).padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.5)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
                    .padding(.top, metrics.bandHeight + 22 * u)
                }
                HStack {
                    Spacer()
                    if step != .done {
                        Button(L("Skip")) { finish() }
                            .buttonStyle(WelcomeButtonStyle(kind: .ghost, unit: u))
                            .padding(.trailing, 28 * u)
                            .padding(.top, metrics.bandHeight + 22 * u)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard case .active(let point) = phase, proxy.size.width > 0, proxy.size.height > 0 else { return }
                stage.pointer = CGSize(width: point.x / proxy.size.width - 0.5, height: point.y / proxy.size.height - 0.5)
            }
            .environment(\.look, scaledLook(u))
        }
        .environment(\.colorScheme, .dark)
        .opacity(appeared || isStaticPreview ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: appeared)
        .onAppear {
            appeared = true
            model.refreshMaintenance()
            // The island lands first; then the page makes its entrance.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { revealed = true }
        }
        .onChange(of: step) { _, new in
            if new == .done { stage.celebrate() }
        }
    }

    /// Chips and other shared pieces follow the page's size.
    private func scaledLook(_ u: CGFloat) -> IslandLook {
        var look = self.look
        look.textScale = u
        return look
    }

    // MARK: Steps

    @ViewBuilder
    private func content(_ u: CGFloat) -> some View {
        switch step {
        case .welcome: welcome(u)
        case .agents: agents(u)
        case .tour: tour(u)
        case .preferences: preferences(u)
        case .done: done(u)
        }
    }

    private var demoStage: DemoIsland.Stage {
        switch step {
        case .welcome: return .hello
        case .agents: return connecting ? .working : .idle
        case .tour: return .cycle
        case .preferences: return .working
        case .done: return .done
        }
    }

    private func go(_ next: Step) {
        withAnimation(Motion.smooth()) { step = next }
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { go(next) } else { finish() }
    }

    private func finish() {
        model.settings.onboardingDone = true
        onFinish()
    }

    private func rounded(_ size: CGFloat, _ weight: Font.Weight, _ u: CGFloat) -> Font {
        .system(size: size * u, weight: weight, design: .rounded)
    }

    private func text(_ size: CGFloat, _ weight: Font.Weight = .regular, _ u: CGFloat) -> Font {
        .system(size: size * u, weight: weight)
    }

    // MARK: Welcome

    private func welcome(_ u: CGFloat) -> some View {
        let title = Array(NikoVersion.displayName)
        return VStack(spacing: 24 * u) {
            // The cast walks on, one after another.
            HStack(spacing: 15 * u) {
                ForEach(Array(Mascots.all.enumerated()), id: \.offset) { index, sprite in
                    Bobbing(delay: Double(index) * 0.11, travel: 6 * u) {
                        MascotView(sprite: sprite, size: 48 * u, animated: true, mood: .idle, seed: sprite.name)
                    }
                    // Up from below, never scaled: a pixel creature drawn small and enlarged is a blurred one.
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 34 * u)
                    .animation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.55 + Double(index) * 0.06), value: revealed)
                }
            }
            VStack(spacing: 12 * u) {
                // The name arrives a letter at a time, then a light passes over it.
                HStack(spacing: 0) {
                    ForEach(Array(title.enumerated()), id: \.offset) { index, character in
                        // Each letter rises out of its own line, as type set from below: sharp all the way.
                        Text(String(character))
                            .font(rounded(92, .heavy, u))
                            .foregroundStyle(LinearGradient(colors: [.white, Color.white.opacity(0.74)], startPoint: .top, endPoint: .bottom))
                            .offset(y: shown ? 0 : 118 * u)
                            .opacity(shown ? 1 : 0.0)
                            .padding(.vertical, 8 * u)
                            .clipped()
                            .padding(.vertical, -8 * u)
                            .animation(.spring(response: 0.72, dampingFraction: 0.8).delay(Double(index) * 0.038), value: revealed)
                    }
                }
                .overlay { if !isStaticPreview { Shimmer(delay: 1.5) .mask(Text(NikoVersion.displayName).font(rounded(92, .heavy, u))) } }
                .shadow(color: look.accent.opacity(0.42), radius: 44 * u, y: 10 * u)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NikoVersion.displayName)

                Text(L("An island at the top of your screen for the agents that write your code."))
                    .font(rounded(22, .medium, u))
                    .foregroundStyle(Theme.primary.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 12 * u)
                    .animation(Motion.fadeIn(0.7).delay(0.62), value: revealed)
            }
            Text(L("See what each one is doing, approve and answer where you are, and go back to the right window when you want to."))
                .font(text(15.5, .regular, u))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580 * u)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 8 * u)
                .animation(Motion.fadeIn(0.7).delay(0.86), value: revealed)
        }
    }

    // MARK: Agents

    private var rows: [MaintenanceState.AgentRow] { model.maintenance.agents }

    /// What is ticked. Until the user touches a card: everything we can vouch
    /// for; adapters taken on trust are offered, unticked.
    private var chosen: Set<String> {
        selectionSeeded ? selected : Set(rows.filter { !$0.wired && $0.stability != .experimental }.map(\.id))
    }

    private func toggle(_ id: String) {
        var next = chosen
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        selected = next
        selectionSeeded = true
    }

    private func agents(_ u: CGFloat) -> some View {
        let pending = rows.filter { chosen.contains($0.id) && !$0.wired }
        return VStack(spacing: 20 * u) {
            stepTitle(rows.isEmpty ? L("No agents found yet") : L("These agents are on your Mac"),
                      rows.isEmpty ? L("Install one, then connect it from Settings. The island also finds Claude Code, Codex and ZCode sessions by itself.")
                      : L("Connecting adds a few entries tagged niko-bridge to each agent's own config, after a backup. Nothing else is touched, and Settings takes them out again."), u)
            if !rows.isEmpty {
                let columns = rows.count > 8 ? 3 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10 * u), count: columns), spacing: 10 * u) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Arriving(delay: 0.12 + Double(index) * 0.035, rise: 18 * u) { agentCard(row, u) }
                    }
                }
                .frame(maxWidth: (columns == 3 ? 900 : 700) * u)
            }
            if let message = followUps, !message.isEmpty {
                Text(message)
                    .font(text(12.5, .regular, u)).foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.center).frame(maxWidth: 640 * u)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !pending.isEmpty {
                Button {
                    connecting = true
                    connectedNow.formUnion(pending.map(\.id))
                    model.runInstaller(.install, agents: pending.map(\.id))
                } label: {
                    Text(model.maintenance.busy ? L("Connecting…") : L("Connect %lld agents", pending.count))
                }
                .buttonStyle(WelcomeButtonStyle(kind: .primary, unit: u, glow: look.accent))
                .disabled(model.maintenance.busy)
            }
        }
        .onChange(of: model.maintenance.busy) { _, busy in
            guard !busy, connecting else { return }
            connecting = false
            if rows.contains(where: { $0.wired && connectedNow.contains($0.id) }) { stage.celebrate() }
        }
    }

    /// What the user still has to do in an agent after connecting it.
    private var followUps: String? {
        let notes = rows.filter { $0.wired && connectedNow.contains($0.id) }.compactMap { row in
            row.followUp.map { L($0) }
        }
        return notes.isEmpty ? nil : notes.joined(separator: "\n")
    }

    private func agentCard(_ row: MaintenanceState.AgentRow, _ u: CGFloat) -> some View {
        let isOn = chosen.contains(row.id)
        let running = model.runningAgents.contains(row.id)
        let accent = look.accent
        let shape = RoundedRectangle(cornerRadius: 18 * u, style: .continuous)
        return Button {
            guard !row.wired else { return }
            toggle(row.id)
        } label: {
            HStack(spacing: 12 * u) {
                MascotView(source: row.id, size: 40 * u, animated: running || (row.wired && connectedNow.contains(row.id)),
                           mood: row.wired && connectedNow.contains(row.id) ? .happy : .idle)
                VStack(alignment: .leading, spacing: 4 * u) {
                    HStack(spacing: 6 * u) {
                        Text(row.name).font(rounded(16, .bold, u)).foregroundStyle(Theme.primary).lineLimit(1).fixedSize()
                        if row.stability == .beta { Chip(text: L("beta"), tint: Theme.sky, mono: false) }
                        if row.stability == .experimental { Chip(text: L("experimental"), tint: Theme.amber, mono: false) }
                    }
                    HStack(spacing: 5 * u) {
                        if row.wired {
                            Text(L("connected")).foregroundStyle(accent)
                            Text("·").foregroundStyle(Theme.quaternary)
                        } else if running {
                            Circle().fill(accent).frame(width: 6 * u, height: 6 * u)
                            Text(L("running now")).foregroundStyle(accent)
                            Text("·").foregroundStyle(Theme.quaternary)
                        }
                        Text(row.approvals ? L("status and approvals") : L("status")).foregroundStyle(Theme.tertiary)
                    }
                    .font(text(12, .regular, u))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: row.wired ? "checkmark.seal.fill" : (isOn ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 22 * u, weight: .semibold))
                    .foregroundStyle(row.wired || isOn ? accent : Theme.quaternary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16 * u)
            .padding(.vertical, 14 * u)
            .background(shape.fill(Color.black.opacity(0.46)))
            .overlay(shape.strokeBorder(isOn || row.wired ? accent.opacity(0.6) : Color.white.opacity(0.10), lineWidth: 1.2 * u))
            .shadow(color: accent.opacity(isOn || row.wired ? 0.18 : 0), radius: 14 * u)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: row.wired)
        .animation(.easeOut(duration: 0.18), value: isOn)
    }

    // MARK: Tour

    private func tour(_ u: CGFloat) -> some View {
        VStack(spacing: 26 * u) {
            stepTitle(L("Small while they work, open when they need you"),
                      L("Watch the island at the top of the screen: this is what it does all day."), u)
            HStack(alignment: .top, spacing: 14 * u) {
                Arriving(delay: 0.10, rise: 22 * u) {
                    tourCard("capsule.fill", L("Out of the way"),
                             L("One creature and a few words. It rests on your menu bar and leaves with it when an app goes full screen."), u)
                }
                Arriving(delay: 0.20, rise: 22 * u) {
                    tourCard("hand.tap.fill", L("Decide in place"),
                             L("When an agent wants to run something, the island opens with the command. Allow, deny, or send it back to the terminal."), u)
                }
                Arriving(delay: 0.30, rise: 22 * u) {
                    tourCard("arrow.up.forward.app.fill", L("Back in one click"),
                             L("Click a session and its terminal tab or app comes forward. Sessions show up even for agents you have not connected."), u)
                }
            }
            .frame(maxWidth: 880 * u)
        }
    }

    private func tourCard(_ symbol: String, _ title: String, _ body: String, _ u: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
        return VStack(alignment: .leading, spacing: 10 * u) {
            Image(systemName: symbol).font(.system(size: 22 * u, weight: .semibold)).foregroundStyle(look.accent)
            Text(title).font(rounded(17, .bold, u)).foregroundStyle(Theme.primary)
            Text(body).font(text(13, .regular, u)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18 * u)
        .frame(maxWidth: .infinity, minHeight: 168 * u, alignment: .topLeading)
        .background(shape.fill(Color.black.opacity(0.46)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: u))
    }

    // MARK: Preferences

    private func preferences(_ u: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
        return VStack(spacing: 22 * u) {
            stepTitle(L("Make it yours"), L("Everything here can be changed later in Settings."), u)
            VStack(spacing: 0) {
                preferenceRow(L("Colour"), L("For sessions at work and for the things you can press."), u) {
                    HStack(spacing: 10 * u) {
                        ForEach(NikoSettings.Accent.allCases, id: \.self) { accent in
                            Button { model.settings.accent = accent } label: {
                                Circle().fill(Theme.color(for: accent)).frame(width: 24 * u, height: 24 * u)
                                    .overlay(Circle().strokeBorder(Color.white, lineWidth: model.settings.accent == accent ? 2.5 * u : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.rawValue)
                        }
                    }
                }
                divider
                preferenceRow(L("Sounds"), L("A short cue when an agent needs you or finishes. Generated by the app, off unless you want them."), u) {
                    HStack(spacing: 8 * u) {
                        if model.settings.soundsEnabled {
                            Button { model.onPreviewSound?(.completed) } label: { Image(systemName: "play.fill").font(.system(size: 11 * u)) }
                                .buttonStyle(WelcomeButtonStyle(kind: .neutral, unit: u, compact: true))
                                .accessibilityLabel(L("Play this sound"))
                        }
                        Toggle(isOn: Binding(get: { model.settings.soundsEnabled }, set: { enabled in
                            model.settings.soundsEnabled = enabled
                            if enabled { model.onPreviewSound?(.completed) }
                        })) { EmptyView() }.toggleStyle(SwitchToggleStyle(scale: u)).frame(width: 46 * u)
                    }
                }
                divider
                preferenceRow(L("Full-screen apps"), L("Where there is no menu bar."), u) {
                    ChoicePills(options: [(FullScreenPolicy.followMenuBar, L("Follow the menu bar")), (.always, L("Always show")), (.never, L("Never"))],
                                selection: Binding(get: { model.settings.fullScreenPolicy }, set: { model.settings.fullScreenPolicy = $0 }), scale: u)
                }
                divider
                preferenceRow(L("Open Niko Island at login"), nil, u) {
                    Toggle(isOn: Binding(get: { LoginItem.isEnabled }, set: { _ = LoginItem.set($0) })) { EmptyView() }
                        .toggleStyle(SwitchToggleStyle(scale: u)).frame(width: 46 * u)
                }
            }
            .padding(.horizontal, 20 * u)
            .padding(.vertical, 6 * u)
            .frame(maxWidth: 720 * u)
            .background(shape.fill(Color.black.opacity(0.46)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: u))
        }
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    private func preferenceRow<Trailing: View>(_ title: String, _ detail: String?, _ u: CGFloat, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14 * u) {
            VStack(alignment: .leading, spacing: 3 * u) {
                Text(title).font(text(14.5, .semibold, u)).foregroundStyle(Theme.primary)
                if let detail {
                    Text(detail).font(text(12, .regular, u)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12 * u)
            trailing()
        }
        .padding(.vertical, 14 * u)
    }

    // MARK: Done

    private func done(_ u: CGFloat) -> some View {
        VStack(spacing: 20 * u) {
            // Everybody turns up for the send-off.
            HStack(alignment: .bottom, spacing: 12 * u) {
                ForEach(Array(Mascots.all.enumerated()), id: \.offset) { index, sprite in
                    let centre = sprite.name == Mascots.island.name
                    Bobbing(delay: Double(index) * 0.09, travel: (centre ? 5 : 12) * u, period: centre ? 1.5 : 0.62) {
                        MascotView(sprite: sprite, size: (centre ? 84 : 40) * u, animated: true, mood: .happy, seed: sprite.name)
                    }
                }
            }
            Text(L("You are all set")).font(rounded(58, .heavy, u)).foregroundStyle(Theme.primary)
                .shadow(color: look.accent.opacity(0.4), radius: 36 * u, y: 8 * u)
            Text(model.settings.hotkeyEnabled
                 ? L("Rest the pointer on the island to open it, or press ⌃⌥I from anywhere.")
                 : L("Rest the pointer on the island to open it."))
                .font(rounded(18.5, .medium, u)).foregroundStyle(Theme.primary.opacity(0.82))
            Text(L("The gear on the island opens Settings. This welcome is under About, if you want to see it again."))
                .font(text(13.5, .regular, u)).foregroundStyle(Theme.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private func stepTitle(_ title: String, _ subtitle: String, _ u: CGFloat) -> some View {
        VStack(spacing: 10 * u) {
            Text(title).font(rounded(40, .heavy, u)).foregroundStyle(Theme.primary)
                .multilineTextAlignment(.center)
                .shadow(color: look.accent.opacity(0.25), radius: 30 * u, y: 6 * u)
            Text(subtitle).font(text(15, .regular, u)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 660 * u).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private func footer(_ u: CGFloat) -> some View {
        VStack(spacing: 18 * u) {
            HStack(spacing: 10 * u) {
                if step != .welcome, step != .done {
                    Button(L("Back")) { go(Step(rawValue: step.rawValue - 1) ?? .welcome) }
                        .buttonStyle(WelcomeButtonStyle(kind: .neutral, unit: u))
                }
                // While something is ticked to connect, that button is the main one; this one steps aside.
                Button(primaryTitle) { advance() }
                    .buttonStyle(WelcomeButtonStyle(kind: step == .agents && hasPending ? .neutral : .primary, unit: u, glow: look.accent))
                    .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 7 * u) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule().fill(item == step ? Color.white : Color.white.opacity(0.22))
                        .frame(width: (item == step ? 22 : 7) * u, height: 7 * u)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
                }
            }
        }
    }

    private var hasPending: Bool { rows.contains { chosen.contains($0.id) && !$0.wired } }

    private var primaryTitle: String {
        switch step {
        case .welcome: return L("Get started")
        case .agents: return hasPending ? L("Not now") : L("Continue")
        case .tour, .preferences: return L("Continue")
        case .done: return L("Start using Niko Island")
        }
    }
}

// MARK: - Pieces

/// The welcome's own buttons: the island's pills, at the size of the page.
struct WelcomeButtonStyle: ButtonStyle {
    enum Kind { case primary, neutral, ghost }
    var kind: Kind = .neutral
    var unit: CGFloat = 1
    var glow: Color?
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration, style: self)
    }

    private struct Label: View {
        let configuration: Configuration
        let style: WelcomeButtonStyle
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let u = style.unit
            let fill: Color = style.kind == .primary ? .white : (style.kind == .neutral ? Color.white.opacity(hovering ? 0.2 : 0.13) : .clear)
            let ink: Color = style.kind == .primary ? .black : (style.kind == .ghost ? Theme.secondary.opacity(hovering ? 1 : 0.8) : .white)
            configuration.label
                .font(.system(size: 14.5 * u, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, (style.compact ? 12 : 22) * u)
                .padding(.vertical, (style.compact ? 7 : 11) * u)
                .foregroundStyle(ink)
                .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.7 : 1)))
                .shadow(color: (style.kind == .primary ? style.glow ?? .clear : .clear).opacity(hovering ? 0.75 : 0.42), radius: (hovering ? 26 : 16) * u)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.55)
                .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.2), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// A gentle up-and-down, out of step with its neighbours.
private struct Bobbing<Content: View>: View {
    var delay: Double
    var travel: CGFloat = 6
    var period = 1.5
    @ViewBuilder var content: Content
    @State private var up = false
    @Environment(\.isStaticPreview) private var isStaticPreview

    var body: some View {
        content
            .offset(y: up ? -travel : travel * 0.7)
            .onAppear {
                guard !isStaticPreview else { return }
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true).delay(delay)) { up = true }
            }
    }
}

/// Comes up into place a moment after it appears; the neighbours follow one by one.
private struct Arriving<Content: View>: View {
    var delay: Double
    var rise: CGFloat
    @ViewBuilder var content: Content
    @State private var arrived = false
    @Environment(\.isStaticPreview) private var isStaticPreview

    var body: some View {
        content
            .opacity(arrived || isStaticPreview ? 1 : 0)
            .offset(y: arrived || isStaticPreview ? 0 : rise)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(delay)) { arrived = true }
            }
    }
}

/// A band of light that crosses whatever it is masked to, now and then.
private struct Shimmer: View {
    var delay: Double
    @State private var across = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(colors: [.clear, Color.white.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.28)
                .rotationEffect(.degrees(18))
                .offset(x: across ? width * 1.15 : -width * 0.45)
                .blendMode(.plusLighter)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.25).delay(delay).repeatForever(autoreverses: false).speed(0.42)) { across = true }
                }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The island, performing

/// A stand-in for the island, drawn where the real one sits, that acts out
/// what the real one does. It never touches real sessions.
struct DemoIsland: View {
    var model: AppModel
    var metrics: IslandMetrics
    var stage: Stage

    enum Stage: Equatable { case hello, idle, working, cycle, done }
    private enum Act: Equatable { case hello, idle, working, asking, finished }

    @State private var cycle = 0
    @Environment(\.look) private var look
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var act: Act {
        switch stage {
        case .hello: return .hello
        case .idle: return .idle
        case .working: return .working
        case .done: return .finished
        case .cycle: return [.working, .asking, .finished][cycle % 3]
        }
    }

    var body: some View {
        let open = act == .asking
        let shape = IslandShape(ear: open ? 10 : 6, radius: open ? 28 : 13)
        VStack(spacing: 0) {
            if open { asking } else { resting }
        }
        .frame(width: open ? 520 : nil)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(open ? 0.6 : 0.35), radius: open ? 30 : 14, y: 10)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: act)
        .task(id: stage) {
            guard stage == .cycle, !isStaticPreview else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                cycle += 1
            }
        }
    }

    private var resting: some View {
        HStack(spacing: 7) {
            switch act {
            case .hello:
                MascotView(sprite: Mascots.island, size: 17, animated: true, mood: .happy)
                Text(L("Hello")).foregroundStyle(Theme.primary)
            case .idle:
                MascotView(sprite: Mascots.island, size: 17)
                Text(NikoVersion.displayName).foregroundStyle(Theme.tertiary)
            case .working:
                MascotView(source: "claude", size: 17, animated: true)
                Text(L("running") + " swift test").foregroundStyle(Theme.primary.opacity(0.9))
                Circle().fill(look.accent).frame(width: 6, height: 6)
            case .finished:
                MascotView(source: "claude", size: 17, animated: true, mood: .happy)
                Text(L("Finished")).foregroundStyle(look.accent)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(look.accent)
            case .asking:
                EmptyView()
            }
        }
        .font(Theme.body(11.5, .semibold))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: metrics.bandHeight)
    }

    private var asking: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MascotView(source: "claude", size: 30, animated: true, mood: .attention)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("%@ wants to run a command", "Claude Code")).font(Theme.title(15)).foregroundStyle(Theme.primary)
                    Text(L("Nothing happens until you decide. The agent is waiting.")).font(Theme.body(11.5)).foregroundStyle(Theme.secondary)
                }
            }
            Text("git push origin main")
                .font(Theme.mono(12, .regular)).foregroundStyle(Theme.primary.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.field))
            HStack(spacing: 8) {
                Text(L("Allow once")).pill(primary: true)
                Text(L("Allow all")).pill()
                Spacer(minLength: 0)
                Text(L("Deny")).pill(tint: Theme.coral)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }
}

private extension Text {
    /// The look of a pill button, for the demo's lookalikes.
    func pill(primary: Bool = false, tint: Color? = nil) -> some View {
        self.font(Theme.body(12.5, .semibold))
            .foregroundStyle(primary ? Color.black : (tint ?? Theme.primary))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(primary ? Color.white : (tint?.opacity(0.16) ?? Color.white.opacity(0.12))))
    }
}

// MARK: - Backdrop

/// A night sea: curtains of light in the sky, stars that lean away from the
/// pointer, three bands of waves, and creatures going about their business,
/// each facing the way it swims. Drawn, not filmed, at the display's own
/// resolution; only the aurora, which is soft by nature, is drawn small and
/// stretched.
struct SeaBackdrop: View {
    var stage: BackdropStage
    var unit: CGFloat = 1
    var accent: Color = Theme.mint
    /// Where the island ends: the opening ripple and the confetti start there.
    var islandBottom: CGFloat = 26
    @Environment(\.isStaticPreview) private var isStaticPreview

    var body: some View {
        if isStaticPreview {
            GeometryReader { proxy in
                if let image = SeaShader.image(size: proxy.size, backing: 2, unit: unit, accent: accent, islandBottom: islandBottom,
                                               time: 12.4, intro: 30) {
                    ZStack {
                        Image(decorative: image, scale: 2).resizable()
                        swimmers(time: 12.4)
                    }
                } else {
                    scene(time: 12.4, intro: 30, pointer: .zero, bursts: [])
                }
            }
            .ignoresSafeArea()
        } else if SeaShader.pipeline != nil {
            // The GPU draws the sea at the display's own resolution and refresh;
            // Core Animation moves the creatures and throws the confetti.
            ZStack {
                SeaMetalView(stage: stage, unit: unit, accent: accent, islandBottom: islandBottom)
                CreatureStageView(stage: stage, unit: unit, accent: accent, islandBottom: islandBottom)
            }
            .ignoresSafeArea()
        } else {
            // No Metal (a virtual machine, say): the same scene drawn by the CPU.
            TimelineView(.animation) { context in
                let now = context.date
                scene(time: now.timeIntervalSinceReferenceDate, intro: now.timeIntervalSince(stage.began), pointer: stage.pointer,
                      bursts: stage.bursts.map { now.timeIntervalSince($0) }.filter { $0 < Confetti.lifetime })
            }
        }
    }

    /// The creatures where they are at `time`, for documentation images.
    private func swimmers(time: Double) -> some View {
        let u = Double(unit)
        return GeometryReader { proxy in
            let width = Double(proxy.size.width), height = Double(proxy.size.height)
            let whale = travel(time, period: 44, offset: 0.12)
            swimmer(Mascots.sprite(for: "codex"), size: 66 * unit, facesLeft: false, movingRight: true,
                    x: whale * (width + 240 * u) - 120 * u, y: height * 0.752 + sin(time * 0.5) * 8 * u, tilt: 0)
            let boat = travel(time, period: 68, offset: 0.55)
            swimmer(Mascots.sprite(for: "claude"), size: 60 * unit, facesLeft: true, movingRight: false,
                    x: (1 - boat) * (width + 240 * u) - 120 * u, y: height * 0.668 + sin(time * 0.9 + 1) * 5 * u, tilt: 0)
            let turtle = travel(time, period: 58, offset: 0.8)
            swimmer(Mascots.sprite(for: "kiro"), size: 44 * unit, facesLeft: false, movingRight: true,
                    x: turtle * (width + 200 * u) - 100 * u, y: height * 0.91 + sin(time * 0.7 + 2) * 9 * u, tilt: 0)
            swimmer(Mascots.sprite(for: "gemini"), size: 40 * unit, facesLeft: true, movingRight: false,
                    x: width * 0.86 + sin(time * 0.3) * 26 * u, y: height * 0.90 + cos(time * 0.6) * 14 * u, tilt: 0)
            let gull = travel(time, period: 29, offset: 0.7)
            swimmer(Mascots.sprite(for: "copilot"), size: 34 * unit, facesLeft: false, movingRight: true,
                    x: gull * (width + 160 * u) - 80 * u, y: height * 0.19 + sin(time * 1.3) * 12 * u, tilt: 0)
        }
        .allowsHitTesting(false)
    }

    private func scene(time: Double, intro: Double, pointer: CGSize, bursts: [Double]) -> some View {
        let u = Double(unit)
        let accent = accent
        let islandBottom = Double(islandBottom)
        // The night comes up out of black as the welcome begins.
        let dawn = min(1, max(0, (intro - 0.15) / 1.6))
        return ZStack {
            Canvas { context, size in
                Self.sky(&context, size: size, time: time, intro: intro, pointer: pointer, accent: accent, u: u, islandBottom: islandBottom)
            }
            aurora(time: time, pointer: pointer, accent: accent)
                .opacity(0.85 * min(1, max(0, (intro - 0.5) / 2.2)))
                .blendMode(.screen)
            Canvas { context, size in
                Self.sea(&context, size: size, time: time, pointer: pointer, accent: accent, u: u)
            }
            // Passers-by.
            GeometryReader { proxy in
                let width = Double(proxy.size.width), height = Double(proxy.size.height)
                let whale = travel(time, period: 44, offset: 0.12)
                swimmer(Mascots.sprite(for: "codex"), size: 66 * unit, facesLeft: false, movingRight: true,
                        x: whale * (width + 240 * u) - 120 * u, y: height * 0.752 + sin(time * 0.5) * 8 * u, tilt: sin(time * 0.5 + 1.2) * 4)
                let boat = travel(time, period: 68, offset: 0.55)
                swimmer(Mascots.sprite(for: "claude"), size: 60 * unit, facesLeft: true, movingRight: false,
                        x: (1 - boat) * (width + 240 * u) - 120 * u, y: height * 0.668 + sin(time * 0.9 + 1) * 5 * u, tilt: sin(time * 0.9) * 5)
                let turtle = travel(time, period: 58, offset: 0.8)
                swimmer(Mascots.sprite(for: "kiro"), size: 44 * unit, facesLeft: false, movingRight: true,
                        x: turtle * (width + 200 * u) - 100 * u, y: height * 0.91 + sin(time * 0.7 + 2) * 9 * u, tilt: sin(time * 0.7) * 3)
                swimmer(Mascots.sprite(for: "gemini"), size: 40 * unit, facesLeft: true, movingRight: false,
                        x: width * 0.86 + sin(time * 0.3) * 26 * u, y: height * 0.90 + cos(time * 0.6) * 14 * u, tilt: sin(time * 0.3) * 6)
                let gull = travel(time, period: 29, offset: 0.7)
                swimmer(Mascots.sprite(for: "copilot"), size: 34 * unit, facesLeft: false, movingRight: true,
                        x: gull * (width + 160 * u) - 80 * u, y: height * 0.19 + sin(time * 1.3) * 12 * u, tilt: sin(time * 1.3) * 5)
            }
            .allowsHitTesting(false)
            if !bursts.isEmpty {
                Canvas { context, size in
                    for age in bursts { Confetti.draw(&context, size: size, age: age, origin: CGPoint(x: size.width / 2, y: islandBottom), u: u, accent: accent) }
                }
                .allowsHitTesting(false)
            }
            Color.black.opacity(1 - dawn).allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func travel(_ time: Double, period: Double, offset: Double) -> Double {
        (time / period + offset).truncatingRemainder(dividingBy: 1)
    }

    /// A creature in the scene, mirrored when it would otherwise swim backwards.
    private func swimmer(_ sprite: MascotSprite, size: CGFloat, facesLeft: Bool, movingRight: Bool, x: Double, y: Double, tilt: Double) -> some View {
        let mirrored = facesLeft == movingRight
        return MascotView(sprite: sprite, size: size, animated: true, mood: .idle, seed: sprite.name)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .rotationEffect(.degrees(tilt))
            .opacity(0.92)
            .position(x: x, y: y)
    }

    // MARK: Aurora

    /// Curtains of light. Drawn at a sixth of the size and stretched: it is all
    /// blur anyway, and this way it costs next to nothing on a 5K display.
    private func aurora(time: Double, pointer: CGSize, accent: Color) -> some View {
        GeometryReader { proxy in
            let factor: CGFloat = 6
            Canvas { context, size in
                let width = Double(size.width), height = Double(size.height)
                context.addFilter(.blur(radius: 3.5))
                let curtains: [(Color, Double, Double, Double, Double)] = [
                    (accent, 0.20, 0.016, 0.21, 0.0), (Theme.sky, 0.27, 0.011, 0.16, 2.1), (Theme.violet, 0.15, 0.021, 0.27, 4.0),
                ]
                let drift = Double(pointer.width) * 10
                for (color, level, frequency, speed, phase) in curtains {
                    var x = -4.0
                    while x < width + 4 {
                        let wave = sin(x * frequency * 6 + time * speed + phase) + 0.5 * sin(x * frequency * 14 - time * speed * 1.6 + phase * 2)
                        let top = height * (level + 0.045 * wave)
                        let fall = height * (0.20 + 0.07 * sin(x * 0.11 + time * 0.23 + phase))
                        // Rays: brighter and dimmer bands that wander along the curtain.
                        let ray = 0.5 + 0.5 * sin(x * 0.75 + time * 0.9 + phase * 3) * sin(x * 0.21 - time * 0.4)
                        let alpha = 0.16 + 0.42 * max(0, ray)
                        let rect = CGRect(x: x + drift, y: top, width: 3.2, height: fall)
                        context.fill(Path(rect), with: .linearGradient(
                            Gradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color.opacity(alpha), location: 0.22),
                                             .init(color: color.opacity(alpha * 0.45), location: 0.6), .init(color: color.opacity(0), location: 1)]),
                            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + fall)))
                        x += 3
                    }
                }
            }
            .frame(width: proxy.size.width / factor, height: proxy.size.height / factor)
            .scaleEffect(factor, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    // MARK: Sky

    nonisolated private static func sky(_ context: inout GraphicsContext, size: CGSize, time: Double, intro: Double, pointer: CGSize,
                            accent: Color, u: Double, islandBottom: Double) {
        let width = Double(size.width), height = Double(size.height)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [Color(red: 0.010, green: 0.012, blue: 0.030), Color(red: 0.018, green: 0.060, blue: 0.120), Color(red: 0.020, green: 0.115, blue: 0.165)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))

        // Slow light behind everything; it leans a little towards the pointer.
        let lights: [(Color, Double, Double, Double, Double)] = [
            (accent, 0.22, 0.28, 0.10, 0.0), (Theme.sky, 0.74, 0.22, 0.08, 1.7),
            (Theme.violet, 0.50, 0.44, 0.07, 3.1), (Theme.coral, 0.88, 0.54, 0.045, 4.4),
        ]
        for (color, x, y, strength, phase) in lights {
            let centre = CGPoint(x: width * (x + 0.05 * sin(time * 0.07 + phase) + Double(pointer.width) * 0.03),
                                 y: height * (y + 0.04 * cos(time * 0.05 + phase) + Double(pointer.height) * 0.03))
            let radius = width * 0.34
            context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [color.opacity(strength * 2.2), color.opacity(0)]),
                                               center: centre, startRadius: 0, endRadius: radius))
        }

        // Stars: square, as befits the creatures. Near ones shift more when the pointer moves.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        for index in 0..<150 {
            let depth = 0.25 + next() * 0.75
            let x = next() * width - Double(pointer.width) * 46 * u * depth
            let y = next() * height * 0.64 - Double(pointer.height) * 30 * u * depth
            let side = (depth > 0.82 ? 3.0 : 2.0) * max(1, u * 0.9)
            let twinkle = 0.22 + 0.78 * abs(sin(time * (0.4 + next()) + next() * 6.28))
            // They come out one after another as the night arrives.
            let lit = min(1, max(0, (intro - 0.4 - Double(index) * 0.012) / 0.6))
            context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(.white.opacity(0.8 * twinkle * lit)))
        }

        // A moon, slightly behind the stars in the parallax.
        let moon = CGPoint(x: width * 0.82 - Double(pointer.width) * 14 * u, y: height * 0.17 - Double(pointer.height) * 9 * u)
        let moonRadius = min(width, height) * 0.045
        context.fill(Path(ellipseIn: CGRect(x: moon.x - moonRadius * 5, y: moon.y - moonRadius * 5, width: moonRadius * 10, height: moonRadius * 10)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(0.17), Color.white.opacity(0)]),
                                           center: moon, startRadius: moonRadius, endRadius: moonRadius * 5))
        context.fill(Path(ellipseIn: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)),
                     with: .color(Color(red: 0.96, green: 0.95, blue: 0.88)))
        for (dx, dy, r) in [(-0.45, -0.5, 0.5), (0.2, 0.15, 0.32), (-0.1, 0.42, 0.2)] {
            context.fill(Path(ellipseIn: CGRect(x: moon.x + moonRadius * dx, y: moon.y + moonRadius * dy, width: moonRadius * r, height: moonRadius * r)),
                         with: .color(Color(red: 0.86, green: 0.85, blue: 0.78)))
        }

        // Shooting stars: one soon after the start, then every few seconds.
        for (period, shift, slope) in [(7.0, 1.6, 0.58), (11.0, 5.2, 0.42)] {
            let lap = (time + shift).truncatingRemainder(dividingBy: period)
            guard lap < 0.95 else { continue }
            let progress = lap / 0.95
            let pass = floor((time + shift) / period)
            let startX = width * (0.12 + 0.6 * abs(sin(pass * 12.9898 + shift)))
            let head = CGPoint(x: startX + progress * width * 0.24, y: height * (0.06 + 0.16 * progress * slope * 2))
            for step in 0..<18 {
                let fade = 1 - Double(step) / 18
                let side = max(2, 3.2 * u * fade)
                context.fill(Path(CGRect(x: head.x - Double(step) * 9 * u, y: head.y - Double(step) * 9 * u * slope, width: side, height: side)),
                             with: .color(.white.opacity(0.95 * fade * sin(progress * .pi))))
            }
        }

        // The island lands: a ring of light runs out from it across the sky.
        let ripple = (intro - 0.55) / 1.7
        if ripple > 0, ripple < 1 {
            let eased = 1 - pow(1 - ripple, 3)
            let radius = eased * max(width, height) * 0.95
            let origin = CGPoint(x: width / 2, y: islandBottom)
            for (offset, strength) in [(0.0, 1.0), (26.0 * u, 0.5), (60.0 * u, 0.25)] {
                let r = max(0, radius - offset)
                context.stroke(Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r * 0.82, width: r * 2, height: r * 1.64)),
                               with: .color(accent.opacity(0.55 * strength * (1 - ripple))), lineWidth: (5 - 3 * eased) * u)
            }
        }
    }

    // MARK: Sea

    nonisolated private static func sea(_ context: inout GraphicsContext, size: CGSize, time: Double, pointer: CGSize, accent: Color, u: Double) {
        let width = Double(size.width), height = Double(size.height)
        let moonX = width * 0.82 - Double(pointer.width) * 14 * u
        let bands: [(Double, Double, Double, Double, Color)] = [
            (0.70, 16, 0.50, 0.9, Color(red: 0.03, green: 0.20, blue: 0.27)),
            (0.77, 20, 0.36, 2.2, Color(red: 0.02, green: 0.15, blue: 0.22)),
            (0.85, 26, 0.26, 4.0, Color(red: 0.015, green: 0.10, blue: 0.16)),
        ]
        func crest(_ x: Double, _ band: Int) -> Double {
            let (level, swell, speed, phase, _) = bands[band]
            // Nearer water moves further when the pointer does.
            let shifted = x + Double(pointer.width) * 40 * u * Double(band + 1)
            return height * level + sin(shifted / (140 * u) + time * speed + phase) * swell * u
                + sin(shifted / (57 * u) + time * speed * 1.7) * swell * u * 0.28
        }
        for (index, band) in bands.enumerated() {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: height))
            var x = 0.0
            while x <= width + 10 {
                path.addLine(to: CGPoint(x: x, y: crest(x, index)))
                x += 10
            }
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
            context.fill(path, with: .linearGradient(Gradient(colors: [band.4.opacity(0.94), band.4.opacity(0.99)]),
                                                     startPoint: CGPoint(x: 0, y: height * band.0), endPoint: CGPoint(x: 0, y: height)))
            if index == 0 {
                // Moonlight breaking on the nearest swell.
                for glint in 0..<10 {
                    let offset = Double(glint) - 4.5
                    let span = (36 - abs(offset) * 5 + sin(time * 1.6 + Double(glint)) * 7) * u
                    let y = height * band.0 + (18 + Double(glint) * 13) * u
                    context.fill(Path(CGRect(x: moonX - span / 2 + sin(time * 0.9 + Double(glint) * 1.3) * 10 * u, y: y, width: max(4, span), height: 3 * u)),
                                 with: .color(Color.white.opacity(0.21 - Double(glint) * 0.017)))
                }
            }
        }
        // Plankton: specks in the water that light up where the pointer passes.
        var seed: UInt64 = 0xD1B5_4A32_D192_ED03
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let px = (Double(pointer.width) + 0.5) * width, py = (Double(pointer.height) + 0.5) * height
        for _ in 0..<70 {
            let x = next() * width + sin(time * 0.2 + next() * 6.28) * 12 * u
            let y = height * (0.74 + next() * 0.24) + cos(time * 0.3 + next() * 6.28) * 6 * u
            let near = max(0, 1 - hypot(x - px, y - py) / (260 * u))
            let glow = 0.05 + 0.2 * abs(sin(time * (0.5 + next()) + next() * 6.28)) + 0.75 * near * near
            let side = (near > 0.5 ? 3.0 : 2.0) * max(1, u * 0.9)
            context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(accent.opacity(min(1, glow))))
        }
    }
}

/// Square confetti, thrown from the island when something is worth it.
enum Confetti {
    static let lifetime = 3.6

    static func draw(_ context: inout GraphicsContext, size: CGSize, age: Double, origin: CGPoint, u: Double, accent: Color) {
        guard age >= 0, age < lifetime else { return }
        let colors = [accent, Theme.sky, Theme.amber, Theme.coral, Theme.violet, Color.white]
        var seed: UInt64 = 0xA24B_AED4_963E_E407
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let fade = min(1, max(0, (lifetime - age) / 1.1))
        for index in 0..<150 {
            // A fan below the island: mostly sideways and down.
            let angle = (0.08 + next() * 0.84) * Double.pi
            let speed = (260 + next() * 760) * u
            let drag = 1 - exp(-age * 1.9)
            let x = Double(origin.x) + cos(angle) * speed * drag / 1.9
            let y = Double(origin.y) + sin(angle) * speed * drag / 1.9 * 0.55 + 300 * u * age * age * (0.5 + next() * 0.6)
            let side = (5 + next() * 6) * u
            // Tumbling: the square turns edge-on and back.
            let turn = abs(cos(age * (5 + next() * 9) + next() * 6.28))
            let rect = CGRect(x: x - side * turn / 2, y: y - side / 2, width: max(1, side * turn), height: side)
            context.fill(Path(rect), with: .color(colors[index % colors.count].opacity(fade)))
        }
    }
}
