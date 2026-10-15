import Foundation

/// Where to bring the user back to when they click a notification
/// (INTEGRATIONS "Terminal jump-back").
public struct JumpTarget: Sendable, Equatable {
    public enum App: Sendable, Equatable {
        case iterm2
        case appleTerminal
        /// Any other host (IDE terminal, another emulator): we can only bring the app forward.
        case other(bundleID: String?)
    }

    public var app: App
    /// GUID part of `ITERM_SESSION_ID` (`w0t0p0:GUID`).
    public var itermSessionGUID: String?
    /// `/dev/ttys004`
    public var ttyDevice: String?
    public var tmuxSocket: String?
    public var tmuxPane: String?
    /// A WezTerm pane, and the socket of the GUI that has it.
    public var weztermPane: String?
    public var weztermSocket: String?
    /// A kitty window, and kitty's remote-control socket (only a unix socket is used).
    public var kittyWindow: String?
    public var kittySocket: String?

    public init(terminal: TerminalContext, ancestors: [ProcessNode] = []) {
        if let id = terminal.itermSessionID, !id.isEmpty {
            itermSessionGUID = id.split(separator: ":", maxSplits: 1).last.map(String.init)
        }
        if let tty = terminal.tty, !tty.isEmpty {
            ttyDevice = tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
        }
        if let tmux = terminal.tmux, !tmux.isEmpty {
            tmuxSocket = tmux.split(separator: ",").first.map(String.init)
            tmuxPane = terminal.tmuxPane
        }
        if let pane = terminal.weztermPane, !pane.isEmpty, pane.allSatisfy(\.isNumber) {
            weztermPane = pane
            weztermSocket = terminal.weztermSocket.flatMap { $0.hasPrefix("/") ? $0 : nil }
        }
        if let window = terminal.kittyWindow, !window.isEmpty, window.allSatisfy(\.isNumber) {
            kittyWindow = window
            // "unix:/path" or "unix:@abstract"; a tcp address is not used.
            kittySocket = terminal.kittyListenOn.flatMap { $0.hasPrefix("unix:") && $0.count > 5 ? $0 : nil }
        }
        let program = terminal.termProgram ?? ""
        let bundles = [terminal.bundleID].compactMap { $0 } + ancestors.compactMap(\.bundleID)
        if program == "iTerm.app" || (itermSessionGUID != nil && program != "Apple_Terminal") || bundles.contains("com.googlecode.iterm2") {
            app = .iterm2
        } else if program == "Apple_Terminal" || bundles.contains("com.apple.Terminal") {
            app = .appleTerminal
        } else if weztermPane != nil, program == "WezTerm" || bundles.isEmpty {
            app = .other(bundleID: bundles.first ?? "com.github.wez.wezterm")
        } else if kittyWindow != nil, bundles.isEmpty {
            app = .other(bundleID: "net.kovidgoyal.kitty")
        } else {
            app = .other(bundleID: bundles.first)
        }
    }

    public var bundleID: String? {
        switch app {
        case .iterm2: return "com.googlecode.iterm2"
        case .appleTerminal: return "com.apple.Terminal"
        case .other(let bundleID): return bundleID
        }
    }

    static let namesByBundlePrefix: [(String, String)] = [
        ("com.mitchellh.ghostty", "Ghostty"), ("dev.warp.", "Warp"), ("net.kovidgoyal.kitty", "kitty"),
        ("org.alacritty", "Alacritty"), ("io.alacritty", "Alacritty"), ("com.github.wez.wezterm", "WezTerm"),
        ("co.zeit.hyper", "Hyper"), ("com.todesktop.230313mzl4w4u92", "Cursor"), ("com.exafunction.windsurf", "Windsurf"),
        ("com.microsoft.VSCode", "VS Code"), ("com.vscodium", "VSCodium"), ("dev.zed.", "Zed"),
        ("com.jetbrains.", "JetBrains"), ("com.apple.dt.Xcode", "Xcode"), ("com.trae.", "Trae"), ("org.tabby", "Tabby"),
    ]

    static let namesByTermProgram: [String: String] = [
        "ghostty": "Ghostty", "WarpTerminal": "Warp", "WezTerm": "WezTerm", "vscode": "VS Code", "zed": "Zed",
        "kitty": "kitty", "alacritty": "Alacritty", "Hyper": "Hyper", "Tabby": "Tabby",
    ]

    /// Short name of the app hosting the session, for the chip on a session row
    /// ("iTerm2", "Terminal", "Ghostty · tmux", …). Nil when we cannot tell.
    public func hostName(termProgram: String?) -> String? {
        var name: String?
        switch app {
        case .iterm2: name = "iTerm2"
        case .appleTerminal: name = "Terminal"
        case .other(let bundleID):
            if let bundleID {
                name = JumpTarget.namesByBundlePrefix.first { bundleID.hasPrefix($0.0) }?.1
            }
            if name == nil, let termProgram, termProgram != "tmux" {
                name = JumpTarget.namesByTermProgram[termProgram]
            }
        }
        if tmuxPane != nil { return name.map { $0 + " · tmux" } ?? "tmux" }
        return name
    }
}

extension Session {
    /// The terminal (or IDE) this session lives in, as shown on its row.
    public var hostName: String? {
        JumpTarget(terminal: terminal, ancestors: ancestors).hostName(termProgram: terminal.termProgram) ?? host?.name
    }

    /// Bundle id of the app to bring forward for this session.
    public var hostBundleID: String? {
        JumpTarget(terminal: terminal, ancestors: ancestors).bundleID ?? host?.bundleID
    }
}

public enum TerminalJump {
    /// A link that opens one conversation in the agent's own desktop app, for
    /// the apps that have such links. Codex: `codex://threads/<id>`.
    public static func threadURL(for session: Session) -> URL? {
        guard session.terminal.isEmpty, session.host == .codexDesktop, session.source == "codex" else { return nil }
        let id = session.key.sessionID
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return URL(string: "codex://threads/\(id)")
    }

    /// AppleScript string literal. Everything interpolated into a script goes through here.
    static func literal(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n", "\r": out += " "
            default:
                if scalar.value >= 0x20 { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// Script that selects the originating tab, or nil when all we can do is activate the app.
    /// `clientTTY` is the tty of the tmux client showing the pane, when the agent runs inside tmux.
    public static func appleScript(for target: JumpTarget, clientTTY: String? = nil) -> String? {
        switch target.app {
        case .iterm2:
            guard let guid = target.itermSessionGUID else {
                return "tell application \"iTerm2\" to activate"
            }
            return """
            tell application "iTerm2"
                activate
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if (unique id of aSession) is \(literal(guid)) then
                                tell aWindow to select
                                tell aTab to select
                                tell aSession to select
                                return "found"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "missing"
            """
        case .appleTerminal:
            guard let tty = clientTTY ?? target.ttyDevice else {
                return "tell application \"Terminal\" to activate"
            }
            return """
            tell application "Terminal"
                activate
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        if (tty of aTab) is \(literal(tty)) then
                            set selected tab of aWindow to aTab
                            set frontmost of aWindow to true
                            return "found"
                        end if
                    end repeat
                end repeat
            end tell
            return "missing"
            """
        case .other:
            return nil
        }
    }

    /// tmux invocations (argv after the tmux binary) that bring the pane to the front of its session.
    public static func tmuxCommands(for target: JumpTarget) -> [[String]] {
        guard let pane = target.tmuxPane, pane.hasPrefix("%"), pane.dropFirst().allSatisfy(\.isNumber) else { return [] }
        let socket = target.tmuxSocket.map { ["-S", $0] } ?? []
        return [socket + ["select-window", "-t", pane], socket + ["select-pane", "-t", pane]]
    }

    /// tmux query for the tty of the client attached to the pane's session.
    public static func tmuxClientQuery(for target: JumpTarget) -> [String]? {
        guard let pane = target.tmuxPane, pane.hasPrefix("%"), pane.dropFirst().allSatisfy(\.isNumber) else { return nil }
        let socket = target.tmuxSocket.map { ["-S", $0] } ?? []
        return socket + ["list-clients", "-t", pane, "-F", "#{client_tty}"]
    }

    /// WezTerm: which tab the pane is in is read from `wezterm cli list --format json`, then that tab and the pane are activated.
    public static func weztermListQuery(for target: JumpTarget) -> [String]? {
        guard target.weztermPane != nil else { return nil }
        return ["cli", "--no-auto-start", "list", "--format", "json"]
    }

    /// The tab of a pane in `wezterm cli list --format json` output.
    public static func weztermTab(ofPane pane: String, listing: String) -> String? {
        guard let rows = (try? JSONValue.parse(Data(listing.utf8)))?.arrayValue else { return nil }
        for row in rows where row["pane_id"]?.intValue.map(String.init) == pane {
            return row["tab_id"]?.intValue.map(String.init)
        }
        return nil
    }

    public static func weztermCommands(for target: JumpTarget, tab: String?) -> [[String]] {
        guard let pane = target.weztermPane else { return [] }
        var commands: [[String]] = []
        if let tab, tab.allSatisfy(\.isNumber) { commands.append(["cli", "--no-auto-start", "activate-tab", "--tab-id", tab]) }
        commands.append(["cli", "--no-auto-start", "activate-pane", "--pane-id", pane])
        return commands
    }

    /// The environment for `wezterm cli`: the socket of the GUI the pane lives in, when known.
    public static func weztermEnvironment(for target: JumpTarget) -> [String: String] {
        target.weztermSocket.map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:]
    }

    /// kitty: focus the window through its remote control. Needs `allow_remote_control` and `listen_on` in kitty's config.
    public static func kittyCommand(for target: JumpTarget) -> [String]? {
        guard let window = target.kittyWindow, let socket = target.kittySocket else { return nil }
        return ["@", "--to", socket, "focus-window", "--match", "id:" + window]
    }

    public static func locateWezTerm(ancestors: [ProcessNode] = []) -> String? {
        // The GUI's own folder has the command line tool next to it.
        let siblings = ancestors.map(\.path).filter { ($0 as NSString).lastPathComponent.hasPrefix("wezterm") }
            .map { (($0 as NSString).deletingLastPathComponent as NSString).appendingPathComponent("wezterm") }
        let candidates = siblings + ["/Applications/WezTerm.app/Contents/MacOS/wezterm", "/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func locateKitty(ancestors: [ProcessNode] = []) -> String? {
        let fromAncestors = ancestors.map(\.path).filter { ($0 as NSString).lastPathComponent == "kitty" }
        let candidates = fromAncestors + ["/Applications/kitty.app/Contents/MacOS/kitty", "/opt/homebrew/bin/kitty", "/usr/local/bin/kitty"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func locateTmux(ancestors: [ProcessNode] = []) -> String? {
        let fromAncestors = ancestors.map(\.path).filter { ($0 as NSString).lastPathComponent == "tmux" }
        let candidates = fromAncestors + ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux", "/opt/local/bin/tmux"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// A follow-up typed on the island and sent into the terminal the agent runs
/// in, as if typed there. Only where the terminal can be addressed exactly
/// (a tmux pane, an iTerm2 session, a Terminal.app tab), and only after
/// checking that what sits at that terminal's prompt is the agent and not a shell.
public enum TerminalReply {
    public enum Channel: Sendable, Equatable {
        case tmux(socket: String?, pane: String)
        case iterm(guid: String)
        case terminal(tty: String)
    }

    public static let limit = 2000

    /// Where a reply to this session can go, if anywhere.
    public static func channel(for session: Session) -> Channel? {
        let target = JumpTarget(terminal: session.terminal, ancestors: session.ancestors)
        if let pane = target.tmuxPane, pane.hasPrefix("%"), pane.count > 1, pane.dropFirst().allSatisfy(\.isNumber) {
            return .tmux(socket: target.tmuxSocket, pane: pane)
        }
        switch target.app {
        case .iterm2:
            guard let guid = target.itermSessionGUID, !guid.isEmpty else { return nil }
            return .iterm(guid: guid)
        case .appleTerminal:
            guard let tty = target.ttyDevice, tty.hasPrefix("/dev/tty"), tty.dropFirst(5).allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            return .terminal(tty: tty)
        case .other:
            return nil
        }
    }

    /// One line: line breaks become spaces, control characters go, and it has an end.
    public static func clean(_ text: String) -> String? {
        var out = ""
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                out += " "
            } else if scalar.value >= 0x20, scalar.value != 0x7F {
                out.unicodeScalars.append(scalar)
            }
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) : trimmed
    }

    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "pwsh", "login", "tmux", "screen", "ssh", "sudo", "su"]

    /// Whether what is in the foreground of a terminal is this agent waiting for
    /// input. A shell there means the agent has gone, and text sent now would
    /// be run as a command: that is refused, whatever else is in the list.
    public static func isAgentWaiting(foreground commands: [String], source: String) -> Bool {
        let names = commands.map { command -> String in
            var name = command.trimmingCharacters(in: .whitespaces)
            if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
            while name.hasPrefix("-") { name.removeFirst() }
            return name.lowercased()
        }.filter { !$0.isEmpty }
        guard !names.isEmpty, !names.contains(where: shells.contains) else { return false }
        let agent = Set((AgentRegistry.descriptor(source)?.processes ?? []).map { $0.lowercased() } + [source.lowercased(), "node", "bun", "deno"])
        return names.contains { name in agent.contains { name == $0 || name.hasPrefix($0 + "-") } }
    }

    /// The foreground commands of a terminal, from `ps -o stat=,comm= -t <tty>`: the lines whose state carries a `+`.
    public static func foreground(psOutput: String) -> [String] {
        psOutput.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2, fields[0].contains("+") else { return nil }
            return fields[1].trimmingCharacters(in: .whitespaces)
        }
    }

    /// tmux: asks what the pane is running.
    public static func tmuxProbe(socket: String?, pane: String) -> [String] {
        (socket.map { ["-S", $0] } ?? []) + ["display-message", "-p", "-t", pane, "#{pane_current_command}"]
    }

    /// tmux: the text, literally, then Return.
    public static func tmuxSend(socket: String?, pane: String, text: String) -> [[String]] {
        let prefix = socket.map { ["-S", $0] } ?? []
        return [prefix + ["send-keys", "-t", pane, "-l", "--", text], prefix + ["send-keys", "-t", pane, "Enter"]]
    }

    /// The tty of an iTerm2 session, to check what runs there.
    public static func itermTTYScript(guid: String) -> String {
        """
        tell application "iTerm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if (unique id of aSession) is \(TerminalJump.literal(guid)) then return (tty of aSession)
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    /// AppleScript that types the text into the session or tab and presses Return. Nothing is activated.
    public static func appleScript(for channel: Channel, text: String) -> String? {
        switch channel {
        case .tmux:
            return nil
        case .iterm(let guid):
            return """
            tell application "iTerm2"
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if (unique id of aSession) is \(TerminalJump.literal(guid)) then
                                tell aSession to write text \(TerminalJump.literal(text))
                                return "sent"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "missing"
            """
        case .terminal(let tty):
            return """
            tell application "Terminal"
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        if (tty of aTab) is \(TerminalJump.literal(tty)) then
                            do script \(TerminalJump.literal(text)) in aTab
                            return "sent"
                        end if
                    end repeat
                end repeat
            end tell
            return "missing"
            """
        }
    }
}

/// A jump the user wrote: for sessions of an agent or in an app, open a link instead
/// (an editor's own link to a folder, a launcher's, a script's). `{cwd}`, `{project}`,
/// `{session}` and `{agent}` are filled in, each escaped for a link.
public struct JumpRule: Sendable, Equatable, Codable {
    /// An agent id ("claude"), an app's name as its row shows it ("VS Code"), a bundle id, or "*" for any session.
    public var match: String
    public var url: String

    public init(match: String, url: String) {
        self.match = match
        self.url = url
    }

    public func matches(_ session: Session) -> Bool {
        let wanted = match.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return false }
        if wanted == "*" { return true }
        let names = [session.source, session.hostName, session.hostBundleID, AgentRegistry.displayName(for: session.source)]
            .compactMap { $0?.lowercased() }
        return names.contains(wanted)
    }

    /// The link for this session, or nil when the template does not make one (or would need a folder it has not got).
    public func link(for session: Session) -> URL? {
        link(cwd: session.cwd, project: session.cwd.flatMap { AutoNamer.projectName(cwd: $0) },
             session: session.key.sessionID.isEmpty ? nil : session.key.sessionID, agent: session.source)
    }

    /// The rule can make a link at all (checked with made-up values before it is added).
    public var isUsable: Bool {
        !match.trimmingCharacters(in: .whitespaces).isEmpty
            && link(cwd: "/Users/someone/Projects/demo app", project: "demo app", session: "0a1b-2c3d", agent: "claude") != nil
    }

    func link(cwd: String?, project: String?, session: String?, agent: String) -> URL? {
        let template = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = template.firstIndex(of: ":"), colon > template.startIndex else { return nil }
        // A link to a web page or a file is not a jump.
        let scheme = template[..<colon].lowercased()
        guard !["http", "https", "file", "javascript", "data"].contains(scheme) else { return nil }
        var path = CharacterSet.urlPathAllowed
        path.remove(charactersIn: "?#")
        var part = CharacterSet.urlQueryAllowed
        part.remove(charactersIn: "&=+?#/")
        let values: [(String, String?, CharacterSet)] = [
            ("{cwd}", cwd, path), ("{project}", project, part), ("{session}", session, part), ("{agent}", agent, part),
        ]
        var text = template
        for (token, value, allowed) in values where text.contains(token) {
            guard let value, let escaped = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            text = text.replacingOccurrences(of: token, with: escaped)
        }
        return URL(string: text)
    }

    /// The first rule that applies to a session, and its link.
    public static func link(for session: Session, rules: [JumpRule]) -> URL? {
        for rule in rules where rule.matches(session) {
            if let link = rule.link(for: session) { return link }
        }
        return nil
    }
}
