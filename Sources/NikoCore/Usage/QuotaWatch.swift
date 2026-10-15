import Foundation

/// How full a plan window is, as a colour: under 70 % used is fine, from 70 % it
/// is worth a look, from 90 % it is nearly gone. (The thresholds agent-hud-open
/// uses; one reading of one window, never a score made of several.)
public enum QuotaLevel: Int, Sendable, Comparable {
    case ok, warning, critical

    public init(used: Double) {
        self = used >= 90 ? .critical : used >= 70 ? .warning : .ok
    }

    public static func < (a: QuotaLevel, b: QuotaLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Where a window is heading at the pace it has been used at lately.
public struct QuotaOutlook: Sendable, Equatable {
    /// Share of the window used per hour, idle time included.
    public var pacePerHour: Double
    /// When the window is used up at that pace; nil while nothing is being used.
    public var runsOutAt: Date?
    /// It is used up before it resets (a window without a reset time counts as such).
    public var runsOutBeforeReset: Bool
    /// The share used by the reset at that pace, at most all of it.
    public var usedAtReset: Double?
}

/// Readings of each window over time, kept so the app can say how fast a plan is
/// being used and warn before it runs out. Only percentages and times are kept.
///
/// The pace is the rise in the share used over the recent past: the last hour of
/// a window of five hours or less, the last day of one up to a week, the last
/// week of anything longer, or the whole series while it is shorter. A series
/// under 15 minutes (an hour, for windows of a day or more) gives no pace. A fall
/// of 5 points or more is a reset, and the series starts again there.
public struct QuotaWatch: Sendable {
    public struct Sample: Sendable, Equatable {
        public var time: Date
        public var used: Double
        public init(time: Date, used: Double) {
            self.time = time
            self.used = used
        }
    }

    public enum Alert: Sendable, Equatable {
        /// The window crossed the warning share (90 % unless chosen otherwise).
        case nearlyFull(agent: String, window: RateLimitWindow)
        /// At the recent pace the window runs out before it resets.
        case runsOutEarly(agent: String, window: RateLimitWindow, at: Date)
    }

    static let keep: TimeInterval = 8 * 86_400
    static let resetFall = 5.0
    /// A reading older than this is still shown, but says nothing new.
    static let freshFor: TimeInterval = 30 * 60
    /// Below this share used, a fast start is not worth a warning yet.
    static let forecastFrom = 50.0

    public private(set) var samples: [String: [Sample]] = [:]
    /// Alerts given in a window's current cycle (window key → what was said, for which reset).
    private var said: [String: Set<String>] = [:]
    /// Windows read since launch: the first reading of each is a baseline, never news.
    private var seen: Set<String> = []

    public init(samples: [String: [Sample]] = [:]) {
        self.samples = samples
    }

    static func key(agent: String, window: String) -> String { agent + "/" + window }

    /// Adds a reading and returns whatever it makes worth saying.
    /// `nearlyFullAt`: the share from which a window counts as nearly used up (90 unless the user chose otherwise).
    public mutating func record(agent: String, window: RateLimitWindow, at time: Date, now: Date = Date(),
                                nearlyFullAt threshold: Double = 90) -> [Alert] {
        guard window.usedPercent.isFinite else { return [] }
        let key = Self.key(agent: agent, window: window.id)
        var series = samples[key] ?? []
        let previous = series.last
        let sample = Sample(time: time, used: window.usedPercent)
        if let last = series.last, time <= last.time {
            if time == last.time { series[series.count - 1] = sample }   // the same reading, read again
        } else if let last = series.last, series.count >= 2, time.timeIntervalSince(series[series.count - 2].time) < 60,
                  last.used == sample.used {
            series[series.count - 1] = sample                              // nothing moved: keep one sample a minute
        } else {
            series.append(sample)
        }
        series.removeAll { now.timeIntervalSince($0.time) > Self.keep }
        samples[key] = series

        let isBaseline = seen.insert(key).inserted
        guard !isBaseline, now.timeIntervalSince(time) <= Self.freshFor else { return [] }
        let cycle = window.resetsAt.map { String(Int($0.timeIntervalSince1970 / 3600)) } ?? "-"
        var alerts: [Alert] = []
        func once(_ what: String) -> Bool { said[key, default: []].insert(what + "@" + cycle).inserted }
        if let previous, previous.used < threshold, sample.used >= threshold, once("full") {
            alerts.append(.nearlyFull(agent: agent, window: window))
        }
        if sample.used >= Self.forecastFrom, sample.used < 99.5, let outlook = outlook(agent: agent, window: window, now: now),
           outlook.runsOutBeforeReset, let at = outlook.runsOutAt, window.resetsAt != nil, once("forecast") {
            alerts.append(.runsOutEarly(agent: agent, window: window, at: at))
        }
        return alerts
    }

    /// The window's pace and where it leads, or nil when the readings give no pace yet.
    public func outlook(agent: String, window: RateLimitWindow, now: Date = Date()) -> QuotaOutlook? {
        guard let pace = Self.pace(samples[Self.key(agent: agent, window: window.id)] ?? [], minutes: window.minutes) else { return nil }
        let used = min(max(window.usedPercent, 0), 100)
        var outlook = QuotaOutlook(pacePerHour: pace, runsOutAt: nil, runsOutBeforeReset: false, usedAtReset: nil)
        if let resets = window.resetsAt, resets > now {
            outlook.usedAtReset = min(100, used + pace * resets.timeIntervalSince(now) / 3600)
        }
        guard pace > 0 else { return outlook }
        let at = now.addingTimeInterval((100 - used) / pace * 3600)
        outlook.runsOutAt = at
        outlook.runsOutBeforeReset = window.resetsAt.map { at < $0 } ?? true
        return outlook
    }

    static func pace(_ series: [Sample], minutes: Int?) -> Double? {
        guard series.count >= 2 else { return nil }
        var start = 0
        for index in series.indices.dropFirst() where series[index].used <= series[index - 1].used - resetFall { start = index }
        let segment = Array(series[start...])
        guard let last = segment.last, let earliest = segment.first else { return nil }
        let length = TimeInterval((minutes ?? 300) * 60)
        let lookback: TimeInterval = length <= 5 * 3600 ? 3600 : length <= 7 * 86_400 ? 86_400 : 7 * 86_400
        let shortest: TimeInterval = length >= 86_400 ? 3600 : 15 * 60
        let first = segment.last { $0.time <= last.time.addingTimeInterval(-lookback) } ?? earliest
        let span = last.time.timeIntervalSince(first.time)
        guard span >= shortest else { return nil }
        return max(0, last.used - first.used) / (span / 3600)
    }

    // MARK: Kept between launches (percentages and times only)

    public static func load(from file: URL) -> QuotaWatch {
        guard let data = try? Data(contentsOf: file), let root = (try? JSONValue.parse(data))?.objectValue else { return QuotaWatch() }
        var samples: [String: [Sample]] = [:]
        for member in root.members {
            samples[member.key] = (member.value.arrayValue ?? []).compactMap { item in
                guard let pair = item.arrayValue, pair.count == 2, let t = pair[0].doubleValue, let used = pair[1].doubleValue,
                      t.isFinite, used.isFinite else { return nil }
                return Sample(time: Date(timeIntervalSince1970: t), used: used)
            }
        }
        return QuotaWatch(samples: samples)
    }

    public func save(to file: URL) {
        var root = JSONObject()
        for (key, series) in samples.sorted(by: { $0.key < $1.key }) where !series.isEmpty {
            root[key] = .array(series.map { .array([.number(String(Int($0.time.timeIntervalSince1970))), .number(String($0.used))]) })
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = AtomicFile.write(JSONValue.object(root).serializedData(.compact), to: file.path, mode: 0o600)
    }
}
