import Foundation

/// User settings in `~/.niko-island/settings.json`, shared by the app and the CLI.
/// Unknown keys are kept on save so older builds do not eat newer settings.
public struct NikoSettings: Sendable, Equatable {
    public enum EventKind: String, Sendable, CaseIterable {
        case permission, question, idle
    }

    public private(set) var raw: JSONObject

    public init(raw: JSONObject = JSONObject()) { self.raw = raw }

    private func bool(_ key: String, default value: Bool) -> Bool { raw[key]?.boolValue ?? value }

    /// Loopback HTTP ingress is only needed by in-process JS plugins; off until one is installed.
    public var httpIngressEnabled: Bool {
        get { bool("httpIngressEnabled", default: false) }
        set { raw["httpIngressEnabled"] = .bool(newValue) }
    }

    public var httpPort: UInt16 {
        get { raw["httpPort"]?.intValue.flatMap { UInt16(exactly: $0) } ?? HTTPIngressServer.defaultPort }
        set { raw["httpPort"] = .int(Int(newValue)) }
    }

    public var deniedBundleIDs: [String] {
        get { (raw["deniedBundleIDs"]?.arrayValue ?? []).compactMap(\.stringValue) }
        set { raw["deniedBundleIDs"] = .array(newValue.map(JSONValue.string)) }
    }

    public var requireDeveloperEvidence: Bool {
        get { bool("requireDeveloperEvidence", default: true) }
        set { raw["requireDeveloperEvidence"] = .bool(newValue) }
    }

    /// Opt-in: the only network request the app can make on its own (SPEC §5).
    public var pricingRefreshEnabled: Bool {
        get { bool("pricingRefreshEnabled", default: false) }
        set { raw["pricingRefreshEnabled"] = .bool(newValue) }
    }

    public var onboardingDone: Bool {
        get { bool("onboardingDone", default: false) }
        set { raw["onboardingDone"] = .bool(newValue) }
    }

    /// Notifications default to on; sounds default to off (SPEC §4).
    public func notificationsEnabled(for kind: EventKind) -> Bool {
        raw["notifications"]?[kind.rawValue]?.boolValue ?? true
    }

    public mutating func setNotifications(_ enabled: Bool, for kind: EventKind) {
        var object = raw["notifications"]?.objectValue ?? JSONObject()
        object[kind.rawValue] = .bool(enabled)
        raw["notifications"] = .object(object)
    }

    // MARK: Sounds (SPEC §4: none by default)

    /// Master switch. Off until the user turns it on. A 0.1.0 settings file that
    /// had any per-event sound switched on counts as on.
    public var soundsEnabled: Bool {
        get {
            if let value = raw["soundsEnabled"]?.boolValue { return value }
            return ["permission", "question", "idle"].contains { raw["sounds"]?[$0]?.boolValue == true }
        }
        set { raw["soundsEnabled"] = .bool(newValue) }
    }

    /// Whether a cue plays once the master switch is on.
    public func soundEnabled(for event: SoundEvent) -> Bool {
        if let value = raw["sounds"]?[event.rawValue]?.boolValue { return value }
        // Keys written by 0.1.0.
        switch event {
        case .attention:
            if let old = raw["sounds"]?["permission"]?.boolValue ?? raw["sounds"]?["question"]?.boolValue { return old }
        case .completed:
            if let old = raw["sounds"]?["idle"]?.boolValue { return old }
        default:
            break
        }
        return event.enabledByDefault
    }

    public mutating func setSound(_ enabled: Bool, for event: SoundEvent) {
        var object = raw["sounds"]?.objectValue ?? JSONObject()
        object[event.rawValue] = .bool(enabled)
        raw["sounds"] = .object(object)
    }

    /// True when this cue should actually be heard.
    public func shouldPlay(_ event: SoundEvent) -> Bool { soundsEnabled && soundEnabled(for: event) }

    public var soundSource: SoundSource {
        get { SoundSource(rawValue: raw["soundSource"]?.stringValue ?? "island") }
        set { raw["soundSource"] = .string(newValue.rawValue) }
    }

    /// 0…1.
    public var soundVolume: Double {
        get { min(1, max(0, raw["soundVolume"]?.doubleValue ?? 0.7)) }
        set { raw["soundVolume"] = .number(String(format: "%.2f", min(1, max(0, newValue)))) }
    }

    public func systemSound(for event: SoundEvent) -> String {
        raw["systemSounds"]?[event.rawValue]?.stringValue ?? event.defaultSystemSound
    }

    public mutating func setSystemSound(_ name: String, for event: SoundEvent) {
        var object = raw["systemSounds"]?.objectValue ?? JSONObject()
        object[event.rawValue] = .string(name)
        raw["systemSounds"] = .object(object)
    }

    // MARK: Island behaviour

    /// Open the island when the pointer rests on it.
    public var expandOnHover: Bool {
        get { bool("expandOnHover", default: true) }
        set { raw["expandOnHover"] = .bool(newValue) }
    }

    /// Open the island by itself when an agent needs a decision.
    public var expandOnAttention: Bool {
        get { bool("expandOnAttention", default: true) }
        set { raw["expandOnAttention"] = .bool(newValue) }
    }

    /// Briefly show a finished session in the collapsed island.
    public var showCompletionToast: Bool {
        get { bool("showCompletionToast", default: true) }
        set { raw["showCompletionToast"] = .bool(newValue) }
    }

    /// What the island does when an agent finishes a turn.
    public enum CompletionStyle: String, Sendable, CaseIterable {
        /// Nothing on the island (sounds and banners have their own switches).
        case off
        /// The closed island names the session for a few seconds.
        case notice
        /// A card comes down with what the agent said last.
        case card
    }

    public var completionStyle: CompletionStyle {
        get {
            if let stored = raw["completionStyle"]?.stringValue.flatMap(CompletionStyle.init(rawValue:)) { return stored }
            // Before there was a choice there was a switch; "off" stays off.
            return showCompletionToast ? .card : .off
        }
        set {
            raw["completionStyle"] = .string(newValue.rawValue)
            raw["showCompletionToast"] = .bool(newValue != .off)
        }
    }

    /// How many lines of the agent's last reply a session row shows (0 to 3).
    public var replyLines: Int {
        get { min(3, max(0, raw["replyLines"]?.intValue ?? 1)) }
        set { raw["replyLines"] = .int(min(3, max(0, newValue))) }
    }

    /// ⌃⌥A allows and ⌃⌥D denies the request the island is showing. The keys
    /// are only claimed while a request is waiting. Off unless switched on.
    public var decisionHotkeys: Bool {
        get { bool("decisionHotkeys", default: false) }
        set { raw["decisionHotkeys"] = .bool(newValue) }
    }

    /// No sounds and no cards while the screen is locked or asleep.
    public var quietWhenAway: Bool {
        get { bool("quietWhenAway", default: true) }
        set { raw["quietWhenAway"] = .bool(newValue) }
    }

    // MARK: New versions (opt-in)

    /// Ask GitHub once a day whether a newer release is out. Off unless switched on.
    public var updateChecks: Bool {
        get { bool("updateChecks", default: false) }
        set { raw["updateChecks"] = .bool(newValue) }
    }

    /// The version that last brought connected agents' wiring up to date.
    public var lastWiredVersion: String? {
        get { raw["lastWiredVersion"]?.stringValue }
        set { raw["lastWiredVersion"] = newValue.map(JSONValue.string) }
    }

    /// When GitHub was last asked (seconds since 1970).
    public var lastUpdateCheck: Double {
        get { raw["lastUpdateCheck"]?.doubleValue ?? 0 }
        set { raw["lastUpdateCheck"] = .number(String(newValue)) }
    }

    // MARK: Quiet hours

    /// A stretch of the day in which nothing makes a sound and nothing is pushed
    /// to a phone. What is shown on the island is shown as usual: it is silent anyway.
    public var quietHoursEnabled: Bool {
        get { bool("quietHoursEnabled", default: false) }
        set { raw["quietHoursEnabled"] = .bool(newValue) }
    }

    /// Minutes after midnight, in steps of half an hour.
    public var quietFrom: Int {
        get { NikoSettings.halfHour(raw["quietFrom"]?.intValue ?? 22 * 60) }
        set { raw["quietFrom"] = .int(NikoSettings.halfHour(newValue)) }
    }

    public var quietUntil: Int {
        get { NikoSettings.halfHour(raw["quietUntil"]?.intValue ?? 8 * 60) }
        set { raw["quietUntil"] = .int(NikoSettings.halfHour(newValue)) }
    }

    static func halfHour(_ minutes: Int) -> Int { min(1410, max(0, minutes / 30 * 30)) }

    /// Whether `date` falls inside the quiet stretch. A stretch may run over midnight.
    /// "Quiet now", until this moment (seconds since 1970; 0: off). Set from the menu, the
    /// settings, or a `nikoisland://quiet` link (what a Shortcuts automation for a Focus calls).
    public var quietNowUntil: Double {
        get { raw["quietNowUntil"]?.doubleValue ?? 0 }
        set { raw["quietNowUntil"] = .number(String(newValue)) }
    }

    /// Quiet now: no sounds, nothing to a phone, and the island does not open by itself.
    public func isQuietNow(at date: Date) -> Bool { quietNowUntil > date.timeIntervalSince1970 }

    /// The island does not open by itself for a session whose own window is in front: you are looking at it already.
    public var notOverAgentWindow: Bool {
        get { bool("notOverAgentWindow", default: true) }
        set { raw["notOverAgentWindow"] = .bool(newValue) }
    }

    /// Sessions in these folders (and below) are not listed, make no sound and send nothing.
    public var silencedFolders: [String] {
        get { (raw["silencedFolders"]?.arrayValue ?? []).compactMap(\.stringValue) }
        set { raw["silencedFolders"] = .array(newValue.map(JSONValue.string)) }
    }

    /// Nor are sessions whose first prompt contains one of these (case does not matter).
    public var silencedPrompts: [String] {
        get { (raw["silencedPrompts"]?.arrayValue ?? []).compactMap(\.stringValue) }
        set { raw["silencedPrompts"] = .array(newValue.map(JSONValue.string)) }
    }

    /// Links the user wrote for going to a session (Settings → Sessions), first match wins.
    public var jumpRules: [JumpRule] {
        get {
            (raw["jumpRules"]?.arrayValue ?? []).compactMap { item in
                guard let match = item["match"]?.stringValue, let url = item["url"]?.stringValue else { return nil }
                return JumpRule(match: match, url: url)
            }
        }
        set {
            raw["jumpRules"] = .array(newValue.map { rule in
                var object = JSONObject()
                object["match"] = .string(rule.match)
                object["url"] = .string(rule.url)
                return .object(object)
            })
        }
    }

    /// Whether a session falls under the rules above.
    public func silences(cwd: String?, firstPrompt: String?) -> Bool {
        if let cwd {
            let path = (cwd as NSString).standardizingPath
            for folder in silencedFolders where !folder.isEmpty {
                let rule = (folder as NSString).standardizingPath
                if path == rule || path.hasPrefix(rule.hasSuffix("/") ? rule : rule + "/") { return true }
            }
        }
        if let prompt = firstPrompt?.lowercased(), !prompt.isEmpty {
            for rule in silencedPrompts {
                let words = rule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !words.isEmpty, prompt.contains(words) { return true }
            }
        }
        return false
    }

    /// Hooks of a connected agent that another tool took out are put back (and the user is told).
    public var restoreRemovedHooks: Bool {
        get { bool("restoreRemovedHooks", default: true) }
        set { raw["restoreRemovedHooks"] = .bool(newValue) }
    }

    /// The reminder about waiting requests also covers finished turns nobody has looked at.
    public var remindUnread: Bool {
        get { bool("remindUnread", default: false) }
        set { raw["remindUnread"] = .bool(newValue) }
    }

    /// Quiet sessions older than a few minutes take one line; hovering one opens it up.
    public var compactOlderRows: Bool {
        get { bool("compactOlderRows", default: true) }
        set { raw["compactOlderRows"] = .bool(newValue) }
    }

    /// The plan limits of the agent last used, along the top of the open island.
    /// Colour seeps out from under the closed island: amber while someone waits on you,
    /// the accent while agents work, and a light runs along its edge.
    public var islandGlow: Bool {
        get { bool("islandGlow", default: true) }
        set { raw["islandGlow"] = .bool(newValue) }
    }

    public var quotaGlance: Bool {
        get { bool("quotaGlance", default: true) }
        set { raw["quotaGlance"] = .bool(newValue) }
    }

    /// A plan window is said to be nearly used up from this share on.
    public static let limitWarningChoices = [70, 80, 90, 95]

    public var limitWarningPercent: Int {
        get {
            let stored = raw["limitWarningPercent"]?.intValue ?? 90
            return NikoSettings.limitWarningChoices.contains(stored) ? stored : 90
        }
        set { raw["limitWarningPercent"] = .int(newValue) }
    }

    public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        if isQuietNow(at: date) { return true }
        guard quietHoursEnabled, quietFrom != quietUntil else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return quietFrom < quietUntil ? (quietFrom..<quietUntil).contains(minute) : (minute >= quietFrom || minute < quietUntil)
    }

    // MARK: The list

    public enum SessionGrouping: String, Sendable, CaseIterable {
        case none, project, agent
    }

    /// How the open island's list is arranged once there are several sessions.
    public var sessionGrouping: SessionGrouping {
        get { raw["sessionGrouping"]?.stringValue.flatMap(SessionGrouping.init(rawValue:)) ?? .none }
        set { raw["sessionGrouping"] = .string(newValue.rawValue) }
    }

    /// Type a follow-up to a session from the island. It is sent into the
    /// terminal the agent runs in, as if typed there. Off unless switched on.
    public var replyFromIsland: Bool {
        get { bool("replyFromIsland", default: false) }
        set { raw["replyFromIsland"] = .bool(newValue) }
    }

    // MARK: A phone (opt-in)

    /// Send a short line to the user's own phone through a push service they
    /// set up themselves. Off unless switched on; the key lives in the Keychain.
    public var pushEnabled: Bool {
        get { bool("pushEnabled", default: false) }
        set { raw["pushEnabled"] = .bool(newValue) }
    }

    /// `bark` or `ntfy`.
    public var pushService: String {
        get { raw["pushService"]?.stringValue == "ntfy" ? "ntfy" : "bark" }
        set { raw["pushService"] = .string(newValue == "ntfy" ? "ntfy" : "bark") }
    }

    /// The server to send to; empty means the service's own public one.
    public var pushServer: String {
        get { raw["pushServer"]?.stringValue ?? "" }
        set { raw["pushServer"] = .string(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Only while nobody is at the screen: that is when a phone is the way to reach someone.
    public var pushOnlyWhenAway: Bool {
        get { bool("pushOnlyWhenAway", default: true) }
        set { raw["pushOnlyWhenAway"] = .bool(newValue) }
    }

    public var pushWhenFinished: Bool {
        get { bool("pushWhenFinished", default: true) }
        set { raw["pushWhenFinished"] = .bool(newValue) }
    }

    /// Say what it is about (the tool, the first line of a reply). Off: only who, where and what kind.
    public var pushDetails: Bool {
        get { bool("pushDetails", default: false) }
        set { raw["pushDetails"] = .bool(newValue) }
    }

    /// ⌃⌥J goes to whatever needs the user: the waiting request, else the session that stopped last. Off unless switched on.
    /// ⌃⌥S opens the quick switcher.
    public var switcherHotkey: Bool {
        get { bool("switcherHotkey", default: true) }
        set { raw["switcherHotkey"] = .bool(newValue) }
    }

    public var jumpHotkey: Bool {
        get { bool("jumpHotkey", default: false) }
        set { raw["jumpHotkey"] = .bool(newValue) }
    }

    /// Minutes a permission request or question waits on the island before it goes back to the
    /// agent's own prompt, answered by nobody. 0: it waits for as long as the agent does.
    public static let approvalWaitChoices = [1, 3, 5, 10, 30, 60, 0]

    public var approvalWaitMinutes: Int {
        get {
            let stored = raw["approvalWaitMinutes"]?.intValue ?? 10
            return NikoSettings.approvalWaitChoices.contains(stored) ? stored : 10
        }
        set { raw["approvalWaitMinutes"] = .int(newValue) }
    }

    /// Minutes a request may wait unanswered before the app speaks up again. 0: never.
    public static let reminderChoices = [0, 2, 5, 10]

    public var reminderMinutes: Int {
        get {
            let stored = raw["reminderMinutes"]?.intValue ?? 0
            return NikoSettings.reminderChoices.contains(stored) ? stored : 0
        }
        set { raw["reminderMinutes"] = .int(newValue) }
    }

    /// Keep the island at the top of the screen even when no agent is running.
    public var showIslandWhenIdle: Bool {
        get { bool("showIslandWhenIdle", default: true) }
        set { raw["showIslandWhenIdle"] = .bool(newValue) }
    }

    // MARK: Usage

    /// Ask Anthropic for the Claude plan's limits, with Claude Code's own login
    /// from the Keychain. Off unless the user switches it on (SPEC §5).
    public var claudeLimitsLookup: Bool {
        get { bool("claudeLimitsLookup", default: false) }
        set { raw["claudeLimitsLookup"] = .bool(newValue) }
    }

    /// Let Claude Code look up the plan's usage itself (`claude -p /usage`) and
    /// read what it keeps. No sign-in is read by this app. Off unless switched on.
    public var claudeAsksItself: Bool {
        get { bool("claudeAsksItself", default: false) }
        set { raw["claudeAsksItself"] = .bool(newValue) }
    }

    /// Whether the provider behind an agent's plan is being asked.
    public func asksProvider(_ agent: String) -> Bool {
        switch agent {
        case "claude": return claudeLimitsLookup
        case "zcode": return glmLimitsLookup
        case "codex": return codexLimitsLookup
        case "kimi": return kimiLimitsLookup
        case "minimax": return minimaxLimitsLookup
        case "gemini": return geminiLimitsLookup
        case "copilot": return copilotLimitsLookup
        case "cursor": return cursorLimitsLookup
        case "kiro": return kiroLimitsLookup
        default: return false
        }
    }

    /// Ask Kimi about the Kimi Code plan, with a key of that plan the user typed in.
    public var kimiLimitsLookup: Bool {
        get { bool("kimiLimitsLookup", default: false) }
        set { raw["kimiLimitsLookup"] = .bool(newValue) }
    }

    /// Ask MiniMax about its Coding Plan, with a key of that plan the user typed in.
    public var minimaxLimitsLookup: Bool {
        get { bool("minimaxLimitsLookup", default: false) }
        set { raw["minimaxLimitsLookup"] = .bool(newValue) }
    }

    /// "cn" (minimaxi.com) or "global" (minimax.io).
    public var minimaxRegion: String {
        get {
            let value = raw["minimaxRegion"]?.stringValue ?? "cn"
            return ["cn", "global"].contains(value) ? value : "cn"
        }
        set { raw["minimaxRegion"] = .string(newValue) }
    }

    /// Ask Kiro about this month's credits, with the sign-in Kiro keeps.
    public var kiroLimitsLookup: Bool {
        get { bool("kiroLimitsLookup", default: false) }
        set { raw["kiroLimitsLookup"] = .bool(newValue) }
    }

    /// Ask Cursor about the plan's included usage this cycle, with the sign-in Cursor's app keeps.
    public var cursorLimitsLookup: Bool {
        get { bool("cursorLimitsLookup", default: false) }
        set { raw["cursorLimitsLookup"] = .bool(newValue) }
    }

    /// Ask GitHub about Copilot's monthly allowances, with the sign-in the GitHub CLI keeps.
    public var copilotLimitsLookup: Bool {
        get { bool("copilotLimitsLookup", default: false) }
        set { raw["copilotLimitsLookup"] = .bool(newValue) }
    }

    /// Ask Google about Gemini CLI's daily quotas, with the sign-in Gemini CLI saved, while it is still good.
    public var geminiLimitsLookup: Bool {
        get { bool("geminiLimitsLookup", default: false) }
        set { raw["geminiLimitsLookup"] = .bool(newValue) }
    }

    /// Ask ChatGPT about the Codex plan with Codex's own sign-in. Codex already
    /// writes its limits into its session files; this adds a current answer
    /// while Codex is idle, and the resets an account has saved.
    public var codexLimitsLookup: Bool {
        get { bool("codexLimitsLookup", default: false) }
        set { raw["codexLimitsLookup"] = .bool(newValue) }
    }

    /// Ask BigModel / Z.ai for the GLM Coding Plan's limits, with a key the user
    /// typed in. Off unless the user switches it on.
    public var glmLimitsLookup: Bool {
        get { bool("glmLimitsLookup", default: false) }
        set { raw["glmLimitsLookup"] = .bool(newValue) }
    }

    /// "auto" (whatever ZCode is set to), "bigmodel" or "zai".
    public var glmRegion: String {
        get {
            let value = raw["glmRegion"]?.stringValue ?? "auto"
            return ["auto", "bigmodel", "zai"].contains(value) ? value : "auto"
        }
        set { raw["glmRegion"] = .string(newValue) }
    }

    // MARK: Appearance

    public enum IslandWidth: String, Sendable, CaseIterable {
        case compact, regular, wide

        public var points: Double {
            switch self {
            case .compact: return 560
            case .regular: return 640
            case .wide: return 720
            }
        }
    }

    /// Width of the open island.
    public var islandWidth: IslandWidth {
        get { raw["islandWidth"]?.stringValue.flatMap(IslandWidth.init(rawValue:)) ?? .regular }
        set { raw["islandWidth"] = .string(newValue.rawValue) }
    }

    /// Which display the island lives on: "auto" (the one with a camera
    /// housing, else the primary display) or a display's name.
    public var islandDisplay: String {
        get { raw["islandDisplay"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? "auto" }
        set { raw["islandDisplay"] = .string(newValue) }
    }

    public enum Accent: String, Sendable, CaseIterable {
        case mint, sky, violet, amber, coral
    }

    /// The colour of "working" and of the things you can press.
    public var accent: Accent {
        get { raw["accent"]?.stringValue.flatMap(Accent.init(rawValue:)) ?? .mint }
        set { raw["accent"] = .string(newValue.rawValue) }
    }

    /// The island's surface and type, beyond its colour.
    public enum IslandStyle: String, Sendable, CaseIterable {
        /// Black, like the camera housing it grows out of.
        case classic
        /// Frosted: what is behind the island shows through, blurred.
        case glass
        /// Square corners, monospaced type, a hard edge.
        case pixel
        /// Deep blue instead of black.
        case midnight
    }

    public var islandStyle: IslandStyle {
        get { raw["islandStyle"]?.stringValue.flatMap(IslandStyle.init(rawValue:)) ?? .classic }
        set { raw["islandStyle"] = .string(newValue.rawValue) }
    }

    public enum Density: String, Sendable, CaseIterable {
        case comfortable, compact
    }

    public var rowDensity: Density {
        get { raw["rowDensity"]?.stringValue.flatMap(Density.init(rawValue:)) ?? .comfortable }
        set { raw["rowDensity"] = .string(newValue.rawValue) }
    }

    public enum RowChip: String, Sendable, CaseIterable {
        case elapsed, agent, host, branch, model, context, cost

        /// The model's name is long and rarely changes, how full the context is matters only
        /// near the end (when it is shown anyway), and not everybody wants a price on every row:
        /// these only on request.
        public var shownByDefault: Bool { self != .model && self != .context && self != .cost }
    }

    /// Whether a kind of chip is shown on session rows.
    public func showsChip(_ chip: RowChip) -> Bool {
        raw["rowChips"]?[chip.rawValue]?.boolValue ?? chip.shownByDefault
    }

    public mutating func setChip(_ chip: RowChip, shown: Bool) {
        var object = raw["rowChips"]?.objectValue ?? JSONObject()
        object[chip.rawValue] = .bool(shown)
        raw["rowChips"] = .object(object)
    }

    /// Show the pixel creatures (off: a plain coloured dot per agent).
    public var showMascots: Bool {
        get { bool("showMascots", default: true) }
        set { raw["showMascots"] = .bool(newValue) }
    }

    /// The creature the user picked for an agent, by sprite name.
    public func mascot(for agent: String) -> String? {
        raw["mascots"]?[agent]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Every choice the user made, agent id → sprite name.
    public var mascotChoices: [String: String] {
        var out: [String: String] = [:]
        for member in raw["mascots"]?.objectValue?.members ?? [] {
            if let name = member.value.stringValue, !name.isEmpty { out[member.key] = name }
        }
        return out
    }

    public mutating func setMascot(_ sprite: String?, for agent: String) {
        var object = raw["mascots"]?.objectValue ?? JSONObject()
        object[agent] = sprite.map(JSONValue.string)
        raw["mascots"] = object.isEmpty ? nil : .object(object)
    }

    /// How many rows the open island shows before it scrolls.
    public static let visibleRowChoices = [4, 6, 8, 12]

    public var visibleRows: Int {
        get { min(20, max(2, raw["visibleRows"]?.intValue ?? 6)) }
        set { raw["visibleRows"] = .int(newValue) }
    }

    /// How large the type inside the island is drawn.
    public enum TextSize: String, Sendable, CaseIterable {
        case small, regular, large

        public var scale: Double {
            switch self {
            case .small: return 0.88
            case .regular: return 0.94
            case .large: return 1.04
            }
        }
    }

    public var textSize: TextSize {
        get { raw["textSize"]?.stringValue.flatMap(TextSize.init(rawValue:)) ?? .regular }
        set { raw["textSize"] = .string(newValue.rawValue) }
    }

    /// How quickly the island opens and closes.
    public enum Motion: String, Sendable, CaseIterable {
        case calm, standard, brisk

        /// Multiplies every duration.
        public var factor: Double {
            switch self {
            case .calm: return 1.3
            case .standard: return 1
            case .brisk: return 0.7
            }
        }
    }

    public var motion: Motion {
        get { raw["motion"]?.stringValue.flatMap(Motion.init(rawValue:)) ?? .standard }
        set { raw["motion"] = .string(newValue.rawValue) }
    }

    // MARK: Timing

    /// Milliseconds the pointer has to rest on the island before it opens.
    public static let hoverDelayChoices = [0, 160, 350, 600]

    public var hoverOpenDelayMS: Int {
        get { min(2000, max(0, raw["hoverOpenDelayMS"]?.intValue ?? 160)) }
        set { raw["hoverOpenDelayMS"] = .int(newValue) }
    }

    /// Milliseconds after the pointer leaves before a hover-opened island closes.
    /// Short enough to feel like it follows the pointer, long enough to forgive
    /// a pointer that slips off the edge for a moment.
    public static let closeDelayChoices = [0, 150, 400, 900]

    public var hoverCloseDelayMS: Int {
        get {
            // Values from before the choices changed land on the nearest one.
            let stored = min(5000, max(0, raw["hoverCloseDelayMS"]?.intValue ?? 150))
            return NikoSettings.closeDelayChoices.min { abs($0 - stored) < abs($1 - stored) } ?? 150
        }
        set { raw["hoverCloseDelayMS"] = .int(newValue) }
    }

    /// Seconds the "finished" notice stays on the closed island.
    public static let toastChoices = [3, 5, 8, 15]

    public var toastSeconds: Int {
        get { min(60, max(1, raw["toastSeconds"]?.intValue ?? 5)) }
        set { raw["toastSeconds"] = .int(newValue) }
    }

    // MARK: App

    /// "system", "en" or "zh-Hans".
    public var language: String {
        get {
            let value = raw["language"]?.stringValue ?? "system"
            return ["en", "zh-Hans"].contains(value) ? value : "system"
        }
        set { raw["language"] = .string(newValue) }
    }

    /// Control-Option-I opens and closes the island from anywhere.
    public var hotkeyEnabled: Bool {
        get { bool("hotkeyEnabled", default: true) }
        set { raw["hotkeyEnabled"] = .bool(newValue) }
    }

    /// Find sessions from the transcripts agents write, not only from hooks.
    public var discoverSessions: Bool {
        get { bool("discoverSessions", default: true) }
        set { raw["discoverSessions"] = .bool(newValue) }
    }

    /// Minutes a quiet session stays listed when it is known only from its transcript.
    public static let retentionChoices = [10, 30, 120, 480]

    public var sessionRetentionMinutes: Int {
        get { min(24 * 60, max(2, raw["sessionRetentionMinutes"]?.intValue ?? 30)) }
        set { raw["sessionRetentionMinutes"] = .int(newValue) }
    }

    public var sessionRetention: TimeInterval { TimeInterval(sessionRetentionMinutes) * 60 }

    /// What the island does in full-screen Spaces, where there is no menu bar.
    public var fullScreenPolicy: FullScreenPolicy {
        get { raw["fullScreenPolicy"]?.stringValue.flatMap(FullScreenPolicy.init(rawValue:)) ?? .followMenuBar }
        set { raw["fullScreenPolicy"] = .string(newValue.rawValue) }
    }

    /// Bring the island in over a full-screen app when an agent needs a decision.
    public var attentionBreaksFullScreen: Bool {
        get { bool("attentionBreaksFullScreen", default: true) }
        set { raw["attentionBreaksFullScreen"] = .bool(newValue) }
    }

    public var admissionPolicy: AdmissionPolicy {
        AdmissionPolicy(deniedBundleIDs: Set(deniedBundleIDs), requireDeveloperEvidence: requireDeveloperEvidence)
    }

    public static func load(paths: NikoPaths) -> NikoSettings {
        guard let data = try? Data(contentsOf: paths.settingsFile),
              let object = (try? JSONValue.parse(data))?.objectValue else { return NikoSettings() }
        return NikoSettings(raw: object)
    }

    @discardableResult
    public func save(paths: NikoPaths) -> Bool {
        guard (try? SecureDirectory.ensure(paths.root)) != nil else { return false }
        return AtomicFile.write(JSONValue.object(raw).serializedData(.pretty), to: paths.settingsFile.path, mode: 0o600)
    }
}
