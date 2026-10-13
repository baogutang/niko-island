import NikoCore
import SwiftUI

/// The welcome a new user sees once: a night sea across the whole screen, the
/// island dropping in where it will live, the agents found on this Mac ready
/// to connect with one click, and the few choices worth making up front.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var metrics: IslandMetrics = .plain
    var onFinish: () -> Void

    enum Step: Int, CaseIterable { case welcome, agents, tour, preferences, done }

    @State var step: Step = .welcome
    @State private var appeared = false
    @State private var selected: Set<String> = []
    @State private var selectionSeeded = false
    @State private var connecting = false
    @State private var connectedNow: Set<String> = []
    @Environment(\.isStaticPreview) private var isStaticPreview

    var body: some View {
        GeometryReader { proxy in
            // Laid out for a 900-point-tall screen; a big display gets a bigger welcome, not a lonelier one.
            let scale = min(1.55, max(0.72, min(proxy.size.height / 900, proxy.size.width / 1280)))
            ZStack(alignment: .top) {
                SeaBackdrop()
                DemoIsland(model: model, metrics: metrics, stage: demoStage)
                    .offset(y: appeared || isStaticPreview ? 0 : -(metrics.bandHeight + 40))
                    .animation(.spring(response: 0.7, dampingFraction: 0.62).delay(0.35), value: appeared)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content
                        .frame(maxWidth: 900)
                        .scaleEffect(scale)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 26)).combined(with: .scale(scale: 0.97)),
                            removal: .opacity.combined(with: .offset(y: -18))))
                    Spacer(minLength: 0)
                    footer.scaleEffect(min(scale, 1.3), anchor: .bottom).padding(.bottom, 44)
                }
                .padding(.horizontal, 40)
                .padding(.top, 120)

                HStack {
                    Spacer()
                    if step != .done {
                        Button(L("Skip")) { finish() }
                            .buttonStyle(PillButtonStyle(kind: .ghost, large: true))
                            .keyboardShortcut(.cancelAction)
                            .scaleEffect(min(scale, 1.3), anchor: .topTrailing)
                            .padding(.trailing, 28)
                            .padding(.top, 54)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .environment(\.colorScheme, .dark)
        .environment(\.look, IslandLook(settings: model.settings))
        .opacity(appeared || isStaticPreview ? 1 : 0)
        .animation(.easeOut(duration: 0.45), value: appeared)
        .onAppear {
            appeared = true
            model.refreshMaintenance()
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .agents: agents
        case .tour: tour
        case .preferences: preferences
        case .done: done
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
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = next }
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { go(next) } else { finish() }
    }

    private func finish() {
        model.settings.onboardingDone = true
        onFinish()
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                ForEach(Array(Mascots.all.enumerated()), id: \.offset) { index, sprite in
                    Bobbing(delay: Double(index) * 0.11) {
                        MascotView(sprite: sprite, size: 46, animated: true)
                    }
                }
            }
            VStack(spacing: 10) {
                Text(NikoVersion.displayName)
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color.white.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: look.accent.opacity(0.35), radius: 40, y: 8)
                Text(L("An island at the top of your screen for the agents that write your code."))
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(L("See what each one is doing, approve and answer where you are, and go back to the right window when you want to."))
                .font(Theme.body(15))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
    }

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

    private var agents: some View {
        let pending = rows.filter { chosen.contains($0.id) && !$0.wired }
        return VStack(spacing: 20) {
            stepTitle(rows.isEmpty ? L("No agents found yet") : L("These agents are on your Mac"),
                      rows.isEmpty ? L("Install one, then connect it from Settings. The island also finds Claude Code and Codex sessions by itself.")
                      : L("Connecting adds a few entries tagged niko-bridge to each agent's own config, after a backup. Nothing else is touched, and Settings takes them out again."))
            if !rows.isEmpty {
                let columns = rows.count > 8 ? 3 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(rows) { row in agentCard(row) }
                }
                .frame(maxWidth: columns == 3 ? 900 : 700)
            }
            if let message = followUps, !message.isEmpty {
                Text(message)
                    .font(Theme.body(12.5)).foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.center).frame(maxWidth: 640)
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
                .buttonStyle(PillButtonStyle(kind: .primary, large: true))
                .disabled(model.maintenance.busy)
            }
        }
        .onChange(of: model.maintenance.busy) { _, busy in if !busy { connecting = false } }
    }

    /// What the user still has to do in an agent after connecting it.
    private var followUps: String? {
        let notes = rows.filter { $0.wired && connectedNow.contains($0.id) }.compactMap { row in
            row.followUp.map { L($0) }
        }
        return notes.isEmpty ? nil : notes.joined(separator: "\n")
    }

    private func agentCard(_ row: MaintenanceState.AgentRow) -> some View {
        let isOn = chosen.contains(row.id)
        let running = model.runningAgents.contains(row.id)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            guard !row.wired else { return }
            toggle(row.id)
        } label: {
            HStack(spacing: 12) {
                MascotView(source: row.id, size: 40, animated: running || (row.wired && connectedNow.contains(row.id)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.name).font(Theme.title(16)).foregroundStyle(Theme.primary).lineLimit(1).fixedSize()
                        if row.stability == .beta { Chip(text: L("beta"), tint: Theme.sky, mono: false) }
                        if row.stability == .experimental { Chip(text: L("experimental"), tint: Theme.amber, mono: false) }
                    }
                    HStack(spacing: 5) {
                        if row.wired {
                            Text(L("connected")).foregroundStyle(look.accent)
                            Text("·").foregroundStyle(Theme.quaternary)
                        } else if running {
                            Circle().fill(look.accent).frame(width: 6, height: 6)
                            Text(L("running now")).foregroundStyle(look.accent)
                            Text("·").foregroundStyle(Theme.quaternary)
                        }
                        Text(row.approvals ? L("status and approvals") : L("status")).foregroundStyle(Theme.tertiary)
                    }
                    .font(Theme.body(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: row.wired ? "checkmark.seal.fill" : (isOn ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(row.wired || isOn ? look.accent : Theme.quaternary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(shape.fill(Color.black.opacity(0.42)))
            .overlay(shape.strokeBorder(isOn || row.wired ? look.accent.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1.2))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: row.wired)
    }

    private var tour: some View {
        VStack(spacing: 26) {
            stepTitle(L("Small while they work, open when they need you"),
                      L("Watch the island at the top of the screen: this is what it does all day."))
            HStack(alignment: .top, spacing: 14) {
                tourCard("capsule.fill", L("Out of the way"),
                         L("One creature and a few words. It rests on your menu bar and leaves with it when an app goes full screen."))
                tourCard("hand.tap.fill", L("Decide in place"),
                         L("When an agent wants to run something, the island opens with the command. Allow, deny, or send it back to the terminal."))
                tourCard("arrow.up.forward.app.fill", L("Back in one click"),
                         L("Click a session and its terminal tab or app comes forward. Sessions show up even for agents you have not connected."))
            }
            .frame(maxWidth: 860)
        }
    }

    private func tourCard(_ symbol: String, _ title: String, _ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(look.accent)
            Text(title).font(Theme.title(17)).foregroundStyle(Theme.primary)
            Text(text).font(Theme.body(13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(shape.fill(Color.black.opacity(0.42)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.10)))
    }

    private var preferences: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(spacing: 22) {
            stepTitle(L("Make it yours"), L("Everything here can be changed later in Settings."))
            VStack(spacing: 0) {
                preferenceRow(L("Colour"), L("For sessions at work and for the things you can press.")) {
                    HStack(spacing: 10) {
                        ForEach(NikoSettings.Accent.allCases, id: \.self) { accent in
                            Button { model.settings.accent = accent } label: {
                                Circle().fill(Theme.color(for: accent)).frame(width: 24, height: 24)
                                    .overlay(Circle().strokeBorder(Color.white, lineWidth: model.settings.accent == accent ? 2.5 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.rawValue)
                        }
                    }
                }
                divider
                preferenceRow(L("Sounds"), L("A short cue when an agent needs you or finishes. Generated by the app, off unless you want them.")) {
                    HStack(spacing: 8) {
                        if model.settings.soundsEnabled {
                            Button { model.onPreviewSound?(.completed) } label: { Image(systemName: "play.fill") }
                                .buttonStyle(PillButtonStyle())
                                .accessibilityLabel(L("Play this sound"))
                        }
                        Toggle(isOn: Binding(get: { model.settings.soundsEnabled }, set: { enabled in
                            model.settings.soundsEnabled = enabled
                            if enabled { model.onPreviewSound?(.completed) }
                        })) { EmptyView() }.toggleStyle(SwitchToggleStyle()).frame(width: 46)
                    }
                }
                divider
                preferenceRow(L("Full-screen apps"), L("Where there is no menu bar.")) {
                    ChoicePills(options: [(FullScreenPolicy.followMenuBar, L("Follow the menu bar")), (.always, L("Always show")), (.never, L("Never"))],
                                selection: Binding(get: { model.settings.fullScreenPolicy }, set: { model.settings.fullScreenPolicy = $0 }))
                }
                divider
                preferenceRow(L("Open Niko Island at login"), nil) {
                    Toggle(isOn: Binding(get: { LoginItem.isEnabled }, set: { _ = LoginItem.set($0) })) { EmptyView() }
                        .toggleStyle(SwitchToggleStyle()).frame(width: 46)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(maxWidth: 720)
            .background(shape.fill(Color.black.opacity(0.42)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.10)))
        }
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    private func preferenceRow<Trailing: View>(_ title: String, _ detail: String?, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body(14.5, .semibold)).foregroundStyle(Theme.primary)
                if let detail { Text(detail).font(Theme.body(12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 14)
    }

    private var done: some View {
        VStack(spacing: 18) {
            Bobbing(delay: 0) { MascotView(sprite: Mascots.island, size: 84, animated: true) }
            Text(L("You are all set")).font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundStyle(Theme.primary)
            Text(model.settings.hotkeyEnabled
                 ? L("Rest the pointer on the island to open it, or press ⌃⌥I from anywhere.")
                 : L("Rest the pointer on the island to open it."))
                .font(.system(size: 18, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondary)
            Text(L("The gear on the island opens Settings. This welcome is under About, if you want to see it again."))
                .font(Theme.body(13.5)).foregroundStyle(Theme.tertiary)
        }
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(Theme.primary)
                .multilineTextAlignment(.center)
            Text(subtitle).font(Theme.body(15)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 640).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                if step != .welcome, step != .done {
                    Button(L("Back")) { go(Step(rawValue: step.rawValue - 1) ?? .welcome) }
                        .buttonStyle(PillButtonStyle(large: true))
                }
                // While something is ticked to connect, that button is the main one; this one steps aside.
                Button(primaryTitle) { advance() }
                    .buttonStyle(PillButtonStyle(kind: step == .agents && hasPending ? .neutral : .primary, large: true))
                    .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule().fill(item == step ? Color.white : Color.white.opacity(0.22))
                        .frame(width: item == step ? 22 : 7, height: 7)
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

    @Environment(\.look) private var look
}

/// A gentle up-and-down, out of step with its neighbours.
private struct Bobbing<Content: View>: View {
    var delay: Double
    @ViewBuilder var content: Content
    @State private var up = false
    @Environment(\.isStaticPreview) private var isStaticPreview

    var body: some View {
        content
            .offset(y: up ? -7 : 5)
            .onAppear {
                guard !isStaticPreview else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(delay)) { up = true }
            }
    }
}

// MARK: - The island, performing

/// A stand-in for the island, drawn where the real one sits, that acts out
/// what the real one does. It never touches real sessions.
struct DemoIsland: View {
    @ObservedObject var model: AppModel
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
                MascotView(sprite: Mascots.island, size: 17, animated: true)
                Text(L("Hello")).foregroundStyle(Theme.primary)
            case .idle:
                MascotView(sprite: Mascots.island, size: 17)
                Text(NikoVersion.displayName).foregroundStyle(Theme.tertiary)
            case .working:
                MascotView(source: "claude", size: 17, animated: true)
                Text(L("running") + " swift test").foregroundStyle(Theme.primary.opacity(0.9))
                Circle().fill(look.accent).frame(width: 6, height: 6)
            case .finished:
                MascotView(source: "claude", size: 17)
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
                MascotView(source: "claude", size: 30)
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

/// A night sea: slow light in the sky, a few stars, three bands of waves and
/// the odd creature going about its business. Drawn, not filmed.
struct SeaBackdrop: View {
    @Environment(\.isStaticPreview) private var isStaticPreview
    @Environment(\.look) private var look

    var body: some View {
        if isStaticPreview {
            scene(time: 12.4)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                scene(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func scene(time: Double) -> some View {
        let accent = look.accent
        return ZStack {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.012, green: 0.016, blue: 0.035), Color(red: 0.02, green: 0.07, blue: 0.13), Color(red: 0.02, green: 0.12, blue: 0.17)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

                // Light drifting across the sky.
                let lights: [(Color, Double, Double, Double, Double)] = [
                    (accent, 0.22, 0.26, 0.11, 0.0), (Theme.sky, 0.74, 0.20, 0.09, 1.7),
                    (Theme.violet, 0.52, 0.42, 0.07, 3.1), (Theme.coral, 0.88, 0.52, 0.05, 4.4),
                ]
                for (color, x, y, strength, phase) in lights {
                    let centre = CGPoint(x: size.width * (x + 0.05 * sin(time * 0.07 + phase)),
                                         y: size.height * (y + 0.04 * cos(time * 0.05 + phase)))
                    let radius = size.width * 0.34
                    context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                                 with: .radialGradient(Gradient(colors: [color.opacity(strength * 2.2), color.opacity(0)]),
                                                       center: centre, startRadius: 0, endRadius: radius))
                }

                // A moon, and the path it lays on the water.
                let moon = CGPoint(x: size.width * 0.82, y: size.height * 0.17)
                let moonRadius = min(size.width, size.height) * 0.045
                context.fill(Path(ellipseIn: CGRect(x: moon.x - moonRadius * 5, y: moon.y - moonRadius * 5, width: moonRadius * 10, height: moonRadius * 10)),
                             with: .radialGradient(Gradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)]),
                                                   center: moon, startRadius: moonRadius, endRadius: moonRadius * 5))
                context.fill(Path(ellipseIn: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)),
                             with: .color(Color(red: 0.96, green: 0.95, blue: 0.88)))
                context.fill(Path(ellipseIn: CGRect(x: moon.x - moonRadius * 0.45, y: moon.y - moonRadius * 0.5, width: moonRadius * 0.5, height: moonRadius * 0.5)),
                             with: .color(Color(red: 0.86, green: 0.85, blue: 0.78)))
                context.fill(Path(ellipseIn: CGRect(x: moon.x + moonRadius * 0.2, y: moon.y + moonRadius * 0.15, width: moonRadius * 0.32, height: moonRadius * 0.32)),
                             with: .color(Color(red: 0.88, green: 0.87, blue: 0.80)))

                // Now and then, a shooting star.
                let lap = time.truncatingRemainder(dividingBy: 9)
                if lap < 0.9 {
                    let progress = lap / 0.9
                    let pass = floor(time / 9)
                    let startX = size.width * (0.18 + 0.5 * abs(sin(pass * 12.9898)))
                    let head = CGPoint(x: startX + progress * size.width * 0.22, y: size.height * (0.07 + 0.13 * progress))
                    for step in 0..<14 {
                        let fade = 1 - Double(step) / 14
                        context.fill(Path(CGRect(x: head.x - Double(step) * 9, y: head.y - Double(step) * 5.2, width: 3, height: 3)),
                                     with: .color(.white.opacity(0.9 * fade * sin(progress * .pi))))
                    }
                }

                // Stars: square, as befits the creatures.
                var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
                func next() -> Double {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    return Double(seed >> 33) / Double(1 << 31)
                }
                for _ in 0..<90 {
                    let x = next() * size.width, y = next() * size.height * 0.62
                    let side = next() < 0.2 ? 3.0 : 2.0
                    let twinkle = 0.25 + 0.75 * abs(sin(time * (0.4 + next()) + next() * 6.28))
                    context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(.white.opacity(0.75 * twinkle)))
                }

                // The sea.
                let bands: [(Double, Double, Double, Double, Color)] = [
                    (0.70, 16, 0.50, 0.9, Color(red: 0.03, green: 0.20, blue: 0.27)),
                    (0.77, 20, 0.36, 2.2, Color(red: 0.02, green: 0.15, blue: 0.22)),
                    (0.85, 26, 0.26, 4.0, Color(red: 0.015, green: 0.10, blue: 0.16)),
                ]
                for (level, height, speed, phase, color) in bands {
                    var path = Path()
                    let base = size.height * level
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: base))
                    var x = 0.0
                    while x <= size.width + 12 {
                        let y = base + sin(x / 140 + time * speed + phase) * height + sin(x / 57 + time * speed * 1.7) * height * 0.28
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 12
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    context.fill(path, with: .color(color.opacity(0.92)))
                    if level < 0.72 {
                        // Moonlight breaking on the nearest swell.
                        for glint in 0..<9 {
                            let offset = Double(glint) - 4
                            let width = 34 - abs(offset) * 5 + sin(time * 1.6 + Double(glint)) * 7
                            let y = base + 18 + Double(glint) * 13
                            context.fill(Path(CGRect(x: moon.x - width / 2 + sin(time * 0.9 + Double(glint) * 1.3) * 10, y: y, width: max(4, width), height: 3)),
                                         with: .color(Color.white.opacity(0.20 - Double(glint) * 0.018)))
                        }
                    }
                }
            }

            // Passers-by.
            GeometryReader { proxy in
                let width = proxy.size.width, height = proxy.size.height
                swimmer(Mascots.whale, size: 64, x: travel(time, period: 46, offset: 0.1) * (width + 200) - 100,
                        y: height * 0.745 + sin(time * 0.5) * 8)
                swimmer(Mascots.boat, size: 52, x: (1 - travel(time, period: 70, offset: 0.55)) * (width + 200) - 100,
                        y: height * 0.665 + sin(time * 0.9 + 1) * 6)
                swimmer(Mascots.jellyfish, size: 40, x: width * 0.84 + sin(time * 0.3) * 30, y: height * 0.90 + cos(time * 0.6) * 14)
                swimmer(Mascots.gull, size: 34, x: travel(time, period: 31, offset: 0.7) * (width + 160) - 80,
                        y: height * 0.17 + sin(time * 1.3) * 12)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func travel(_ time: Double, period: Double, offset: Double) -> Double {
        (time / period + offset).truncatingRemainder(dividingBy: 1)
    }

    private func swimmer(_ sprite: MascotSprite, size: CGFloat, x: Double, y: Double) -> some View {
        MascotView(sprite: sprite, size: size, animated: true)
            .opacity(0.9)
            .position(x: x, y: y)
    }
}
