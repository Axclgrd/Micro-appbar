import Commun
import Carbon.HIToolbox

/// Les combinaisons proposées pour Grab. Le mécanisme, partagé avec Fonte,
/// vit dans `Commun`.
extension Shortcut {
    static let all: [Shortcut] = [
        Shortcut(id: "cmd-opt-shift-t", label: "⌥⇧⌘T",
                 keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey | shiftKey)),
        Shortcut(id: "cmd-ctrl-opt-t", label: "⌃⌥⌘T",
                 keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | controlKey | optionKey)),
        Shortcut(id: "cmd-opt-shift-g", label: "⌥⇧⌘G",
                 keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | optionKey | shiftKey)),
        Shortcut(id: "cmd-ctrl-opt-g", label: "⌃⌥⌘G",
                 keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | controlKey | optionKey)),
    ]

    static func named(_ id: String?) -> Shortcut {
        all.first { $0.id == id } ?? all[0]
    }
}

@MainActor
extension Hotkey {
    /// Le raccourci de Grab ; « GRAB » en OSType.
    static let shared = Hotkey(signature: 0x47524142)
}
