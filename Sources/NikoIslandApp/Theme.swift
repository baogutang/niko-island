import NikoCore
import SwiftUI

/// Visual language of the island: pure black surface, bold type, soft chips.
enum Theme {
    static let island = Color.black
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.66)
    static let tertiary = Color.white.opacity(0.42)
    static let quaternary = Color.white.opacity(0.24)
    static let hairline = Color.white.opacity(0.08)
    static let chip = Color.white.opacity(0.10)
    static let field = Color.white.opacity(0.06)
    static let hover = Color.white.opacity(0.05)

    static let mint = Color(red: 0.42, green: 0.88, blue: 0.74)
    static let amber = Color(red: 0.98, green: 0.76, blue: 0.36)
    static let coral = Color(red: 1.00, green: 0.47, blue: 0.43)
    static let sky = Color(red: 0.45, green: 0.72, blue: 1.00)

    // Settings window surfaces.
    static let window = Color(red: 0.086, green: 0.090, blue: 0.102)
    static let sidebar = Color(red: 0.063, green: 0.066, blue: 0.075)
    static let card = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.09)

    static let violet = Color(red: 0.72, green: 0.62, blue: 1.00)

    static func color(for phase: Session.Phase, accent: Color = mint) -> Color {
        switch phase {
        case .working: return accent
        case .waiting: return amber
        case .needsAttention: return coral
        }
    }

    static func color(for accent: NikoSettings.Accent) -> Color {
        switch accent {
        case .mint: return mint
        case .sky: return sky
        case .violet: return violet
        case .amber: return amber
        case .coral: return coral
        }
    }

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

/// The parts of the island's look the user can change, handed down the view tree.
struct IslandLook: Equatable {
    var accent = Theme.mint
    /// Agent id → sprite name, for agents whose creature the user picked.
    var mascots: [String: String] = [:]
    var showMascots = true
    var compact = false
    var chips = Set(NikoSettings.RowChip.allCases.filter(\.shownByDefault))
    var replyLines = 1
    /// The island's type is drawn a little smaller or larger on request.
    var textScale: CGFloat = NikoSettings.TextSize.regular.scale
    /// How long the island takes to open and close, relative to the standard.
    var motion: Double = 1

    init() {}

    // Type inside the island: semibold rather than bold, so a list of sessions reads as a list.
    func title(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size * textScale, weight: weight, design: .rounded) }
    func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size * textScale, weight: weight) }
    func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size * textScale, weight: weight, design: .monospaced) }

    init(settings: NikoSettings) {
        textScale = settings.textSize.scale
        motion = settings.motion.factor
        replyLines = settings.replyLines
        accent = Theme.color(for: settings.accent)
        mascots = settings.mascotChoices
        showMascots = settings.showMascots
        compact = settings.rowDensity == .compact
        chips = Set(NikoSettings.RowChip.allCases.filter(settings.showsChip))
    }
}

private struct IslandLookKey: EnvironmentKey {
    static let defaultValue = IslandLook()
}

extension EnvironmentValues {
    var look: IslandLook {
        get { self[IslandLookKey.self] }
        set { self[IslandLookKey.self] = newValue }
    }
}

/// Tint used for an agent's chip. Our own palette, not vendor brand colours.
enum AgentTint {
    static func color(for source: String) -> Color {
        switch source {
        case "claude": return Color(red: 0.96, green: 0.60, blue: 0.42)
        case "codex": return Color(red: 0.47, green: 0.74, blue: 1.00)
        case "cursor": return Color(red: 0.80, green: 0.83, blue: 0.88)
        case "copilot": return Color(red: 0.72, green: 0.62, blue: 1.00)
        case "zcode": return Color(red: 0.96, green: 0.50, blue: 0.48)
        case "codebuddy": return Color(red: 0.60, green: 0.78, blue: 1.00)
        case "gemini": return Color(red: 0.62, green: 0.70, blue: 1.00)
        case "grok": return Color(red: 0.96, green: 0.83, blue: 0.40)
        case "opencode", "mimocode": return Color(red: 0.50, green: 0.86, blue: 0.62)
        case "qwen", "qwenwork": return Color(red: 0.52, green: 0.84, blue: 0.90)
        case "trae", "trae-cn": return Color(red: 0.98, green: 0.62, blue: 0.78)
        case "windsurf": return Color(red: 0.45, green: 0.88, blue: 0.80)
        case "kiro": return Color(red: 0.78, green: 0.66, blue: 1.00)
        case "factory": return Color(red: 0.95, green: 0.72, blue: 0.45)
        default: return Color.white.opacity(0.75)
        }
    }
}

// MARK: - Chips

struct Chip: View {
    var text: String
    var tint: Color?
    var mono = true
    @Environment(\.look) private var look

    var body: some View {
        Text(text)
            .font(mono ? look.mono(10.5) : look.body(10.5, .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint ?? Theme.primary.opacity(0.88))
            .background(Capsule().fill(tint.map { $0.opacity(0.20) } ?? Theme.chip))
    }
}

struct BellBadge: View {
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Theme.amber)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.amber.opacity(0.16)))
            .overlay(Circle().strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1))
            .accessibilityLabel(L("Needs you"))
    }
}

// MARK: - Buttons

/// Capsule buttons used across the island.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, neutral, destructive, ghost }
    var kind: Kind = .neutral
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        let text: Color
        switch kind {
        case .primary: fill = .white; text = .black
        case .neutral: fill = Color.white.opacity(0.12); text = .white
        case .destructive: fill = Theme.coral.opacity(0.20); text = Theme.coral
        case .ghost: fill = .clear; text = Theme.secondary
        }
        return configuration.label
            .font(Theme.body(large ? 13.5 : 12.5, .semibold))
            .lineLimit(1)
            .padding(.horizontal, large ? 18 : 13)
            .padding(.vertical, large ? 9.5 : 7)
            .foregroundStyle(text)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.65 : 1)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Round icon button for the island's header.
struct IconButton: View {
    var symbol: String
    var active = false
    var label: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.black : Theme.primary.opacity(hovering ? 1 : 0.8))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Color.white : Color.white.opacity(hovering ? 0.18 : 0.10)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Controls drawn in SwiftUI
// (AppKit-backed switches, sliders and pop-ups cannot be rendered off-screen for
// the documentation images, and would not match the island's look anyway.)

struct SwitchToggleStyle: ToggleStyle {
    var scale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                configuration.label
                Spacer(minLength: 8)
                SwitchTrack(isOn: configuration.isOn, scale: scale)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private struct SwitchTrack: View {
    var isOn: Bool
    var scale: CGFloat = 1
    @Environment(\.look) private var look

    var body: some View {
        Capsule()
            .fill(isOn ? look.accent : Color.white.opacity(0.16))
            .frame(width: 36 * scale, height: 21 * scale)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(Color.white).frame(width: 17 * scale, height: 17 * scale).padding(2 * scale)
            }
            .animation(.easeOut(duration: 0.14), value: isOn)
    }
}

struct LevelSlider: View {
    @Binding var value: Double
    @Environment(\.look) private var look

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 5)
                Capsule().fill(look.accent).frame(width: max(5, width * value), height: 5)
                Circle().fill(Color.white).frame(width: 15, height: 15)
                    .offset(x: min(max(0, width * value - 7.5), width - 15))
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(1, max(0, drag.location.x / max(1, width)))
            })
        }
        .frame(height: 18)
        .accessibilityValue("\(Int(value * 100))%")
    }
}

/// One-of-many choice as a row of pills.
struct ChoicePills<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    /// Drawn larger on a large welcome screen; type is laid out at that size, never magnified.
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 6 * scale) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(Theme.body(12 * scale, .semibold))
                        .padding(.horizontal, 12 * scale).padding(.vertical, 6.5 * scale)
                        .foregroundStyle(selection == option.value ? Color.black : Theme.primary.opacity(0.85))
                        .background(Capsule().fill(selection == option.value ? Color.white : Color.white.opacity(0.10)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct StaticPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering documentation images: no live text fields, no timers.
    var isStaticPreview: Bool {
        get { self[StaticPreviewKey.self] }
        set { self[StaticPreviewKey.self] = newValue }
    }
}

extension Activity {
    /// Verbs are a closed set (PROTOCOLS §1.2), so they can be looked up in the string catalog.
    var localizedVerb: String { L(verb) }
}

func elapsedText(since start: Date, now: Date) -> String {
    let seconds = max(0, now.timeIntervalSince(start).wholeSeconds)
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
}

func tokenText(_ count: Int) -> String {
    switch count {
    case 1_000_000_000...: return String(format: "%.1fB", Double(count) / 1_000_000_000)
    case 1_000_000...: return String(format: "%.1fM", Double(count) / 1_000_000)
    case 1_000...: return String(format: "%.1fK", Double(count) / 1_000)
    default: return "\(count)"
    }
}

func costText(_ cost: Double) -> String {
    cost > 0 && cost < 0.01 ? "<$0.01" : String(format: "$%.2f", cost)
}
