import Foundation

/// What the usage tab shows. Filled in by the usage engine (M5).
public struct UsageSnapshot: Sendable, Equatable {
    public init() {}

    public static func demo(now: Date) -> UsageSnapshot { UsageSnapshot() }
}
