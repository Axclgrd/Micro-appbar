import AppKit
import Foundation

/// L'autorisation « Enregistrement audio du système », sans laquelle un tap
/// ne livre que des zéros — tout en coupant le son d'origine.
///
/// C'est le piège que Nuit a rencontré à la mesure : un tap non autorisé ne
/// signale aucune erreur, il rend l'app muette. Nuit s'en protège après coup,
/// par un chien de garde. Un mélangeur ne peut pas se contenter de ça : ses
/// tranches tournent en permanence, et une app qui se tait trois secondes à
/// chaque lancement serait un défaut, pas un garde-fou. On demande donc
/// l'état **avant** de poser le moindre tap.
///
/// macOS n'expose pas cet état publiquement. `TCCAccessPreflight` et
/// `TCCAccessRequest` sont les fonctions qu'utilisent les outils d'Apple ;
/// on les charge à l'exécution, en lecture et en demande seulement. Si elles
/// venaient à manquer, l'état devient `.indisponible` : on pose alors les taps
/// comme Nuit, et le chien de garde reste le filet.
public enum Autorisation: Equatable, Sendable {
    case accordee
    case refusee
    /// Jamais demandée : la fenêtre du système s'ouvrira à la première demande.
    case inconnue
    case indisponible
}

enum AutorisationAudio {
    private static var service: CFString { "kTCCServiceAudioCapture" as CFString }

    /// Ouvert une fois, jamais refermé ni réécrit : la poignée ne bouge plus
    /// après l'initialisation, d'où le `nonisolated(unsafe)`.
    nonisolated(unsafe) private static let tcc: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?,
                                                @escaping @convention(block) (Bool) -> Void) -> Void

    static func etat() -> Autorisation {
        guard let tcc, let symbole = dlsym(tcc, "TCCAccessPreflight") else { return .indisponible }
        switch unsafeBitCast(symbole, to: Preflight.self)(service, nil) {
        case 0: return .accordee
        case 1: return .refusee
        default: return .inconnue
        }
    }

    /// Ouvre la fenêtre du système. `fin` est appelé sur le fil principal.
    static func demander(_ fin: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let tcc, let symbole = dlsym(tcc, "TCCAccessRequest") else {
            Task { @MainActor in fin(false) }
            return
        }
        unsafeBitCast(symbole, to: Request.self)(service, nil) { accorde in
            Task { @MainActor in fin(accorde) }
        }
    }

    /// Une fois refusée, macOS ne repose plus la question : seul le panneau
    /// des réglages permet de revenir en arrière.
    @MainActor
    static func ouvrirReglages() {
        let adresses = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for adresse in adresses {
            if let url = URL(string: adresse), NSWorkspace.shared.open(url) { return }
        }
    }
}
