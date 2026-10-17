import Foundation
import Observation

/// Follows something read from observed state (the model): `react` gets its value now,
/// and again on the main actor each time it has changed. Keep the watch to keep it going.
@MainActor
final class Watch<Value: Equatable> {
    private let read: @MainActor () -> Value
    private let react: @MainActor (Value) -> Void
    private var last: Value?

    init(_ read: @escaping @MainActor () -> Value, react: @escaping @MainActor (Value) -> Void) {
        self.read = read
        self.react = react
        track()
    }

    private func track() {
        let value = withObservationTracking { read() } onChange: { [weak self] in
            // Called as the change is being made: look again once it has been.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.track() } }
        }
        guard value != last else { return }
        last = value
        react(value)
    }
}

/// Several values watched together, compared as one.
struct Pair<A: Equatable, B: Equatable>: Equatable {
    var first: A
    var second: B
}
