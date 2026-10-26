import AudioToolbox
import CoreAudio
import Foundation

/// Les deux sens d'un périphérique. Un casque-micro Bluetooth est les deux à
/// la fois : c'est le même objet CoreAudio, lu dans deux portées.
public enum Sens: Sendable {
    case sortie, entree

    var portee: AudioObjectPropertyScope {
        self == .sortie ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }
}

/// Un périphérique audio tel que le système le connaît : haut-parleurs,
/// casque, écran, AirPlay, interface USB, micro de l'iPhone, appareil virtuel…
public struct Peripherique: Identifiable, Equatable, Sendable {
    public let id: AudioObjectID
    public let uid: String
    public let nom: String
    public let transport: UInt32
    public let canauxSortie: Int
    public let canauxEntree: Int
    /// Ce que Réglages Système propose dans ses listes. Un appareil comme
    /// « Microsoft Teams Audio » existe mais ne peut pas être la sortie par
    /// défaut : on le cache là où le système le cache.
    public let sortiePossible: Bool
    public let entreePossible: Bool
    public let alertesPossible: Bool

    public var nature: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:     "Intégré"
        case kAudioDeviceTransportTypeUSB:         "USB"
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE: "Bluetooth"
        case kAudioDeviceTransportTypeHDMI:        "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay:     "AirPlay"
        case kAudioDeviceTransportTypeThunderbolt: "Thunderbolt"
        case kAudioDeviceTransportTypeVirtual:     "Virtuel"
        case kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate: "Agrégé"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: "Continuité"
        case kAudioDeviceTransportTypeFireWire:    "FireWire"
        case kAudioDeviceTransportTypePCI:         "PCI"
        default:                                   "Autre"
        }
    }

    public func symbole(_ sens: Sens) -> String {
        let n = nom.lowercased()
        // Le nom d'abord : un AirPods Pro est un « Bluetooth » comme un autre
        // pour CoreAudio, mais c'est son dessin qu'on reconnaît d'un coup d'œil.
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("homepod") { return "homepod" }
        if n.contains("iphone") { return "iphone" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return sens == .sortie ? "laptopcomputer" : "mic"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt:
            return sens == .sortie ? "hifispeaker" : "mic"
        case kAudioDeviceTransportTypeVirtual:
            return "waveform"
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            return "square.stack.3d.up"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless:
            return "iphone"
        default:
            return sens == .sortie ? "speaker.wave.2" : "mic"
        }
    }
}

/// Ce qui se règle sur un périphérique, dans un sens donné. `nil` veut dire
/// « ce périphérique ne le permet pas », pas « inconnu ».
public struct ReglagesPeripherique: Equatable, Sendable {
    public var volume: Float?
    public var muet: Bool?
    /// 0 à gauche, 0,5 au centre, 1 à droite.
    public var balance: Float?
    public var debit: Double
    public var debits: [Double]

    public static let aucun = ReglagesPeripherique(volume: nil, muet: nil, balance: nil, debit: 0, debits: [])
}

enum Peripheriques {

    /// Préfixe des appareils agrégés que posent les outils de la famille. Ils
    /// sont privés, donc invisibles pour les autres apps — mais pas pour la
    /// nôtre, qui doit les sauter pour ne pas s'afficher elle-même.
    static let prefixePrive = "local.microapp."

    static func tous() -> [Peripherique] {
        let ids: [AudioObjectID] = CA.tableau(CA.systeme, kAudioHardwarePropertyDevices)
        return ids.compactMap { id in
            guard let uid = CA.chaine(id, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix(prefixePrive)
            else { return nil }
            if let cache: UInt32 = CA.lire(id, kAudioDevicePropertyIsHidden), cache != 0 { return nil }
            let sortie = kAudioObjectPropertyScopeOutput, entree = kAudioObjectPropertyScopeInput
            return Peripherique(
                id: id,
                uid: uid,
                nom: CA.chaine(id, kAudioObjectPropertyName) ?? "Périphérique",
                transport: CA.lire(id, kAudioDevicePropertyTransportType) ?? 0,
                canauxSortie: CA.canaux(id, sortie),
                canauxEntree: CA.canaux(id, entree),
                sortiePossible: (CA.lire(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, sortie) as UInt32? ?? 0) != 0,
                entreePossible: (CA.lire(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, entree) as UInt32? ?? 0) != 0,
                alertesPossible: (CA.lire(id, kAudioDevicePropertyDeviceCanBeDefaultSystemDevice, sortie) as UInt32? ?? 0) != 0
            )
        }
    }

    // MARK: Défauts

    static func defaut(_ sens: Sens) -> AudioObjectID {
        CA.lire(CA.systeme, sens == .sortie
                ? kAudioHardwarePropertyDefaultOutputDevice
                : kAudioHardwarePropertyDefaultInputDevice) ?? CA.inconnu
    }

    static func alertes() -> AudioObjectID {
        CA.lire(CA.systeme, kAudioHardwarePropertyDefaultSystemOutputDevice) ?? CA.inconnu
    }

    @discardableResult
    static func choisir(_ id: AudioObjectID, _ sens: Sens) -> Bool {
        CA.ecrire(CA.systeme, sens == .sortie
                  ? kAudioHardwarePropertyDefaultOutputDevice
                  : kAudioHardwarePropertyDefaultInputDevice, id)
    }

    @discardableResult
    static func choisirAlertes(_ id: AudioObjectID) -> Bool {
        CA.ecrire(CA.systeme, kAudioHardwarePropertyDefaultSystemOutputDevice, id)
    }

    static func uid(_ id: AudioObjectID) -> String? {
        CA.chaine(id, kAudioDevicePropertyDeviceUID)
    }

    // MARK: Réglages

    static func reglages(_ id: AudioObjectID, _ sens: Sens) -> ReglagesPeripherique {
        guard id != CA.inconnu else { return .aucun }
        let p = sens.portee
        // Le volume « principal virtuel » : celui que règle la barre des menus.
        // Il couvre les périphériques qui n'ont qu'un volume par canal, en
        // répartissant la valeur sur chacun sans écraser leur balance.
        let volume: Float? = CA.reglable(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, p)
            ? CA.lire(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, p) : nil
        return ReglagesPeripherique(
            volume: volume,
            muet: muet(id, p),
            balance: sens == .sortie ? balance(id) : nil,
            debit: CA.lire(id, kAudioDevicePropertyNominalSampleRate) ?? 0,
            debits: debits(id)
        )
    }

    static func reglerVolume(_ id: AudioObjectID, _ sens: Sens, _ valeur: Float) {
        let v = min(1, max(0, valeur))
        CA.ecrire(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(v), sens.portee)
    }

    static func reglerMuet(_ id: AudioObjectID, _ sens: Sens, _ oui: Bool) {
        let v: UInt32 = oui ? 1 : 0
        for element in elementsMuet(id, sens.portee) {
            CA.ecrire(id, kAudioDevicePropertyMute, v, sens.portee, element)
        }
    }

    static func reglerBalance(_ id: AudioObjectID, _ valeur: Float) {
        let v = min(1, max(0, valeur))
        let sortie = kAudioObjectPropertyScopeOutput
        if CA.reglable(id, kAudioDevicePropertyStereoPan, sortie) {
            CA.ecrire(id, kAudioDevicePropertyStereoPan, Float32(v), sortie)
        } else {
            CA.ecrire(id, kAudioHardwareServiceDeviceProperty_VirtualMainBalance, Float32(v), sortie)
        }
    }

    @discardableResult
    static func reglerDebit(_ id: AudioObjectID, _ debit: Double) -> Bool {
        CA.ecrire(id, kAudioDevicePropertyNominalSampleRate, Float64(debit))
    }

    // MARK: Détails

    /// La coupure se règle tantôt sur l'élément principal, tantôt canal par
    /// canal (beaucoup d'interfaces USB). On rend ceux qui l'acceptent.
    private static func elementsMuet(_ id: AudioObjectID, _ portee: AudioObjectPropertyScope) -> [UInt32] {
        if CA.reglable(id, kAudioDevicePropertyMute, portee, kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return (1...2).map(UInt32.init).filter { CA.reglable(id, kAudioDevicePropertyMute, portee, $0) }
    }

    private static func muet(_ id: AudioObjectID, _ portee: AudioObjectPropertyScope) -> Bool? {
        guard let element = elementsMuet(id, portee).first,
              let v: UInt32 = CA.lire(id, kAudioDevicePropertyMute, portee, element)
        else { return nil }
        return v != 0
    }

    private static func balance(_ id: AudioObjectID) -> Float? {
        let sortie = kAudioObjectPropertyScopeOutput
        // Une balance n'a de sens qu'en stéréo.
        guard CA.canaux(id, sortie) >= 2 else { return nil }
        if CA.reglable(id, kAudioDevicePropertyStereoPan, sortie) {
            return CA.lire(id, kAudioDevicePropertyStereoPan, sortie)
        }
        if CA.reglable(id, kAudioHardwareServiceDeviceProperty_VirtualMainBalance, sortie) {
            return CA.lire(id, kAudioHardwareServiceDeviceProperty_VirtualMainBalance, sortie)
        }
        return nil
    }

    /// Les fréquences d'échantillonnage acceptées. Certains appareils donnent
    /// des valeurs exactes, d'autres une plage continue (8 à 192 kHz) : on la
    /// ramène aux fréquences qu'on rencontre vraiment.
    private static func debits(_ id: AudioObjectID) -> [Double] {
        guard CA.reglable(id, kAudioDevicePropertyNominalSampleRate) else { return [] }
        let plages: [AudioValueRange] = CA.tableau(id, kAudioDevicePropertyAvailableNominalSampleRates)
        let usuels: [Double] = [32000, 44100, 48000, 88200, 96000, 176400, 192000]
        var trouves = Set<Double>()
        for plage in plages {
            if plage.mMinimum == plage.mMaximum {
                trouves.insert(plage.mMinimum)
            } else {
                for f in usuels where f >= plage.mMinimum && f <= plage.mMaximum { trouves.insert(f) }
            }
        }
        return trouves.sorted()
    }
}
