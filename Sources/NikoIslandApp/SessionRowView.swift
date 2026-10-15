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
    /// app is "Desktop": its name is already on the chip next to it.
    var hostLabel: String? {
        if let host, terminal.isEmpty, AgentRegistry.descriptor(source)?.apps.contains(host.bundleID ?? "") == true {
            return L("Desktop")
        }
        return hostName
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

/// One session in the flat list: creature, project and headline, what the
/// agent is doing right now, and a row of chips.
struct SessionRowView: View {
    @ObservedObject var model: AppModel
    let session: Session
    var now: Date
    /// Off under a heading that already names the project.
    var showsProject = true
    /// The row the pointer is over. One highlight serves the whole list and slides to it.
    var hovered: Binding<SessionKey?>? = nil
    var hoverSpace: Namespace.ID? = nil
    @State private var hovering = false
    @Environment(\.look) private var look
    @Environment(\.islandNamespace) private var islandSpace

    private var pendingHere: AppModel.PendingRequest? {
        model.pending.first { $0.sessionKey == session.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summary
                .contentShape(Rectangle())
                .onTapGesture {
                    // A row that is waiting on you opens its request; any other row takes you to its terminal.
                    if let pendingHere { model.focusedRequestID = pendingHere.id } else { model.jump(to: session.key) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            if model.canReply(to: session.key) || model.replies[session.key] != nil {
                // Its own line, so that a click into the field is not a click on the row.
                ReplyField(model: model, key: session.key).padding(.leading, 43)
            }
        }
        .padding(.vertical, look.compact ? 5 : 9)
        .padding(.horizontal, 10)
        .background {
            if let hovered, let hoverSpace {
                if hovered.wrappedValue == session.key {
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
            if model.grantedSessions.contains(session.key) {
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
            MascotView(source: session.source, size: 30, animated: session.phase == .working)
                .travels("creature/" + session.key.description, in: islandSpace)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if showsProject {
                        Text(session.projectName)
                            .font(look.body(12.5, .medium)).foregroundStyle(Theme.secondary)
                            .lineLimit(1).fixedSize()
                    }
                    if look.chips.contains(.branch), let branch = session.cwd.flatMap({ model.branches[$0] }) {
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
                    if showsProject || (look.chips.contains(.branch) && session.cwd.flatMap({ model.branches[$0] }) != nil) {
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
                if model.grantedSessions.contains(session.key) { grantLine }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if look.chips.contains(.elapsed) { Chip(text: elapsedText(since: session.phaseSince, now: now)) }
                if look.chips.contains(.agent) {
                    Chip(text: AgentRegistry.displayName(for: session.source), tint: AgentTint.color(for: session.source))
                }
                if look.chips.contains(.host), let host = session.hostLabel { Chip(text: host) }
                if look.chips.contains(.model), let model = session.modelLabel { Chip(text: model) }
                if look.chips.contains(.cost), let use = model.usage.use(of: session.key) { Chip(text: use.label) }
                if let context = session.context, look.chips.contains(.context) || context.isNearlyFull {
                    // Shown on request, and by itself once the context is nearly full: that is when it is news.
                    Chip(text: L("context %@", context.label), tint: context.isNearlyFull ? Theme.amber : nil)
                }
                if session.subagents > 0 { Chip(text: L("%lld helpers", session.subagents), tint: Theme.sky) }
                if session.phase == .needsAttention { BellBadge().transition(.scale(scale: 0.4).combined(with: .opacity)) }
            }
            .padding(.top, 1)
        }
    }

    private var activityLine: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.color(for: session.phase, accent: look.accent)).frame(width: 6, height: 6)
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

    private var grantLine: some View {
        let summary = model.grantSummary(for: session.key)
        let text = summary.all ? L("Auto-approving everything this session")
            : L("Auto-approving: %@", summary.tools.joined(separator: ", "))
        return HStack(spacing: 6) {
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
