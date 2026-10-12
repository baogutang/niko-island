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

    public func soundEnabled(for kind: EventKind) -> Bool {
        raw["sounds"]?[kind.rawValue]?.boolValue ?? false
    }

    public mutating func setSound(_ enabled: Bool, for kind: EventKind) {
        var object = raw["sounds"]?.objectValue ?? JSONObject()
        object[kind.rawValue] = .bool(enabled)
        raw["sounds"] = .object(object)
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
