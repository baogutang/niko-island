import SwiftUI

// Small motions that say the island is alive without asking to be looked at:
// a glow beneath it, a light running along its edge while agents work, a dot
// that breathes, a word that shimmers, rows that arrive one after another.
// All of them stand still in pictures and when Reduce Motion is on.

/// Colour seeping out from under the closed island: amber and breathing when
/// someone is waiting on you, the accent and faint while agents work, a short
/// flash of it when a turn finishes.
struct IslandGlow<S: Shape>: View {
    var shape: S
    var color: Color
    /// Breathes in and out; otherwise it holds steady.
    var breathing: Bool
    var strength: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var high = false

    var body: some View {
        shape
            .fill(color)
            .blur(radius: 13)
            .scaleEffect(x: 1.04, y: 1.18, anchor: .top)
            .opacity(strength * (breathing && !reduceMotion ? (high ? 1 : 0.35) : 0.7))
            .allowsHitTesting(false)
            .onAppear {
                guard breathing, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { high = true }
            }
            .transition(.opacity.animation(Motion.fadeIn(0.4)))
    }
}

/// A short bright stroke that runs along the bottom of the closed island while
/// agents work: the island is busy even when the creature is too small to see.
struct ActivitySheen: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                GeometryReader { proxy in
                    let period = 2.4
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    // Ease in and out across the width, with a pause off the edges.
                    let eased = 0.5 - 0.5 * cos(min(1, phase * 1.25) * .pi)
                    let width = proxy.size.width * 0.38
                    let x = -width + (proxy.size.width + width) * eased
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0), color.opacity(0.95), color.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: width, height: 1.6)
                        .offset(x: x, y: proxy.size.height - 1.8)
                        .blur(radius: 0.3)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

/// The status dot of a row: a ring goes out from it while the session works or waits on you.
struct PulseDot: View {
    var color: Color
    var pulsing: Bool
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isStaticPreview) private var isStaticPreview
    @State private var out = false

    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .background {
                if pulsing, !reduceMotion, !isStaticPreview {
                    Circle().stroke(color, lineWidth: 1.2)
                        .scaleEffect(out ? 2.6 : 1)
                        .opacity(out ? 0 : 0.7)
                        .onAppear {
                            out = false
                            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { out = true }
                        }
                        .onDisappear { out = false }
                }
            }
    }
}

/// Light passing over text, for the word that says an agent is at work.
struct TextShimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isStaticPreview) private var isStaticPreview

    func body(content: Content) -> some View {
        if active, !reduceMotion, !isStaticPreview {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    GeometryReader { proxy in
                        let period = 1.9
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                        let band = max(24, proxy.size.width * 0.6)
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + (proxy.size.width + 2 * band) * phase)
                    }
                }
                .mask(content)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

/// A row arriving with the others when the island opens: a moment after the one above it.
struct Cascade: ViewModifier {
    var index: Int
    @Environment(\.isStaticPreview) private var isStaticPreview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.look) private var look
    @State private var shown = false

    func body(content: Content) -> some View {
        let still = isStaticPreview || reduceMotion
        content
            .opacity(shown || still ? 1 : 0)
            .offset(y: shown || still ? 0 : 10)
            .onAppear {
                guard !still, !shown else { return }
                withAnimation(Motion.smooth(look.motion).delay(0.06 + Motion.stagger(index, step: 0.032))) { shown = true }
            }
    }
}

extension View {
    func shimmer(_ active: Bool) -> some View { modifier(TextShimmer(active: active)) }
    func cascade(_ index: Int) -> some View { modifier(Cascade(index: index)) }
}
