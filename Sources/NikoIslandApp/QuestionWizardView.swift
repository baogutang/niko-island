import NikoCore
import SwiftUI

/// Multi-step answer form for AskUserQuestion-style requests.
/// The result is sent back as `updatedInput.answers` (one label array per question).
struct QuestionWizardView: View {
    @ObservedObject var model: AppModel
    let request: AppModel.PendingRequest

    @State private var step = 0
    @State private var selections: [Int: Set<String>] = [:]
    @State private var custom: [Int: String] = [:]
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var question: AgentQuestion { request.questions[min(step, request.questions.count - 1)] }
    private var isLast: Bool { step >= request.questions.count - 1 }

    /// Labels chosen for a question, in option order, plus any free-text answer.
    static func answer(for question: AgentQuestion, selected: Set<String>, custom: String) -> [String] {
        var out = question.options.map(\.label).filter(selected.contains)
        let typed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            if question.multiSelect { out.append(typed) } else { out = [typed] }
        }
        return out
    }

    private func answers() -> [[String]] {
        request.questions.map { QuestionWizardView.answer(for: $0, selected: selections[$0.id] ?? [], custom: custom[$0.id] ?? "") }
    }

    private var currentAnswered: Bool {
        !QuestionWizardView.answer(for: question, selected: selections[question.id] ?? [], custom: custom[question.id] ?? "").isEmpty
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(Theme.accent).font(.system(size: 12))
                Text(request.questions.count > 1
                     ? L("Question %lld of %lld", step + 1, request.questions.count)
                     : L("%@ has a question", AgentRegistry.displayName(for: request.event.source)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                if let header = question.header, !header.isEmpty {
                    Text(header).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 0)
            }
            Text(question.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
            if question.multiSelect {
                Text(L("Choose any that apply")).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(question.options) { option in optionRow(option) }
            }
            otherField
            HStack(spacing: 6) {
                if step > 0 {
                    Button(L("Back")) { step -= 1 }.buttonStyle(PillButtonStyle())
                }
                Button(isLast ? L("Send answer") : L("Next")) {
                    if isLast { model.decide(request.id, .answer(answers())) } else { step += 1 }
                }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .disabled(!currentAnswered)
                .opacity(currentAnswered ? 1 : 0.45)
                Spacer(minLength: 0)
                Button { model.decide(request.id, .passToTerminal) } label: {
                    Label(L("Open in Terminal"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.45)))
    }

    @ViewBuilder
    private var otherField: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if isStaticPreview {
            Text(L("Other…")).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(shape.fill(Theme.field))
        } else {
            TextField(L("Other…"), text: Binding(
                get: { custom[question.id] ?? "" },
                set: { value in
                    custom[question.id] = value
                    if !question.multiSelect, !value.trimmingCharacters(in: .whitespaces).isEmpty { selections[question.id] = [] }
                }))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(shape.fill(Theme.field))
        }
    }

    private func optionRow(_ option: AgentQuestion.Option) -> some View {
        let selected = selections[question.id]?.contains(option.label) ?? false
        let symbol = question.multiSelect ? (selected ? "checkmark.square.fill" : "square")
            : (selected ? "largecircle.fill.circle" : "circle")
        return Button { toggle(option.label) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.accent : Theme.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.primary)
                    if let detail = option.detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Theme.accent.opacity(0.16) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
