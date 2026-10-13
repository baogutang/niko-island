import Foundation

// Claude Code can be asked to look up the plan's usage itself: `claude -p /usage`
// is a command of its own that asks Anthropic with Claude Code's own sign-in
// (renewing it if need be) and keeps the answer in `~/.claude.json`. That file
// is then read like any other local source (`ClaudeUsageAPI.cached`). This app
// never sees the sign-in and sends nothing itself. Off until switched on.

public enum ClaudeCodeUsage {
    /// Where a Claude Code binary is usually found, nearest to "what the user runs" first.
    public static func candidates(home: URL) -> [URL] {
        var out = [".local/bin/claude", ".claude/local/claude", ".npm-global/bin/claude", ".bun/bin/claude"].map { home.appendingPathComponent($0) }
        out += ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"].map { URL(fileURLWithPath: $0) }
        // The desktop app keeps its own copies, one folder per version.
        let bundled = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: bundled.path)) ?? [])
            .filter { $0.first?.isNumber == true }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for version in versions.prefix(3) {
            let folder = bundled.appendingPathComponent(version)
            for build in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() {
                out.append(folder.appendingPathComponent(build).appendingPathComponent("claude.app/Contents/MacOS/claude"))
            }
        }
        return out
    }

    public static func locate(home: URL) -> URL? {
        candidates(home: home).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The quietest form of the question: nothing is saved as a session, the
    /// user's own settings (and with them hooks and plugins) are not loaded,
    /// no MCP server is started, no browser is touched.
    public static let arguments = ["-p", "/usage", "--no-session-persistence", "--setting-sources", "project", "--strict-mcp-config", "--no-chrome"]

    /// An empty folder of our own to run it in, so that nothing of a real project is read.
    public static func workingDirectory(paths: NikoPaths) -> URL { paths.cache.appendingPathComponent("claude-usage") }

    public enum Outcome: Sendable, Equatable {
        /// Claude Code looked, and its file now holds an answer from this moment.
        case fresh
        /// It ran, but the file holds nothing newer (not signed in, or it declined to ask again so soon).
        case unchanged
        case noClaudeCode
        case failed
    }

    /// When Claude Code last kept an answer, or nil.
    public static func lastFetched(home: URL) -> Date? { ClaudeUsageAPI.cached(home: home, includingReset: true)?.capturedAt }

    /// Runs the question once and waits for it (at most `timeout` seconds). Call off the main thread.
    public static func ask(home: URL, paths: NikoPaths, binary: URL? = nil, timeout: TimeInterval = 40, now: Date = Date()) -> Outcome {
        guard let executable = binary ?? locate(home: home) else { return .noClaudeCode }
        let before = lastFetched(home: home)
        let folder = workingDirectory(paths: paths)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        guard (try? process.run()) != nil else { return .failed }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return .failed
        }
        guard process.terminationStatus == 0 else { return .failed }
        guard let after = lastFetched(home: home) else { return .unchanged }
        // An answer from the last few minutes counts: Claude Code does not ask again while its own is that young.
        if let before, after <= before, now.timeIntervalSince(after) > 600 { return .unchanged }
        return now.timeIntervalSince(after) <= 600 ? .fresh : .unchanged
    }
}
