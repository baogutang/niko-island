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

    /// What the agent said last, shown once it has stopped.
    var replyLine: String? {
        guard phase == .waiting, let reply = lastReply else { return nil }
        let line = Activity.oneLine(reply, limit: 120)
        return line.isEmpty ? nil : line
    }
}

/// One session in the flat list: creature, project and headline, what the
/// agent is doing right now, and a row of chips.
struct SessionRowView: View {
    @ObservedObject var model: AppModel
    let session: Session
    var now: Date
    @State private var hovering = false

    private var pendingHere: AppModel.PendingRequest? {
        model.pending.first { $0.sessionKey == session.key }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            MascotView(source: session.source, size: 30, animated: session.phase == .working)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.projectName)
                        .font(Theme.body(12.5, .medium)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).fixedSize()
                    Text("·").font(Theme.body(12.5)).foregroundStyle(Theme.tertiary)
                    Text(session.headline)
                        .font(Theme.title(15)).foregroundStyle(Theme.primary)
                        .lineLimit(1).truncationMode(.tail)
                }
                if let followUp = session.followUp {
                    Text(L("You: %@", followUp))
                        .font(Theme.body(12)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                activityLine
                if let reply = session.replyLine {
                    Text(reply)
                        .font(Theme.body(12)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.tail)
                }
                if model.grantedSessions.contains(session.key) { grantLine }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Chip(text: elapsedText(since: session.phaseSince, now: now))
                Chip(text: AgentRegistry.displayName(for: session.source), tint: AgentTint.color(for: session.source))
                if let host = session.hostName { Chip(text: host) }
                if session.subagents > 0 { Chip(text: L("%lld helpers", session.subagents), tint: Theme.sky) }
                if session.phase == .needsAttention { BellBadge() }
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovering ? Theme.hover : Color.clear))
        .padding(.horizontal, -10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            // A row that is waiting on you opens its request; any other row takes you to its terminal.
            if let pendingHere { model.focusedRequestID = pendingHere.id } else { model.jump(to: session.key) }
        }
        .contextMenu {
            Button(L("Open in Terminal")) { model.jump(to: session.key) }
            if model.grantedSessions.contains(session.key) {
                Button(L("Stop auto-approving")) { model.revokeGrants(for: session.key) }
            }
            Button(L("Dismiss")) { model.dismiss(session.key) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var activityLine: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.color(for: session.phase)).frame(width: 6, height: 6)
            Text(session.activity.localizedVerb)
                .font(Theme.body(12, .medium))
                .foregroundStyle(Theme.color(for: session.phase))
                .fixedSize()
            if let detail = session.activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.mono(11.5, .regular))
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
        .font(Theme.body(11.5))
        .foregroundStyle(Theme.amber)
    }
}
