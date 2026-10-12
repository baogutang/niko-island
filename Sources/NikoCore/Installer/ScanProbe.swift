import Foundation

/// Phase A of installation (PROTOCOLS §5): a read-only POSIX shell probe that
/// reports, per agent, whether its directory exists and what its config files
/// contain. Nothing is ever modified before a scan has completed successfully.
public enum ScanProbe {
    public static let sizeCap = 1 << 20
    static let marker = "<<<NI:"

    /// The probe script. Plain POSIX sh so the same text can later run over SSH.
    public static func script(agents: [AgentDescriptor], includeVersions: Bool = false) -> String {
        var lines: [String] = [
            "#!/bin/sh",
            "# niko-island scan probe — read-only. Emits <<<NI:section>>> delimited sections.",
            "NI_CAP=\(sizeCap)",
            "ni_dir() {",
            "    d=\"$HOME/$1\"",
            "    if [ -d \"$d\" ]; then",
            "        if [ -r \"$d\" ] && [ -x \"$d\" ]; then printf 'dir=D\\n'; else printf 'dir=U\\n'; fi",
            "    elif [ -e \"$d\" ] || [ -L \"$d\" ]; then",
            "        printf 'dir=U\\n'",
            "    else",
            "        printf 'dir=N\\n'",
            "    fi",
            "}",
            "ni_file() {",
            "    f=\"$HOME/$1\"",
            "    if [ ! -e \"$f\" ] && [ ! -L \"$f\" ]; then printf 'file=%s|N||\\n' \"$1\"; return 0; fi",
            "    if [ ! -f \"$f\" ] || [ ! -r \"$f\" ]; then printf 'file=%s|U||\\n' \"$1\"; return 0; fi",
            "    size=$(wc -c < \"$f\" 2>/dev/null | tr -d ' \\t')",
            "    case \"$size\" in",
            "        ''|*[!0-9]*) printf 'file=%s|U||\\n' \"$1\"; return 0 ;;",
            "    esac",
            "    if [ \"$size\" -gt \"$NI_CAP\" ]; then printf 'file=%s|L|%s|\\n' \"$1\" \"$size\"; return 0; fi",
            "    if data=$(base64 < \"$f\" 2>/dev/null | tr -d '\\n'); then",
            "        printf 'file=%s|F|%s|%s\\n' \"$1\" \"$size\" \"$data\"",
            "    else",
            "        printf 'file=%s|U||\\n' \"$1\"",
            "    fi",
            "}",
            "ni_bin() {",
            "    p=$(command -v \"$1\" 2>/dev/null) || return 0",
            "    printf 'bin=%s\\n' \"$p\"",
        ]
        if includeVersions {
            lines += [
                "    v=$(\"$p\" --version 2>/dev/null | head -n 1) || v=''",
                "    if [ -n \"$v\" ]; then printf 'version=%s\\n' \"$v\"; fi",
            ]
        }
        lines += [
            "}",
            "printf '<<<NI:meta>>>\\n'",
            "printf 'probe=1\\nhome=%s\\nuid=%s\\n' \"$HOME\" \"$(id -u)\"",
        ]
        for agent in agents {
            lines.append("printf '<<<NI:agent:\(agent.id)>>>\\n'")
            lines.append("ni_dir \(ShellQuote.single(agent.directory))")
            if let binary = agent.binary { lines.append("ni_bin \(ShellQuote.single(binary))") }
            for file in agent.files { lines.append("ni_file \(ShellQuote.single(file))") }
        }
        lines.append("printf '<<<NI:end>>>\\n'")
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct ScanReport: Sendable, Equatable {
    public enum DirectoryState: String, Sendable { case present = "D", missing = "N", unknown = "U" }

    public enum FileState: Sendable, Equatable {
        case present(Data)
        case missing
        /// Not a regular file, not readable, or the read failed: never touched.
        case unreadable
        /// Larger than the probe's cap: never touched.
        case tooLarge(Int)

        public var data: Data? {
            if case .present(let data) = self { return data }
            return nil
        }
    }

    public struct Agent: Sendable, Equatable {
        public var directory: DirectoryState = .unknown
        public var binary: String?
        public var version: String?
        public var files: [String: FileState] = [:]
    }

    public var home: String
    public var uid: String
    public var agents: [String: Agent]

    public func file(_ relative: String, agent id: String) -> FileState {
        agents[id]?.files[relative] ?? .unreadable
    }
}

public enum ScanError: Error, CustomStringConvertible, Equatable {
    case probeFailed(Int32, String)
    case malformedOutput(String)
    case incomplete(String)

    public var description: String {
        switch self {
        case .probeFailed(let status, let detail): return "scan probe exited \(status): \(detail)"
        case .malformedOutput(let detail): return "scan output malformed: \(detail)"
        case .incomplete(let detail): return "scan incomplete: \(detail)"
        }
    }
}

extension ScanProbe {
    /// Parses probe output. Anything short of a complete, well-formed report throws.
    public static func parse(_ output: String, expecting agents: [AgentDescriptor]) throws -> ScanReport {
        var section: String?
        var meta: [String: String] = [:]
        var parsed: [String: ScanReport.Agent] = [:]
        var sawEnd = false

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.hasPrefix(marker), line.hasSuffix(">>>") {
                let name = String(line.dropFirst(marker.count).dropLast(3))
                if name == "end" {
                    sawEnd = true
                    section = nil
                } else {
                    section = name
                    if name.hasPrefix("agent:") { parsed[String(name.dropFirst(6))] = ScanReport.Agent() }
                }
                continue
            }
            guard !sawEnd, let section, let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            if section == "meta" {
                meta[key] = value
                continue
            }
            guard section.hasPrefix("agent:") else { continue }
            let id = String(section.dropFirst(6))
            var agent = parsed[id] ?? ScanReport.Agent()
            switch key {
            case "dir":
                agent.directory = ScanReport.DirectoryState(rawValue: value) ?? .unknown
            case "bin":
                agent.binary = value
            case "version":
                agent.version = value
            case "file":
                let fields = value.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 4 else { throw ScanError.malformedOutput("bad file record for \(id)") }
                switch fields[1] {
                case "F":
                    guard let data = Data(base64Encoded: fields[3]), data.count == Int(fields[2]) else {
                        throw ScanError.malformedOutput("content of \(fields[0]) did not survive transport")
                    }
                    agent.files[fields[0]] = .present(data)
                case "N": agent.files[fields[0]] = .missing
                case "L": agent.files[fields[0]] = .tooLarge(Int(fields[2]) ?? 0)
                default: agent.files[fields[0]] = .unreadable
                }
            default:
                break
            }
            parsed[id] = agent
        }

        guard meta["probe"] == "1", let home = meta["home"], !home.isEmpty else {
            throw ScanError.malformedOutput("missing meta section")
        }
        guard sawEnd else { throw ScanError.incomplete("no end marker") }
        for agent in agents {
            guard let scanned = parsed[agent.id] else { throw ScanError.incomplete("no section for \(agent.id)") }
            for file in agent.files where scanned.files[file] == nil {
                throw ScanError.incomplete("no record for \(file)")
            }
        }
        return ScanReport(home: home, uid: meta["uid"] ?? "", agents: parsed)
    }

    /// Runs the probe locally with `HOME` pointed at `home`.
    public static func run(home: URL, agents: [AgentDescriptor], includeVersions: Bool = false) throws -> ScanReport {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script(agents: agents, includeVersions: includeVersions)]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["LC_ALL"] = "C"
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            throw ScanError.probeFailed(-1, "\(error)")
        }
        // Drain stdout before waiting so a large report cannot fill the pipe.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errorData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ScanError.probeFailed(process.terminationStatus, String(decoding: errorData.prefix(400), as: UTF8.self))
        }
        return try parse(String(decoding: data, as: UTF8.self), expecting: agents)
    }
}
