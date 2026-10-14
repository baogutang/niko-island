import CryptoKit
import Foundation

public enum UsageProvider: String, Sendable, CaseIterable {
    case claude, codex, opencode

    var parserVersion: Int {
        switch self {
        case .claude: return ClaudeUsageParser.version
        case .codex: return CodexUsageParser.version
        case .opencode: return OpenCodeUsageParser.version
        }
    }

    var needles: [Data] {
        switch self {
        case .claude: return ClaudeUsageParser.needles
        case .codex: return CodexUsageParser.needles
        case .opencode: return OpenCodeUsageParser.needles
        }
    }

    /// Keys whose values hold conversation text, tool traffic or instructions:
    /// big, and never looked at when counting tokens.
    var skippedKeys: Set<String> {
        switch self {
        case .claude: return ["content", "toolUseResult", "thinking", "signature"]
        case .codex: return ["base_instructions", "instructions", "content", "encrypted_content", "arguments", "output", "input", "tools"]
        case .opencode: return []
        }
    }

    func makeParser() -> any UsageParser {
        switch self {
        case .claude: return ClaudeUsageParser()
        case .codex: return CodexUsageParser()
        case .opencode: return OpenCodeUsageParser()
        }
    }
}

/// Incremental JSONL reader (PROTOCOLS §6.1). Per file it remembers how far it
/// got (`committed_offset`) and a hash of the bytes just before that point
/// (`tail_hash`). A file that was replaced, truncated or rewritten starts a
/// new generation and is read again from the top; identity keys make that
/// re-read free of double counting.
public final class TranscriptTailer {
    public enum Outcome: Equatable, Sendable {
        case unchanged
        case missing
        /// `restarted` is true when a new generation was begun.
        case read(records: Int, restarted: Bool)
    }

    static let chunkSize = 1 << 20
    static let maxLineBytes = 64 << 20
    static let tailWindow = 64

    private let store: UsageStore
    public var pricing: Pricing
    private var parsers: [String: (generation: Int, parser: any UsageParser)] = [:]

    /// How much of a file is read before what was found is written down.
    let segmentBytes: Int

    public init(store: UsageStore, pricing: Pricing, segmentBytes: Int = 4 << 20) {
        self.segmentBytes = max(1024, segmentBytes)
        self.store = store
        self.pricing = pricing
    }

    static func tailHash(fd: Int32, offset: Int) -> String {
        guard offset > 0 else { return "" }
        let length = min(tailWindow, offset)
        var buffer = [UInt8](repeating: 0, count: length)
        let n = pread(fd, &buffer, length, off_t(offset - length))
        guard n == length else { return "" }
        return SHA256.hash(data: buffer).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public func forget(path: String) { parsers[path] = nil }

    @discardableResult
    public func sync(path: String, provider: UsageProvider) throws -> Outcome {
        let previous = try store.latestState(for: path)
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else {
            if let previous, previous.status != "missing" {
                try store.setStatus("missing", path: path, generation: previous.generation)
            }
            parsers[path] = nil
            return .missing
        }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { return .missing }
        let size = Int(st.st_size)
        let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        let identity = "\(st.st_dev):\(st.st_ino)"

        var generation = 0
        var start = 0
        var restarted = false
        if let previous {
            generation = previous.generation
            start = previous.committedOffset
            let replaced = previous.fileIdentity != identity
            let truncated = size < previous.committedOffset
            let reparsing = previous.parserVersion != provider.parserVersion
            let rewritten = !replaced && !truncated && previous.committedOffset > 0
                && TranscriptTailer.tailHash(fd: fd, offset: previous.committedOffset) != previous.tailHash
            if replaced || truncated || rewritten || reparsing {
                try store.setStatus(replaced ? "rotated" : "superseded", path: path, generation: previous.generation)
                generation = previous.generation + 1
                start = 0
                restarted = true
                parsers[path] = nil
            } else if size == previous.committedOffset {
                return .unchanged
            }
        }

        // A parser follows one generation of one file from byte zero. After a
        // restart of the app it has to be brought up to date first (context
        // such as "current model" lives in earlier lines).
        var parser: any UsageParser
        if let cached = parsers[path], cached.generation == generation {
            parser = cached.parser
        } else {
            parser = provider.makeParser()
            if start > 0 {
                _ = TranscriptTailer.scan(fd: fd, path: path, from: 0, to: start, provider: provider, parser: &parser)
            }
        }

        // A large file is read and written down a few megabytes at a time: what is held in memory
        // is one stretch's records, not the whole file's, and an interrupted first pass resumes
        // where the last stretch ended.
        var position = start
        var read = 0
        var stretch = segmentBytes
        while true {
            let end = min(size, position + stretch)
            let result = autoreleasepool {
                TranscriptTailer.scan(fd: fd, path: path, from: position, to: end, provider: provider, parser: &parser)
            }
            if result.committed <= position, end < size {
                // One line is longer than the stretch: read further in one go.
                stretch *= 4
                continue
            }
            let state = SourceFileState(path: path, provider: provider.rawValue, fileIdentity: identity, generation: generation,
                                        size: size, mtime: mtime, committedOffset: result.committed,
                                        tailHash: TranscriptTailer.tailHash(fd: fd, offset: result.committed),
                                        parserVersion: provider.parserVersion, status: "active")
            try store.commit(records: result.records, pricing: pricing, file: state)
            read += result.records.count
            if end >= size || result.committed <= position { break }
            position = result.committed
            stretch = segmentBytes
        }
        parsers[path] = (generation, parser)
        return .read(records: read, restarted: restarted)
    }

    /// Reads complete lines in `[from, to)`. `committed` is the offset just
    /// past the last complete line: a half-written final line is left for next time.
    static func scan(fd: Int32, path: String, from: Int, to: Int, provider: UsageProvider,
                     parser: inout any UsageParser) -> (records: [UsageRecord], committed: Int) {
        var records: [UsageRecord] = []
        var offset = from
        // The start of a line that runs past the chunk read so far. Only new bytes are appended to
        // it, so a line of many megabytes is copied once, not once per chunk.
        var pending = Data()
        var pendingStart = from
        var skippingOversize = false
        let needles = provider.needles
        let skipped = provider.skippedKeys
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        func consider(_ line: Data, at start: Int) {
            guard !line.isEmpty, needles.contains(where: { line.range(of: $0) != nil }),
                  let json = try? JSONValue.parse(line, skipping: skipped) else { return }
            records.append(contentsOf: parser.parse(line: json, offset: start, file: path))
        }

        while offset < to {
            let want = min(chunkSize, to - offset)
            let n = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, want, off_t(offset)) }
            guard n > 0 else { break }
            buffer.withUnsafeBufferPointer { raw in
                let chunk = UnsafeBufferPointer(rebasing: raw[0..<n])
                var lineStart = 0
                while let newline = chunk[lineStart...].firstIndex(of: 0x0A) {
                    if skippingOversize {
                        skippingOversize = false
                    } else if pending.isEmpty {
                        consider(Data(chunk[lineStart..<newline]), at: offset + lineStart)
                    } else {
                        pending.append(contentsOf: chunk[lineStart..<newline])
                        consider(pending, at: pendingStart)
                    }
                    pending = Data()
                    lineStart = newline + 1
                    pendingStart = offset + lineStart
                }
                if lineStart < n {
                    if pending.isEmpty { pendingStart = offset + lineStart }
                    pending.append(contentsOf: chunk[lineStart..<n])
                }
            }
            if pending.count > maxLineBytes {
                // Not a line we could ever use; drop it without holding on to it.
                pending = Data()
                skippingOversize = true
            }
            offset += n
        }
        return (records, skippingOversize ? offset : (pending.isEmpty ? offset : pendingStart))
    }
}
