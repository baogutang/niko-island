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
        let program = terminal.termProgram ?? ""
        let bundles = [terminal.bundleID].compactMap { $0 } + ancestors.compactMap(\.bundleID)
        if program == "iTerm.app" || (itermSessionGUID != nil && program != "Apple_Terminal") || bundles.contains("com.googlecode.iterm2") {
            app = .iterm2
        } else if program == "Apple_Terminal" || bundles.contains("com.apple.Terminal") {
            app = .appleTerminal
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

    public static func locateTmux(ancestors: [ProcessNode] = []) -> String? {
        let fromAncestors = ancestors.map(\.path).filter { ($0 as NSString).lastPathComponent == "tmux" }
        let candidates = fromAncestors + ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux", "/opt/local/bin/tmux"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
