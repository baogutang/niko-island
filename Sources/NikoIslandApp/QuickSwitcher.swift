import AppKit
import NikoCore
import SwiftUI

/// A small search panel over everything else: type a few letters of a project,
/// a prompt or an agent, move with ↑ ↓ and press ↩ to go to that session.
/// A session with a request waiting opens the island on that request instead.
@MainActor
final class QuickSwitcherController {
    private let model: AppModel
    private let state = SwitcherState()
    private var panel: SwitcherPanel?
    private var keys: Any?

    init(model: AppModel) {
        self.model = model
    }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() {
        if isShown { close() } else { show() }
    }

    func show() {
        state.query = ""
        state.selected = 0
        state.shown = false
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel, height: state.height)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        installKeys()
        withAnimation(Motion.open(IslandLook(settings: model.settings).motion)) { state.shown = true }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        removeKeys()
        withAnimation(Motion.fadeOut(0.12)) { state.shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self, weak panel] in
            guard let panel, self?.state.shown == false else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: SwitcherState.width, height: 120),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Drawn on black whatever the system's appearance: the field's own colours must be the dark ones.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onResign = { [weak self] in self?.close() }
        let root = SwitcherView(model: model, state: state, choose: { [weak self] key in self?.choose(key) })
            .environment(\.look, IslandLook(settings: model.settings))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        state.onHeight = { [weak self, weak panel] height in
            guard let self, let panel else { return }
            self.place(panel, height: height)
        }
        return panel
    }

    /// A third of the way down the island's display, keeping its top edge where it is as the list grows.
    private func place(_ panel: NSPanel, height: CGFloat) {
        guard let screen = IslandWindowController.targetScreen(preference: model.settings.islandDisplay) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let top = frame.maxY - frame.height * 0.22
        let width = SwitcherState.width + SwitcherState.margin * 2
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: top - height, width: width, height: height), display: true)
    }

    private func choose(_ key: SessionKey) {
        close()
        if let request = model.pending.first(where: { $0.sessionKey == key }) {
            model.focusedRequestID = request.id
            model.expand(.click)
        } else {
            model.jump(to: key)
        }
    }

    // MARK: Keys

    /// ↑ ↓ (and ⌃P ⌃N) move, ↩ goes, ⎋ closes. Everything else goes to the search field.
    private func installKeys() {
        removeKeys()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            // Candidate navigation and Return belong to the input method until it commits.
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            let control = event.modifierFlags.contains(.control)
            switch Int(event.keyCode) {
            case 125: self.state.move(1); return nil
            case 126: self.state.move(-1); return nil
            case 45 where control: self.state.move(1); return nil        // ⌃N
            case 35 where control: self.state.move(-1); return nil       // ⌃P
            case 36, 76:
                if let key = self.state.selectedKey { self.choose(key) }
                return nil
            case 53: self.close(); return nil
            default: return event
            }
        }
    }

    private func removeKeys() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }
}

final class SwitcherPanel: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

@MainActor
final class SwitcherState: ObservableObject {
    static let width: CGFloat = 560
    /// Room around the card for its shadow.
    static let margin: CGFloat = 28
    static let maxRows = 8

    @Published var query = "" { didSet { if query != oldValue { selected = 0 } } }
    @Published var selected = 0
    @Published var shown = false
    var results: [SessionKey] = []
    var height: CGFloat = 120 {
        didSet { if abs(height - oldValue) > 0.5 { onHeight?(height) } }
    }
    var onHeight: ((CGFloat) -> Void)?

    var selectedKey: SessionKey? { results.indices.contains(selected) ? results[selected] : nil }

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        withAnimation(Motion.snappy()) { selected = (selected + step + results.count) % results.count }
    }
}

struct SwitcherView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: SwitcherState
    var choose: (SessionKey) -> Void
    @Environment(\.look) private var look
    @Environment(\.isStaticPreview) private var isStaticPreview
    @FocusState private var focused: Bool
    @Namespace private var selection

    /// Needs-you first, then the rest as the island orders them; ranked by the match once something is typed.
    private var matches: [Session] {
        let sessions = model.sessions
        let query = state.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sessions }
        let scored = sessions.enumerated().compactMap { index, session -> (Session, Int, Int)? in
            let fields = [session.projectName, session.headline, session.customTitle ?? "", session.lastPrompt ?? "",
                          AgentRegistry.displayName(for: session.source), session.hostLabel ?? "", session.cwd ?? ""]
            return QuickFind.score(query, fields: fields).map { (session, $0, index) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }.map(\.0)
    }

    var body: some View {
        let matches = self.matches
        let keys = matches.map(\.key)
        VStack(spacing: 0) {
            field
            if !matches.isEmpty {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ScrollViewReader { reader in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(Array(matches.enumerated()), id: \.element.key) { index, session in
                                row(session, index: index).id(session.key)
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: CGFloat(min(matches.count, SwitcherState.maxRows)) * 52 + 12)
                    .onChange(of: state.selected) { _, index in
                        guard keys.indices.contains(index) else { return }
                        withAnimation(Motion.snappy()) { reader.scrollTo(keys[index]) }
                    }
                }
            } else {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Text(model.sessions.isEmpty ? L("No sessions yet.") : L("No session matches."))
                    .font(look.body(12.5)).foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity).frame(height: 54)
            }
            footer
        }
        .background(
            IslandSurface(shape: RoundedRectangle(cornerRadius: look.radius(20), style: .continuous), style: look.style)
                .overlay(RoundedRectangle(cornerRadius: look.radius(20), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2))
        .frame(width: SwitcherState.width)
        .scaleEffect(state.shown ? 1 : 0.965, anchor: .top)
        .opacity(state.shown ? 1 : 0)
        .padding(SwitcherState.margin)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { state.height = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in state.height = height }
        })
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
        .onChange(of: state.shown) { _, shown in if shown { focused = true } }
        .onChange(of: keys, initial: true) { _, keys in
            state.results = keys
            if state.selected >= keys.count { state.selected = max(0, keys.count - 1) }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.tertiary)
            ZStack(alignment: .leading) {
                if state.query.isEmpty {
                    Text(L("Find a session: project, prompt or agent"))
                        .foregroundStyle(Theme.secondary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $state.query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.primary)
                    .accessibilityLabel(Text(L("Find a session: project, prompt or agent")))
                    .focused($focused)
            }
            .font(look.body(17))
            if !model.pending.isEmpty {
                Chip(text: L("%lld waiting", model.pending.count), tint: Theme.amber, mono: false)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    private func row(_ session: Session, index: Int) -> some View {
        let selected = index == state.selected
        let waiting = model.pending.contains { $0.sessionKey == session.key }
        return Button { choose(session.key) } label: {
            HStack(spacing: 12) {
                MascotView(source: session.source, size: 24, animated: session.phase == .working)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.headline).font(look.body(13.5, .semibold)).foregroundStyle(Theme.primary).lineLimit(1)
                    Text([session.projectName, AgentRegistry.displayName(for: session.source), session.hostLabel]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(look.body(11.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if waiting {
                    Chip(text: L("needs you"), tint: Theme.amber, mono: false)
                } else {
                    Circle().fill(Theme.color(for: session.phase, accent: look.accent)).frame(width: 7, height: 7)
                }
                Text(elapsedText(since: session.phaseSince, now: isStaticPreview ? PreviewClock.now : Date()))
                    .font(look.mono(10.5)).foregroundStyle(Theme.tertiary)
                if selected {
                    Image(systemName: "return").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                        .transition(.opacity.animation(Motion.fadeIn(0.15)))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: look.radius(12), style: .continuous)
                        .fill(look.accent.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: look.radius(12), style: .continuous)
                            .strokeBorder(look.accent.opacity(0.28), lineWidth: 1))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(pressed: 0.985))
        .onHover { inside in
            if inside, state.selected != index { withAnimation(Motion.snappy()) { state.selected = index } }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", L("move"))
            hint("↩", L("go to it"))
            hint("esc", L("close"))
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 32)
        .background(Color.white.opacity(0.025))
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(look.mono(10, .semibold)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.08)))
            Text(text).font(look.body(11)).foregroundStyle(Theme.tertiary)
        }
    }
}
