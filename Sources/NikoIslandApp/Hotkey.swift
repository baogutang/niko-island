import AppKit
import Carbon.HIToolbox

/// The app's system-wide shortcuts. Carbon hot keys need no permission and
/// see nothing but their own key. ⌃⌥I opens and closes the island; ⌃⌥A and
/// ⌃⌥D decide the request the island is showing, and are only claimed while
/// there is one, so they stay free for other apps the rest of the time.
@MainActor
final class Hotkey {
    enum Key: UInt32, CaseIterable {
        case toggle = 1, allow, deny, jump

        var code: Int {
            switch self {
            case .toggle: return kVK_ANSI_I
            case .allow: return kVK_ANSI_A
            case .deny: return kVK_ANSI_D
            case .jump: return kVK_ANSI_J
            }
        }

        nonisolated var display: String {
            switch self {
            case .toggle: return "⌃⌥I"
            case .allow: return "⌃⌥A"
            case .deny: return "⌃⌥D"
            case .jump: return "⌃⌥J"
            }
        }
    }

    static let shared = Hotkey()
    nonisolated static let display = Key.toggle.display

    /// What the island's own shortcut does.
    var action: (() -> Void)? {
        get { actions[.toggle] }
        set { actions[.toggle] = newValue }
    }
    var actions: [Key: () -> Void] = [:]
    private var registered: [Key: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    var isRegistered: Bool { registered[.toggle] != nil }
    func isClaimed(_ key: Key) -> Bool { registered[key] != nil }

    func setEnabled(_ enabled: Bool) { set(.toggle, enabled: enabled) }

    func set(_ key: Key, enabled: Bool) {
        if enabled { register(key) } else { unregister(key) }
    }

    private func register(_ key: Key) {
        guard registered[key] == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, let key = Key(rawValue: id.id) else { return noErr }
                // Carbon delivers hot keys on the main thread.
                MainActor.assumeIsolated { Hotkey.shared.actions[key]?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4E_49_4B_4F), id: key.rawValue)       // 'NIKO'
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(key.code), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference { registered[key] = reference }
    }

    private func unregister(_ key: Key) {
        if let reference = registered[key] { UnregisterEventHotKey(reference) }
        registered[key] = nil
    }
}
