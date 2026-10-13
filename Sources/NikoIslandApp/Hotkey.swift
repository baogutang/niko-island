import AppKit
import Carbon.HIToolbox

/// One system-wide shortcut (Control-Option-I) that opens and closes the
/// island. Carbon hot keys need no permission and see nothing but their own key.
@MainActor
final class Hotkey {
    static let shared = Hotkey()
    nonisolated static let display = "⌃⌥I"

    var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var isRegistered: Bool { hotKey != nil }

    func setEnabled(_ enabled: Bool) {
        if enabled { register() } else { unregister() }
    }

    private func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                // Carbon delivers hot keys on the main thread.
                MainActor.assumeIsolated { Hotkey.shared.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4E_49_4B_4F), id: 1)       // 'NIKO'
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_I), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &reference)
        if status == noErr { hotKey = reference }
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
