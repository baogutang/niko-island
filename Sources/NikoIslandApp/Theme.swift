import NikoCore
import SwiftUI

enum Theme {
    static let panel = Color(red: 0.055, green: 0.058, blue: 0.066)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.09)
    static let field = Color.black.opacity(0.35)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)

    static let working = Color(red: 0.36, green: 0.84, blue: 0.72)
    static let waiting = Color(red: 0.98, green: 0.76, blue: 0.36)
    static let attention = Color(red: 1.00, green: 0.47, blue: 0.43)
    static let accent = Color(red: 0.45, green: 0.72, blue: 1.00)

    static func color(for phase: Session.Phase) -> Color {
        switch phase {
        case .working: return working
        case .waiting: return waiting
        case .needsAttention: return attention
        }
    }
}

/// Compact capsule button used on cards.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, neutral, destructive }
    var kind: Kind = .neutral

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        let text: Color
        switch kind {
        case .primary: fill = Theme.working; text = .black
        case .neutral: fill = Color.white.opacity(0.12); text = .white
        case .destructive: fill = Theme.attention.opacity(0.22); text = Theme.attention
        }
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(text)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.6 : 1)))
            .contentShape(Capsule())
    }
}

extension Activity {
    /// Verbs are a closed set (PROTOCOLS §1.2), so they can be looked up in the string catalog.
    var localizedVerb: String { L(verb) }
}

func elapsedText(since start: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(start)))
    if seconds < 3600 { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
    return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
}

/// Drawn checkbox: matches the dark panel and, unlike the AppKit-backed
/// control, can be rendered off-screen for documentation images.
struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(configuration.isOn ? Theme.working : Theme.tertiary)
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private struct StaticPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering documentation images, where live text fields cannot be drawn.
    var isStaticPreview: Bool {
        get { self[StaticPreviewKey.self] }
        set { self[StaticPreviewKey.self] = newValue }
    }
}
