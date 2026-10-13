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

    /// Keep the island at the top of the screen even when no agent is running.
    public var showIslandWhenIdle: Bool {
        get { bool("showIslandWhenIdle", default: true) }
        set { raw["showIslandWhenIdle"] = .bool(newValue) }
    }

    // MARK: Usage

    /// When the user last pressed Reset for a counter ("all" or an agent id).
    public var usageResets: [String: Date] {
        var out: [String: Date] = [:]
        for member in raw["usageResets"]?.objectValue?.members ?? [] {
            if let seconds = member.value.doubleValue, seconds > 0 { out[member.key] = Date(timeIntervalSince1970: seconds) }
        }
        return out
    }

    public mutating func setUsageReset(_ date: Date?, for counter: String) {
        var object = raw["usageResets"]?.objectValue ?? JSONObject()
        object[counter] = date.map { .number(String(Int($0.timeIntervalSince1970))) }
        raw["usageResets"] = object.isEmpty ? nil : .object(object)
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

    public enum Density: String, Sendable, CaseIterable {
        case comfortable, compact
    }

    public var rowDensity: Density {
        get { raw["rowDensity"]?.stringValue.flatMap(Density.init(rawValue:)) ?? .comfortable }
        set { raw["rowDensity"] = .string(newValue.rawValue) }
    }

    public enum RowChip: String, Sendable, CaseIterable {
        case elapsed, agent, host
    }

    /// Whether a kind of chip is shown on session rows.
    public func showsChip(_ chip: RowChip) -> Bool {
        raw["rowChips"]?[chip.rawValue]?.boolValue ?? true
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

    // MARK: Timing

    /// Milliseconds the pointer has to rest on the island before it opens.
    public static let hoverDelayChoices = [0, 160, 350, 600]

    public var hoverOpenDelayMS: Int {
        get { min(2000, max(0, raw["hoverOpenDelayMS"]?.intValue ?? 160)) }
        set { raw["hoverOpenDelayMS"] = .int(newValue) }
    }

    /// Milliseconds after the pointer leaves before a hover-opened island closes.
    public static let closeDelayChoices = [200, 450, 900, 1500]

    public var hoverCloseDelayMS: Int {
        get { min(5000, max(0, raw["hoverCloseDelayMS"]?.intValue ?? 450)) }
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
