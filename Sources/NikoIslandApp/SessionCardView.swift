import NikoCore
import SwiftUI

struct SessionCardView: View {
    @ObservedObject var model: AppModel
    let session: Session
    var now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: AgentRegistry.symbol(for: session.source))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.color(for: session.phase))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.color(for: session.phase).opacity(0.16)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(elapsedText(since: session.phaseSince, now: now))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                }
                activityLine
                if model.grantedSessions.contains(session.key) { grantLine }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(count: 2) { model.jump(to: session.key) }
        .contextMenu {
            Button(L("Open in Terminal")) { model.jump(to: session.key) }
            if model.grantedSessions.contains(session.key) {
                Button(L("Stop auto-approving")) { model.revokeGrants(for: session.key) }
            }
            Button(L("Dismiss")) { model.dismiss(session.key) }
        }
        .accessibilityElement(children: .combine)
    }

    private var activityLine: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.color(for: session.phase)).frame(width: 6, height: 6)
            Text(AgentRegistry.displayName(for: session.source))
                .foregroundStyle(Theme.secondary)
            Text("·").foregroundStyle(Theme.tertiary)
            Text(session.activity.localizedVerb)
                .foregroundStyle(Theme.color(for: session.phase))
            if let detail = session.activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }

    private var grantLine: some View {
        let summary = model.grantSummary(for: session.key)
        let text = summary.all ? L("Auto-approving everything this session")
            : L("Auto-approving: %@", summary.tools.joined(separator: ", "))
        return HStack(spacing: 6) {
            Image(systemName: "checkmark.shield").font(.system(size: 10))
            Text(text).lineLimit(1)
            Button(L("Stop")) { model.revokeGrants(for: session.key) }
                .buttonStyle(.plain)
                .underline()
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.waiting)
    }
}
