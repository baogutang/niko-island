import AppKit
import NikoCore
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, island, sessions, agents, sounds, usage, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L("General")
        case .island: return L("Island")
        case .sessions: return L("Sessions")
        case .agents: return L("Agents")
        case .sounds: return L("Sounds")
        case .usage: return L("Usage")
        case .about: return L("About")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return L("Language, startup, notifications")
        case .island: return L("How it looks and behaves")
        case .sessions: return L("What is listed, and for how long")
        case .agents: return L("Connections and creatures")
        case .sounds: return L("Cues for each moment")
        case .usage: return L("Tokens, cost and limits")
        case .about: return L("Version and privacy")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .island: return "capsule.fill"
        case .sessions: return "list.bullet"
        case .agents: return "link"
        case .sounds: return "speaker.wave.2.fill"
        case .usage: return "chart.bar.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(red: 0.36, green: 0.56, blue: 0.98)
        case .island: return Color(red: 0.55, green: 0.48, blue: 0.96)
        case .sessions: return Color(red: 0.36, green: 0.70, blue: 0.92)
        case .agents: return Color(red: 0.25, green: 0.74, blue: 0.66)
        case .sounds: return Color(red: 0.36, green: 0.78, blue: 0.45)
        case .usage: return Color(red: 0.95, green: 0.66, blue: 0.28)
        case .about: return Color(red: 0.92, green: 0.45, blue: 0.56)
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func show(page: SettingsPage? = nil) {
        if let page { model.settingsPage = page.rawValue }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 590),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = L("Niko Island Settings")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(red: 0.086, green: 0.090, blue: 0.102, alpha: 1)
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsRootView(model: model))
            window.center()
            self.window = window
        }
        model.refreshMaintenance()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var page: SettingsPage { SettingsPage(rawValue: model.settingsPage) ?? .general }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 1)
            Group {
                if isStaticPreview {
                    SettingsPageView(model: model, page: page)
                } else {
                    ScrollView(.vertical, showsIndicators: false) { SettingsPageView(model: model, page: page) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.window)
        }
        .frame(minWidth: 820, minHeight: 540)
        .environment(\.colorScheme, .dark)
        .environment(\.look, IslandLook(settings: model.settings))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                MascotView(sprite: Mascots.island, size: 22)
                Text(NikoVersion.displayName).font(Theme.title(15)).foregroundStyle(Theme.primary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 38)
            .padding(.bottom, 12)
            ForEach(SettingsPage.allCases) { item in
                Button { model.settingsPage = item.rawValue } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(item.tint))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(Theme.body(13, .semibold)).foregroundStyle(Theme.primary)
                            Text(item.subtitle).font(Theme.body(11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(page == item ? Color.white.opacity(0.10) : Color.clear))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Text(L("Version %@", NikoVersion.current)).font(Theme.mono(10.5, .regular)).foregroundStyle(Theme.quaternary)
                .padding(10)
        }
        .padding(.horizontal, 10)
        .frame(width: 236)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }
}

// MARK: - Pages

struct SettingsPageView: View {
    @ObservedObject var model: AppModel
    var page: SettingsPage
    @Environment(\.isStaticPreview) private var isStaticPreview
    @State private var loginItemError: String?
    @State private var exportedPath: String?
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title).font(Theme.title(24)).foregroundStyle(Theme.primary)
                Text(page.subtitle).font(Theme.body(13)).foregroundStyle(Theme.secondary)
            }
            switch page {
            case .general: general
            case .island: island
            case .sessions: sessions
            case .agents: agents
            case .sounds: sounds
            case .usage: usage
            case .about: about
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Building blocks

    private func card<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased()).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
        }
    }

    private func row<Trailing: View>(_ title: String, _ detail: String? = nil, divider: Bool = true,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.body(13.5, .semibold)).foregroundStyle(Theme.primary)
                    if let detail {
                        Text(detail).font(Theme.body(11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 10)
                trailing()
            }
            .padding(.vertical, 11)
            if divider { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }

    /// A choice between a few values: title and detail, then the pills on their own line.
    private func choiceRow<Value: Hashable>(_ title: String, _ detail: String? = nil, divider: Bool = true,
                                            options: [(Value, String)], selection: Binding<Value>) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.body(13.5, .semibold)).foregroundStyle(Theme.primary)
                    if let detail {
                        Text(detail).font(Theme.body(11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ChoicePills(options: options.map { (value: $0.0, label: $0.1) }, selection: selection)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)
            if divider { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }

    private func toggleRow(_ title: String, _ detail: String? = nil, divider: Bool = true, isOn: Binding<Bool>) -> some View {
        row(title, detail, divider: divider) {
            Toggle(isOn: isOn) { EmptyView() }.toggleStyle(SwitchToggleStyle()).frame(width: 46)
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<NikoSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.settings[keyPath: keyPath] = $0 })
    }

    // MARK: General

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            card(L("Notify me when")) {
                toggleRow(L("An agent asks for permission"), isOn: Binding(
                    get: { model.settings.notificationsEnabled(for: .permission) },
                    set: { model.settings.setNotifications($0, for: .permission) }))
                toggleRow(L("An agent asks a question"), isOn: Binding(
                    get: { model.settings.notificationsEnabled(for: .question) },
                    set: { model.settings.setNotifications($0, for: .question) }))
                toggleRow(L("An agent finishes and waits for me"),
                          L("No banner appears while the session's own terminal is in front."), divider: false, isOn: Binding(
                    get: { model.settings.notificationsEnabled(for: .idle) },
                    set: { model.settings.setNotifications($0, for: .idle) }))
            }
            card(L("App")) {
                toggleRow(L("Open Niko Island at login"), loginItemError, isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { enabled in loginItemError = LoginItem.set(enabled) }))
                toggleRow(L("Open the island with %@", Hotkey.display),
                          L("From anywhere, without the pointer."), isOn: settingsBinding(\.hotkeyEnabled))
                choiceRow(L("Language"), divider: false,
                          options: [("system", L("Same as macOS")), ("en", "English"), ("zh-Hans", "简体中文")],
                          selection: settingsBinding(\.language))
            }
        }
    }

    // MARK: Island

    private var island: some View {
        VStack(alignment: .leading, spacing: 18) {
            card(L("Look")) {
                row(L("Colour"), L("For sessions at work and for the things you can press.")) {
                    HStack(spacing: 9) {
                        ForEach(NikoSettings.Accent.allCases, id: \.self) { accent in
                            Button { model.settings.accent = accent } label: {
                                Circle().fill(Theme.color(for: accent)).frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(Color.white, lineWidth: model.settings.accent == accent ? 2.5 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.rawValue)
                        }
                    }
                }
                if NSScreen.screens.count > 1 {
                    choiceRow(L("Display"), L("Automatic: the display with a camera housing, else the main one."),
                              options: [("auto", L("Automatic"))] + NSScreen.screens.map { ($0.localizedName, $0.localizedName) },
                              selection: settingsBinding(\.islandDisplay))
                }
                choiceRow(L("Width when open"),
                          options: [(NikoSettings.IslandWidth.compact, L("Compact")), (.regular, L("Regular")), (.wide, L("Wide"))],
                          selection: settingsBinding(\.islandWidth))
                choiceRow(L("Rows"),
                          options: [(NikoSettings.Density.comfortable, L("Roomy")), (.compact, L("Tight"))],
                          selection: settingsBinding(\.rowDensity))
                choiceRow(L("Sessions before the list scrolls"),
                          options: NikoSettings.visibleRowChoices.map { ($0, "\($0)") }, selection: settingsBinding(\.visibleRows))
                toggleRow(L("Pixel creatures"), L("Off: a plain dot in each agent's colour."), isOn: settingsBinding(\.showMascots))
                toggleRow(L("Show how long"), isOn: chipBinding(.elapsed))
                toggleRow(L("Show which agent"), isOn: chipBinding(.agent))
                toggleRow(L("Show which terminal or app"), divider: false, isOn: chipBinding(.host))
            }
            card(L("Opening and closing")) {
                toggleRow(L("Open when the pointer rests on it"),
                          L("It closes again when the pointer leaves."), isOn: settingsBinding(\.expandOnHover))
                choiceRow(L("How long the pointer has to rest"),
                          options: [(0, L("No wait")), (160, L("Short")), (350, L("Medium")), (600, L("Long"))],
                          selection: settingsBinding(\.hoverOpenDelayMS))
                choiceRow(L("How soon it closes after the pointer leaves"),
                          options: [(200, L("At once")), (450, L("Short")), (900, L("Medium")), (1500, L("Long"))],
                          selection: settingsBinding(\.hoverCloseDelayMS))
                toggleRow(L("Open by itself when an agent needs a decision"),
                          L("It never takes keyboard focus away from what you are typing."), isOn: settingsBinding(\.expandOnAttention))
                toggleRow(L("Show a short notice when an agent finishes"),
                          L("The collapsed island names the session for a few seconds."), isOn: settingsBinding(\.showCompletionToast))
                choiceRow(L("How long the notice stays"),
                          options: NikoSettings.toastChoices.map { ($0, L("%lld s", $0)) }, selection: settingsBinding(\.toastSeconds))
                toggleRow(L("Keep the island visible when nothing is running"),
                          L("Off: it appears only while there are sessions."), divider: false, isOn: settingsBinding(\.showIslandWhenIdle))
            }
            card(L("Full-screen apps")) {
                choiceRow(L("Where there is no menu bar"),
                          L("Following the menu bar, the island slides away with the desktop and comes down when you push the pointer to the top of the screen."),
                          options: [(FullScreenPolicy.followMenuBar, L("Follow the menu bar")), (.always, L("Always show")), (.never, L("Never"))],
                          selection: settingsBinding(\.fullScreenPolicy))
                toggleRow(L("Come in over a full-screen app when an agent needs a decision"),
                          divider: false, isOn: settingsBinding(\.attentionBreaksFullScreen))
            }
        }
    }

    private func chipBinding(_ chip: NikoSettings.RowChip) -> Binding<Bool> {
        Binding(get: { model.settings.showsChip(chip) }, set: { model.settings.setChip(chip, shown: $0) })
    }

    // MARK: Sessions

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                toggleRow(L("Find sessions by reading the agents' own session logs"),
                          L("Claude Code and Codex sessions show up even when they are idle, were started before this app, or run in a desktop app that is not connected. The logs are only read, on this Mac."),
                          isOn: settingsBinding(\.discoverSessions))
                choiceRow(L("Keep a quiet session listed for"), divider: false,
                          options: [(10, L("10 min")), (30, L("30 min")), (120, L("2 hours")), (480, L("8 hours"))],
                          selection: settingsBinding(\.sessionRetentionMinutes))
            }
            Text(L("Sessions found this way can be watched and jumped to. Approving from the island needs the agent to be connected."))
                .font(Theme.body(12)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Agents

    @ViewBuilder
    private var agents: some View {
        if let fix = model.maintenance.quarantineFix {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("macOS is still holding this app in quarantine"), systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.body(13, .semibold)).foregroundStyle(Theme.amber)
                Text(L("Hooks cannot start the bridge until the flag is cleared. Run this once in a terminal, then reopen the app:"))
                    .font(Theme.body(12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Text(fix).font(Theme.mono(12, .regular)).foregroundStyle(Theme.primary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.field))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.amber.opacity(0.10)))
        }
        let unconnected = model.maintenance.agents.filter { !$0.wired && $0.stability != .experimental }
        if !unconnected.isEmpty {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("%lld agents on this Mac are not connected", unconnected.count))
                        .font(Theme.body(13.5, .semibold)).foregroundStyle(Theme.primary)
                    Text(unconnected.map(\.name).joined(separator: ", "))
                        .font(Theme.body(11.5)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Button(L("Connect all")) { model.runInstaller(.install, agents: unconnected.map(\.id)) }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .disabled(model.maintenance.busy)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look.accent.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(look.accent.opacity(0.25)))
        }
        card {
            if model.maintenance.agents.isEmpty {
                row(L("No supported agent was found in your home directory."), divider: false) { EmptyView() }
            }
            ForEach(Array(model.maintenance.agents.enumerated()), id: \.element.id) { index, agent in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        MascotView(source: agent.id, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                Text(agent.name).font(Theme.body(13.5, .semibold)).foregroundStyle(Theme.primary)
                                if agent.stability == .experimental { Chip(text: L("experimental"), tint: Theme.amber, mono: false) }
                                if agent.stability == .beta { Chip(text: L("beta"), tint: Theme.sky, mono: false) }
                                if model.runningAgents.contains(agent.id) { Chip(text: L("running now"), tint: look.accent, mono: false) }
                            }
                            Text((agent.wired ? L("connected") : L("not connected")) + " · "
                                 + (agent.approvals ? L("status and approvals") : L("status")))
                                .font(Theme.body(11.5)).foregroundStyle(agent.wired ? look.accent : Theme.tertiary)
                        }
                        Spacer()
                        Button(agent.wired ? L("Remove") : L("Connect")) {
                            model.runInstaller(agent.wired ? .uninstall : .install, agents: [agent.id])
                        }
                        .buttonStyle(PillButtonStyle(kind: agent.wired ? .neutral : .primary))
                        .disabled(model.maintenance.busy)
                    }
                    if agent.wired, let followUp = agent.followUp {
                        Text(L(followUp)).font(Theme.body(11.5)).foregroundStyle(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true).padding(.leading, 40)
                    }
                    creaturePicker(for: agent.id)
                }
                .padding(.vertical, 10)
                if index < model.maintenance.agents.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
        Text(L("Connecting adds entries tagged niko-bridge to the agent's config after a backup. Removing takes out only those entries."))
            .font(Theme.body(12)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
        if let message = model.maintenance.message {
            Text(message)
                .font(Theme.mono(11, .regular)).foregroundStyle(Theme.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
        }
    }

    /// Any creature can stand for any agent.
    private func creaturePicker(for agent: String) -> some View {
        let chosen = Mascots.sprite(for: agent, choices: model.settings.mascotChoices).name
        return HStack(spacing: 5) {
            ForEach(Mascots.all, id: \.name) { sprite in
                Button {
                    // Picking the agent's own creature clears the choice.
                    model.settings.setMascot(sprite.name == Mascots.sprite(for: agent).name ? nil : sprite.name, for: agent)
                } label: {
                    MascotView(sprite: sprite, size: 18)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(sprite.name == chosen ? Color.white.opacity(0.16) : Color.clear))
                        .opacity(sprite.name == chosen ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sprite.name)
            }
        }
        .padding(.leading, 36)
    }

    // MARK: Sounds

    private func title(for event: SoundEvent) -> (String, String) {
        switch event {
        case .started: return (L("Work started"), L("An agent picked up your prompt."))
        case .attention: return (L("Needs you"), L("A permission request or a question is waiting."))
        case .completed: return (L("Finished"), L("An agent finished its turn."))
        case .error: return (L("Hit an error"), L("A turn ended because something failed."))
        case .limit: return (L("Limit close"), L("A rate-limit window passed 90%."))
        }
    }

    private var sourceOptions: [(value: String, label: String)] {
        var options: [(String, String)] = [
            ("island", L("Island")), ("chiptune", L("8-bit")), ("system", L("macOS")),
        ]
        if isStaticPreview || UserSoundFiles.hasAny(paths: model.paths) { options.append(("files", L("My files"))) }
        if !isStaticPreview {
            for pack in SoundPack.discover(paths: model.paths, home: model.home) {
                options.append(("pack:" + pack.id, pack.displayName))
            }
        }
        return options
    }

    private var sounds: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                toggleRow(L("Play sounds"), L("Off by default. Each moment below can be switched on its own."),
                          isOn: settingsBinding(\.soundsEnabled))
                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Sound set")).font(Theme.body(13.5, .semibold)).foregroundStyle(Theme.primary)
                        Text(L("Island and 8-bit are generated by the app itself; no audio files are bundled."))
                            .font(Theme.body(11.5)).foregroundStyle(Theme.secondary)
                    }
                    ChoicePills(options: sourceOptions, selection: Binding(
                        get: { model.settings.soundSource.rawValue },
                        set: { model.settings.soundSource = SoundSource(rawValue: $0) }))
                }
                .padding(.vertical, 11)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                row(L("Volume"), divider: false) {
                    HStack(spacing: 10) {
                        LevelSlider(value: settingsBinding(\.soundVolume)).frame(width: 190)
                        Text("\(Int((model.settings.soundVolume * 100).rounded()))%")
                            .font(Theme.mono(12)).foregroundStyle(Theme.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
            }
            card(L("Moments")) {
                ForEach(Array(SoundEvent.allCases.enumerated()), id: \.element) { index, event in
                    let text = title(for: event)
                    row(text.0, text.1, divider: index < SoundEvent.allCases.count - 1) {
                        HStack(spacing: 10) {
                            if model.settings.soundSource == .system { systemSoundPicker(for: event) }
                            Button { model.onPreviewSound?(event) } label: {
                                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .help(L("Play this sound"))
                            .accessibilityLabel(L("Play this sound"))
                            Toggle(isOn: Binding(get: { model.settings.soundEnabled(for: event) },
                                                 set: { model.settings.setSound($0, for: event) })) { EmptyView() }
                                .toggleStyle(SwitchToggleStyle()).frame(width: 46)
                        }
                    }
                }
            }
            card(L("Your own sounds")) {
                row(L("Files and sound packs"),
                    L("Put started, attention, completed, error or limit (.wav, .aiff, .mp3, .m4a) in the sounds folder, or a pack folder with an openpeon.json manifest inside its packs folder."),
                    divider: false) {
                    Button(L("Open folder")) { SettingsActions.openSoundsFolder(paths: model.paths) }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func systemSoundPicker(for event: SoundEvent) -> some View {
        let current = model.settings.systemSound(for: event)
        if isStaticPreview {
            Chip(text: current)
        } else {
            Menu {
                ForEach(SettingsActions.systemSoundNames, id: \.self) { name in
                    Button(name) {
                        model.settings.setSystemSound(name, for: event)
                        model.onPreviewSound?(event)
                    }
                }
            } label: {
                Chip(text: current)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: Usage

    private var usage: some View {
        VStack(alignment: .leading, spacing: 18) {
            UsageView(model: model)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
            card(L("Price list")) {
                toggleRow(L("Refresh the model price list from the network (weekly)"),
                          L("Off by default. It is the only network request this app can make; everything else stays on this Mac."),
                          divider: false, isOn: settingsBinding(\.pricingRefreshEnabled))
            }
        }
    }

    // MARK: About

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                MascotView(sprite: Mascots.island, size: 64, animated: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(NikoVersion.displayName).font(Theme.title(22)).foregroundStyle(Theme.primary)
                    Text(L("Version %@ · no telemetry, no account, MIT licensed", NikoVersion.current))
                        .font(Theme.body(12.5)).foregroundStyle(Theme.secondary)
                }
            }
            card(L("Privacy")) {
                row(L("Everything stays on this Mac"),
                    L("No analytics, no crash reports, no update checks. Events are kept in memory; the usage database holds numbers and identifiers only."),
                    divider: model.httpPort > 0) { EmptyView() }
                if model.httpPort > 0 {
                    row(L("Plugin ingress listening on 127.0.0.1:%lld", Int(model.httpPort)), divider: false) { EmptyView() }
                }
            }
            card {
                row(L("Welcome"), L("The introduction from the first launch."), divider: true) {
                    Button(L("Show it again")) { model.wantsOnboarding = true }.buttonStyle(PillButtonStyle())
                }
                row(L("Diagnostics"), exportedPath ?? L("A redacted report you can attach to an issue."), divider: true) {
                    Button(L("Export diagnostics")) {
                        if let url = model.exportDiagnostics() {
                            exportedPath = url.path
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                row(L("Releases"), L("Opens the download page in your browser."), divider: true) {
                    Button(L("Open Releases Page")) {
                        if let url = URL(string: NikoVersion.releasesURL) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                row(L("Quit Niko Island"), L("Agents keep working; waiting requests go back to their terminals."), divider: false) {
                    Button(L("Quit")) { NSApp.terminate(nil) }.buttonStyle(PillButtonStyle(kind: .destructive))
                }
            }
        }
    }
}

// MARK: - Helpers

@MainActor
enum SettingsActions {
    static let systemSoundNames: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let cleaned = names.map { ($0 as NSString).deletingPathExtension }.sorted()
        return cleaned.isEmpty ? SoundEvent.allCases.map(\.defaultSystemSound) : cleaned
    }()

    static func openSoundsFolder(paths: NikoPaths) {
        let packs = paths.sounds.appendingPathComponent("packs")
        try? FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(paths.sounds)
    }
}

/// "Open at login" through the system's login-item service. Only meaningful
/// for the bundled app; from `swift run` it reports off and declines politely.
@MainActor
enum LoginItem {
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var isEnabled: Bool {
        guard isBundled else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns a message when the change did not work.
    static func set(_ enabled: Bool) -> String? {
        guard isBundled else { return L("Available in the installed app.") }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
