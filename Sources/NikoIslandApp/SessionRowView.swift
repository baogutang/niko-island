import NikoCore
import SwiftUI

extension Session {
    /// Name of the project the session runs in.
    var projectName: String {
        AutoNamer.projectName(cwd: cwd) ?? AgentRegistry.displayName(for: source)
    }

    /// The headline of a row: the session's own name, else what the user
    /// asked for, in their own words.
    var headline: String {
        if let name = customTitle.map({ Activity.oneLine($0, limit: 72) }), !name.isEmpty { return name }
        if let prompt = firstPrompt.map({ Activity.oneLine($0, limit: 72) }), !prompt.isEmpty { return prompt }
        return L("New session")
    }

    /// The latest prompt, when the headline does not already say it.
    var followUp: String? {
        guard let last = lastPrompt else { return nil }
        let line = Activity.oneLine(last, limit: 96)
        return line.isEmpty || line == headline || Activity.oneLine(last, limit: 72) == headline ? nil : line
    }

    /// Where the session lives, as the chip says it. An agent's own desktop
    /// app is "Desktop": its name is already on the chip next to it. (Hooks that
    /// run inside the app report it as their terminal, so the app is asked for,
    /// not whether there is a terminal.)
    var hostLabel: String? {
        let apps = AgentRegistry.descriptor(source)?.apps ?? []
        if let bundle = hostBundleID ?? host?.bundleID, apps.contains(bundle) { return L("Desktop") }
        guard let name = hostName else { return nil }
        let agent = AgentRegistry.displayName(for: source)
        // "Claude" next to "Claude Code", "ZCode" next to "ZCode": the same name twice.
        if agent.lowercased().hasPrefix(name.lowercased()) { return L("Desktop") }
        return name
    }

    /// What the agent said last, shown once it has stopped.
    var replyLine: String? { replyText(lines: 1) }

    /// The reply as one paragraph, long enough to fill the lines a row may use.
    func replyText(lines: Int) -> String? {
        guard lines > 0, phase == .waiting, let reply = lastReply else { return nil }
        let text = ReplyText.flattened(reply, limit: 110 * lines)
        return text.isEmpty ? nil : text
    }

    /// What to type in a terminal to pick this conversation up again, for the agents that have such a thing.
    var resumeCommand: String? {
        let id = key.sessionID
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        switch source {
        case "claude": return "claude --resume \(id)"
        case "codex": return "codex resume \(id)"
        default: return nil
        }
    }

    /// The model, shortened to what fits on a chip.
    var modelLabel: String? {
        model.map(ModelLabel.short).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// What a row shows besides its session, worked out by the list. A row never reads the
/// model while it draws, so an event in one session redraws that row and no other.
struct RowFacts: Equatable {
    var elapsed: String
    var mood: CreatureMood
    var moves: Bool
    var branch: String?
    /// The project the session works in; none for an agent's own workspace (the agent chip says who it is).
    var project: String?
    var cost: String?
    var canReply = false
    var reply: AppModel.ReplyState?
    /// "Auto-approving …" when the session has standing grants.
    var grants: String?
    var hovered = false

    @MainActor
    init(session: Session, model: AppModel, now: Date, hovered: Bool = false) {
        elapsed = elapsedText(since: session.phaseSince, now: now)
        mood = CreatureMood.of(session, now: now)
        moves = CreatureMood.moves(session, now: now)
        branch = session.cwd.flatMap { model.branches[$0] }
        project = AutoNamer.projectName(cwd: session.cwd)
        // A model with no list price is counted in tokens: said so, not a bare "11.1M".
        cost = model.usage.use(of: session.key).map { $0.cost >= 0.005 ? $0.label : L("%@ tokens", $0.label) }
        canReply = model.canReply(to: session.key)
        reply = model.replies[session.key]
        if model.grantedSessions.contains(session.key) {
            let summary = model.grantSummary(for: session.key)
            grants = summary.all ? L("Auto-approving everything this session") : L("Auto-approving: %@", summary.tools.joined(separator: ", "))
        }
        self.hovered = hovered
    }
}

/// One session in the flat list: creature, project and headline, what the
/// agent is doing right now, and a row of chips.
struct SessionRowView: View, Equatable {
    /// For what a click does; never read while drawing (see `RowFacts`).
    var model: AppModel
    let session: Session
    var facts: RowFacts
    /// Off under a heading that already names the project.
    var showsProject = true
    /// One line instead of the card, for a quiet session; resting the pointer on it opens the card.
    var compact = false
    /// The row the pointer is over. One highlight serves the whole list and slides to it.
    var hovered: Binding<SessionKey?>? = nil
    var hoverSpace: Namespace.ID? = nil
    @State private var hovering = false
    @State private var opened = false
    @State private var dwell: Task<Void, Never>?
    @Environment(\.look) private var look
    @Environment(\.islandNamespace) private var islandSpace

    nonisolated static func == (a: SessionRowView, b: SessionRowView) -> Bool {
        MainActor.assumeIsolated { a.session == b.session && a.facts == b.facts && a.showsProject == b.showsProject && a.compact == b.compact }
    }

    private var pendingHere: AppModel.PendingRequest? {
        model.pending.first { $0.sessionKey == session.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if compact && !opened { line } else { summary }
            }
                .contentShape(Rectangle())
                .onTapGesture {
                    // A row that is waiting on you opens its request; any other row takes you to its terminal.
                    if let pendingHere { model.focusedRequestID = pendingHere.id } else { model.jump(to: session.key) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            if facts.canReply || facts.reply != nil {
                // Its own line, so that a click into the field is not a click on the row.
                ReplyField(model: model, key: session.key).padding(.leading, 43)
            }
        }
        .padding(.vertical, compact && !opened ? 4 : (look.compact ? 5 : 9))
        .padding(.horizontal, 10)
        .background {
            if hovered != nil, let hoverSpace {
                if facts.hovered {
                    RoundedRectangle(cornerRadius: look.radius(14), style: .continuous).fill(Theme.hover)
                        .matchedGeometryEffect(id: "row-highlight", in: hoverSpace)
                }
            } else {
                RoundedRectangle(cornerRadius: look.radius(14), style: .continuous).fill(hovering ? Theme.hover : Color.clear)
            }
        }
        .padding(.horizontal, -10)
        .onHover { inside in
            hovering = inside
            // A one-line row opens after the pointer rests on it, so sweeping across the list stays calm.
            dwell?.cancel()
            if compact {
                if inside {
                    dwell = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(Motion.smooth(look.motion)) { opened = true }
                    }
                } else if opened {
                    withAnimation(Motion.smooth(look.motion)) { opened = false }
                }
            }
            // Entering a row takes the highlight; the list itself lets it go when the pointer leaves it.
            if inside, let hovered { withAnimation(Motion.snappy(look.motion)) { hovered.wrappedValue = session.key } }
        }
        .contextMenu {
            Button(L("Open in Terminal")) { model.jump(to: session.key) }
            if let reply = session.lastReply, !reply.isEmpty {
                Button(L("Copy the last reply")) { model.copy(reply) }
            }
            if let folder = session.cwd {
                Button(L("Show the folder in Finder")) { model.reveal(folder) }
            }
            if let command = session.resumeCommand {
                Button(L("Copy the command that resumes it")) { model.copy(command) }
            }
            if facts.grants != nil {
                Button(L("Stop auto-approving")) { model.revokeGrants(for: session.key) }
            }
            Button(L("Dismiss")) { model.dismiss(session.key) }
            if let folder = session.cwd, !folder.isEmpty {
                Divider()
                Button(L("Hide every session in %@", (folder as NSString).lastPathComponent)) {
                    withAnimation(Motion.smooth()) { model.hideSessions(inFolder: folder) }
                }
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 13) {
            MascotView(source: session.source, size: 30, animated: facts.moves, mood: facts.mood, seed: session.key.description)
                .travels("creature/" + session.key.description, in: islandSpace)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if showsProject, let project = facts.project {
                        Text(project)
                            .font(look.body(12.5, .medium)).foregroundStyle(Theme.secondary)
                            .lineLimit(1).fixedSize()
                    }
                    if look.chips.contains(.branch), let branch = facts.branch {
                        // The branch belongs to the project, so it sits with its name.
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 8.5, weight: .semibold))
                            Text(branch).font(look.mono(10.5, .regular)).lineLimit(1).truncationMode(.middle)
                        }
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: 130, alignment: .leading)
                        .fixedSize()
                        .help(branch)
                    }
                    if (showsProject && facts.project != nil) || (look.chips.contains(.branch) && facts.branch != nil) {
                        Text("·").font(look.body(12.5)).foregroundStyle(Theme.tertiary)
                    }
                    Text(session.headline)
                        .font(look.title(15, .medium)).foregroundStyle(Theme.primary)
                        .lineLimit(1).truncationMode(.tail)
                }
                if let followUp = session.followUp {
                    Text(L("You: %@", followUp))
                        .font(look.body(12)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                activityLine
                if let progress = session.progress, !(progress.isComplete && session.phase == .waiting) {
                    ProgressLine(progress: progress)
                }
                if let reply = session.replyText(lines: look.replyLines) {
                    Text(reply)
                        .font(look.body(12)).foregroundStyle(Theme.secondary).lineLimit(look.replyLines).truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let grants = facts.grants { grantLine(grants) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(chips) { chip in Chip(text: chip.text, tint: chip.tint) }
                if session.phase == .needsAttention { BellBadge().transition(.scale(scale: 0.4).combined(with: .opacity)) }
            }
            .padding(.top, 1)
        }
    }

    /// The one-line form: creature, project and headline, then the chips that tell rows apart.
    private var line: some View {
        HStack(spacing: 10) {
            MascotView(source: session.source, size: 18, mood: facts.mood, seed: session.key.description)
                .travels("creature/" + session.key.description, in: islandSpace)
                .frame(width: 30)
            HStack(spacing: 6) {
                if showsProject, let project = facts.project {
                    Text(project).font(look.body(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1).fixedSize()
                    Text("·").font(look.body(12)).foregroundStyle(Theme.tertiary)
                }
                Text(session.headline).font(look.body(13, .medium)).foregroundStyle(Theme.primary.opacity(0.86))
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if look.chips.contains(.elapsed) { Chip(text: facts.elapsed) }
                if look.chips.contains(.agent) {
                    Chip(text: AgentRegistry.displayName(for: session.source), tint: AgentTint.color(for: session.source))
                }
                if look.chips.contains(.host), let host = session.hostLabel { Chip(text: host) }
            }
            .opacity(0.85)
        }
        .frame(minHeight: 26)
    }

    private var activityLine: some View {
        HStack(spacing: 5) {
            PulseDot(color: Theme.color(for: session.phase, accent: look.accent), pulsing: session.phase != .waiting)
                .animation(Motion.smooth(look.motion), value: session.phase)
            Text(session.activity.localizedVerb)
                .font(look.body(12, .medium))
                .foregroundStyle(Theme.color(for: session.phase, accent: look.accent))
                .fixedSize()
            if let detail = session.activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(look.mono(11.5, .regular))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// The chips this row has room for: the least telling go first, so the headline keeps
    /// at least about half the row (a full set of chips once left it four letters).
    private var chips: [RowChip] {
        var all: [RowChip] = []
        if look.chips.contains(.elapsed) { all.append(RowChip(id: "elapsed", text: facts.elapsed, keep: 100)) }
        if look.chips.contains(.agent) {
            all.append(RowChip(id: "agent", text: AgentRegistry.displayName(for: session.source), tint: AgentTint.color(for: session.source), keep: 60))
        }
        if look.chips.contains(.host), let host = session.hostLabel { all.append(RowChip(id: "host", text: host, keep: 20)) }
        if look.chips.contains(.model), let model = session.modelLabel { all.append(RowChip(id: "model", text: model, keep: 30)) }
        if look.chips.contains(.cost), let cost = facts.cost { all.append(RowChip(id: "cost", text: cost, keep: 50)) }
        if let context = session.context, look.chips.contains(.context) || context.isNearlyFull {
            // Shown on request, and by itself once the context is nearly full: that is when it is news.
            all.append(RowChip(id: "context", text: L("context %@", context.label), tint: context.isNearlyFull ? Theme.amber : nil,
                               keep: context.isNearlyFull ? 95 : 40))
        }
        if session.subagents > 0 { all.append(RowChip(id: "helpers", text: L("%lld helpers", session.subagents), tint: Theme.sky, keep: 90)) }
        // The row's own width: the island's, less its margins and the creature.
        return RowChip.fit(all, budget: (look.islandWidth - 48 - 43) * 0.45, scale: look.textScale)
    }

    private func grantLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 10))
            Text(text).lineLimit(1)
            Button(L("Stop")) { model.revokeGrants(for: session.key) }
                .buttonStyle(.plain)
                .underline()
        }
        .font(look.body(11.5))
        .foregroundStyle(Theme.amber)
    }
}


/// One chip on a row, and how much it is worth keeping when the row is short of room.
struct RowChip: Identifiable {
    var id: String
    var text: String
    var tint: Color?
    /// Lower goes first.
    var keep: Int

    /// Leaves out the least telling chips until the rest fit in `budget` points (the order is kept).
    static func fit(_ chips: [RowChip], budget: CGFloat, scale: CGFloat) -> [RowChip] {
        let font = NSFont.monospacedSystemFont(ofSize: 10.5 * scale, weight: .medium)
        func width(_ chip: RowChip) -> CGFloat { ceil((chip.text as NSString).size(withAttributes: [.font: font]).width) + 16 }
        var kept = chips
        var total = kept.map(width).reduce(0, +) + CGFloat(max(0, kept.count - 1)) * 6
        while total > budget, kept.count > 1, let drop = kept.indices.min(by: { kept[$0].keep < kept[$1].keep }) {
            total -= width(kept[drop]) + 6
            kept.remove(at: drop)
        }
        return kept
    }
}
