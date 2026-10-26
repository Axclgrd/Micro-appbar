import AudioToolbox
import CoreAudio
import Foundation

public enum PriseErreur: Error, CustomStringConvertible, Sendable {
    case coreAudio(String, OSStatus)
    case exclusionImpossible
    case pasDeSortie
    case formatInattendu(String)

    public var description: String {
        switch self {
        case .coreAudio(let quoi, let s): return "\(quoi) a échoué (OSStatus \(s))"
        case .exclusionImpossible:
            return "Impossible d'exclure ce processus de la capture : démarrage refusé pour éviter une boucle de larsen."
        case .pasDeSortie: return "Aucune sortie audio par défaut."
        case .formatInattendu(let d): return "Format audio inattendu : \(d)"
        }
    }
}

/// Une prise de son globale, coupée à la source, retraitée puis rejouée.
///
/// ```
///  toutes les apps ─► [tap global stéréo, muteBehavior = .mutedWhenTapped]
///                            │ (le son d'origine n'atteint plus la sortie)
///                            ▼
///               appareil agrégé privé { tap + sortie par défaut }
///                            │ IOProc : Dynamique.traiter()
///                            ▼
///                       sortie par défaut
/// ```
///
/// Sécurité, dans l'ordre de ce qui compte :
/// 1. Le tap est **privé** et rattaché à ce processus : si le processus meurt
///    (plantage, kill -9), le HAL détruit le tap et le son d'origine revient.
/// 2. `arreter()` détruit tout, dans l'ordre inverse de la création, et peut
///    être appelé n'importe quand, plusieurs fois.
/// 3. Tout échec dans `demarrer()` appelle `arreter()` avant de relancer l'erreur.
/// 4. Le tap exclut notre propre processus, sinon notre sortie serait
///    recapturée à l'infini ; si l'exclusion est impossible, on ne démarre pas.
public final class PriseSysteme: @unchecked Sendable {
    public let dynamique: Dynamique

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agregat = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var demarre = false
    private var ecouteurSortie: AudioObjectPropertyListenerBlock?
    private var ecouteurDebit: AudioObjectPropertyListenerBlock?

    public private(set) var nomSortie = ""
    public private(set) var debit: Double = 0
    /// Latence statique annoncée par le matériel (sortie + marge de sécurité + tampon), ms.
    public private(set) var latenceMaterielMs: Double = 0
    public private(set) var tailleTampon: UInt32 = 0

    /// Appelé sur le fil principal quand la sortie par défaut ou son débit change.
    public var surChangementDePeripherique: (@Sendable () -> Void)?

    public init(dynamique: Dynamique = Dynamique()) { self.dynamique = dynamique }
    deinit { arreter() }

    public var estActive: Bool { demarre }

    // MARK: - Démarrage

    /// `exclus` : des processus que quelqu'un d'autre rejoue déjà — le
    /// mélangeur, qui les a repris à son propre volume. Les capter ici aussi
    /// les ferait entendre deux fois. Voir `CoordinationAudio`.
    public func demarrer(tampon: UInt32 = 128, exclus: [AudioObjectID] = []) throws {
        arreter()
        do { try monter(tampon: tampon, exclus: exclus) } catch {
            arreter()
            throw error
        }
    }

    private func monter(tampon: UInt32, exclus: [AudioObjectID]) throws {
        let systeme = AudioObjectID(kAudioObjectSystemObject)

        // Sortie par défaut.
        let sortie: AudioObjectID = try lire(systeme, kAudioHardwarePropertyDefaultOutputDevice)
        guard sortie != kAudioObjectUnknown else { throw PriseErreur.pasDeSortie }
        let uidSortie: CFString = try lire(sortie, kAudioDevicePropertyDeviceUID)
        nomSortie = (try? lire(sortie, kAudioObjectPropertyName) as CFString) as String? ?? "Sortie"

        // Notre propre objet-processus, à exclure.
        guard let moi = Self.objetProcessus(pid: getpid()) else { throw PriseErreur.exclusionImpossible }

        // Le tap. `.mutedWhenTapped` : le son d'origine est coupé tant que
        // notre IOProc tourne, et revient dès que le tap disparaît.
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [moi] + exclus.filter { $0 != moi })
        desc.name = "Nuit"
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        var s = AudioHardwareCreateProcessTap(desc, &tap)
        guard s == noErr else { tap = AudioObjectID(kAudioObjectUnknown); throw PriseErreur.coreAudio("Création du tap", s) }

        // L'agrégat privé : la sortie en maître d'horloge, le tap en entrée.
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Nuit",
            kAudioAggregateDeviceUIDKey: "local.microapp.nuit.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: uidSortie as String,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: uidSortie as String]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true,
                 kAudioSubTapUIDKey: desc.uuid.uuidString]
            ],
        ]
        s = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agregat)
        guard s == noErr else { agregat = AudioObjectID(kAudioObjectUnknown); throw PriseErreur.coreAudio("Création de l'appareil agrégé", s) }

        // Débit et tampon. Un petit tampon, c'est ce qui fait la latence.
        debit = (try? lire(agregat, kAudioDevicePropertyNominalSampleRate) as Float64) ?? 48000
        var voulu = tampon
        var adr = adresse(kAudioDevicePropertyBufferFrameSize)
        AudioObjectSetPropertyData(agregat, &adr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &voulu)
        tailleTampon = (try? lire(agregat, kAudioDevicePropertyBufferFrameSize) as UInt32) ?? 0
        let latence = (try? lire(agregat, kAudioDevicePropertyLatency, portee: kAudioObjectPropertyScopeOutput) as UInt32) ?? 0
        let marge = (try? lire(agregat, kAudioDevicePropertySafetyOffset, portee: kAudioObjectPropertyScopeOutput) as UInt32) ?? 0
        latenceMaterielMs = Double(latence + marge + tailleTampon) / debit * 1000

        dynamique.configurer(sampleRate: debit, reglage: reglageCourant)
        dynamique.remettreMesures()

        // L'IOProc.
        let dsp = dynamique
        let freqHote = Self.hotesParMs
        s = AudioDeviceCreateIOProcIDWithBlock(&procID, agregat, nil) {
            _, entree, tempsEntree, sortie, tempsSortie in
            Self.rendre(dsp, entree, tempsEntree, sortie, tempsSortie, freqHote)
        }
        guard s == noErr, procID != nil else { throw PriseErreur.coreAudio("Création de l'IOProc", s) }

        // Démarrer déclenche la demande d'autorisation (« Enregistrement audio du système »).
        s = AudioDeviceStart(agregat, procID)
        guard s == noErr else { throw PriseErreur.coreAudio("Démarrage de l'appareil", s) }
        demarre = true

        ecouter()
    }

    /// Dernier réglage donné par l'appelant ; réappliqué à chaque (re)démarrage.
    public var reglageCourant = Dynamique.Reglage() {
        didSet { dynamique.appliquer(reglageCourant) }
    }

    // MARK: - Arrêt

    /// Détruit tout. Sans risque à appeler plusieurs fois, depuis n'importe où.
    /// C'est ce qui rend le son d'origine : un tap détruit ne coupe plus rien.
    public func arreter() {
        let systeme = AudioObjectID(kAudioObjectSystemObject)
        if let b = ecouteurSortie {
            var a = adresse(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(systeme, &a, .main, b)
            ecouteurSortie = nil
        }
        if let b = ecouteurDebit, agregat != kAudioObjectUnknown {
            var a = adresse(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(agregat, &a, .main, b)
            ecouteurDebit = nil
        }
        // Le tap d'abord : c'est lui qui coupe le son d'origine. Une fois détruit,
        // le reste n'est que du ménage.
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = AudioObjectID(kAudioObjectUnknown)
        }
        if agregat != kAudioObjectUnknown {
            if let p = procID {
                AudioDeviceStop(agregat, p)
                AudioDeviceDestroyIOProcID(agregat, p)
                procID = nil
            }
            AudioHardwareDestroyAggregateDevice(agregat)
            agregat = AudioObjectID(kAudioObjectUnknown)
        }
        demarre = false
    }

    // MARK: - Surveillance

    private func ecouter() {
        let systeme = AudioObjectID(kAudioObjectSystemObject)
        var a = adresse(kAudioHardwarePropertyDefaultOutputDevice)
        let b1: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.surChangementDePeripherique?() }
        ecouteurSortie = b1
        AudioObjectAddPropertyListenerBlock(systeme, &a, .main, b1)

        var d = adresse(kAudioDevicePropertyNominalSampleRate)
        let b2: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.surChangementDePeripherique?() }
        ecouteurDebit = b2
        AudioObjectAddPropertyListenerBlock(agregat, &d, .main, b2)
    }

    /// Un processus (autre que nous) est-il en train de jouer du son ?
    /// Sert à distinguer « personne ne joue » de « le tap ne reçoit rien ».
    public static func quelquUnJoue() -> Bool {
        let moi = getpid()
        guard let liste: [AudioObjectID] = try? lireTableau(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) else { return false }
        for o in liste {
            if let pid: pid_t = try? lire(o, kAudioProcessPropertyPID), pid == moi { continue }
            if let run: UInt32 = try? lire(o, kAudioProcessPropertyIsRunningOutput), run != 0 { return true }
        }
        return false
    }

    // MARK: - Fil temps réel

    private static let hotesParMs: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return 1e6 * Double(tb.denom) / Double(tb.numer)   // ticks par ms
    }()

    private static func rendre(_ dsp: Dynamique,
                               _ entree: UnsafePointer<AudioBufferList>, _ tEntree: UnsafePointer<AudioTimeStamp>,
                               _ sortie: UnsafeMutablePointer<AudioBufferList>, _ tSortie: UnsafePointer<AudioTimeStamp>,
                               _ ticksParMs: Double) {
        let ent = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: entree))
        let sor = UnsafeMutableAudioBufferListPointer(sortie)

        // Sortie : on vide tout, puis on remplit les deux premiers canaux.
        for b in sor { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
        guard ent.count > 0, sor.count > 0 else { return }

        // Entrée : le tap est le dernier flux (les flux de la sortie, s'il y en a, passent avant).
        var eL: UnsafePointer<Float>?, eR: UnsafePointer<Float>?, pasE = 1, nE = 0
        let dernier = ent[ent.count - 1]
        guard let dd = dernier.mData else { return }
        let cE = Int(dernier.mNumberChannels)
        if cE >= 2 {
            let p = dd.assumingMemoryBound(to: Float.self)
            eL = UnsafePointer(p); eR = UnsafePointer(p + 1); pasE = cE
            nE = Int(dernier.mDataByteSize) / (4 * cE)
        } else if ent.count >= 2, let d0 = ent[ent.count - 2].mData {
            eL = UnsafePointer(d0.assumingMemoryBound(to: Float.self))
            eR = UnsafePointer(dd.assumingMemoryBound(to: Float.self))
            nE = Int(dernier.mDataByteSize) / 4
        } else if cE == 1 {                       // tap mono : on duplique
            let p = UnsafePointer(dd.assumingMemoryBound(to: Float.self))
            eL = p; eR = p
            nE = Int(dernier.mDataByteSize) / 4
        }

        var oL: UnsafeMutablePointer<Float>?, oR: UnsafeMutablePointer<Float>?, pasO = 1, nO = 0
        let premier = sor[0]
        guard let od = premier.mData else { return }
        let cO = Int(premier.mNumberChannels)
        if cO >= 2 {
            let p = od.assumingMemoryBound(to: Float.self)
            oL = p; oR = p + 1; pasO = cO
            nO = Int(premier.mDataByteSize) / (4 * cO)
        } else if sor.count >= 2, let o1 = sor[1].mData {
            oL = od.assumingMemoryBound(to: Float.self)
            oR = o1.assumingMemoryBound(to: Float.self)
            nO = Int(premier.mDataByteSize) / 4
        } else if cO == 1 {
            oL = od.assumingMemoryBound(to: Float.self); oR = oL
            nO = Int(premier.mDataByteSize) / 4
        }

        guard let eL, let eR, let oL, let oR else { return }
        let n = min(nE, nO)
        if n > 0 {
            dsp.traiter(n: n, entreeL: eL, entreeR: eR, pasEntree: pasE,
                        sortieL: oL, sortieR: oR, pasSortie: pasO)
        }
        // Décalage entre l'instant où le tap a produit ce bloc et celui où la sortie le jouera.
        let ecart = Double(Int64(bitPattern: tSortie.pointee.mHostTime) - Int64(bitPattern: tEntree.pointee.mHostTime))
        dsp.noterAppel(latenceMs: ecart / ticksParMs)
    }

    // MARK: - Aides CoreAudio

    static func objetProcessus(pid: pid_t) -> AudioObjectID? {
        var p = pid
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var out = AudioObjectID(kAudioObjectUnknown)
        var taille = UInt32(MemoryLayout<AudioObjectID>.size)
        let s = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a,
                                           UInt32(MemoryLayout<pid_t>.size), &p, &taille, &out)
        return s == noErr && out != kAudioObjectUnknown ? out : nil
    }
}

private func adresse(_ sel: AudioObjectPropertySelector,
                     portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: portee, mElement: kAudioObjectPropertyElementMain)
}

private func lire<T>(_ o: AudioObjectID, _ sel: AudioObjectPropertySelector,
                     portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
    var a = adresse(sel, portee: portee)
    var taille = UInt32(MemoryLayout<T>.size)
    let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { p.deallocate() }
    let s = AudioObjectGetPropertyData(o, &a, 0, nil, &taille, p)
    guard s == noErr else { throw PriseErreur.coreAudio("lecture de la propriété \(sel)", s) }
    return p.move()
}

private func lireTableau<T>(_ o: AudioObjectID, _ sel: AudioObjectPropertySelector) throws -> [T] {
    var a = adresse(sel)
    var taille: UInt32 = 0
    var s = AudioObjectGetPropertyDataSize(o, &a, 0, nil, &taille)
    guard s == noErr else { throw PriseErreur.coreAudio("taille de \(sel)", s) }
    let n = Int(taille) / MemoryLayout<T>.size
    var out = [T]()
    out.reserveCapacity(n)
    try withUnsafeTemporaryAllocation(of: T.self, capacity: max(n, 1)) { buf in
        s = AudioObjectGetPropertyData(o, &a, 0, nil, &taille, buf.baseAddress!)
        guard s == noErr else { throw PriseErreur.coreAudio("lecture de \(sel)", s) }
        out.append(contentsOf: buf.prefix(Int(taille) / MemoryLayout<T>.size))
    }
    return out
}
