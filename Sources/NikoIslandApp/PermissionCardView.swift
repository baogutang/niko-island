import NikoCore
import SwiftUI

/// A pending permission request. It stays until the user decides or the agent withdraws it.
struct PermissionCardView: View {
    @ObservedObject var model: AppModel
    let request: AppModel.PendingRequest

    private var sessionTitle: String {
        model.sessions.first { $0.key == request.sessionKey }?.title ?? AgentRegistry.displayName(for: request.event.source)
    }

    private var headline: String {
        let agent = AgentRegistry.displayName(for: request.event.source)
        switch request.summary.kind {
        case .command: return L("%@ wants to run a command", agent)
        case .edit(let file): return L("%@ wants to edit %@", agent, file ?? L("a file"))
        case .read(let file): return L("%@ wants to read %@", agent, file ?? L("a file"))
        case .fetch: return L("%@ wants to fetch a URL", agent)
        case .search: return L("%@ wants to search the project", agent)
        case .subagent: return L("%@ wants to start a sub-agent", agent)
        case .other(let tool): return L("%@ wants to use %@", agent, tool)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.attention).font(.system(size: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary).lineLimit(2)
                    Text(sessionTitle).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            if let detail = request.summary.detail {
                Text(detail)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.primary.opacity(0.9))
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
            }
            HStack(spacing: 6) {
                Button(L("Allow once")) { model.decide(request.id, .allowOnce) }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                if let tool = request.event.toolName {
                    Button(L("Always allow %@", tool)) { model.decide(request.id, .allowAlwaysTool) }
                        .buttonStyle(PillButtonStyle())
                        .help(L("Allow this tool for the rest of the session"))
                }
                Button(L("Allow all")) { model.decide(request.id, .allowAllSession) }
                    .buttonStyle(PillButtonStyle())
                    .help(L("Allow every request for the rest of this session"))
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Button(L("Deny")) { model.decide(request.id, .deny) }
                    .buttonStyle(PillButtonStyle(kind: .destructive))
                Button { model.decide(request.id, .passToTerminal) } label: {
                    Label(L("Open in Terminal"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(PillButtonStyle())
                .help(L("Decide in the agent's own prompt instead"))
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.attention.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.attention.opacity(0.45)))
    }
}
