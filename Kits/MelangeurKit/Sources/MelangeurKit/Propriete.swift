import AudioToolbox
import CoreAudio
import Foundation

/// Lire et écrire une propriété CoreAudio sans répéter dix lignes de pointeurs.
///
/// Tout rend un optionnel plutôt que de lever : dans un mélangeur, une
/// propriété absente est un cas normal — un écran HDMI n'a pas de volume, un
/// micro n'a pas de balance — et non une erreur à remonter.
///
/// Les génériques sont limités aux types copiables bit à bit : on passe leur
/// adresse brute à CoreAudio, ce qui n'aurait aucun sens pour une référence
/// d'objet. Les chaînes, qui en sont, passent par `chaine`.
enum CA {
    static let systeme = AudioObjectID(kAudioObjectSystemObject)
    static let inconnu = AudioObjectID(kAudioObjectUnknown)

    static func adresse(_ selecteur: AudioObjectPropertySelector,
                        _ portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selecteur, mScope: portee, mElement: element)
    }

    static func existe(_ objet: AudioObjectID, _ selecteur: AudioObjectPropertySelector,
                       _ portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                       _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var a = adresse(selecteur, portee, element)
        return AudioObjectHasProperty(objet, &a)
    }

    static func reglable(_ objet: AudioObjectID, _ selecteur: AudioObjectPropertySelector,
                         _ portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var a = adresse(selecteur, portee, element)
        guard AudioObjectHasProperty(objet, &a) else { return false }
        var oui: DarwinBoolean = false
        return AudioObjectIsPropertySettable(objet, &a, &oui) == noErr && oui.boolValue
    }

    static func lire<T: BitwiseCopyable>(_ objet: AudioObjectID, _ selecteur: AudioObjectPropertySelector,
                        _ portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var a = adresse(selecteur, portee, element)
        var taille = UInt32(MemoryLayout<T>.size)
        let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(objet, &a, 0, nil, &taille, p) == noErr else { return nil }
        return p.move()
    }

    @discardableResult
    static func ecrire<T: BitwiseCopyable>(_ objet: AudioObjectID, _ selecteur: AudioObjectPropertySelector, _ valeur: T,
                          _ portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var a = adresse(selecteur, portee, element)
        var v = valeur
        return AudioObjectSetPropertyData(objet, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }

    static func chaine(_ objet: AudioObjectID, _ selecteur: AudioObjectPropertySelector,
                       _ portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var a = adresse(selecteur, portee)
        var valeur: Unmanaged<CFString>?
        var taille = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objet, &a, 0, nil, &taille, &valeur) == noErr else { return nil }
        return valeur?.takeRetainedValue() as String?
    }

    static func tableau<T: BitwiseCopyable>(_ objet: AudioObjectID, _ selecteur: AudioObjectPropertySelector,
                           _ portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [T] {
        var a = adresse(selecteur, portee)
        var taille: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objet, &a, 0, nil, &taille) == noErr, taille > 0 else { return [] }
        let n = Int(taille) / MemoryLayout<T>.size
        return [T](unsafeUninitializedCapacity: n) { tampon, compte in
            guard AudioObjectGetPropertyData(objet, &a, 0, nil, &taille, tampon.baseAddress!) == noErr else {
                compte = 0
                return
            }
            compte = Int(taille) / MemoryLayout<T>.size
        }
    }

    /// Nombre de canaux d'un périphérique dans un sens, d'après sa
    /// configuration de flux.
    static func canaux(_ objet: AudioObjectID, _ portee: AudioObjectPropertyScope) -> Int {
        var a = adresse(kAudioDevicePropertyStreamConfiguration, portee)
        var taille: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objet, &a, 0, nil, &taille) == noErr, taille > 0 else { return 0 }
        let brut = UnsafeMutableRawPointer.allocate(byteCount: Int(taille),
                                                    alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { brut.deallocate() }
        guard AudioObjectGetPropertyData(objet, &a, 0, nil, &taille, brut) == noErr else { return 0 }
        let liste = UnsafeMutableAudioBufferListPointer(brut.assumingMemoryBound(to: AudioBufferList.self))
        return liste.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
