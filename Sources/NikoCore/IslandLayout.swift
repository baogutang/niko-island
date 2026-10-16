import Foundation

/// The plan limits worth a glance at the top of the open island: the agent you
/// were last busy with, its short window and its long one.
public struct QuotaGlance: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// "5h", "7d", or the window's own length.
        public var label: String
        public var percent: Int
        /// Until it resets: "42m", "2h39m", "3d"; nil when the source did not say.
        public var resetsIn: String?
        public var level: Level
    }

    public enum Level: Equatable, Sendable { case calm, warm, hot }

    public var agent: String
    public var entries: [Entry]

    /// `recentAgents` in the order the list shows them; the first that has limits wins.
    public static func make(usage: UsageSnapshot, recentAgents: [String], now: Date) -> QuotaGlance? {
        let candidates = recentAgents + usage.agents.map(\.id).filter { !recentAgents.contains($0) }
        for id in candidates {
            guard let agent = usage.agent(id) else { continue }
            let live = agent.limits.filter { $0.resetsAt.map { $0 > now } ?? true }
            let windows = live.sorted { ($0.minutes ?? .max) < ($1.minutes ?? .max) }
            guard let short = windows.first else { continue }
            var picked = [short]
            if let long = windows.last, long.id != short.id { picked.append(long) }
            return QuotaGlance(agent: id, entries: picked.map { entry($0, now: now) })
        }
        return nil
    }

    static func entry(_ window: RateLimitWindow, now: Date) -> Entry {
        let percent = Int(window.usedPercent.rounded())
        let level: Level = percent >= 90 ? .hot : percent >= 70 ? .warm : .calm
        return Entry(label: label(minutes: window.minutes, id: window.id), percent: percent,
                     resetsIn: window.resetsAt.map { remaining($0.timeIntervalSince(now)) }, level: level)
    }

    static func label(minutes: Int?, id: String) -> String {
        guard let minutes, minutes > 0 else { return id.replacingOccurrences(of: "_", with: " ") }
        if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    /// Compact time left: under an hour in minutes, under a day in hours and minutes, else days.
    static func remaining(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1440 { return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)m" }
        return "\(Int((Double(minutes) / 1440).rounded()))d"
    }
}

/// Which rows of the list keep their full card, and which sit on one line.
public enum RowTiers {
    /// How long after its last change a quiet session still counts as recent.
    public static let recent: TimeInterval = 300

    /// The first row always stays full, as do sessions at work, waiting on a decision,
    /// changed in the last five minutes, or listed in `alwaysFull`.
    public static func full(_ sessions: [Session], alwaysFull: Set<SessionKey>, now: Date) -> Set<SessionKey> {
        var keys = Set<SessionKey>()
        for (index, session) in sessions.enumerated() {
            if index == 0 || session.phase != .waiting || alwaysFull.contains(session.key)
                || now.timeIntervalSince(session.phaseSince) < recent {
                keys.insert(session.key)
            }
        }
        return keys
    }
}
