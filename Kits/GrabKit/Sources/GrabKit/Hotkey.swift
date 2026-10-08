import Commun
import AppKit
import Carbon.HIToolbox

/// Une combinaison enregistrable, avec son écriture lisible.
struct Shortcut: Identifiable, Sendable, Hashable {
    let id: String
    let label: String
    let keyCode: UInt32
    let modifiers: UInt32

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

/// Le raccourci global.
///
/// Carbon en 2026, et c'est délibéré : `RegisterEventHotKey` est la seule API
/// publique qui capte une combinaison quand l'app n'est pas au premier plan
/// sans rien demander à l'utilisateur. L'alternative, un moniteur global
/// `NSEvent`, exigerait l'autorisation d'accessibilité — c'est-à-dire de lui
/// confier la lecture de *toutes* ses frappes, pour une seule combinaison.
@MainActor
final class Hotkey {

    static let shared = Hotkey()

    var onFire: (() -> Void)?

    private var reference: EventHotKeyRef?
    private var installed = false

    private init() {}

    /// Rend `false` si la combinaison est déjà prise par une autre app — le
    /// cas se produit en silence, et sans ce retour l'app paraît cassée alors
    /// qu'elle n'a simplement jamais reçu la frappe.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        install()
        unregister()

        // La signature identifie l'émetteur du raccourci ; « GRAB » en OSType.
        let identifier = EventHotKeyID(signature: 0x47524142, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, identifier,
            GetApplicationEventTarget(), 0, &reference
        )
        return status == noErr
    }

    private func unregister() {
        guard let reference else { return }
        UnregisterEventHotKey(reference)
        self.reference = nil
    }

    private func install() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // Rappel C : aucune capture possible, d'où le passage par le singleton.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Hotkey.shared.onFire?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
