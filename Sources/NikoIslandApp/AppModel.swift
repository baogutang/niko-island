import Foundation
import NikoCore

/// Main-actor state for the panel. M0 skeleton: no ingress yet.
@MainActor
public final class AppModel: ObservableObject {
    public struct Badge: Equatable, Sendable {
        public var active = 0
        public var pending = 0
    }

    public let paths: NikoPaths
    @Published public private(set) var badge = Badge()
    public var onAttentionNeeded: (() -> Void)?

    public init(paths: NikoPaths) {
        self.paths = paths
    }

    public func start() {}
    public func stop() {}
}
