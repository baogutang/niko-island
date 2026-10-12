import Darwin
import Foundation

public struct ProcessNode: Sendable, Equatable {
    public var pid: Int32
    public var path: String
    public var bundleID: String?

    public init(pid: Int32, path: String, bundleID: String? = nil) {
        self.pid = pid
        self.path = path
        self.bundleID = bundleID
    }

    public var executableName: String { (path as NSString).lastPathComponent }
}

/// Read-only process inspection through libproc. Works for same-uid processes.
public enum ProcessInspector {
    public static func path(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    private static func bsdInfo(of pid: pid_t) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    public static func parent(of pid: pid_t) -> pid_t? {
        bsdInfo(of: pid).map { pid_t($0.pbi_ppid) }
    }

    /// `ttys003`-style name of the controlling terminal, if any.
    public static func controllingTTY(of pid: pid_t) -> String? {
        guard let info = bsdInfo(of: pid) else { return nil }
        let device = dev_t(bitPattern: info.e_tdev)
        guard device != -1, info.e_tdev != 0, let name = devname(device, S_IFCHR) else { return nil }
        let tty = String(cString: name)
        return tty.hasPrefix("tty") ? tty : nil
    }

    /// The process itself first, then its parents up to launchd.
    public static func ancestors(of pid: pid_t, limit: Int = 16) -> [ProcessNode] {
        var chain: [ProcessNode] = []
        var current = pid
        var seen: Set<pid_t> = []
        while current > 1, chain.count < limit, !seen.contains(current) {
            seen.insert(current)
            guard let path = path(of: current) else { break }
            chain.append(ProcessNode(pid: current, path: path, bundleID: BundleIDCache.shared.bundleID(forExecutable: path)))
            guard let next = parent(of: current) else { break }
            current = next
        }
        return chain
    }
}

/// Maps executable paths to the identifier of the outermost enclosing `.app`.
public final class BundleIDCache: @unchecked Sendable {
    public static let shared = BundleIDCache()
    private let lock = NSLock()
    private var cache: [String: String?] = [:]

    public func bundleID(forExecutable path: String) -> String? {
        guard let appPath = BundleIDCache.enclosingApp(path) else { return nil }
        lock.lock()
        if let hit = cache[appPath] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let plist = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        var identifier: String?
        if let data = try? Data(contentsOf: plist),
           let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            identifier = object["CFBundleIdentifier"] as? String
        }
        lock.lock()
        cache[appPath] = .some(identifier)
        lock.unlock()
        return identifier
    }

    static func enclosingApp(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

public struct AdmissionEvidence: Sendable, Equatable {
    public enum Channel: String, Sendable { case unixSocket, http }

    public var channel: Channel
    /// Kernel-reported uid of the socket peer (`nil` when unavailable).
    public var peerUID: uid_t?
    public var peerPID: pid_t?
    public var cwd: String?
    /// Kernel-derived ancestor chain when the peer was still alive, else the
    /// chain the bridge reported about itself.
    public var ancestors: [ProcessNode]
    public var ancestorsAreSelfReported: Bool

    public init(channel: Channel, peerUID: uid_t?, peerPID: pid_t? = nil, cwd: String? = nil,
                ancestors: [ProcessNode] = [], ancestorsAreSelfReported: Bool = false) {
        self.channel = channel
        self.peerUID = peerUID
        self.peerPID = peerPID
        self.cwd = cwd
        self.ancestors = ancestors
        self.ancestorsAreSelfReported = ancestorsAreSelfReported
    }
}

public enum AdmissionDecision: Sendable, Equatable {
    case admit
    case deny(String)

    public var isAdmitted: Bool { self == .admit }
}

/// PROTOCOLS §2.5. The hard gate is the kernel-verified peer uid; the
/// "developer tooling" heuristic and the bundle deny-list sit on top of it.
public struct AdmissionPolicy: Sendable, Equatable {
    public var appUID: uid_t
    public var deniedBundleIDs: Set<String>
    public var requireDeveloperEvidence: Bool

    public init(appUID: uid_t = getuid(), deniedBundleIDs: Set<String> = [], requireDeveloperEvidence: Bool = true) {
        self.appUID = appUID
        self.deniedBundleIDs = deniedBundleIDs
        self.requireDeveloperEvidence = requireDeveloperEvidence
    }

    public func evaluate(_ evidence: AdmissionEvidence) -> AdmissionDecision {
        switch evidence.channel {
        case .unixSocket:
            guard let uid = evidence.peerUID else { return .deny("peer credentials unavailable") }
            guard uid == appUID else { return .deny("peer uid \(uid) is not the app uid \(appUID)") }
        case .http:
            // The bearer token lives in a 0600 file inside a 0700 directory:
            // presenting it is the same-uid proof for this channel.
            break
        }
        for node in evidence.ancestors {
            if let bundle = node.bundleID, deniedBundleIDs.contains(bundle) {
                return .deny("bundle \(bundle) is deny-listed")
            }
        }
        guard requireDeveloperEvidence else { return .admit }
        if evidence.ancestors.contains(where: AdmissionPolicy.looksLikeDeveloperTool) { return .admit }
        if let cwd = evidence.cwd, AdmissionPolicy.looksLikeProjectDirectory(cwd) { return .admit }
        return .deny("no developer-tooling evidence (cwd and ancestors unrecognised)")
    }

    static let developerExecutables: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh", "nu", "pwsh", "xonsh", "elvish",
        "tmux", "screen", "zellij", "login", "sshd", "sshd-session", "mosh-server", "script",
        "node", "bun", "deno", "ruby", "perl", "java", "go", "cargo", "swift", "make", "git",
        "claude", "codex", "cursor", "cursor-agent", "gemini", "opencode", "copilot", "grok", "qwen",
        "kimi", "kiro", "droid", "amp", "aider", "trae", "windsurf", "mimocode", "deepseek", "pi", "openclaw",
        "nvim", "vim", "vi", "emacs", "hx", "code", "zed", "xctest", "swiftpm-testing-helper", "niko-bridge",
    ]

    static let developerBundlePrefixes: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.",
        "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        "com.microsoft.VSCode", "com.vscodium", "dev.zed.", "com.jetbrains.", "com.apple.dt.Xcode",
        "com.sublimetext.", "com.todesktop.", "com.exafunction.windsurf", "com.trae.", "org.tabby",
        "com.anthropic.", "com.openai.",
    ]

    static func looksLikeDeveloperTool(_ node: ProcessNode) -> Bool {
        if let bundle = node.bundleID, developerBundlePrefixes.contains(where: { bundle.hasPrefix($0) }) {
            return true
        }
        var name = node.executableName.lowercased()
        if name.hasPrefix("-") { name.removeFirst() }          // login shells show up as "-zsh"
        if developerExecutables.contains(name) { return true }
        // python3.12, node22, ruby3.3 …
        let stem = String(name.prefix { !($0.isNumber || $0 == ".") })
        return !stem.isEmpty && (developerExecutables.contains(stem) || stem == "python")
    }

    static let projectMarkers = [
        ".git", ".hg", ".svn", ".jj", "package.json", "Package.swift", "Cargo.toml", "go.mod",
        "pyproject.toml", "requirements.txt", "Gemfile", "pom.xml", "build.gradle", "build.gradle.kts",
        "Makefile", "CMakeLists.txt", "CLAUDE.md", "AGENTS.md", ".claude", ".cursor", "composer.json",
        "deno.json", "mix.exs", "flake.nix",
    ]

    /// An existing absolute directory that is, or sits inside, something with a project marker.
    static func looksLikeProjectDirectory(_ cwd: String) -> Bool {
        guard cwd.hasPrefix("/") else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        var url = URL(fileURLWithPath: cwd).standardizedFileURL
        for _ in 0..<12 {
            for marker in projectMarkers
            where FileManager.default.fileExists(atPath: url.appendingPathComponent(marker).path) {
                return true
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path || parent.path == "/" { break }
            url = parent
        }
        return false
    }
}
