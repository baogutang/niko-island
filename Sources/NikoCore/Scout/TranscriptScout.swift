import Foundation

/// Watches the transcripts agents write for themselves (Claude Code and Codex
/// as files, ZCode as a database) and reports the sessions that have been
/// active recently. Read-only, local, and cheap: file times are polled, and a
/// file is only read again when it has grown.
public final class TranscriptScout: @unchecked Sendable {
    public struct Options: Sendable {
        /// Sessions quiet for longer than this are no longer reported.
        public var window: TimeInterval = 30 * 60
        /// How often known files are checked for growth.
        public var interval: TimeInterval = 1.5
        /// How often the whole tree is searched for files not seen before.
        public var discoveryEvery = 6
        public var tailBytes = 256 * 1024
        public var headBytes = 256 * 1024
        public var maxFiles = 64

        public init() {}
    }

    private struct Entry {
        var modified: Date
        var size: UInt64
        var claudeFirstPrompt: String?
        var codexMeta: CodexTranscript.Meta?
        var headRead = false
        var tail = Data()
        var tailIsWholeFile = false
    }

    private let home: URL
    public var options: Options
    private let onChange: @Sendable ([TranscriptSnapshot]) -> Void
    private let queue = DispatchQueue(label: "app.nikoisland.scout", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var entries: [String: Entry] = [:]
    private var tick = 0
    private var lastEmitted: [TranscriptSnapshot]?
    private lazy var zcode = ZCodeSessions(home: home)

    public init(home: URL, options: Options = Options(), onChange: @escaping @Sendable ([TranscriptSnapshot]) -> Void) {
        self.home = home
        self.options = options
        self.onChange = onChange
    }

    deinit { timer?.cancel() }

    public func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.options.interval, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let snapshots = self.scan(now: Date())
                if snapshots != self.lastEmitted {
                    self.lastEmitted = snapshots
                    self.onChange(snapshots)
                }
            }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// Change how long quiet sessions stay listed.
    public func setWindow(_ window: TimeInterval) {
        queue.async { [weak self] in self?.options.window = window }
    }

    /// One pass, synchronously (tests and the first paint).
    public func scanOnce(now: Date = Date()) -> [TranscriptSnapshot] {
        queue.sync { scan(now: now) }
    }

    // MARK: Scanning (on `queue`)

    private var claudeRoot: URL { home.appendingPathComponent(".claude/projects") }
    private var codexRoot: URL { home.appendingPathComponent(".codex/sessions") }

    private func scan(now: Date) -> [TranscriptSnapshot] {
        defer { tick += 1 }
        let cutoff = now.addingTimeInterval(-options.window)
        if tick % max(1, options.discoveryEvery) == 0 { discover(cutoff: cutoff) }

        var out: [TranscriptSnapshot] = []
        for path in Array(entries.keys) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = (attributes[.size] as? NSNumber)?.uint64Value, modified >= cutoff else {
                entries[path] = nil
                continue
            }
            var entry = entries[path] ?? Entry(modified: .distantPast, size: 0)
            if entry.modified != modified || entry.size != size || !entry.headRead {
                read(path, size: size, into: &entry)
                entry.modified = modified
                entry.size = size
                entries[path] = entry
            }
            if let snapshot = snapshot(path: path, entry: entry, now: now) { out.append(snapshot) }
        }
        // ZCode keeps its sessions in a database instead of one file each.
        out.append(contentsOf: zcode.snapshots(since: cutoff, now: now))
        return out.sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.path < $1.path }
    }

    private func isCodex(_ path: String) -> Bool { path.hasPrefix(codexRoot.path + "/") }

    private func snapshot(path: String, entry: Entry, now: Date) -> TranscriptSnapshot? {
        if isCodex(path) {
            guard let meta = entry.codexMeta else { return nil }
            return CodexTranscript.snapshot(path: path, meta: meta, tail: entry.tail, tailIsWholeFile: entry.tailIsWholeFile,
                                            modified: entry.modified, now: now)
        }
        return ClaudeTranscript.snapshot(path: path, tail: entry.tail, tailIsWholeFile: entry.tailIsWholeFile,
                                         firstPrompt: entry.claudeFirstPrompt, modified: entry.modified, now: now)
    }

    private func read(_ path: String, size: UInt64, into entry: inout Entry) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        if !entry.headRead {
            let head = (try? handle.read(upToCount: options.headBytes)) ?? Data()
            if isCodex(path) {
                entry.codexMeta = CodexTranscript.meta(path: path, head: head)
            } else {
                entry.claudeFirstPrompt = ClaudeTranscript.firstPrompt(head: head)
            }
            entry.headRead = true
        }
        let wanted = UInt64(options.tailBytes)
        if size > wanted {
            try? handle.seek(toOffset: size - wanted)
            entry.tailIsWholeFile = false
        } else {
            try? handle.seek(toOffset: 0)
            entry.tailIsWholeFile = true
        }
        entry.tail = (try? handle.readToEnd()) ?? Data()
    }

    /// Looks for transcripts written since `cutoff` that are not tracked yet.
    private func discover(cutoff: Date) {
        var found: [(String, Date)] = []
        let manager = FileManager.default
        // Claude: one directory per project, sessions directly inside it. Deeper files are sub-agents.
        for project in (try? manager.contentsOfDirectory(at: claudeRoot, includingPropertiesForKeys: nil)) ?? [] {
            let files = (try? manager.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date >= cutoff {
                    found.append((file.path, date))
                }
            }
        }
        // Codex: YYYY/MM/DD/rollout-*.jsonl. A long session keeps appending to the day it started on.
        if let walker = manager.enumerator(at: codexRoot, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                           options: [.skipsHiddenFiles]) {
            for case let file as URL in walker {
                if walker.level > 4 { walker.skipDescendants(); continue }
                guard file.pathExtension == "jsonl",
                      let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date >= cutoff else { continue }
                found.append((file.path, date))
            }
        }
        // Newest first, and never more than a screenful: this is a status display, not an archive.
        for (path, _) in found.sorted(by: { $0.1 > $1.1 }).prefix(options.maxFiles) where entries[path] == nil {
            entries[path] = Entry(modified: .distantPast, size: 0)
        }
    }
}
