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
    private var failure: String?
    private var running = false

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
        for (path, provider) in files {
            guard store != nil else { return }
            var st = stat()
            guard stat(path, &st) == 0 else { continue }
            let size = Int(st.st_size)
            let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
            if let seen = known[path], seen.size == size, seen.mtime == mtime { continue }
            sync(path, provider)
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

    // MARK: FSEvents

    fileprivate func filesChanged(_ changed: [String]) {
        // Already on `queue` (the stream is scheduled there).
        for path in changed where provider(forPath: path) != nil || path == paths.rateLimitCache.path {
            pendingPaths.insert(path)
        }
        guard !pendingPaths.isEmpty, !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            let batch = self.pendingPaths
            self.pendingPaths = []
            for path in batch {
                if let provider = self.provider(forPath: path) { self.sync(path, provider) }
            }
            self.publish()
        }
    }

    private func restartStreamIfNeeded() {
        let roots = (sources.map(\.root) + [paths.cache.path]).filter { FileManager.default.fileExists(atPath: $0) }
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
        onSnapshot(makeSnapshot())
    }

    private func makeSnapshot(now: Date = Date()) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.indexing = indexing
        snapshot.updatedAt = now
        snapshot.pricingSource = pricing.source
        snapshot.failure = failure
        lastRateLimits = RateLimits.load(paths: paths, now: now)
        snapshot.rateLimits = lastRateLimits.windows
        snapshot.rateLimitsCapturedAt = lastRateLimits.capturedAt
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
        } catch {
            recover(from: error)
        }
        return snapshot
    }
}
