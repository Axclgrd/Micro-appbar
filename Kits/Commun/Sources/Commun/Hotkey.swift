import AppKit
import Carbon.HIToolbox

/// Une combinaison enregistrable, avec son écriture lisible. Chaque outil
/// définit sa propre liste : Grab tourne autour du T, Fonte autour du F.
public struct Shortcut: Identifiable, Sendable, Hashable {
    public let id: String
    public let label: String
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(id: String, label: String, keyCode: UInt32, modifiers: UInt32) {
        self.id = id
        self.label = label
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// Un raccourci global, un par outil.
///
/// Carbon en 2026, et c'est délibéré : `RegisterEventHotKey` est la seule API
/// publique qui capte une combinaison quand l'app n'est pas au premier plan
/// sans rien demander à l'utilisateur. L'alternative, un moniteur global
/// `NSEvent`, exigerait l'autorisation d'accessibilité — c'est-à-dire de lui
/// confier la lecture de *toutes* ses frappes, pour une seule combinaison.
///
/// Chaque outil a sa signature, et le gestionnaire unique aiguille selon elle.
/// C'est indispensable dans Trousse, qui héberge Grab et Fonte dans le même
/// processus : un gestionnaire qui ne regarderait pas *quelle* combinaison a
/// été frappée déclencherait les deux outils à chaque fois.
@MainActor
public final class Hotkey {

    public var onFire: (() -> Void)?

    private let signature: OSType
    private var reference: EventHotKeyRef?

    private static var registry: [OSType: Hotkey] = [:]
    private static var installed = false

    /// `signature` : quatre lettres propres à l'outil, en OSType — « GRAB »,
    /// « FONT ».
    public init(signature: OSType) {
        self.signature = signature
        Self.registry[signature] = self
    }

    /// Rend `false` si la combinaison est déjà prise par une autre app — le
    /// cas se produit en silence, et sans ce retour l'app paraît cassée alors
    /// qu'elle n'a simplement jamais reçu la frappe.
    @discardableResult
    public func register(_ shortcut: Shortcut) -> Bool {
        Self.install()
        unregister()

        let identifier = EventHotKeyID(signature: signature, id: 1)
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

    private static func install() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // Rappel C : aucune capture possible, d'où le passage par le registre.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            let signature = identifier.signature
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Hotkey.registry[signature]?.onFire?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
