import NikoCore
import SwiftUI

/// The agent's own words, with the light formatting it tends to use (bold,
/// italics, code, links) drawn as such instead of as asterisks and backticks.
enum ReplyText {
    static func attributed(_ text: String, limit: Int = 900) -> AttributedString {
        let clipped = text.count > limit ? String(text.prefix(limit)) + "…" : text
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: clipped, options: options)) ?? AttributedString(clipped)
    }

    /// One paragraph for a row: line breaks become spaces, markup characters are dropped.
    static func flattened(_ text: String, limit: Int) -> String {
        let plain = String(attributed(text, limit: limit * 2).characters)
        let joined = plain.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return joined.count > limit ? String(joined.prefix(limit - 1)) + "…" : joined
    }
}

/// A thin bar for how far an agent is through its own list of steps.
struct ProgressLine: View {
    var progress: TaskProgress
    var showsStep = true
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(look.accent).frame(width: max(3, proxy.size.width * CGFloat(progress.fraction)))
                }
            }
            .frame(width: 64, height: 4)
            Text("\(progress.done)/\(progress.total)").font(look.mono(10.5)).foregroundStyle(Theme.secondary)
            if showsStep, let step = progress.current, !progress.isComplete {
                Text(step).font(look.body(11.5)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%lld of %lld steps done", progress.done, progress.total))
    }
}

/// What the island shows for a few seconds when a turn ends: who finished,
/// what they said, and a way back to them. It opens nothing and decides
/// nothing; a click goes to the session, the ✕ puts the card away.
struct CompletionCard: View {
    @ObservedObject var model: AppModel
    var completion: AppModel.Completion
    var metrics: IslandMetrics
    @Environment(\.look) private var look
    @State private var hovering = false
    @State private var typing = false

    var body: some View {
        let tone = completion.failed ? Theme.coral : look.accent
        VStack(alignment: .leading, spacing: 0) {
            // The band the menu bar occupies: on a notched display its middle is behind the camera.
            HStack(spacing: 7) {
                MascotView(source: completion.source, size: 17)
                Text(completion.failed ? L("Stopped with an error") : L("Finished"))
                    .font(look.body(11.5, .semibold)).foregroundStyle(tone)
                Image(systemName: completion.failed ? "exclamationmark" : "checkmark")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(tone)
                Spacer(minLength: 0)
                Button { model.dismissCompletion() } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondary)
                        .frame(width: 22, height: 18)
                        .background(RoundedRectangle(cornerRadius: look.radius(6), style: .continuous).fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Dismiss"))
            }
            .padding(.horizontal, 16)
            .frame(height: max(metrics.bandHeight, 30))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(completion.project).font(look.body(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1).fixedSize()
                    Text("·").font(look.body(12)).foregroundStyle(Theme.tertiary)
                    Text(completion.title).font(look.title(14.5, .medium)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.tail)
                }
                if let reply = completion.reply {
                    Text(ReplyText.attributed(reply))
                        .font(look.body(12.5)).foregroundStyle(Theme.primary.opacity(0.86))
                        .lineSpacing(2).lineLimit(6).truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    if let progress = completion.progress { ProgressLine(progress: progress, showsStep: false) }
                    Spacer(minLength: 0)
                    Text(L("Click to go to the session")).font(look.body(11)).foregroundStyle(Theme.tertiary)
                    Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, model.canReply(to: completion.key) ? 8 : 14)
            .contentShape(Rectangle())
            .onTapGesture { model.openCompletion() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            if model.canReply(to: completion.key) {
                ReplyField(model: model, key: completion.key) { focused in
                    typing = focused
                    model.holdCompletion(focused || hovering)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(width: min(CGFloat(model.settings.islandWidth.points), 520))
        .onHover { inside in
            hovering = inside
            model.holdCompletion(inside || typing)
        }
    }
}

/// A line to type a follow-up into. The island takes the keyboard only once
/// the field is clicked; Return sends what was typed into the session's terminal.
struct ReplyField: View {
    @ObservedObject var model: AppModel
    var key: SessionKey
    var onFocus: (Bool) -> Void = { _ in }
    @Environment(\.look) private var look
    @Environment(\.isStaticPreview) private var isStaticPreview
    @State private var text = ""
    @FocusState private var focused: Bool

    private func send() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.reply(to: key, text)
        text = ""
    }

    var body: some View {
        let state = model.replies[key]
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 9.5)).foregroundStyle(Theme.tertiary)
            if state == .sent {
                Text(L("Sent to its terminal")).font(look.body(12)).foregroundStyle(look.accent)
                Spacer(minLength: 0)
            } else if isStaticPreview {
                Text(L("Reply…")).font(look.body(12)).foregroundStyle(Theme.tertiary)
                Spacer(minLength: 0)
            } else {
                TextField(L("Reply…"), text: $text)
                    .textFieldStyle(.plain).font(look.body(12)).foregroundStyle(Theme.primary)
                    .focused($focused)
                    .onSubmit(send)
                    .disabled(state == .sending)
                if state == .failed {
                    Text(L("Not sent: its terminal is not waiting for input")).font(look.body(11)).foregroundStyle(Theme.coral).lineLimit(1)
                }
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.black)
                        .frame(width: 18, height: 18).background(Circle().fill(Color.white.opacity(text.isEmpty ? 0.25 : 0.95)))
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty || state == .sending)
                .accessibilityLabel(L("Send"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: look.radius(10), style: .continuous).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: look.radius(10), style: .continuous).strokeBorder(Theme.hairline))
        .onChange(of: focused) { _, now in onFocus(now) }
    }
}

/// What ended while the screen was locked or asleep, said once when somebody
/// is back: one line per session, each a way to that session.
struct RecapCard: View {
    @ObservedObject var model: AppModel
    var recap: AppModel.Recap
    var metrics: IslandMetrics
    @Environment(\.look) private var look
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                MascotView(sprite: Mascots.island, size: 17)
                Text(L("While you were away")).font(look.body(11.5, .semibold)).foregroundStyle(look.accent)
                Text(L("%lld finished", recap.items.count)).font(look.body(11.5)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                Button { model.dismissRecap() } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondary)
                        .frame(width: 22, height: 18)
                        .background(RoundedRectangle(cornerRadius: look.radius(6), style: .continuous).fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Dismiss"))
            }
            .padding(.horizontal, 16)
            .frame(height: max(metrics.bandHeight, 30))

            VStack(alignment: .leading, spacing: 2) {
                ForEach(recap.items) { item in
                    RecapLine(item: item) { model.openRecap(item.key) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .frame(width: min(CGFloat(model.settings.islandWidth.points), 520))
        .onHover { inside in
            hovering = inside
            model.holdRecap(inside)
        }
    }
}

private struct RecapLine: View {
    var item: AppModel.Recap.Item
    var action: () -> Void
    @Environment(\.look) private var look
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            MascotView(source: item.key.source, size: 18)
            Text(item.project).font(look.body(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1).fixedSize()
            Text("·").font(look.body(12)).foregroundStyle(Theme.tertiary)
            Text(item.title).font(look.title(13.5, .medium)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            Image(systemName: item.failed ? "exclamationmark" : "checkmark")
                .font(.system(size: 9, weight: .heavy)).foregroundStyle(item.failed ? Theme.coral : look.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: look.radius(10), style: .continuous).fill(hovering ? Theme.hover : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
