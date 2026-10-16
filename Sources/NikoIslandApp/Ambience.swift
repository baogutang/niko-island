import AppKit
import SwiftUI

// Small motions that say the island is alive without asking to be looked at:
// a glow beneath it, a dot that breathes, rows that arrive one after another
// (the light along its edge is in CreatureLayer.swift).
// All of them stand still in pictures and when Reduce Motion is on.

/// Colour seeping out from under the closed island: amber when someone is
/// waiting on you, the accent and faint while agents work, a short flash of it
/// when a turn finishes. It holds still: it may be there all day.
struct IslandGlow<S: Shape>: View {
    var shape: S
    var color: Color
    var strength: Double

    var body: some View {
        shape
            .fill(color)
            .blur(radius: 13)
            .scaleEffect(x: 1.04, y: 1.18, anchor: .top)
            .opacity(strength * 0.7)
            .allowsHitTesting(false)
            .transition(.opacity.animation(Motion.fadeIn(0.4)))
    }
}

/// The status dot of a row: a ring goes out from it while the session works or waits on you.
/// The ring is a Core Animation layer: a SwiftUI animation that never ends would have the
/// whole island drawn again on every frame for as long as it is open.
struct PulseDot: View {
    var color: Color
    var pulsing: Bool
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isStaticPreview) private var isStaticPreview

    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .background {
                if pulsing, !reduceMotion, !isStaticPreview {
                    PulseRing(color: NSColor(color)).frame(width: size * 3, height: size * 3).allowsHitTesting(false)
                }
            }
    }
}

private struct PulseRing: NSViewRepresentable {
    var color: NSColor

    func makeNSView(context: Context) -> PulseRingView { PulseRingView() }
    func updateNSView(_ view: PulseRingView, context: Context) { view.color = color }
}

private final class PulseRingView: NSView {
    private let ring = CAShapeLayer()
    var color: NSColor = .systemTeal { didSet { ring.strokeColor = color.cgColor } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        ring.fillColor = nil
        ring.lineWidth = 1.2
        ring.strokeColor = color.cgColor
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height) / 3
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.path = CGPath(ellipseIn: CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side), transform: nil)
        CATransaction.commit()
        guard ring.animation(forKey: "pulse") == nil else { return }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        let pulse = CAAnimationGroup()
        pulse.animations = [grow, fade]
        pulse.duration = 1.3
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulse.repeatCount = .infinity
        pulse.isRemovedOnCompletion = false
        ring.add(pulse, forKey: "pulse")
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
    func cascade(_ index: Int) -> some View { modifier(Cascade(index: index)) }
}
