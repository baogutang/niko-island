import Foundation

/// One hook registration: which event, which matcher, how long the agent may wait.
public struct HookSpec: Sendable, Equatable {
    public var event: String
    public var matcher: String?
    public var timeout: Int?

    public init(_ event: String, matcher: String? = "*", timeout: Int? = HookSpec.quickTimeout) {
        self.event = event
        self.matcher = matcher
        self.timeout = timeout
    }

    /// Fire-and-forget hooks: the bridge returns in milliseconds, this is only a backstop.
    public static let quickTimeout = 10
    /// PROTOCOLS §2.2: a pending approval may wait a day.
    public static let approvalTimeout = 86400
}

/// Static description of how an agent accepts hooks (INTEGRATIONS.md).
public struct AgentDescriptor: Sendable, Equatable {
    public enum Stability: String, Sendable {
        /// Wired end to end and covered by tests against the documented format.
        case stable
        /// Follows INTEGRATIONS.md but not validated against a live agent; opt-in only.
        case experimental
        /// Listed for completeness; no adapter yet.
        case planned
    }

    public enum Mechanism: Sendable, Equatable {
        /// Our entries are merged into a JSON config the agent shares with the user.
        case sharedSettings(file: String, events: [HookSpec], statusLine: Bool)
        /// A hook file that is entirely ours.
        case ownedHookFile(file: String, events: [HookSpec])
        /// A plugin directory that is entirely ours (manifest + hooks file).
        case ownedPluginDirectory(directory: String, events: [HookSpec])
        /// An in-process JS plugin that talks to the loopback HTTP ingress.
        case jsPlugin(file: String)
        case none
    }

    public var id: String
    public var displayName: String
    /// HOME-relative directory whose existence means "this agent is installed".
    public var directory: String
    public var binary: String?
    public var mechanism: Mechanism
    public var stability: Stability
    /// SF Symbol shown on session cards.
    public var symbol: String

    /// HOME-relative files the scan has to read for this agent.
    public var files: [String] {
        switch mechanism {
        case .sharedSettings(let file, _, _): return [file]
        case .ownedHookFile(let file, _): return [file]
        case .ownedPluginDirectory(let directory, _): return [directory + "/hooks.json", directory + "/plugin.json"]
        case .jsPlugin(let file): return [file]
        case .none: return []
        }
    }

    public var usesHTTPIngress: Bool {
        if case .jsPlugin = mechanism { return true }
        return false
    }
}

public enum AgentRegistry {
    static let claudeEvents: [HookSpec] = [
        HookSpec(HookEvent.sessionStart),
        HookSpec(HookEvent.sessionEnd),
        HookSpec(HookEvent.userPromptSubmit),
        HookSpec(HookEvent.preToolUse),
        HookSpec(HookEvent.postToolUse),
        HookSpec(HookEvent.notification),
        HookSpec(HookEvent.stop),
        HookSpec(HookEvent.subagentStop),
        HookSpec(HookEvent.preCompact, matcher: "manual|auto"),
        HookSpec(HookEvent.postCompact, matcher: "manual|auto"),
        HookSpec(HookEvent.permissionRequest, timeout: HookSpec.approvalTimeout),
    ]

    /// Status-only wiring for agents whose approval contract we have not verified.
    static let monitorEvents: [HookSpec] = [
        HookSpec(HookEvent.sessionStart),
        HookSpec(HookEvent.sessionEnd),
        HookSpec(HookEvent.userPromptSubmit),
        HookSpec(HookEvent.preToolUse),
        HookSpec(HookEvent.postToolUse),
        HookSpec(HookEvent.notification),
        HookSpec(HookEvent.stop),
    ]

    private static func shared(_ id: String, _ name: String, dir: String, file: String, binary: String? = nil,
                               symbol: String) -> AgentDescriptor {
        AgentDescriptor(id: id, displayName: name, directory: dir, binary: binary ?? id,
                        mechanism: .sharedSettings(file: file, events: monitorEvents, statusLine: false),
                        stability: .experimental, symbol: symbol)
    }

    private static func planned(_ id: String, _ name: String, dir: String, symbol: String = "questionmark.circle") -> AgentDescriptor {
        AgentDescriptor(id: id, displayName: name, directory: dir, binary: nil, mechanism: .none,
                        stability: .planned, symbol: symbol)
    }

    public static let all: [AgentDescriptor] = [
        AgentDescriptor(id: "claude", displayName: "Claude Code", directory: ".claude", binary: "claude",
                        mechanism: .sharedSettings(file: ".claude/settings.json", events: claudeEvents, statusLine: true),
                        stability: .stable, symbol: "sparkle"),
        shared("codex", "Codex CLI", dir: ".codex", file: ".codex/hooks.json", symbol: "chevron.left.forwardslash.chevron.right"),
        shared("cursor", "Cursor CLI", dir: ".cursor", file: ".cursor/hooks.json", binary: "cursor-agent", symbol: "cursorarrow.rays"),
        AgentDescriptor(id: "copilot", displayName: "Copilot CLI", directory: ".copilot", binary: "copilot",
                        mechanism: .ownedHookFile(file: ".copilot/hooks/niko.json", events: monitorEvents),
                        stability: .experimental, symbol: "airplane"),
        AgentDescriptor(id: "gemini", displayName: "Gemini CLI", directory: ".gemini", binary: "gemini",
                        mechanism: .ownedPluginDirectory(directory: ".gemini/config/plugins/niko", events: monitorEvents),
                        stability: .experimental, symbol: "diamond"),
        AgentDescriptor(id: "grok", displayName: "Grok CLI", directory: ".grok", binary: "grok",
                        mechanism: .ownedHookFile(file: ".grok/hooks/niko.json", events: monitorEvents),
                        stability: .experimental, symbol: "bolt"),
        shared("trae", "Trae", dir: ".trae", file: ".trae/hooks.json", symbol: "hammer"),
        shared("trae-cn", "Trae (CN)", dir: ".trae-cn", file: ".trae-cn/hooks.json", binary: "trae", symbol: "hammer"),
        shared("windsurf", "Windsurf", dir: ".codeium/windsurf", file: ".codeium/windsurf/hooks.json", symbol: "wind"),
        AgentDescriptor(id: "opencode", displayName: "OpenCode", directory: ".config/opencode", binary: "opencode",
                        mechanism: .jsPlugin(file: ".config/opencode/plugins/niko.js"),
                        stability: .experimental, symbol: "terminal"),
        AgentDescriptor(id: "mimocode", displayName: "MiMoCode", directory: ".config/mimocode", binary: "mimocode",
                        mechanism: .jsPlugin(file: ".config/mimocode/plugins/niko.js"),
                        stability: .experimental, symbol: "terminal"),
        shared("qwen", "Qwen Code", dir: ".qwen", file: ".qwen/settings.json", symbol: "q.circle"),
        shared("qwenwork", "QwenWork", dir: ".qwenwork", file: ".qwenwork/settings.json", symbol: "q.circle"),
        shared("kiro", "Kiro", dir: ".kiro", file: ".kiro/settings/cli.json", symbol: "k.circle"),
        shared("factory", "Factory", dir: ".factory", file: ".factory/settings.json", binary: "droid", symbol: "gearshape.2"),
        planned("kimi", "Kimi Code", dir: ".kimi"),
        planned("deepseek", "DeepSeek CLI", dir: ".deepseek"),
        planned("droid", "Droid (dsh)", dir: ".dsh"),
        planned("pi", "Pi / OhMyPi", dir: ".pi"),
        planned("openclaw", "OpenClaw", dir: ".openclaw"),
        planned("amp", "Amp", dir: ".amp"),
    ]

    public static func descriptor(_ id: String) -> AgentDescriptor? { all.first { $0.id == id } }

    public static var installable: [AgentDescriptor] { all.filter { $0.stability != .planned } }

    /// What a bare `niko-island install` wires up: stable adapters only.
    public static var defaultIDs: [String] { all.filter { $0.stability == .stable }.map(\.id) }

    public static func symbol(for source: String) -> String {
        descriptor(source)?.symbol ?? "questionmark.circle"
    }

    public static func displayName(for source: String) -> String {
        descriptor(source)?.displayName ?? source
    }
}
