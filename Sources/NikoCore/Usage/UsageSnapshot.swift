import Foundation

/// One rate-limit window as reported in Claude Code's statusline payload
/// and cached by the bridge in `cache/rl.json` (PROTOCOLS §4).
public struct RateLimitWindow: Sendable, Equatable, Identifiable {
    /// Key from the payload, e.g. `five_hour`, `seven_day`.
    public var id: String
    public var usedPercent: Double
    public var resetsAt: Date?
    /// Length of the window, when the source says (300 = five hours, 10080 = a week).
    public var windowMinutes: Int?

    public init(id: String, usedPercent: Double, resetsAt: Date? = nil, windowMinutes: Int? = nil) {
        self.id = id
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }

    /// Minutes in the window, from the source or from the conventional key names.
    public var minutes: Int? {
        if let windowMinutes { return windowMinutes }
        if id.contains("five_hour") { return 300 }
        if id.contains("seven_day") || id.contains("week") { return 10080 }
        return nil
    }
}

public enum RateLimits {
    public struct Cache: Sendable, Equatable {
        public var windows: [RateLimitWindow] = []
        public var capturedAt: Date?
        public var model: String?
    }

    /// Lenient reader: unknown windows are shown as they are, windows that
    /// have already reset are dropped (their percentage is no longer true).
    public static func parse(_ data: Data, now: Date = Date()) -> Cache {
        guard let root = try? JSONValue.parse(data), let limits = root["rate_limits"]?.objectValue else { return Cache() }
        var cache = Cache()
        cache.capturedAt = ISOTime.flexible(root["captured_at"]).map(Date.init(timeIntervalSince1970:))
        cache.model = root["model"]?.stringValue
        for member in limits.members {
            let window = member.value
            guard window.objectValue != nil,
                  let used = (window["used_percentage"] ?? window["used_percent"] ?? window["utilization"] ?? window["percent_used"])?.doubleValue,
                  used.isFinite else { continue }
            let resets = ISOTime.flexible(window["resets_at"] ?? window["reset_at"] ?? window["resets"]).map(Date.init(timeIntervalSince1970:))
            if let resets, resets < now { continue }
            cache.windows.append(RateLimitWindow(id: member.key, usedPercent: min(max(used, 0), 100), resetsAt: resets))
        }
        return cache
    }

    public static func load(paths: NikoPaths, now: Date = Date()) -> Cache {
        guard let data = try? Data(contentsOf: paths.rateLimitCache) else { return Cache() }
        return parse(data, now: now)
    }
}

/// What the usage tab shows.
public struct UsageSnapshot: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public var id: String      // YYYY-MM-DD
        public var tokens: Int
        public var cost: Double
    }

    /// Tokens and estimated cost over one stretch of time.
    public struct Window: Sendable, Equatable {
        public var tokens = 0
        public var cost = 0.0
        public var messages = 0

        public init(tokens: Int = 0, cost: Double = 0, messages: Int = 0) {
            self.tokens = tokens
            self.cost = cost
            self.messages = messages
        }

        public init(_ rows: [UsageTotals]) {
            tokens = rows.reduce(0) { $0 + $1.tokens }
            cost = rows.reduce(0) { $0 + $1.cost }
            messages = rows.reduce(0) { $0 + $1.messages }
        }
    }

    /// One agent's usage: the rolling five hours, today, the last seven days,
    /// since the user last reset the counter, and the provider's own limits
    /// where it reports them.
    public struct AgentUsage: Sendable, Equatable, Identifiable {
        public var id: String
        public var fiveHours = Window()
        public var today = Window()
        public var week = Window()
        public var sinceReset: Window?
        public var resetAt: Date?
        /// Per model, last seven days.
        public var models: [UsageTotals] = []
        public var days: [Day] = []
        public var limits: [RateLimitWindow] = []
        public var limitsCapturedAt: Date?
        public var plan: String?

        public init(id: String) { self.id = id }
    }

    /// "all" first, then every agent with usage or limits, busiest first.
    public var agents: [AgentUsage] = []

    public func agent(_ id: String) -> AgentUsage? { agents.first { $0.id == id } }

    public var today: [UsageTotals] = []
    public var week: [UsageTotals] = []
    /// Seven entries, oldest first, ending today.
    public var days: [Day] = []
    public var rateLimits: [RateLimitWindow] = []
    public var rateLimitsCapturedAt: Date?
    public var unpricedModels: [String] = []
    /// The first pass over existing transcripts is still running.
    public var indexing = false
    public var updatedAt: Date?
    public var pricingSource = "none"
    public var failure: String?

    public init() {}

    public var todayCost: Double { today.reduce(0) { $0 + $1.cost } }
    public var weekCost: Double { week.reduce(0) { $0 + $1.cost } }
    public var todayTokens: Int { today.reduce(0) { $0 + $1.tokens } }
    public var weekTokens: Int { week.reduce(0) { $0 + $1.tokens } }
    public var isEmpty: Bool { week.isEmpty && rateLimits.isEmpty }

    /// Totals per agent, largest first.
    public static func byAgent(_ rows: [UsageTotals]) -> [UsageTotals] {
        var merged: [String: UsageTotals] = [:]
        for row in rows {
            var total = merged[row.agent] ?? UsageTotals(agent: row.agent, model: "")
            total.input += row.input
            total.output += row.output
            total.cacheRead += row.cacheRead
            total.cacheWrite += row.cacheWrite
            total.reasoning += row.reasoning
            total.cost += row.cost
            total.messages += row.messages
            merged[row.agent] = total
        }
        return merged.values.sorted { ($0.cost, $0.tokens, $1.agent) > ($1.cost, $1.tokens, $0.agent) }
    }

    /// Made-up numbers for documentation images.
    public static func demo(now: Date) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.today = [
            UsageTotals(agent: "claude", model: "claude-opus-5", input: 18_400, output: 96_200, cacheRead: 4_310_000, cacheWrite: 402_000, cost: 7.42, messages: 318),
            UsageTotals(agent: "claude", model: "claude-haiku-5", input: 9_100, output: 21_500, cacheRead: 610_000, cacheWrite: 88_000, cost: 0.31, messages: 97),
            UsageTotals(agent: "codex", model: "gpt-5-codex", input: 212_000, output: 38_400, cacheRead: 1_940_000, reasoning: 21_000, cost: 0.89, messages: 64),
        ]
        snapshot.week = [
            UsageTotals(agent: "claude", model: "claude-opus-5", input: 121_000, output: 640_000, cacheRead: 29_800_000, cacheWrite: 2_610_000, cost: 49.80, messages: 2210),
            UsageTotals(agent: "claude", model: "claude-haiku-5", input: 60_000, output: 139_000, cacheRead: 4_100_000, cacheWrite: 540_000, cost: 2.05, messages: 655),
            UsageTotals(agent: "codex", model: "gpt-5-codex", input: 1_310_000, output: 244_000, cacheRead: 11_700_000, reasoning: 130_000, cost: 5.54, messages: 402),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let costs = [6.1, 9.4, 3.2, 11.8, 8.9, 9.3, 8.62]
        snapshot.days = costs.enumerated().map { index, cost in
            let date = calendar.date(byAdding: .day, value: index - 6, to: now) ?? now
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return Day(id: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                       tokens: Int(cost * 640_000), cost: cost)
        }
        snapshot.rateLimits = [
            RateLimitWindow(id: "five_hour", usedPercent: 37, resetsAt: now.addingTimeInterval(2.4 * 3600)),
            RateLimitWindow(id: "seven_day", usedPercent: 61, resetsAt: now.addingTimeInterval(3.2 * 86_400)),
        ]
        snapshot.rateLimitsCapturedAt = now.addingTimeInterval(-40)
        func usage(_ id: String, five: (Int, Double), limits: [RateLimitWindow], reset: Double?) -> AgentUsage {
            var agent = AgentUsage(id: id)
            let today = id == "all" ? snapshot.today : snapshot.today.filter { $0.agent == id }
            let week = id == "all" ? snapshot.week : snapshot.week.filter { $0.agent == id }
            agent.fiveHours = Window(tokens: five.0, cost: five.1, messages: 40)
            agent.today = Window(today)
            agent.week = Window(week)
            agent.models = week
            let share = snapshot.weekCost > 0 ? agent.week.cost / snapshot.weekCost : 1
            agent.days = snapshot.days.map { Day(id: $0.id, tokens: Int(Double($0.tokens) * share), cost: $0.cost * share) }
            agent.limits = limits
            agent.limitsCapturedAt = limits.isEmpty ? nil : now.addingTimeInterval(-40)
            if let reset {
                agent.resetAt = now.addingTimeInterval(-reset * 3600)
                agent.sinceReset = Window(tokens: Int(Double(agent.today.tokens) * 0.4), cost: agent.today.cost * 0.4, messages: 60)
            }
            return agent
        }
        snapshot.agents = [
            usage("all", five: (2_240_000, 3.86), limits: [], reset: nil),
            usage("claude", five: (1_900_000, 3.41), limits: snapshot.rateLimits, reset: 3.5),
            usage("codex", five: (340_000, 0.45), limits: [
                RateLimitWindow(id: "primary", usedPercent: 22, resetsAt: now.addingTimeInterval(1.6 * 3600), windowMinutes: 300),
                RateLimitWindow(id: "secondary", usedPercent: 48, resetsAt: now.addingTimeInterval(4.1 * 86_400), windowMinutes: 10080),
            ], reset: nil),
        ]
        snapshot.updatedAt = now
        snapshot.pricingSource = "bundled"
        return snapshot
    }
}
