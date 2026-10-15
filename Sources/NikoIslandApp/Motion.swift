import SwiftUI

/// One vocabulary of motion for the whole app.
///
/// Anything that changes size or place moves on a spring: a spring keeps its
/// speed when it is interrupted, so a hover that changes its mind half way
/// turns round from where it is instead of jumping. Only appearing and
/// disappearing use timed curves, and those are lopsided on purpose: a thing
/// arrives fast and settles slowly, and leaves quickly without lingering.
///
/// `scale` is the user's "how fast it opens and closes" (1 is standard).
enum Motion {
    /// Growing, opening: settles with the lightest overshoot.
    static func open(_ scale: Double = 1) -> Animation { .spring(response: 0.36 * scale, dampingFraction: 0.82) }
    /// Shrinking, closing: no overshoot, and quicker than opening.
    static func close(_ scale: Double = 1) -> Animation { .spring(response: 0.25 * scale, dampingFraction: 1) }
    /// Small things that follow the pointer or a press: quick and firm.
    static func snappy(_ scale: Double = 1) -> Animation { .spring(response: 0.22 * scale, dampingFraction: 0.86) }
    /// Content finding its place.
    static func smooth(_ scale: Double = 1) -> Animation { .spring(response: 0.42 * scale, dampingFraction: 0.92) }
    /// Something landing: a card dropping out of the island, the island arriving.
    static func land(_ scale: Double = 1) -> Animation { .spring(response: 0.5 * scale, dampingFraction: 0.7) }

    /// Arriving: a fast start and a long, soft settle (cubic Bézier 0.05, 0.7, 0.1, 1).
    static func fadeIn(_ duration: Double = 0.24) -> Animation { .timingCurve(0.05, 0.7, 0.1, 1, duration: duration) }
    /// Leaving: gone before it is noticed (cubic Bézier 0.3, 0, 0.8, 0.15).
    static func fadeOut(_ duration: Double = 0.12) -> Animation { .timingCurve(0.3, 0, 0.8, 0.15, duration: duration) }

    /// Delay for the n-th of several things arriving together: a cascade, not a wall.
    static func stagger(_ index: Int, step: Double = 0.028, cap: Int = 8) -> Double {
        Double(min(max(index, 0), cap)) * step
    }
}

extension AnyTransition {
    /// Content arriving in place: rises a few points and fades up, never blurs.
    static var rise: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.985, anchor: .top))
                .animation(Motion.fadeIn()),
            removal: .opacity.animation(Motion.fadeOut()))
    }

    /// Content of the island itself as it changes state: the shape does the moving, the content only fades,
    /// arriving a moment after the shape has started so it never shows outside it.
    static func islandContent(delay: Double = 0.06) -> AnyTransition {
        .asymmetric(insertion: .opacity.animation(Motion.fadeIn(0.22).delay(delay)),
                    removal: .opacity.animation(Motion.fadeOut(0.09)))
    }

    /// A row joining or leaving a list: it opens its own height rather than popping in.
    static var row: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)).animation(Motion.smooth()),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(Motion.fadeOut(0.16)))
    }
}

/// The island's namespace, for things that travel between its states (a creature
/// from the closed island to its row, a row's creature into its card).
private struct IslandNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var islandNamespace: Namespace.ID? {
        get { self[IslandNamespaceKey.self] }
        set { self[IslandNamespaceKey.self] = newValue }
    }
}

extension View {
    /// `matchedGeometryEffect` when the island has a namespace (previews and settings have none).
    @ViewBuilder
    func travels(_ id: String, in namespace: Namespace.ID?, isSource: Bool = true) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            self
        }
    }
}
