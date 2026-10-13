import NikoCore
import SwiftUI

/// Turns what was ticked and typed into the answer for one question.
enum QuestionAnswers {
    /// Labels chosen for a question, in option order, plus any free-text answer.
    static func answer(for question: AgentQuestion, selected: Set<String>, custom: String) -> [String] {
        var out = question.options.map(\.label).filter(selected.contains)
        let typed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            if question.multiSelect { out.append(typed) } else { out = [typed] }
        }
        return out
    }
}

/// The request that needs a decision, opened up at the top of the island.
/// It stays until the user decides or the agent withdraws it.
struct RequestDetailView: View {
    @ObservedObject var model: AppModel
    let request: AppModel.PendingRequest

    private var session: Session? { model.sessions.first { $0.key == request.sessionKey } }
    private var agent: String { AgentRegistry.displayName(for: request.event.source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if request.isQuestion {
                QuestionForm(model: model, request: request)
            } else {
                PermissionForm(model: model, request: request)
            }
        }
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            MascotView(source: request.event.source, size: 36)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.amber)
                        .offset(x: 7, y: -6)
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session?.projectName ?? agent)
                        .font(Theme.body(13, .medium)).foregroundStyle(Theme.secondary).lineLimit(1).fixedSize()
                    Text("·").foregroundStyle(Theme.tertiary)
                    Text(session?.headline ?? L("New session"))
                        .font(Theme.title(16)).foregroundStyle(Theme.primary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Chip(text: agent, tint: AgentTint.color(for: request.event.source))
                    if let host = session?.hostName { Chip(text: host) }
                    if model.pending.count > 1 {
                        Chip(text: L("%lld waiting", model.pending.count), tint: Theme.amber)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Permission

struct PermissionForm: View {
    @ObservedObject var model: AppModel
    let request: AppModel.PendingRequest

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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(Theme.title(17)).foregroundStyle(Theme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Nothing happens until you decide. The agent is waiting."))
                    .font(Theme.body(12.5)).foregroundStyle(Theme.secondary)
            }
            if let detail = request.summary.detail {
                Text(detail)
                    .font(Theme.mono(12.5, .regular))
                    .foregroundStyle(Theme.primary.opacity(0.92))
                    .lineLimit(7)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
            }
            HStack(spacing: 8) {
                Button(L("Allow once")) { model.decide(request.id, .allowOnce) }
                    .buttonStyle(PillButtonStyle(kind: .primary, large: true))
                if let tool = request.event.toolName {
                    Button(L("Always allow %@", tool)) { model.decide(request.id, .allowAlwaysTool) }
                        .buttonStyle(PillButtonStyle(large: true))
                        .help(L("Allow this tool for the rest of the session"))
                }
                Button(L("Allow all")) { model.decide(request.id, .allowAllSession) }
                    .buttonStyle(PillButtonStyle(large: true))
                    .help(L("Allow every request for the rest of this session"))
                Spacer(minLength: 0)
                Button(L("Deny")) { model.decide(request.id, .deny) }
                    .buttonStyle(PillButtonStyle(kind: .destructive, large: true))
            }
            Button { model.decide(request.id, .passToTerminal) } label: {
                Label(L("Decide in the terminal instead"), systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(PillButtonStyle(kind: .ghost))
            .padding(.leading, -13)
            .help(L("Decide in the agent's own prompt instead"))
        }
    }
}

// MARK: - Question

/// Answer form for question-style requests: options as tiles, one question at
/// a time. The result goes back as `updatedInput.answers`.
struct QuestionForm: View {
    @ObservedObject var model: AppModel
    let request: AppModel.PendingRequest

    @State private var step = 0
    @State private var selections: [Int: Set<String>] = [:]
    @State private var custom: [Int: String] = [:]
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var question: AgentQuestion { request.questions[min(step, request.questions.count - 1)] }
    private var isLast: Bool { step >= request.questions.count - 1 }

    private func answers() -> [[String]] {
        request.questions.map { QuestionAnswers.answer(for: $0, selected: selections[$0.id] ?? [], custom: custom[$0.id] ?? "") }
    }

    private var currentAnswered: Bool {
        !QuestionAnswers.answer(for: question, selected: selections[question.id] ?? [], custom: custom[question.id] ?? "").isEmpty
    }

    private func toggle(_ label: String) {
        var set = selections[question.id] ?? []
        if question.multiSelect {
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
        } else {
            set = [label]
            custom[question.id] = ""
        }
        selections[question.id] = set
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("%@ has a question", AgentRegistry.displayName(for: request.event.source)))
                    .font(Theme.title(17)).foregroundStyle(Theme.primary)
                Text(L("Answer here and the agent carries on with the session."))
                    .font(Theme.body(12.5)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if let header = question.header, !header.isEmpty {
                        Text(header).font(Theme.mono(12, .semibold)).foregroundStyle(Theme.sky)
                    }
                    if request.questions.count > 1 {
                        Text(L("Question %lld of %lld", step + 1, request.questions.count))
                            .font(Theme.mono(11)).foregroundStyle(Theme.tertiary)
                    }
                    if question.multiSelect {
                        Text(L("Choose any that apply")).font(Theme.body(11.5)).foregroundStyle(Theme.tertiary)
                    }
                }
                Text(question.text)
                    .font(Theme.body(15, .semibold)).foregroundStyle(Theme.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    tile(option, letter: index)
                }
            }
            otherField
            HStack(spacing: 8) {
                if step > 0 {
                    Button(L("Back")) { step -= 1 }.buttonStyle(PillButtonStyle(large: true))
                }
                Button(isLast ? L("Send answers") : L("Next")) {
                    if isLast { model.decide(request.id, .answer(answers())) } else { step += 1 }
                }
                .buttonStyle(PillButtonStyle(kind: .primary, large: true))
                .disabled(!currentAnswered)
                .opacity(currentAnswered ? 1 : 0.4)
                Spacer(minLength: 0)
                Button { model.decide(request.id, .passToTerminal) } label: {
                    Label(L("Answer in the terminal"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(PillButtonStyle(kind: .ghost))
            }
        }
    }

    private func tile(_ option: AgentQuestion.Option, letter: Int) -> some View {
        let selected = selections[question.id]?.contains(option.label) ?? false
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let badge = letter < 26 ? String(UnicodeScalar(UInt8(65 + letter))) : "•"
        return Button { toggle(option.label) } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(badge)
                    .font(Theme.mono(11, .bold))
                    .foregroundStyle(selected ? Color.black : Theme.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(selected ? Theme.sky : Color.white.opacity(0.10)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(Theme.body(13.5, .semibold)).foregroundStyle(Theme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = option.detail, !detail.isEmpty {
                        Text(detail).font(Theme.body(11.5)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .background(shape.fill(selected ? Theme.sky.opacity(0.14) : Theme.field))
            .overlay(shape.strokeBorder(selected ? Theme.sky.opacity(0.9) : Theme.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var otherField: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 8) {
            Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary)
            if isStaticPreview {
                Text(L("Type something else…")).font(Theme.body(13)).foregroundStyle(Theme.tertiary)
                Spacer(minLength: 0)
            } else {
                TextField(L("Type something else…"), text: Binding(
                    get: { custom[question.id] ?? "" },
                    set: { value in
                        custom[question.id] = value
                        if !question.multiSelect, !value.trimmingCharacters(in: .whitespaces).isEmpty { selections[question.id] = [] }
                    }))
                    .textFieldStyle(.plain)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(shape.fill(Theme.field))
        .overlay(shape.strokeBorder(Theme.hairline))
    }
}
