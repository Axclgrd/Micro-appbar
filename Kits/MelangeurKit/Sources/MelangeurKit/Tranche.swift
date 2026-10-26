import AudioToolbox
import CoreAudio
import Foundation

public enum TrancheErreur: Error, CustomStringConvertible, Sendable {
    case coreAudio(String, OSStatus)
    case pasDeSortie

    public var description: String {
        switch self {
        case .coreAudio(let quoi, let s): "\(quoi) a échoué (OSStatus \(s))"
        case .pasDeSortie: "Aucune sortie audio disponible."
        }
    }
}

/// Ce que le fil principal et le fil temps réel se partagent.
///
/// Écrit sans verrou, comme `Dynamique` dans Nuit : le fil principal écrit un
/// `Float` ou un `Bool` alignés, le fil temps réel les lit. Sur arm64 comme sur
/// x86, une telle lecture n'est jamais déchirée ; au pire elle arrive un
/// tampon plus tard. Aucune allocation, aucun appel Objective-C côté temps réel.
final class Commande: @unchecked Sendable {
    /// Gain voulu, 0 à 2. Écrit par le fil principal.
    var gain: Float = 1
    /// Tranche relâchée : le son d'origine passe, on n'émet plus rien.
    var silence = false

    // Fil temps réel seulement.
    var gainApplique: Float = 1

    // Mesures, écrites par le fil temps réel, lues par le fil principal.
    private(set) var appels = 0
    private(set) var nonNuls = 0
    private(set) var creteEntree: Float = 0
    private(set) var creteSortie: Float = 0

    func noter(nonNuls n: Int, entree: Float, sortie: Float) {
        appels &+= 1
        nonNuls &+= n
        if entree > creteEntree { creteEntree = entree }
        if sortie > creteSortie { creteSortie = sortie }
    }

    func remettreCretes() { creteEntree = 0; creteSortie = 0 }
}

/// Une tranche de console : une application, son gain, sa sortie.
///
/// ```
///  app ─► [tap de ses processus, muteBehavior = .mutedWhenTapped]
///              │ (le son d'origine n'atteint plus la sortie)
///              ▼
///  appareil agrégé privé { tap + sortie choisie }
///              │ IOProc : gain, limiteur
///              ▼
///  sortie choisie (par défaut, ou une autre : routage par application)
/// ```
///
/// Mêmes garanties que la prise de Nuit, dont elle reprend la construction :
/// 1. Le tap est **privé** et rattaché à ce processus. Si l'app plante ou est
///    tuée, le HAL le détruit et le son d'origine revient de lui-même.
/// 2. `.mutedWhenTapped` coupe l'original *seulement pendant qu'on le lit*.
///    Si l'IOProc s'arrête pour une raison quelconque, le son revient.
/// 3. `arreter()` peut être appelé n'importe quand, plusieurs fois, et
///    commence par le tap : c'est lui qui coupe.
final class Tranche: @unchecked Sendable {
    let cle: String
    let commande = Commande()
    private(set) var processus: [AudioObjectID]
    private(set) var sortieUID: String
    private(set) var relachee = false

    private let description: CATapDescription
    private var tap = CA.inconnu
    private var agregat = CA.inconnu
    private var procID: AudioDeviceIOProcID?
    private var ecouteurDebit: AudioObjectPropertyListenerBlock?

    /// Appelé sur le fil principal quand la fréquence de la sortie change :
    /// l'agrégat doit être reconstruit.
    var surChangementDeDebit: (@Sendable () -> Void)?

    init(cle: String, nom: String, processus: [AudioObjectID], sortieUID: String, gain: Float) throws {
        self.cle = cle
        self.processus = processus
        self.sortieUID = sortieUID
        commande.gain = gain
        commande.gainApplique = gain

        let desc = CATapDescription(stereoMixdownOfProcesses: processus)
        desc.name = "Mélangeur · \(nom)"
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        description = desc

        let s = AudioHardwareCreateProcessTap(desc, &tap)
        guard s == noErr else {
            tap = CA.inconnu
            throw TrancheErreur.coreAudio("Création du tap", s)
        }
        do {
            try monter()
        } catch {
            arreter()
            throw error
        }
    }

    deinit { arreter() }

    var active: Bool { tap != CA.inconnu && procID != nil }

    // MARK: Agrégat

    /// L'appareil agrégé et son IOProc, autour du tap existant.
    private func monter() throws {
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Mélangeur",
            kAudioAggregateDeviceUIDKey: "\(Peripheriques.prefixePrive)melangeur.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: sortieUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: sortieUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true,
                 kAudioSubTapUIDKey: description.uuid.uuidString]
            ],
        ]
        var s = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agregat)
        guard s == noErr else {
            agregat = CA.inconnu
            throw TrancheErreur.coreAudio("Création de l'appareil agrégé", s)
        }

        let commande = self.commande
        s = AudioDeviceCreateIOProcIDWithBlock(&procID, agregat, nil) { _, entree, _, sortie, _ in
            Self.rendre(commande, entree, sortie)
        }
        guard s == noErr, procID != nil else {
            throw TrancheErreur.coreAudio("Création de l'IOProc", s)
        }
        s = AudioDeviceStart(agregat, procID)
        guard s == noErr else { throw TrancheErreur.coreAudio("Démarrage de l'appareil", s) }

        var a = CA.adresse(kAudioDevicePropertyNominalSampleRate)
        let bloc: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.surChangementDeDebit?() }
        ecouteurDebit = bloc
        AudioObjectAddPropertyListenerBlock(agregat, &a, .main, bloc)
    }

    /// Détruit l'agrégat et son IOProc, en gardant le tap.
    private func demonter() {
        guard agregat != CA.inconnu else { return }
        if let bloc = ecouteurDebit {
            var a = CA.adresse(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(agregat, &a, .main, bloc)
            ecouteurDebit = nil
        }
        if let p = procID {
            AudioDeviceStop(agregat, p)
            AudioDeviceDestroyIOProcID(agregat, p)
            procID = nil
        }
        AudioHardwareDestroyAggregateDevice(agregat)
        agregat = CA.inconnu
    }

    /// Détruit tout. C'est ce qui rend le son d'origine.
    func arreter() {
        // Le tap d'abord : une fois détruit, plus rien ne coupe l'app, et le
        // reste n'est que du ménage.
        if tap != CA.inconnu {
            AudioHardwareDestroyProcessTap(tap)
            tap = CA.inconnu
        }
        demonter()
    }

    // MARK: Changements à chaud

    /// Rejoue sur une autre sortie, ou reconstruit sur la même après un
    /// changement de fréquence.
    ///
    /// Le tap passe en `.muted` le temps de la reconstruction : sans agrégat
    /// pour le lire, `.mutedWhenTapped` laisserait l'original repartir à plein
    /// volume pendant quelques centaines de millisecondes — exactement ce
    /// qu'on ne veut pas dans un casque qu'on vient de brancher. En cas
    /// d'échec, tout est détruit : mieux vaut le son d'origine que le silence.
    func changerSortie(_ uid: String) throws {
        appliquer(muteBehavior: .muted)
        demonter()
        sortieUID = uid
        do {
            try monter()
            appliquer(muteBehavior: relachee ? .unmuted : .mutedWhenTapped)
        } catch {
            arreter()
            throw error
        }
    }

    /// L'application a ouvert ou fermé un processus audio (un nouvel onglet,
    /// un assistant qui démarre) : on étend le tap sans tout reconstruire.
    func changerProcessus(_ nouveaux: [AudioObjectID]) {
        guard nouveaux != processus else { return }
        processus = nouveaux
        description.processes = nouveaux
        ecrireDescription()
    }

    /// Relâcher : laisser passer le son d'origine et se taire. Sert quand le
    /// tap ne reçoit que des zéros alors que l'app joue — contenu protégé
    /// (DRM), qu'un tap ne peut pas lire. Couper l'original rendrait l'app
    /// muette ; on préfère qu'elle joue à son volume d'origine.
    func relacher(_ oui: Bool) {
        guard oui != relachee else { return }
        relachee = oui
        // L'ordre compte pour ne jamais rien entendre en double : en relâchant,
        // on se tait avant de rendre l'original ; en reprenant, on recoupe
        // l'original avant de réémettre.
        if oui {
            commande.silence = true
            appliquer(muteBehavior: .unmuted)
        } else {
            appliquer(muteBehavior: .mutedWhenTapped)
            commande.silence = false
        }
    }

    private func appliquer(muteBehavior: CATapMuteBehavior) {
        guard tap != CA.inconnu, description.muteBehavior != muteBehavior else { return }
        description.muteBehavior = muteBehavior
        ecrireDescription()
    }

    /// La propriété attend une référence d'objet, comme un `CFTypeRef` : on
    /// lui passe l'adresse d'un pointeur vers la description, pas la
    /// description elle-même.
    private func ecrireDescription() {
        guard tap != CA.inconnu else { return }
        var a = CA.adresse(kAudioTapPropertyDescription)
        var reference = Unmanaged.passUnretained(description).toOpaque()
        AudioObjectSetPropertyData(tap, &a, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &reference)
    }

    /// Ce que CoreAudio retient réellement du tap — pour vérifier qu'une
    /// écriture a pris, pas seulement qu'elle a été tentée.
    var descriptionLue: CATapDescription? {
        guard tap != CA.inconnu else { return nil }
        var a = CA.adresse(kAudioTapPropertyDescription)
        var valeur: Unmanaged<CATapDescription>?
        var taille = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        guard AudioObjectGetPropertyData(tap, &a, 0, nil, &taille, &valeur) == noErr else { return nil }
        return valeur?.takeRetainedValue()
    }

    // MARK: Fil temps réel

    /// Au-delà de ce seuil, le limiteur arrondit au lieu de laisser écrêter.
    /// Ne sert qu'au-dessus de 100 % : en dessous, rien n'atteint le seuil
    /// que le signal d'origine n'atteignait déjà.
    private static let genou: Float = 0.8

    @inline(__always)
    static func limiter(_ x: Float) -> Float {
        let a = abs(x)
        guard a > genou else { return x }
        let marge = 1 - genou
        let y = genou + marge * tanhf((a - genou) / marge)
        return x < 0 ? -y : y
    }

    private static func rendre(_ c: Commande,
                               _ entree: UnsafePointer<AudioBufferList>,
                               _ sortie: UnsafeMutablePointer<AudioBufferList>) {
        let ent = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: entree))
        let sor = UnsafeMutableAudioBufferListPointer(sortie)

        for b in sor { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
        guard ent.count > 0, sor.count > 0 else { return }

        // Entrée : le tap est le dernier flux de l'agrégat. Même lecture que
        // la prise de Nuit — entrelacé, deux flux mono, ou mono seul.
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
        } else if cE == 1 {
            let p = UnsafePointer(dd.assumingMemoryBound(to: Float.self))
            eL = p; eR = p
            nE = Int(dernier.mDataByteSize) / 4
        }

        // Sortie : les deux premiers canaux du premier flux, ou deux flux mono.
        var oL: UnsafeMutablePointer<Float>?, oR: UnsafeMutablePointer<Float>?, pasO = 1, nO = 0
        let premier = sor[0]
        guard let od = premier.mData else { return }
        let cO = Int(premier.mNumberChannels)
        var mono = false
        if cO >= 2 {
            let p = od.assumingMemoryBound(to: Float.self)
            oL = p; oR = p + 1; pasO = cO
            nO = Int(premier.mDataByteSize) / (4 * cO)
        } else if sor.count >= 2, let o1 = sor[1].mData {
            oL = od.assumingMemoryBound(to: Float.self)
            oR = o1.assumingMemoryBound(to: Float.self)
            nO = Int(premier.mDataByteSize) / 4
        } else if cO == 1 {
            oL = od.assumingMemoryBound(to: Float.self); oR = oL; mono = true
            nO = Int(premier.mDataByteSize) / 4
        }
        guard let eL, let eR, let oL, let oR else { return }

        let n = min(nE, nO)
        guard n > 0 else { return }

        // Le gain glisse d'un bout à l'autre du tampon : un saut net de 30 à
        // 80 % s'entendrait comme un clic.
        let cible = c.silence ? 0 : c.gain
        var g = c.gainApplique
        let pas = (cible - g) / Float(n)
        var nonNuls = 0
        var crE: Float = 0, crS: Float = 0

        for i in 0..<n {
            g += pas
            let l = eL[i * pasE], r = eR[i * pasE]
            if l != 0 || r != 0 { nonNuls += 1 }
            crE = max(crE, max(abs(l), abs(r)))
            if mono {
                let m = limiter((l + r) * 0.5 * g)
                oL[i * pasO] = m
                crS = max(crS, abs(m))
            } else {
                let sl = limiter(l * g), sr = limiter(r * g)
                oL[i * pasO] = sl
                oR[i * pasO] = sr
                crS = max(crS, max(abs(sl), abs(sr)))
            }
        }
        c.gainApplique = cible
        c.noter(nonNuls: nonNuls, entree: crE, sortie: crS)
    }
}
