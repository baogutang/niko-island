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

/// Static description of how an agent accepts hooks.
public struct AgentDescriptor: Sendable, Equatable {
    public enum Stability: String, Sendable {
        /// Wired end to end and covered by tests against the documented format.
        case stable
        /// Follows the agent's own hook reference (or registrations seen
        /// working in the wild); not yet driven by us against the live agent.
        case beta
        /// Format taken on trust; opt-in only.
        case experimental
        /// Listed for completeness; no adapter yet.
        case planned
    }

    /// How a hook file that is entirely ours is spelled.
    public enum HookFileFormat: Sendable, Equatable {
        /// Claude Code's shape: `{ "hooks": { event: [group] } }`.
        case claude
        /// Copilot CLI (hooks reference): `{ "version": 1, "hooks": { event: [{ "type", "bash", "timeoutSec" }] } }`.
        /// Claude's event names select its Claude-shaped payloads.
        case copilot
        /// Kiro (hooks reference, CLI V3 and the IDE): `{ "version": "v1", "hooks": [{ "name", "trigger", "action", … }] }`.
        case kiro
    }

    /// Which in-process plugin we generate.
    public enum PluginFlavor: Sendable, Equatable {
        /// OpenCode and its relatives: `export const NikoIsland = async ({ client, directory }) => hooks`.
        case openCode
        /// Amp (plugin API): `export default function (amp) { amp.on(event, handler) }`, run by Bun.
        case amp
    }

    public enum Mechanism: Sendable, Equatable {
        /// Our entries are merged into a JSON config the agent shares with the user.
        case sharedSettings(file: String, events: [HookSpec], statusLine: Bool, dialect: HookDialect = .claude)
        /// A hook file that is entirely ours.
        case ownedHookFile(file: String, events: [HookSpec], format: HookFileFormat = .claude)
        /// A plugin pack that is entirely ours, laid out as Claude Code plugins are:
        /// `.claude-plugin/plugin.json` and `hooks/hooks.json`.
        case pluginPack(directory: String, events: [HookSpec])
        /// A block of `[[hooks]]` tables of ours at the end of a TOML config the agent shares with the user.
        case tomlHooks(file: String, events: [HookSpec])
        /// An in-process JS plugin that talks to the loopback HTTP ingress.
        case jsPlugin(file: String, flavor: PluginFlavor = .openCode)
        case none
    }

    public var id: String
    public var displayName: String
    /// HOME-relative directory the agent keeps its config in. Its existence means
    /// "installed" unless `markers` says what else to look for.
    public var directory: String
    public var binary: String?
    public var mechanism: Mechanism
    public var stability: Stability
    /// SF Symbol shown on session cards.
    public var symbol: String
    /// Extra arguments for the bridge (how to phrase a decision, for one).
    public var bridgeArguments: [String] = []
    /// Bundle ids of the agent's desktop apps.
    public var apps: [String] = []
    /// Executable names of the agent's command-line tools.
    public var processes: [String] = []
    /// The island can decide permission requests for this agent.
    public var approvals = false
    /// The agent's own app can spend a quota reset (ZCode's reset cards). We
    /// never do that for it; the usage view offers to bring the app forward.
    public var quotaResetInApp = false
    /// Something the user has to do in the agent itself after connecting.
    public var followUp: String?
    /// Files an earlier version of ours wrote for this agent and no longer uses.
    public var legacyFiles: [String] = []
    /// HOME-relative paths of which at least one exists once the agent has really
    /// run here, for an agent whose directory other tools create too (`~/.claude`
    /// holds skills and settings that Cursor and skill installers read and write).
    /// Its command on the PATH counts as well. Empty: the directory is enough.
    public var markers: [String] = []
    /// Configs the agent shares with the user where an earlier version of ours
    /// put hook entries (Claude's shape) the agent never read. Only our entries
    /// are taken out of them; the files themselves stay.
    public var legacySettings: [String] = []

    /// HOME-relative files the scan has to read for this agent.
    public var files: [String] {
        let current: [String]
        switch mechanism {
        case .sharedSettings(let file, _, _, _), .ownedHookFile(let file, _, _), .tomlHooks(let file, _), .jsPlugin(let file, _):
            current = [file]
        case .pluginPack(let directory, _):
            current = [directory + "/" + AgentDescriptor.packManifest, directory + "/" + AgentDescriptor.packHooks]
        case .none:
            return []
        }
        return current + legacyFiles + legacySettings
    }

    static let packManifest = ".claude-plugin/plugin.json"
    static let packHooks = "hooks/hooks.json"

    /// The files that hold this agent's current wiring (legacy leftovers excluded).
    public var activeFiles: [String] { files.filter { !legacyFiles.contains($0) && !legacySettings.contains($0) } }

    public var usesHTTPIngress: Bool {
        if case .jsPlugin = mechanism { return true }
        return false
    }

    /// Good enough to be offered, ticked, the first time the app runs.
    public var isRecommended: Bool { stability == .stable || stability == .beta }
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
        HookSpec(HookEvent.stopFailure),
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

    /// Codex (hooks reference): no matcher means "every tool"; SessionEnd may
    /// take three seconds at most, so it gets no timeout of ours.
    static let codexEvents: [HookSpec] = [
        HookSpec(HookEvent.sessionStart, matcher: nil),
        HookSpec(HookEvent.sessionEnd, matcher: nil, timeout: nil),
        HookSpec(HookEvent.userPromptSubmit, matcher: nil),
        HookSpec(HookEvent.preToolUse, matcher: nil),
        HookSpec(HookEvent.postToolUse, matcher: nil),
        HookSpec(HookEvent.stop, matcher: nil),
        HookSpec(HookEvent.subagentStop, matcher: nil),
        HookSpec(HookEvent.preCompact, matcher: nil),
        HookSpec(HookEvent.postCompact, matcher: nil),
        HookSpec(HookEvent.permissionRequest, matcher: nil, timeout: HookSpec.approvalTimeout),
    ]

    /// ZCode (hooks reference): its seven events; matchers are regular expressions.
    static let zcodeEvents: [HookSpec] = [
        HookSpec(HookEvent.sessionStart, matcher: ".*"),
        HookSpec(HookEvent.userPromptSubmit, matcher: ".*"),
        HookSpec(HookEvent.preToolUse, matcher: ".*"),
        HookSpec(HookEvent.postToolUse, matcher: ".*"),
        HookSpec("PostToolUseFailure", matcher: ".*"),
        HookSpec(HookEvent.stop, matcher: ".*"),
        HookSpec(HookEvent.permissionRequest, matcher: ".*", timeout: HookSpec.approvalTimeout),
    ]

    /// Cursor (hooks reference): only hooks that observe. Its permission hooks
    /// (beforeShellExecution and friends) must answer with a decision, and the
    /// island does not decide for Cursor.
    static let cursorEvents: [HookSpec] = [
        "sessionStart", "sessionEnd", "beforeSubmitPrompt", "afterAgentThought", "afterAgentResponse",
        "afterShellExecution", "afterMCPExecution", "afterFileEdit", "postToolUse", "postToolUseFailure",
        "subagentStop", "preCompact", "stop",
    ].map { HookSpec($0, matcher: nil) }

    /// Windsurf / Cascade (hooks reference): a pre-hook that exits 0 without output lets the action through.
    static let windsurfEvents: [HookSpec] = [
        "pre_user_prompt", "pre_run_command", "post_run_command", "pre_read_code", "post_read_code",
        "pre_write_code", "post_write_code", "pre_mcp_tool_use", "post_mcp_tool_use", "post_cascade_response",
    ].map { HookSpec($0, matcher: nil, timeout: nil) }

    /// Gemini CLI (hooks reference): its own event names; timeouts in milliseconds.
    static let geminiEvents: [HookSpec] = [
        "SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool", "Notification",
    ].map { HookSpec($0, matcher: nil, timeout: 5) }

    static let traeEvents: [HookSpec] = [
        HookSpec(HookEvent.sessionStart, matcher: nil),
        HookSpec(HookEvent.userPromptSubmit, matcher: nil),
        HookSpec(HookEvent.preToolUse),
        HookSpec(HookEvent.postToolUse),
        HookSpec(HookEvent.notification, matcher: nil),
        HookSpec(HookEvent.stop, matcher: nil),
    ]

    /// Qoder, Qoder CN and QoderWork read Claude Code's format from their own
    /// settings file (the registration CodeIsland ships). Their approval hook
    /// is only watched: the bridge says "needs permission" and returns at once.
    static let qoderEvents: [HookSpec] = [
        HookSpec(HookEvent.sessionStart),
        HookSpec(HookEvent.sessionEnd),
        HookSpec(HookEvent.userPromptSubmit),
        HookSpec(HookEvent.preToolUse),
        HookSpec(HookEvent.postToolUse),
        HookSpec("PostToolUseFailure"),
        HookSpec(HookEvent.permissionRequest),
        HookSpec(HookEvent.notification),
        HookSpec(HookEvent.stop),
        HookSpec(HookEvent.subagentStop),
        HookSpec(HookEvent.preCompact),
    ]

    /// Kimi Code (hooks reference): twenty events, every one of which may only
    /// watch except UserPromptSubmit, PreToolUse and Stop; an unknown event or
    /// key stops the whole config from loading, so only names from its list.
    /// No matcher means every tool; timeouts in seconds, 1 to 600.
    static let kimiEvents: [HookSpec] = [
        HookEvent.sessionStart, HookEvent.sessionEnd, HookEvent.userPromptSubmit, HookEvent.preToolUse,
        HookEvent.postToolUse, "PostToolUseFailure", HookEvent.permissionRequest, "PermissionResult",
        HookEvent.notification, HookEvent.stop, HookEvent.stopFailure, "Interrupt", HookEvent.subagentStop,
        HookEvent.preCompact, HookEvent.postCompact,
    ].map { HookSpec($0, matcher: nil) }

    /// MiniMax Code (`mcode`): Claude's events and payloads, loaded from a plugin
    /// pack only. A timeout must be a whole number of seconds from 1 to 10, or
    /// the handler is dropped; so its approval hook is only watched.
    static let minimaxEvents: [HookSpec] = [
        HookEvent.sessionStart, HookEvent.sessionEnd, HookEvent.userPromptSubmit, HookEvent.preToolUse,
        HookEvent.permissionRequest, HookEvent.postToolUse, HookEvent.subagentStop, HookEvent.stop,
        HookEvent.preCompact, HookEvent.postCompact,
    ].map { HookSpec($0, matcher: nil, timeout: 5) }

    /// Devin (hooks reference): Claude's shape in ~/.config/devin/config.json;
    /// a missing matcher means every tool; timeouts in seconds. It answers a
    /// permission request with `{"decision": "approve" | "block"}`.
    static let devinEvents: [HookSpec] = [
        HookSpec(HookEvent.sessionStart, matcher: nil),
        HookSpec(HookEvent.sessionEnd, matcher: nil),
        HookSpec(HookEvent.userPromptSubmit, matcher: nil),
        HookSpec(HookEvent.preToolUse, matcher: nil),
        HookSpec(HookEvent.postToolUse, matcher: nil),
        HookSpec(HookEvent.stop, matcher: nil),
        HookSpec("PostCompaction", matcher: nil),
        HookSpec(HookEvent.permissionRequest, matcher: nil, timeout: HookSpec.approvalTimeout),
    ]

    /// Copilot CLI (hooks reference): Claude's event names select Claude-shaped
    /// payloads (`hook_event_name`, `session_id`, `tool_name`, `tool_input`).
    /// Its tool hook fails closed on a non-zero exit; ours always exits 0.
    static let copilotEvents: [HookSpec] = [
        HookEvent.sessionStart, HookEvent.sessionEnd, HookEvent.userPromptSubmit, HookEvent.preToolUse,
        HookEvent.postToolUse, HookEvent.notification, HookEvent.stop, HookEvent.subagentStop, HookEvent.preCompact,
    ].map { HookSpec($0, matcher: nil) }

    /// Kiro (hooks reference, CLI V3 and the IDE): global hook files in
    /// ~/.kiro/hooks run in every workspace; no matcher means always.
    static let kiroEvents: [HookSpec] = [
        HookEvent.sessionStart, HookEvent.sessionEnd, HookEvent.userPromptSubmit, HookEvent.preToolUse,
        HookEvent.postToolUse, HookEvent.stop,
    ].map { HookSpec($0, matcher: nil) }

    private static func shared(_ id: String, _ name: String, dir: String, file: String, binary: String? = nil,
                               events: [HookSpec] = monitorEvents, dialect: HookDialect = .claude,
                               stability: AgentDescriptor.Stability = .experimental, symbol: String,
                               apps: [String] = [], processes: [String]? = nil) -> AgentDescriptor {
        AgentDescriptor(id: id, displayName: name, directory: dir, binary: binary ?? id,
                        mechanism: .sharedSettings(file: file, events: events, statusLine: false, dialect: dialect),
                        stability: stability, symbol: symbol, apps: apps, processes: processes ?? [binary ?? id])
    }

    private static func planned(_ id: String, _ name: String, dir: String, symbol: String = "questionmark.circle") -> AgentDescriptor {
        AgentDescriptor(id: id, displayName: name, directory: dir, binary: nil, mechanism: .none,
                        stability: .planned, symbol: symbol)
    }

    private static func with(_ descriptor: AgentDescriptor, _ change: (inout AgentDescriptor) -> Void) -> AgentDescriptor {
        var copy = descriptor
        change(&copy)
        return copy
    }

    public static let all: [AgentDescriptor] = [
        AgentDescriptor(id: "claude", displayName: "Claude Code", directory: ".claude", binary: "claude",
                        mechanism: .sharedSettings(file: ".claude/settings.json", events: claudeEvents, statusLine: true),
                        stability: .stable, symbol: "sparkle",
                        apps: ["com.anthropic.claudefordesktop"], processes: ["claude"], approvals: true,
                        markers: [".claude.json", ".claude/projects", ".local/share/claude/versions", ".claude/local/claude"]),
        with(shared("codex", "Codex", dir: ".codex", file: ".codex/hooks.json", events: codexEvents, stability: .beta,
                    symbol: "chevron.left.forwardslash.chevron.right", apps: ["com.openai.codex"])) {
            $0.bridgeArguments = ["--reply", "json-strict"]
            $0.approvals = true
            $0.followUp = "Codex runs a new hook only after you trust it: type /hooks in Codex and trust the niko-bridge entries."
        },
        with(shared("zcode", "ZCode", dir: ".zcode/cli", file: ".zcode/cli/config.json", events: zcodeEvents, dialect: .zcode,
                    stability: .beta, symbol: "z.circle", apps: ["dev.zcode.app"], processes: ["zcode", "zcode-cli"])) {
            $0.bridgeArguments = ["--reply", "json-strict"]
            $0.approvals = true
            $0.followUp = "ZCode reads its hooks when a session starts: sessions that are already open stay as they are."
            $0.quotaResetInApp = true
        },
        shared("cursor", "Cursor", dir: ".cursor", file: ".cursor/hooks.json", binary: "cursor-agent", events: cursorEvents,
               dialect: .cursor, stability: .beta, symbol: "cursorarrow.rays", apps: ["com.todesktop.230313mzl4w4u92"]),
        shared("windsurf", "Windsurf", dir: ".codeium/windsurf", file: ".codeium/windsurf/hooks.json", events: windsurfEvents,
               dialect: .windsurf, stability: .beta, symbol: "wind", apps: ["com.exafunction.windsurf"]),
        with(shared("gemini", "Gemini CLI", dir: ".gemini", file: ".gemini/settings.json", events: geminiEvents, dialect: .gemini,
                    stability: .beta, symbol: "diamond")) {
            // 0.2.0 wrote a plugin directory Gemini CLI never read.
            $0.legacyFiles = [".gemini/config/plugins/niko/hooks.json", ".gemini/config/plugins/niko/plugin.json"]
        },
        AgentDescriptor(id: "opencode", displayName: "OpenCode", directory: ".config/opencode", binary: "opencode",
                        mechanism: .jsPlugin(file: ".config/opencode/plugins/niko.js"),
                        stability: .experimental, symbol: "terminal", apps: ["ai.opencode.desktop"], processes: ["opencode"]),
        shared("trae", "Trae", dir: ".trae", file: ".trae/hooks.json", events: traeEvents, dialect: .trae, stability: .beta,
               symbol: "hammer", apps: ["com.trae.app"]),
        shared("trae-cn", "Trae (CN)", dir: ".trae-cn", file: ".trae-cn/hooks.json", binary: "trae", events: traeEvents,
               dialect: .trae, stability: .beta, symbol: "hammer", apps: ["cn.trae.app"]),
        shared("qwen", "Qwen Code", dir: ".qwen", file: ".qwen/settings.json", stability: .beta, symbol: "q.circle"),
        shared("codebuddy", "CodeBuddy", dir: ".codebuddy", file: ".codebuddy/settings.json", stability: .beta, symbol: "person.2"),
        shared("factory", "Factory", dir: ".factory", file: ".factory/settings.json", binary: "droid", stability: .beta,
               symbol: "gearshape.2"),
        AgentDescriptor(id: "grok", displayName: "Grok CLI", directory: ".grok", binary: "grok",
                        mechanism: .ownedHookFile(file: ".grok/hooks/niko.json", events: monitorEvents),
                        stability: .beta, symbol: "bolt", processes: ["grok"]),
        AgentDescriptor(id: "copilot", displayName: "Copilot CLI", directory: ".copilot", binary: "copilot",
                        mechanism: .ownedHookFile(file: ".copilot/hooks/niko.json", events: copilotEvents, format: .copilot),
                        stability: .beta, symbol: "airplane", processes: ["copilot"]),
        AgentDescriptor(id: "mimocode", displayName: "MiMoCode", directory: ".config/mimocode", binary: "mimocode",
                        mechanism: .jsPlugin(file: ".config/mimocode/plugins/niko.js"),
                        stability: .experimental, symbol: "terminal", processes: ["mimocode"]),
        shared("qwenwork", "QwenWork", dir: ".qwenwork", file: ".qwenwork/settings.json", symbol: "q.circle"),
        with(shared("qoder", "Qoder", dir: ".qoder", file: ".qoder/settings.json", binary: "qodercli", events: qoderEvents,
                    stability: .beta, symbol: "chevron.left.slash.chevron.right")) {
            $0.bridgeArguments = ["--observe"]
        },
        with(shared("qoder-cn", "Qoder (CN)", dir: ".qoder-cn", file: ".qoder-cn/settings.json", binary: "qodercli",
                    events: qoderEvents, stability: .beta, symbol: "chevron.left.slash.chevron.right")) {
            $0.bridgeArguments = ["--observe"]
        },
        with(shared("qoderwork", "QoderWork", dir: ".qoderwork", file: ".qoderwork/settings.json", binary: "qoderwork",
                    events: qoderEvents, symbol: "chevron.left.slash.chevron.right")) {
            $0.bridgeArguments = ["--observe"]
        },
        AgentDescriptor(id: "kiro", displayName: "Kiro", directory: ".kiro", binary: "kiro-cli",
                        mechanism: .ownedHookFile(file: ".kiro/hooks/niko.json", events: kiroEvents, format: .kiro),
                        stability: .experimental, symbol: "k.circle", apps: ["dev.kiro.desktop"], processes: ["kiro-cli"],
                        followUp: "Kiro runs global hook files in its app and from version 3 of its CLI; an older Kiro CLI does not.",
                        legacySettings: [".kiro/settings/cli.json"]),
        AgentDescriptor(id: "kimi", displayName: "Kimi Code", directory: ".kimi-code", binary: "kimi",
                        mechanism: .tomlHooks(file: ".kimi-code/config.toml", events: kimiEvents),
                        stability: .beta, symbol: "moon", bridgeArguments: ["--observe"], processes: ["kimi"],
                        followUp: "Kimi Code reads its hooks when a session starts: sessions that are already open stay as they are."),
        AgentDescriptor(id: "minimax", displayName: "MiniMax Code", directory: ".minimax", binary: "mcode",
                        mechanism: .pluginPack(directory: ".minimax/plugins/niko", events: minimaxEvents),
                        stability: .experimental, symbol: "m.circle", bridgeArguments: ["--observe"], processes: ["mcode"]),
        with(shared("devin", "Devin", dir: ".config/devin", file: ".config/devin/config.json", events: devinEvents,
                    stability: .beta, symbol: "d.circle")) {
            $0.bridgeArguments = ["--reply", "devin"]
            $0.approvals = true
        },
        AgentDescriptor(id: "amp", displayName: "Amp", directory: ".config/amp", binary: "amp",
                        mechanism: .jsPlugin(file: ".config/amp/plugins/niko.ts", flavor: .amp),
                        stability: .experimental, symbol: "bolt.horizontal", processes: ["amp"],
                        followUp: "Amp's plugin API is experimental and runs in its command-line app only: reload plugins in Amp (or start it again) to load ours."),
        planned("vibe", "Mistral Vibe", dir: ".vibe"),
        planned("deepseek", "DeepSeek CLI", dir: ".deepseek"),
        planned("pi", "Pi / OhMyPi", dir: ".pi"),
        planned("openclaw", "OpenClaw", dir: ".openclaw"),
    ]

    public static func descriptor(_ id: String) -> AgentDescriptor? { all.first { $0.id == id } }

    public static var installable: [AgentDescriptor] { all.filter { $0.stability != .planned } }

    /// What a bare `niko-island install` wires up: stable adapters only.
    public static var defaultIDs: [String] { all.filter { $0.stability == .stable }.map(\.id) }

    /// What the app offers, ticked, on first launch: everything it can vouch for.
    public static var recommendedIDs: [String] { all.filter(\.isRecommended).map(\.id) }

    public static func symbol(for source: String) -> String {
        descriptor(source)?.symbol ?? "questionmark.circle"
    }

    public static func displayName(for source: String) -> String {
        descriptor(source)?.displayName ?? source
    }

    /// The agent a desktop app belongs to.
    public static func agent(forApp bundleID: String) -> AgentDescriptor? {
        all.first { $0.apps.contains(bundleID) }
    }
}
