import Foundation

/// Redacted, content-free snapshot for bug reports (SPEC v3 "diagnostics export").
/// It lists states and counts; it never includes config contents, prompts,
/// tool inputs or tokens, and the whole text passes through the redactor.
public enum Diagnostics {
    public static func isAppRunning(paths: NikoPaths) -> Bool {
        let fd = SocketIO.connectUnix(paths.socket.path, timeoutMS: 300)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard SocketIO.writeAll(fd, Data("{\"\(UnixIngressServer.probeKey)\":1}\n".utf8), timeoutMS: 300) else { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, 500) > 0 else { return false }
        var byte: UInt8 = 0
        return read(fd, &byte, 1) == 1
    }

    /// Whether macOS still has the download quarantine flag on a file. A
    /// quarantined, ad-hoc signed bridge is refused by Gatekeeper when a hook
    /// tries to run it, which would leave hooks silently doing nothing.
    public static func isQuarantined(_ path: String) -> Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// The command that clears the flag for a bundle (or a single file).
    public static func quarantineFix(for bridgePath: String) -> String {
        var target = bridgePath
        if let range = bridgePath.range(of: ".app/") { target = String(bridgePath[..<range.lowerBound]) + ".app" }
        return "xattr -cr " + ShellQuote.single(target)
    }

    static func describe(_ url: URL) -> String {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return "missing" }
        let type: String
        switch st.st_mode & S_IFMT {
        case S_IFDIR: type = "dir"
        case S_IFLNK: type = "symlink"
        case S_IFSOCK: type = "socket"
        case S_IFREG: type = "file"
        default: type = "other"
        }
        let owner = st.st_uid == getuid() ? "self" : "uid \(st.st_uid)"
        return "\(type) \(String(st.st_mode & 0o777, radix: 8)) \(owner)"
    }

    public static func agentSummary(home: URL, includeVersions: Bool = false) -> [String] {
        let installer = Installer(options: InstallOptions(home: home))
        guard let report = try? installer.scan(.uninstall, includeVersions: includeVersions) else {
            return ["scan failed"]
        }
        var lines: [String] = []
        for agent in AgentRegistry.installable {
            guard let scanned = report.agents[agent.id], scanned.directory != .missing else { continue }
            var wired = false
            var states: [String] = []
            for file in agent.files {
                switch scanned.files[file] ?? .unreadable {
                case .present(let data):
                    let ours = HookMerge.isOurs(command: String(decoding: data, as: UTF8.self))
                    wired = wired || ours
                    states.append("\(file): \(data.count) bytes")
                case .missing:
                    // Where an older version put its files: they are meant to be gone.
                    if !agent.activeFiles.contains(file) { continue }
                    states.append("\(file): missing")
                case .unreadable: states.append("\(file): unreadable")
                case .tooLarge(let size): states.append("\(file): \(size) bytes (over limit)")
                }
            }
            var line = "\(agent.displayName) [\(agent.stability.rawValue)]: \(wired ? "hooks installed" : "not wired")"
            if let version = scanned.version { line += ", \(version)" }
            line += " — " + states.joined(separator: "; ")
            lines.append(line)
        }
        return lines.isEmpty ? ["no supported agent directories found"] : lines
    }

    public static func export(paths: NikoPaths, home: URL = NikoPaths.userHome(), extra: [String] = []) -> String {
        var lines: [String] = []
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var machine = utsname()
        uname(&machine)
        let arch = withUnsafeBytes(of: &machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        lines.append("Niko Island diagnostics")
        lines.append("version: \(NikoVersion.current)")
        lines.append("macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (\(arch))")
        lines.append("app running: \(isAppRunning(paths: paths))")
        lines.append("")
        lines.append("[runtime directory]")
        for url in paths.allDirectories + [paths.socket, paths.ingressToken, paths.bridgeShim, paths.statuslineScript,
                                           paths.usageDB, paths.rateLimitCache] {
            lines.append("\(url.path): \(describe(url))")
        }
        lines.append("")
        lines.append("[settings]")
        let settings = NikoSettings.load(paths: paths)
        lines.append("httpIngressEnabled: \(settings.httpIngressEnabled)")
        lines.append("pricingRefreshEnabled: \(settings.pricingRefreshEnabled)")
        lines.append("requireDeveloperEvidence: \(settings.requireDeveloperEvidence)")
        lines.append("deniedBundleIDs: \(settings.deniedBundleIDs.count)")
        lines.append("")
        lines.append("[agents]")
        lines.append(contentsOf: agentSummary(home: home))
        if !extra.isEmpty {
            lines.append("")
            lines.append("[app]")
            lines.append(contentsOf: extra)
        }
        lines.append("")
        lines.append("[recent log]")
        if let log = try? String(contentsOf: paths.logFile, encoding: .utf8) {
            lines.append(contentsOf: log.split(separator: "\n").suffix(200).map(String.init))
        } else {
            lines.append("(no log file)")
        }
        return Redactor.redact(lines.joined(separator: "\n"), home: home.path) + "\n"
    }
}
