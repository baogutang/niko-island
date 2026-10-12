import Foundation

/// Small rotating file logger. Every line is redacted before it is written.
/// Log lines carry event names, ids and counts — never tool inputs or prompts.
public final class NikoLog: @unchecked Sendable {
    public enum Level: String, Sendable { case info = "INFO", warn = "WARN", error = "ERROR" }

    public static let shared = NikoLog()

    private let lock = NSLock()
    private var fileURL: URL?
    private var maxBytes = 1 << 20
    private var keep = 3
    private var memory: [String]?
    private var echo = ProcessInfo.processInfo.environment["NIKO_ISLAND_DEBUG"] != nil

    public init() {}

    /// In-memory logger for tests.
    public static func inMemory() -> NikoLog {
        let log = NikoLog()
        log.memory = []
        log.echo = false
        return log
    }

    public func configure(fileURL: URL?, maxBytes: Int = 1 << 20, keep: Int = 3) {
        lock.lock()
        defer { lock.unlock() }
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.keep = keep
    }

    public var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return memory ?? []
    }

    public func info(_ message: @autoclosure () -> String) { write(.info, message()) }
    public func warn(_ message: @autoclosure () -> String) { write(.warn, message()) }
    public func error(_ message: @autoclosure () -> String) { write(.error, message()) }

    private static func timestamp() -> String {
        var now = time(nil)
        var parts = tm()
        gmtime_r(&now, &parts)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
                      Int(parts.tm_year) + 1900, Int(parts.tm_mon) + 1, Int(parts.tm_mday),
                      Int(parts.tm_hour), Int(parts.tm_min), Int(parts.tm_sec))
    }

    private func write(_ level: Level, _ message: String) {
        let line = "\(NikoLog.timestamp()) \(level.rawValue) \(Redactor.redact(message))"
        lock.lock()
        defer { lock.unlock() }
        if memory != nil { memory?.append(line) }
        if echo { FileHandle.standardError.write(Data((line + "\n").utf8)) }
        guard let fileURL else { return }
        rotateIfNeeded(fileURL)
        let data = Data((line + "\n").utf8)
        let fd = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        data.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress, $0.count) }
    }

    private func rotateIfNeeded(_ url: URL) {
        var st = stat()
        guard stat(url.path, &st) == 0, Int(st.st_size) >= maxBytes else { return }
        let fm = FileManager.default
        for index in stride(from: keep - 1, through: 1, by: -1) {
            let from = url.path + ".\(index)"
            let to = url.path + ".\(index + 1)"
            if fm.fileExists(atPath: from) {
                try? fm.removeItem(atPath: to)
                try? fm.moveItem(atPath: from, toPath: to)
            }
        }
        try? fm.removeItem(atPath: url.path + ".1")
        try? fm.moveItem(atPath: url.path, toPath: url.path + ".1")
        try? fm.removeItem(atPath: url.path + ".\(keep + 1)")
    }
}
