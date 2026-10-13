import Foundation

/// Runtime layout under `~/.niko-island/` (SPEC §2).
public struct NikoPaths: Sendable, Equatable {
    public let root: URL
    /// True when `root` is the default `~/.niko-island`, so generated shell can use `$HOME`.
    public let isDefaultLocation: Bool

    public init(root: URL, isDefaultLocation: Bool = false) {
        self.root = URL(fileURLWithPath: NikoPaths.normalize(root.path))
        self.isDefaultLocation = isDefaultLocation
    }

    /// Purely lexical clean-up (`.`/`..`/duplicate slashes). Foundation's
    /// `standardizedFileURL` also strips `/private`, which would make a path
    /// differ from its own realpath and trip the hardening check.
    public static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        let joined = parts.joined(separator: "/")
        return path.hasPrefix("/") ? "/" + joined : joined
    }

    public static let homeOverrideVariable = "NIKO_ISLAND_HOME"

    /// The user's real home directory with symlinked parents resolved, so the
    /// hardening checks only ever judge the components we create ourselves.
    public static func userHome() -> URL {
        let raw: String
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            raw = String(cString: dir)
        } else {
            raw = NSHomeDirectory()
        }
        return URL(fileURLWithPath: canonicalPath(raw))
    }

    /// `realpath(3)` when the path exists, else the input unchanged. (Foundation's
    /// `resolvingSymlinksInPath` strips `/private`, which would defeat the realpath check.)
    public static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> NikoPaths {
        if let override = environment[homeOverrideVariable], !override.isEmpty {
            // Canonicalise the parent only: the leaf is ours to create and must not be a symlink.
            let absolute = override.hasPrefix("/") ? override : FileManager.default.currentDirectoryPath + "/" + override
            let url = URL(fileURLWithPath: normalize(absolute))
            let parent = canonicalPath(url.deletingLastPathComponent().path)
            return NikoPaths(root: URL(fileURLWithPath: parent).appendingPathComponent(url.lastPathComponent))
        }
        return NikoPaths(root: userHome().appendingPathComponent(".niko-island"), isDefaultLocation: true)
    }

    public var bin: URL { root.appendingPathComponent("bin") }
    public var run: URL { root.appendingPathComponent("run") }
    public var cache: URL { root.appendingPathComponent("cache") }
    public var data: URL { root.appendingPathComponent("data") }
    public var usageDir: URL { data.appendingPathComponent("usage") }
    public var logs: URL { root.appendingPathComponent("logs") }
    /// The user's own sound files and sound packs (created on demand, not part of the tree).
    public var sounds: URL { root.appendingPathComponent("sounds") }

    public var socket: URL { run.appendingPathComponent("niko-island.sock") }
    public var ingressToken: URL { run.appendingPathComponent("ingress-token") }
    public var ingressPort: URL { run.appendingPathComponent("ingress-port") }
    public var rateLimitCache: URL { cache.appendingPathComponent("rl.json") }
    public var pricingCache: URL { cache.appendingPathComponent("pricing.json") }
    public var statuslineOriginal: URL { cache.appendingPathComponent("statusline-original.json") }
    public var usageDB: URL { usageDir.appendingPathComponent("usage.sqlite") }
    public var bridgeShim: URL { bin.appendingPathComponent("niko-bridge") }
    public var statuslineScript: URL { bin.appendingPathComponent("niko-statusline") }
    public var bridgeCache: URL { bin.appendingPathComponent(".bridge-cache") }
    public var bridgeMiss: URL { bin.appendingPathComponent(".bridge-miss") }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    public var logFile: URL { logs.appendingPathComponent("niko-island.log") }

    public var allDirectories: [URL] { [root, bin, run, cache, data, usageDir, logs] }

    /// Shell expression for a path below root: `"$HOME/.niko-island/bin/x"` at the
    /// default location (portable across machines), else a single-quoted absolute path.
    public func shellPath(_ url: URL) -> String {
        let rootPath = root.path
        let path = NikoPaths.normalize(url.path)
        if isDefaultLocation, path.hasPrefix(rootPath + "/") {
            let suffix = String(path.dropFirst(rootPath.count))
            return "\"$HOME/.niko-island\(ShellQuote.doubleQuotedBody(suffix))\""
        }
        return ShellQuote.single(path)
    }
}

public enum ShellQuote {
    /// POSIX single-quote a string: `it's` → `'it'\''s'`.
    public static func single(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape for use inside an existing double-quoted shell word.
    public static func doubleQuotedBody(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch == "\\" || ch == "\"" || ch == "$" || ch == "`" { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}

public enum SecureDirectoryError: Error, CustomStringConvertible, Equatable {
    case symlink(String)
    case notDirectory(String)
    case wrongOwner(String, uid_t)
    case realpathMismatch(String, String)
    case createFailed(String, Int32)
    case chmodFailed(String, Int32)

    public var description: String {
        switch self {
        case .symlink(let p): return "refusing symlinked path: \(p)"
        case .notDirectory(let p): return "not a directory: \(p)"
        case .wrongOwner(let p, let uid): return "\(p) is owned by uid \(uid), expected \(getuid())"
        case .realpathMismatch(let p, let r): return "realpath mismatch: \(p) resolves to \(r)"
        case .createFailed(let p, let e): return "mkdir \(p) failed: \(String(cString: strerror(e)))"
        case .chmodFailed(let p, let e): return "chmod \(p) failed: \(String(cString: strerror(e)))"
        }
    }
}

/// Creates/validates directories we own: mode 0700, owned by us, never a symlink,
/// and resolving to exactly the path we asked for (PROTOCOLS §2.1).
public enum SecureDirectory {
    public static func ensure(_ url: URL, mode: mode_t = 0o700) throws {
        let path = NikoPaths.normalize(url.path)
        var st = stat()
        if lstat(path, &st) != 0 {
            guard errno == ENOENT else { throw SecureDirectoryError.createFailed(path, errno) }
            if mkdir(path, mode) != 0, errno != EEXIST {
                throw SecureDirectoryError.createFailed(path, errno)
            }
            guard lstat(path, &st) == 0 else { throw SecureDirectoryError.createFailed(path, errno) }
        }
        try validate(path: path, st: st)
        if (st.st_mode & 0o777) != mode {
            guard chmod(path, mode) == 0 else { throw SecureDirectoryError.chmodFailed(path, errno) }
        }
    }

    /// Read-only check; never creates or chmods.
    public static func validate(_ url: URL) throws {
        let path = NikoPaths.normalize(url.path)
        var st = stat()
        guard lstat(path, &st) == 0 else { throw SecureDirectoryError.notDirectory(path) }
        try validate(path: path, st: st)
    }

    private static func validate(path: String, st: stat) throws {
        let type = st.st_mode & S_IFMT
        if type == S_IFLNK { throw SecureDirectoryError.symlink(path) }
        guard type == S_IFDIR else { throw SecureDirectoryError.notDirectory(path) }
        guard st.st_uid == getuid() else { throw SecureDirectoryError.wrongOwner(path, st.st_uid) }
        guard let resolved = realpath(path, nil) else { throw SecureDirectoryError.notDirectory(path) }
        defer { free(resolved) }
        let real = String(cString: resolved)
        guard real == path else { throw SecureDirectoryError.realpathMismatch(path, real) }
    }

    /// Ensure the whole runtime tree. `root` and `run` are the security boundary;
    /// the rest get the same treatment for consistency.
    public static func ensureTree(_ paths: NikoPaths) throws {
        for dir in paths.allDirectories { try ensure(dir) }
    }
}
