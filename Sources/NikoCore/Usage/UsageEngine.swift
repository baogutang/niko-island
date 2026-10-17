import CoreServices
import Foundation

/// Finds transcript files, keeps the usage database in step with them
/// (FSEvents, with a slow poll as fallback) and publishes snapshots.
/// Everything runs on one utility queue; nothing here leaves the machine.
public final class UsageEngine: @unchecked Sendable {
    public struct Source: Sendable, Equatable {
        public var provider: UsageProvider
        public var root: String
        /// `nil` = any `*.jsonl`; otherwise only these file names.
        public var fileNames: Set<String>?
        public var maxDepth: Int
    }

    public static let pollInterval: TimeInterval = 300
    static let rateLimitInterval: TimeInterval = 20

    public let paths: NikoPaths
    public let sources: [Source]
    private let queue = DispatchQueue(label: "app.nikoisland.usage", qos: .utility)
    private let onSnapshot: @Sendable (UsageSnapshot) -> Void
    private let log: NikoLog

    // Queue-confined state.
    private var store: UsageStore?
    private var tailer: TranscriptTailer?
    private var pricing: Pricing
    private var known: [String: (size: Int, mtime: Double)] = [:]
    private var stream: FSEventStreamRef?
    private var watchedRoots: [String] = []
    private var pollTimer: DispatchSourceTimer?
    private var rateLimitTimer: DispatchSourceTimer?
    private var pendingPaths: Set<String> = []
    private var flushScheduled = false
    private var indexing = false
    private var lastRateLimits = RateLimits.Cache()
    private var codexLimits = ProviderLimits()
    /// What the providers answered when asked directly (opt-in), by agent id.
    private var askedLimits: [String: ProviderLimits] = [:]
    /// "This window is full until …", as an agent that was turned away wrote it down.
    private var reachedLimits: [String: ProviderLimits] = [:]
    private var zcodePending = false
    private var failure: String?
    private var running = false
    private let home: URL
    static let codexLimitsKey = "limits.codex"

    public static func defaultSources(home: URL) -> [Source] {
        let h = home.path
        // `**` in PROTOCOLS §6.1 means any depth: Claude Code nests sub-agent and
        // workflow transcripts six levels down. The cap only guards against runaway trees.
        var sources = [
            Source(provider: .claude, root: h + "/.claude/projects", fileNames: nil, maxDepth: 16),
            Source(provider: .codex, root: h + "/.codex/sessions", fileNames: nil, maxDepth: 16),
            Source(provider: .codex, root: h + "/.codex/archived_sessions", fileNames: nil, maxDepth: 16),
        ]
        let names: Set<String> = ["transcript.jsonl", "wire.jsonl", "events-recent.jsonl"]
        for family in ["opencode", "mimocode"] {
            for base in ["/.local/share/", "/.local/state/"] {
                sources.append(Source(provider: .opencode, root: h + base + family, fileNames: names, maxDepth: 16))
            }
        }
        return sources
    }

    public init(paths: NikoPaths, home: URL, pricing: Pricing, sources: [Source]? = nil, log: NikoLog = .shared,
                onSnapshot: @escaping @Sendable (UsageSnapshot) -> Void) {
        self.paths = paths
        self.home = home
        self.pricing = pricing
        self.sources = sources ?? UsageEngine.defaultSources(home: home)
        self.log = log
        self.onSnapshot = onSnapshot
    }

    deinit {
        // No queue hop (deinit may run on `queue`); the stream holds an unretained pointer to us.
        pollTimer?.cancel()
        rateLimitTimer?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: Lifecycle

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            guard openStore() else { publish(); return }
            indexing = true
            publish()
            fullScan()
            indexing = false
            publish()
            restartStreamIfNeeded()

            let poll = DispatchSource.makeTimerSource(queue: queue)
            poll.schedule(deadline: .now() + UsageEngine.pollInterval, repeating: UsageEngine.pollInterval)
            poll.setEventHandler { [weak self] in
                guard let self else { return }
                self.fullScan()
                self.restartStreamIfNeeded()
                self.publish()
            }
            poll.resume()
            pollTimer = poll

            let limits = DispatchSource.makeTimerSource(queue: queue)
            limits.schedule(deadline: .now() + UsageEngine.rateLimitInterval, repeating: UsageEngine.rateLimitInterval)
            limits.setEventHandler { [weak self] in
                guard let self else { return }
                if RateLimits.load(paths: self.paths) != self.lastRateLimits { self.publish() }
            }
            limits.resume()
            rateLimitTimer = limits
        }
    }

    public func stop() {
        queue.sync {
            running = false
            pollTimer?.cancel()
            pollTimer = nil
            rateLimitTimer?.cancel()
            rateLimitTimer = nil
            stopStream()
            store?.close()
            store = nil
            tailer = nil
        }
    }

    /// Runs one full pass synchronously (tests and the CLI).
    public func scanNow() -> UsageSnapshot {
        queue.sync {
            if store == nil { _ = openStore() }
            fullScan()
            return makeSnapshot()
        }
    }

    /// A local source of limits has something new (Claude Code refreshed its own file): draw again.
    public func limitsChanged() {
        queue.async { [self] in
            claudeCacheStamp = nil
            if running { publish() }
        }
    }

    /// Limits the providers reported when asked (see `ProviderLimitsClient`).
    public func setAskedLimits(_ limits: [String: ProviderLimits]) {
        queue.async { [self] in
            guard limits != askedLimits else { return }
            askedLimits = limits
            if running { publish() }
        }
    }

    /// An agent was refused because one of its windows is used up.
    public func noteLimitReached(agent: String, window: RateLimitWindow, at date: Date) {
        queue.async { [self] in
            var known = reachedLimits[agent] ?? ProviderLimits(source: .limitReached)
            if let index = known.windows.firstIndex(where: { $0.id == window.id }) {
                guard known.windows[index] != window else { return }
                known.windows[index] = window
            } else {
                known.windows.append(window)
            }
            known.capturedAt = max(known.capturedAt ?? .distantPast, date)
            reachedLimits[agent] = known
            if running { publish() }
        }
    }

    public func setPricing(_ pricing: Pricing) {
        queue.async { [self] in
            self.pricing = pricing
            tailer?.pricing = pricing
            do {
                try store?.reprice(with: pricing)
            } catch {
                log.warn("usage: repricing failed: \(error)")
            }
            publish()
        }
    }

    // MARK: Store

    private func openStore() -> Bool {
        do {
            try SecureDirectory.ensureTree(paths)
            let store = try UsageStore(path: paths.usageDB.path)
            if store.recoveredFromCorruption {
                log.warn("usage: the database was unreadable and has been rebuilt from the transcripts")
            }
            self.store = store
            tailer = TranscriptTailer(store: store, pricing: pricing)
            if let saved = (try? store.meta(UsageEngine.codexLimitsKey)).flatMap({ $0 }).flatMap(ProviderLimits.init(json:)) {
                codexLimits = saved
            }
            known = [:]
            for (path, state) in try store.allLatestStates() where state.status == "active" && state.size == state.committedOffset {
                known[path] = (state.size, state.mtime)
            }
            failure = nil
            return true
        } catch {
            failure = "\(error)"
            log.error("usage: cannot open the database: \(error)")
            return false
        }
    }

    /// A database that breaks while we are running is rebuilt the same way as one that is broken at launch.
    private func recover(from error: Error) {
        guard let sqlite = error as? SQLiteError, sqlite.isCorruption else {
            log.warn("usage: \(error)")
            return
        }
        log.warn("usage: database damaged while running, rebuilding")
        store?.close()
        store = nil
        tailer = nil
        _ = openStore()
    }

    // MARK: Discovery and syncing

    func discover() -> [(path: String, provider: UsageProvider)] {
        var found: [(String, UsageProvider)] = []
        let fm = FileManager.default
        for source in sources {
            guard let enumerator = fm.enumerator(atPath: source.root) else { continue }
            while let relative = enumerator.nextObject() as? String {
                if enumerator.level > source.maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard relative.hasSuffix(".jsonl") else { continue }
                if let names = source.fileNames, !names.contains((relative as NSString).lastPathComponent) { continue }
                found.append((source.root + "/" + relative, source.provider))
            }
        }
        return found
    }

    func provider(forPath path: String) -> UsageProvider? {
        guard path.hasSuffix(".jsonl") else { return nil }
        for source in sources where path.hasPrefix(source.root + "/") {
            if let names = source.fileNames, !names.contains((path as NSString).lastPathComponent) { continue }
            return source.provider
        }
        return nil
    }

    private func fullScan() {
        let files = discover()
        var lastPublish = Date()
        var newestCodex: (path: String, mtime: Double)?
        // ZCode first: its rows are one cheap query, and on a first run the
        // transcripts below can take half a minute to index.
        syncZCode()
        defer {
            // Codex states its limits in the rollout it wrote last.
            if let newestCodex, newestCodex.mtime > (codexLimits.capturedAt?.timeIntervalSince1970 ?? 0) { noteCodexLimits(newestCodex.path) }
        }
        for (path, provider) in files {
            guard store != nil else { return }
            var st = stat()
            guard stat(path, &st) == 0 else { continue }
            let size = Int(st.st_size)
            let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
            if provider == .codex, mtime > (newestCodex?.mtime ?? 0) { newestCodex = (path, mtime) }
            if let seen = known[path], seen.size == size, seen.mtime == mtime { continue }
            // Foundation hands back some of what a file's lines are parsed into for later release;
            // without a pool per file a first pass holds all of it until the very end.
            autoreleasepool { sync(path, provider) }
            if indexing, Date().timeIntervalSince(lastPublish) > 2 {
                publish()
                lastPublish = Date()
            }
        }
    }

    private func sync(_ path: String, _ provider: UsageProvider) {
        guard let tailer else { return }
        do {
            switch try tailer.sync(path: path, provider: provider) {
            case .missing:
                known[path] = nil
            case .unchanged, .read:
                var st = stat()
                if stat(path, &st) == 0 {
                    known[path] = (Int(st.st_size), Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
                }
            }
        } catch {
            recover(from: error)
        }
    }

    /// Keeps the newest limits Codex has written, and remembers them across launches.
    private func noteCodexLimits(_ path: String) {
        guard let found = CodexLimits.latest(inFile: path), !found.windows.isEmpty else { return }
        if let captured = found.capturedAt, let current = codexLimits.capturedAt, captured < current { return }
        guard found != codexLimits else { return }
        codexLimits = found
        try? store?.setMeta(UsageEngine.codexLimitsKey, found.json)
    }

    /// ZCode's usage lives in its own database; new rows are copied over.
    private func syncZCode() {
        guard let store else { return }
        do {
            try ZCodeUsage.sync(home: home, store: store, pricing: pricing)
        } catch let error as SQLiteError where error.isCorruption {
            log.warn("usage: ZCode's database could not be read: \(error)")
        } catch {
            // Busy or mid-migration: the next pass will pick the rows up.
        }
    }

    private var zcodeDirectory: String { (ZCodeUsage.databasePath(home: home) as NSString).deletingLastPathComponent }

    // MARK: FSEvents

    fileprivate func filesChanged(_ changed: [String]) {
        // Already on `queue` (the stream is scheduled there).
        for path in changed where provider(forPath: path) != nil || path == paths.rateLimitCache.path {
            pendingPaths.insert(path)
        }
        if changed.contains(where: { $0.hasPrefix(zcodeDirectory + "/") }) { zcodePending = true }
        guard !pendingPaths.isEmpty || zcodePending, !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            let batch = self.pendingPaths
            self.pendingPaths = []
            for path in batch {
                if let provider = self.provider(forPath: path) {
                    self.sync(path, provider)
                    if provider == .codex { self.noteCodexLimits(path) }
                }
            }
            if self.zcodePending {
                self.zcodePending = false
                self.syncZCode()
            }
            self.publishThrottled()
        }
    }

    /// While an agent works, its transcript changes every second or two. What is new is counted
    /// each time, but the figures (a handful of queries over the whole history, and whatever
    /// shows them redrawn) are worked out again at most this often.
    static let publishInterval: TimeInterval = 4
    private var lastPublish = Date.distantPast
    private var publishScheduled = false

    private func publishThrottled() {
        let wait = lastPublish.addingTimeInterval(Self.publishInterval).timeIntervalSinceNow
        guard wait > 0 else {
            publish()
            return
        }
        guard !publishScheduled else { return }
        publishScheduled = true
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.publishScheduled = false
            self.publish()
        }
    }

    private func restartStreamIfNeeded() {
        let roots = (sources.map(\.root) + [paths.cache.path, zcodeDirectory]).filter { FileManager.default.fileExists(atPath: $0) }
        guard roots != watchedRoots else { return }
        stopStream()
        guard !roots.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let engine = Unmanaged<UsageEngine>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            engine.filesChanged(paths)
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, callback, &context, roots as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags) else {
            log.warn("usage: FSEvents unavailable, relying on the \(Int(UsageEngine.pollInterval)) s poll")
            return
        }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        watchedRoots = roots
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        watchedRoots = []
    }

    // MARK: Snapshots

    private func publish() {
        lastPublish = Date()
        onSnapshot(makeSnapshot())
    }

    private lazy var kiroCredits = KiroCredits(home: home)

    private var claudeCacheStamp: Date?
    private var claudeCached: ProviderLimits?

    /// Claude Code's own cached answer, read again only when its file has changed.
    private func claudeCache() -> ProviderLimits? {
        let file = home.appendingPathComponent(".claude.json")
        let stamp = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        guard stamp != claudeCacheStamp else { return claudeCached }
        claudeCacheStamp = stamp
        claudeCached = stamp == nil ? nil : ClaudeUsageAPI.cached(home: home)
        return claudeCached
    }

    private func makeSnapshot(now: Date = Date()) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.indexing = indexing
        snapshot.updatedAt = now
        snapshot.pricingSource = pricing.source
        snapshot.failure = failure
        lastRateLimits = RateLimits.load(paths: paths, now: now)
        // Each source knows some windows; whichever looked last wins a window.
        var sources: [String: [ProviderLimits]] = [:]
        sources["claude", default: []].append(ProviderLimits(windows: lastRateLimits.windows, capturedAt: lastRateLimits.capturedAt, source: .statusLine))
        if let cached = claudeCache() { sources["claude", default: []].append(cached) }
        sources["codex", default: []].append(codexLimits)
        for (id, asked) in askedLimits { sources[id, default: []].append(asked) }
        for (id, reached) in reachedLimits { sources[id, default: []].append(reached) }
        var limits: [String: ProviderLimits] = [:]
        for (id, candidates) in sources { limits[id] = ProviderLimits.merged(candidates, now: now) }
        let ordered = limits.keys.sorted { ($0 == "claude" ? "" : $0) < ($1 == "claude" ? "" : $1) }
        snapshot.rateLimits = ordered.flatMap { limits[$0]?.windows ?? [] }
        snapshot.rateLimitsCapturedAt = ordered.compactMap { limits[$0]?.capturedAt }.max()
        guard let store else { return snapshot }
        do {
            let today = store.day(for: now.timeIntervalSince1970)
            var dayIDs: [String] = []
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = store.timeZone
            for back in stride(from: 6, through: 0, by: -1) {
                let date = calendar.date(byAdding: .day, value: -back, to: now) ?? now
                dayIDs.append(store.day(for: date.timeIntervalSince1970))
            }
            let first = dayIDs.first ?? today
            snapshot.today = try store.totals(fromDay: today, toDay: today)
            snapshot.week = try store.totals(fromDay: first, toDay: today)
            let daily = try store.dailyTotals(fromDay: first, toDay: today)
            snapshot.days = dayIDs.map { UsageSnapshot.Day(id: $0, tokens: daily[$0]?.tokens ?? 0, cost: daily[$0]?.cost ?? 0) }
            snapshot.unpricedModels = try store.unpricedModels(fromDay: first, toDay: today)

            // One entry per agent, and one for everything together.
            let fiveHours = try store.totals(since: now.timeIntervalSince1970 - 5 * 3600)
            let month = try store.totals(since: now.timeIntervalSince1970 - 30 * 86_400)
            let perDay = try store.dailyTotalsByAgent(fromDay: first, toDay: today)
            let monthIDs = UsageSnapshot.monthIDs(endingAt: now, calendar: calendar)
            let perMonth = try store.monthlyTotalsByAgent(fromDay: (monthIDs.first ?? "") + "-01")
            // The last day in quarter hours, and four weeks by weekday and hour, for the charts.
            let quarterNow = Int(now.timeIntervalSince1970 / 900)
            let quarterRows = try store.stretches(since: Double((quarterNow - 95) * 900), seconds: 900)
            let hourRows = try store.stretches(since: now.timeIntervalSince1970 - 28 * 86_400, seconds: 3600)
            snapshot.sessions = try store.sessionTotals(since: now.timeIntervalSince1970 - 2 * 86_400)
            snapshot.topSessions = try store.topSessions(since: now.timeIntervalSince1970 - 7 * 86_400)

            func usage(_ id: String) -> UsageSnapshot.AgentUsage {
                func pick(_ rows: [UsageTotals]) -> [UsageTotals] { id == "all" ? rows : rows.filter { $0.agent == id } }
                var agent = UsageSnapshot.AgentUsage(id: id)
                agent.fiveHours = .init(pick(fiveHours))
                agent.today = .init(pick(snapshot.today))
                agent.week = .init(pick(snapshot.week))
                agent.month = .init(pick(month))
                agent.models = pick(snapshot.week)
                agent.days = id == "all" ? snapshot.days : dayIDs.map {
                    UsageSnapshot.Day(id: $0, tokens: perDay[id]?[$0]?.tokens ?? 0, cost: perDay[id]?[$0]?.cost ?? 0)
                }
                agent.months = monthIDs.map { month in
                    let rows = id == "all" ? perMonth.values.compactMap { $0[month] } : [perMonth[id]?[month]].compactMap { $0 }
                    return UsageSnapshot.Day(id: month, tokens: rows.reduce(0) { $0 + $1.tokens }, cost: rows.reduce(0) { $0 + $1.cost })
                }
                agent.limits = limits[id]?.windows ?? []
                agent.limitsCapturedAt = limits[id]?.capturedAt
                agent.limitsSource = limits[id]?.source
                agent.plan = limits[id]?.plan
                agent.resetsLeft = limits[id]?.resetsLeft
                func tokens(_ row: [String: Int]?) -> Int {
                    guard let row else { return 0 }
                    return id == "all" ? row.values.reduce(0, +) : row[id] ?? 0
                }
                agent.quarters = (quarterNow - 95...quarterNow).map { tokens(quarterRows[$0]) }
                var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
                for (hour, row) in hourRows {
                    let date = Date(timeIntervalSince1970: TimeInterval(hour * 3600))
                    let weekday = (calendar.component(.weekday, from: date) + 5) % 7   // Monday is 0
                    grid[weekday][calendar.component(.hour, from: date)] += tokens(row)
                }
                agent.weekHours = grid
                return agent
            }
            var ids = Set(snapshot.week.map(\.agent)).union(fiveHours.map(\.agent)).union(limits.keys)
            let credits = kiroCredits.totals(now: now, calendar: calendar)
            if credits != nil { ids.insert(KiroSessions.source) }
            ids.remove("")
            let ranked = ids.map { id -> UsageSnapshot.AgentUsage in
                var agent = usage(id)
                if id == KiroSessions.source { agent.credits = credits }
                return agent
            }.sorted { ($0.week.cost, $0.week.tokens, $1.id) > ($1.week.cost, $1.week.tokens, $0.id) }
            snapshot.agents = [usage("all")] + ranked
        } catch {
            recover(from: error)
        }
        return snapshot
    }
}
