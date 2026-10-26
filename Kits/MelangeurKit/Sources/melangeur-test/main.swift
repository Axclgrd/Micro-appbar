import Commun
import CoreAudio
import Foundation
@testable import MelangeurKit

// Banc d'essai en ligne de commande. Voir essai.sh : il l'enrobe dans un .app
// lancé par LaunchServices, pour que macOS attribue la demande d'autorisation
// audio au banc lui-même et non au terminal.
//
//   melangeur-test liste           les sources, regroupées comme dans le panneau
//   melangeur-test peripheriques   les périphériques et leurs réglages
//   melangeur-test autorisation    l'état de « Enregistrement audio du système »
//   melangeur-test demander        ouvre la demande d'autorisation
//   melangeur-test gain            joue un 440 Hz connu et mesure le gain réel
//                                  appliqué par une tranche, palier par palier

setvbuf(stdout, nil, _IOLBF, 0)
let commande = CommandLine.arguments.dropFirst().first ?? "liste"

@MainActor
func liste() {
    for s in Sources.lister() {
        let marques = (s.joue ? "▶︎" : " ") + (s.ecoute ? "🎙" : " ")
        print("\(marques) \(s.systeme ? "[sys]" : "     ") \(s.nom)  — \(s.id)  pid \(s.pid)  " +
              "\(s.processus.count) processus\(s.navigateur ? "  (navigateur)" : "")")
    }
}

func peripheriques() {
    let sortie = Peripheriques.defaut(.sortie), entree = Peripheriques.defaut(.entree)
    for p in Peripheriques.tous() {
        var roles: [String] = []
        if p.id == sortie { roles.append("SORTIE") }
        if p.id == entree { roles.append("ENTRÉE") }
        if p.id == Peripheriques.alertes() { roles.append("ALERTES") }
        print("\(p.nom) [\(p.nature)] \(p.symbole(p.canauxSortie > 0 ? .sortie : .entree)) " +
              "sortie=\(p.canauxSortie) entrée=\(p.canauxEntree) \(roles.joined(separator: ","))")
        for sens in [Sens.sortie, .entree] where (sens == .sortie ? p.canauxSortie : p.canauxEntree) > 0 {
            let r = Peripheriques.reglages(p.id, sens)
            print("    \(sens): volume=\(r.volume.map { String(format: "%.2f", $0) } ?? "—") " +
                  "muet=\(r.muet.map(String.init) ?? "—") balance=\(r.balance.map { String(format: "%.2f", $0) } ?? "—") " +
                  "débit=\(Int(r.debit)) débits=\(r.debits.map { Int($0) })")
        }
    }
}

/// Un WAV de 440 Hz stéréo 16 bits, à l'amplitude crête donnée.
func ecrireTon(_ url: URL, secondes: Double, amplitude: Double) throws {
    let debit = 48000, canaux = 2
    let n = Int(Double(debit) * secondes)
    var donnees = Data(capacity: n * canaux * 2 + 44)
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { donnees.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { donnees.append(contentsOf: $0) } }
    let taille = UInt32(n * canaux * 2)
    donnees.append(contentsOf: Array("RIFF".utf8)); u32(36 + taille)
    donnees.append(contentsOf: Array("WAVE".utf8))
    donnees.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(UInt16(canaux))
    u32(UInt32(debit)); u32(UInt32(debit * canaux * 2)); u16(UInt16(canaux * 2)); u16(16)
    donnees.append(contentsOf: Array("data".utf8)); u32(taille)
    for i in 0..<n {
        let v = Int16(amplitude * 32767 * sin(2 * Double.pi * 440 * Double(i) / Double(debit)))
        u16(UInt16(bitPattern: v)); u16(UInt16(bitPattern: v))
    }
    try donnees.write(to: url)
}

func objetProcessus(_ pid: pid_t) -> AudioObjectID? {
    var p = pid
    var a = CA.adresse(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var objet = CA.inconnu
    var taille = UInt32(MemoryLayout<AudioObjectID>.size)
    let s = AudioObjectGetPropertyData(CA.systeme, &a, UInt32(MemoryLayout<pid_t>.size), &p, &taille, &objet)
    return s == noErr && objet != CA.inconnu ? objet : nil
}

func db(_ x: Float) -> String { x > 1e-6 ? String(format: "%6.1f dB", 20 * log10f(x)) : "  —     " }

/// Le test qui compte : un son d'amplitude connue, une tranche, et la mesure
/// de ce qui entre et de ce qui sort de l'IOProc, palier par palier.
///
/// Le son est discret (−26 dBFS) : les gains forts partent vers un appareil
/// virtuel muet quand il en existe un, ce qui éprouve au passage le routage et
/// le chemin mono. Le limiteur, lui, se vérifie hors ligne.
func gain() throws {
    print("— limiteur, hors ligne —")
    for x: Float in [0.5, 0.8, 0.9, 1.2, 1.6, 4] {
        let y = Tranche.limiter(x), attendu = x <= 0.8 ? x : 0.8 + 0.2 * tanhf((x - 0.8) / 0.2)
        // Pleine échelle (1,0) atteinte pour une entrée énorme : c'est la
        // limite, pas un dépassement.
        print(String(format: "%@ limiter(%.2f) = %.4f  (attendu %.4f, jamais > 1 : %@)",
                     abs(y - attendu) < 1e-6 && y <= 1 ? "✓" : "✗", x, y, attendu, y <= 1 ? "oui" : "NON"))
    }

    let amplitude: Float = 0.05
    let ton = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("melangeur-440.wav")
    try ecrireTon(ton, secondes: 16, amplitude: Double(amplitude))
    let lecteur = Process()
    lecteur.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    lecteur.arguments = [ton.path]
    try lecteur.run()
    defer { lecteur.terminate() }

    var objet: AudioObjectID?
    for _ in 0..<40 {
        if let o = objetProcessus(lecteur.processIdentifier),
           (CA.lire(o, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0 {
            objet = o
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let objet else { print("ÉCHEC : afplay n'a pas ouvert de session audio"); return }
    guard let defaut = Peripheriques.uid(Peripheriques.defaut(.sortie)) else { print("ÉCHEC : pas de sortie"); return }
    let muet = Peripheriques.tous().first { $0.transport == kAudioDeviceTransportTypeVirtual && $0.canauxSortie > 0
                                             && $0.nom.contains("Teams") }
    print("— tranche réelle —  afplay pid \(lecteur.processIdentifier), autorisation \(AutorisationAudio.etat())")

    let t = try Tranche(cle: "essai", nom: "essai", processus: [objet], sortieUID: defaut, gain: 0.25)
    defer { t.arreter() }

    // (nom, gain, relâchée, sortie)
    var paliers: [(String, Float, Bool, String)] = [("25 %", 0.25, false, defaut), ("100 %", 1.0, false, defaut)]
    if let muet {
        paliers += [("150 % mono", 1.5, false, muet.uid), ("200 % mono", 2.0, false, muet.uid)]
    }
    paliers += [("relâchée", 1.0, true, defaut), ("reprise 50 %", 0.5, false, defaut)]

    for (nom, g, relache, uid) in paliers {
        if t.sortieUID != uid { try t.changerSortie(uid) }
        t.commande.gain = g
        t.relacher(relache)
        Thread.sleep(forTimeInterval: 0.5)        // laisser glisser le gain
        t.commande.remettreCretes()
        let avant = (t.commande.appels, t.commande.nonNuls)
        Thread.sleep(forTimeInterval: 1.0)
        let e = t.commande.creteEntree, s = t.commande.creteSortie
        let appels = t.commande.appels - avant.0, nonNuls = t.commande.nonNuls - avant.1
        let attendu = relache ? 0 : Tranche.limiter(amplitude * g)
        let ok = abs(s - attendu) < 0.004 && abs(e - amplitude) < 0.004 && appels > 0
        let sortie = Peripheriques.tous().first { $0.uid == uid }?.nom ?? uid
        // Ce que CoreAudio a retenu, relu et non supposé : c'est ce réglage
        // qui coupe ou rend le son d'origine.
        let lu = t.descriptionLue?.muteBehavior
        let voulu: CATapMuteBehavior = relache ? .unmuted : .mutedWhenTapped
        let coupure = lu == voulu ? "✓" : "✗"
        print(String(format: "%@ %-13@ entrée %.4f  sortie %.4f  attendu %.4f  · %3d appels · %@ · origine %@ %@",
                     ok ? "✓" : "✗", nom as NSString, e, s, attendu, appels, sortie as NSString,
                     (lu == .unmuted ? "rendue" : lu == .mutedWhenTapped ? "coupée" : "?") as NSString, coupure))
        _ = nonNuls
    }

    // Un second processus qui arrive en cours de route (un nouvel onglet) :
    // le tap doit l'englober sans être reconstruit.
    // 660 Hz, pas 440 : deux sinus de même fréquence et de phase quelconque
    // peuvent s'annuler, et la mesure ne voudrait plus rien dire.
    let ton2 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("melangeur-660.wav")
    try ecrireTonF(ton2, secondes: 6, amplitude: Double(amplitude), frequence: 660)
    let second = Process()
    second.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    second.arguments = [ton2.path]
    try second.run()
    defer { second.terminate() }
    var objet2: AudioObjectID?
    for _ in 0..<40 {
        if let o = objetProcessus(second.processIdentifier),
           (CA.lire(o, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0 { objet2 = o; break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    if let objet2 {
        t.commande.gain = 1
        for (nom, liste) in [("un processus", [objet]), ("deux processus", [objet, objet2]), ("retour à un", [objet])] {
            t.changerProcessus(liste)
            Thread.sleep(forTimeInterval: 0.5)
            t.commande.remettreCretes()
            Thread.sleep(forTimeInterval: 1.0)
            let e = t.commande.creteEntree
            let retenus = t.descriptionLue?.processes.count ?? -1
            // Deux sinus de même amplitude, 440 et 660 Hz : la somme monte
            // vers le double de l'amplitude.
            let ok = liste.count == 1 ? abs(e - amplitude) < 0.004 : e > amplitude * 1.6
            print(String(format: "%@ %-15@ entrée %.4f · tap sur %d processus", ok && retenus == liste.count ? "✓" : "✗",
                         nom as NSString, e, retenus))
        }
    }
    t.arreter()
    print("tranche arrêtée : le son d'origine est rendu (\(t.active ? "NON" : "oui"))")
}

/// Deux processus dans un même tap : posés d'emblée, ou ajoutés à chaud ?
/// Mesure les deux, pour choisir entre étendre le tap et le reconstruire.
func processus() throws {
    let amplitude: Float = 0.05
    func lancer(_ frequence: Int) throws -> (Process, AudioObjectID)? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("melangeur-\(frequence).wav")
        try ecrireTonF(url, secondes: 12, amplitude: Double(amplitude), frequence: Double(frequence))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        p.arguments = [url.path]
        try p.run()
        for _ in 0..<40 {
            if let o = objetProcessus(p.processIdentifier),
               (CA.lire(o, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0 { return (p, o) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        p.terminate()
        return nil
    }
    guard let (p1, o1) = try lancer(440), let (p2, o2) = try lancer(660) else { print("ÉCHEC : afplay"); return }
    defer { p1.terminate(); p2.terminate() }
    let surDefaut = CommandLine.arguments.contains("defaut")
    guard let uid = (surDefaut ? nil : Peripheriques.tous().first(where: { $0.nom.contains("Teams") })?.uid)
            ?? Peripheriques.uid(Peripheriques.defaut(.sortie)) else { return }
    let debit: Double = Peripheriques.tous().first { $0.uid == uid }.map { Peripheriques.reglages($0.id, .sortie).debit } ?? 0
    print("sortie \(uid) à \(Int(debit)) Hz (sons à 48000 Hz)")

    func mesurer(_ t: Tranche, _ nom: String) {
        Thread.sleep(forTimeInterval: 0.6)
        t.commande.remettreCretes()
        let n0 = t.commande.appels
        Thread.sleep(forTimeInterval: 1.0)
        print(String(format: "  %-34@ crête entrée %.4f · %d appels · tap sur %d", nom as NSString,
                     t.commande.creteEntree, t.commande.appels - n0, t.descriptionLue?.processes.count ?? -1))
    }

    let seul = try Tranche(cle: "a", nom: "a", processus: [o1], sortieUID: uid, gain: 1)
    mesurer(seul, "440 seul, tap neuf")
    seul.arreter()
    let deux = try Tranche(cle: "b", nom: "b", processus: [o1, o2], sortieUID: uid, gain: 1)
    mesurer(deux, "440 + 660, tap neuf")
    deux.arreter()
    let chaud = try Tranche(cle: "c", nom: "c", processus: [o1], sortieUID: uid, gain: 1)
    mesurer(chaud, "440, puis…")
    chaud.changerProcessus([o1, o2])
    mesurer(chaud, "… + 660 ajouté à chaud")
    try chaud.changerSortie(uid)
    mesurer(chaud, "… et agrégat reconstruit")
    chaud.arreter()
}

/// Reproduit la séquence du test complet (relâche, reprise, deux changements
/// de sortie) avant d'ajouter un second processus, et suit le niveau capté
/// par fenêtres de 250 ms.
func historique() throws {
    let amplitude: Float = 0.05
    func lancer(_ f: Int, _ secondes: Double) throws -> (Process, AudioObjectID)? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("melangeur-h\(f).wav")
        try ecrireTonF(url, secondes: secondes, amplitude: Double(amplitude), frequence: Double(f))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        p.arguments = [url.path]
        try p.run()
        for _ in 0..<40 {
            if let o = objetProcessus(p.processIdentifier),
               (CA.lire(o, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0 { return (p, o) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        p.terminate(); return nil
    }
    guard let defaut = Peripheriques.uid(Peripheriques.defaut(.sortie)),
          let teams = Peripheriques.tous().first(where: { $0.nom.contains("Teams") })?.uid else { return }
    let variante = CommandLine.arguments.last ?? "complet"
    print("variante : \(variante)")
    guard let (p1, o1) = try lancer(440, 14) else { return }
    defer { p1.terminate() }
    let t = try Tranche(cle: "h", nom: "h", processus: [o1], sortieUID: defaut, gain: 1)
    defer { t.arreter() }
    if variante == "complet" || variante == "sortie" {
        try t.changerSortie(teams); Thread.sleep(forTimeInterval: 0.5)
        try t.changerSortie(defaut); Thread.sleep(forTimeInterval: 0.5)
    }
    if variante == "complet" || variante == "relache" {
        t.relacher(true); Thread.sleep(forTimeInterval: 0.5)
        t.relacher(false); Thread.sleep(forTimeInterval: 0.5)
    }
    guard let (p2, o2) = try lancer(660, 8) else { return }
    defer { p2.terminate() }
    Thread.sleep(forTimeInterval: 0.5)
    t.changerProcessus([o1, o2])
    var ligne = "après ajout :"
    for _ in 0..<10 {
        t.commande.remettreCretes()
        Thread.sleep(forTimeInterval: 0.25)
        ligne += String(format: " %.3f", t.commande.creteEntree)
    }
    print(ligne)
}

func ecrireTonF(_ url: URL, secondes: Double, amplitude: Double, frequence: Double) throws {
    let debit = 48000, canaux = 2
    let n = Int(Double(debit) * secondes)
    var donnees = Data(capacity: n * canaux * 2 + 44)
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { donnees.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { donnees.append(contentsOf: $0) } }
    let taille = UInt32(n * canaux * 2)
    donnees.append(contentsOf: Array("RIFF".utf8)); u32(36 + taille)
    donnees.append(contentsOf: Array("WAVE".utf8))
    donnees.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(UInt16(canaux))
    u32(UInt32(debit)); u32(UInt32(debit * canaux * 2)); u16(UInt16(canaux * 2)); u16(16)
    donnees.append(contentsOf: Array("data".utf8)); u32(taille)
    for i in 0..<n {
        let v = Int16(amplitude * 32767 * sin(2 * Double.pi * frequence * Double(i) / Double(debit)))
        u16(UInt16(bitPattern: v)); u16(UInt16(bitPattern: v))
    }
    try donnees.write(to: url)
}

/// L'orchestration, de bout en bout, par le modèle lui-même : réglage,
/// mémorisation, libération quand l'app quitte, ré-application quand elle
/// revient, et chien de garde face à un son qu'aucun tap ne peut lire.
///
/// `afplay` est lancé par launchd (`launchctl submit`), pas par le banc : un
/// enfant du banc aurait le banc pour responsable, et le mélangeur s'exclut
/// lui-même de sa liste.
@MainActor
func modele() async throws {
    func lancer(_ etiquette: String, _ fichier: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["submit", "-l", etiquette, "--", "/usr/bin/afplay", fichier.path]
        try? p.run(); p.waitUntilExit()
    }
    func arreter(_ etiquette: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["remove", etiquette]
        try? p.run(); p.waitUntilExit()
    }
    func attendre(_ secondes: Double, jusqua condition: () -> Bool) async -> Bool {
        let fin = Date().addingTimeInterval(secondes)
        while Date() < fin {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }
    func verifier(_ ok: Bool, _ quoi: String) { print("\(ok ? "✓" : "✗") \(quoi)") }

    let dossier = URL(fileURLWithPath: NSTemporaryDirectory())
    let son = dossier.appendingPathComponent("melangeur-modele.wav")
    let silence = dossier.appendingPathComponent("melangeur-silence.wav")
    try ecrireTonF(son, secondes: 30, amplitude: 0.03, frequence: 440)
    try ecrireTonF(silence, secondes: 30, amplitude: 0, frequence: 440)
    let a = "local.microapp.essai.a", b = "local.microapp.essai.b"
    defer { arreter(a); arreter(b) }

    let m = Melangeur()
    m.panelVisible = true
    lancer(a, son)
    let apparu = await attendre(4) { m.sources.contains { $0.nom == "afplay" && $0.joue } }
    verifier(apparu, "afplay apparaît dans les sources, en train de jouer")
    guard apparu, let source = m.sources.first(where: { $0.nom == "afplay" }) else { return }
    print("  source : \(source.id), \(source.processus.count) processus, service : \(source.systeme)")

    m.reglerVolume(0.25, de: source, fini: true)
    verifier(m.etats[source.id] == .active, "réglé à 25 % : tranche active")
    verifier(CoordinationAudio.repris == Set(source.processus), "processus déclarés à Nuit")
    let lu = Shared.defaults.data(forKey: "melangeur.reglages")
        .flatMap { try? JSONDecoder().decode([String: ReglageSource].self, from: $0) }
    verifier(lu?[source.id]?.volume == 0.25, "réglage mémorisé (25 %)")

    try? await Task.sleep(for: .seconds(4))
    verifier(m.etats[source.id] == .active, "4 s de son réel : le chien de garde ne relâche pas")

    arreter(a)
    let parti = await attendre(4) { !m.sources.contains { $0.id == source.id } && m.etats[source.id] == nil }
    verifier(parti, "l'app quitte : tranche libérée")
    verifier(CoordinationAudio.repris.isEmpty, "plus rien de déclaré à Nuit")

    // Même exécutable, donc même clé : le réglage mémorisé doit revenir seul.
    // Et ce son-là n'est que du silence numérique : comme un contenu protégé,
    // le tap ne recevra que des zéros alors que l'app « joue ».
    lancer(b, silence)
    let revenu = await attendre(4) { m.etats[source.id] == .active }
    verifier(revenu, "l'app revient : réglage réappliqué sans rien toucher")
    let relache = await attendre(6) { m.etats[source.id] == .relachee }
    verifier(relache, "zéros seulement depuis le début : tranche relâchée, son d'origine rendu")

    arreter(b)
    _ = await attendre(4) { m.etats[source.id] == nil }

    // Une lecture qui commence par cinq secondes de silence (une vidéo avec
    // une intro muette) puis démarre vraiment : relâchée d'abord, elle doit
    // être reprise dès que le son arrive — sinon l'app jouerait à 100 %
    // malgré le réglage.
    let differe = dossier.appendingPathComponent("melangeur-differe.wav")
    try ecrireDiffere(differe, silence: 5, son: 10, amplitude: 0.03)
    lancer(b, differe)
    let relache2 = await attendre(5) { m.etats[source.id] == .relachee }
    verifier(relache2, "intro muette : relâchée")
    let reprise = await attendre(5) { m.etats[source.id] == .active }
    verifier(reprise, "le son arrive : tranche reprise, réglage de nouveau appliqué")

    m.remettre(source)
    verifier(m.etats[source.id] == nil && m.reglages[source.id] == nil, "remis à 100 % : plus de tranche, plus de réglage")
    m.panelVisible = false
}

/// Du silence numérique, puis un 440 Hz.
func ecrireDiffere(_ url: URL, silence: Double, son: Double, amplitude: Double) throws {
    let debit = 48000, canaux = 2
    let n0 = Int(Double(debit) * silence), n = n0 + Int(Double(debit) * son)
    var donnees = Data(capacity: n * canaux * 2 + 44)
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { donnees.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { donnees.append(contentsOf: $0) } }
    let taille = UInt32(n * canaux * 2)
    donnees.append(contentsOf: Array("RIFF".utf8)); u32(36 + taille)
    donnees.append(contentsOf: Array("WAVE".utf8))
    donnees.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(UInt16(canaux))
    u32(UInt32(debit)); u32(UInt32(debit * canaux * 2)); u16(UInt16(canaux * 2)); u16(16)
    donnees.append(contentsOf: Array("data".utf8)); u32(taille)
    for i in 0..<n {
        let v = i < n0 ? 0 : Int16(amplitude * 32767 * sin(2 * Double.pi * 440 * Double(i) / Double(debit)))
        u16(UInt16(bitPattern: v)); u16(UInt16(bitPattern: v))
    }
    try donnees.write(to: url)
}

let semaphore = DispatchSemaphore(value: 0)
Task { @MainActor in
    switch commande {
    case "liste": liste()
    case "peripheriques": peripheriques()
    case "autorisation": print(AutorisationAudio.etat())
    case "demander":
        AutorisationAudio.demander { accorde in
            print("réponse : \(accorde ? "accordée" : "refusée") — état \(AutorisationAudio.etat())")
            semaphore.signal()
        }
        return
    case "gain":
        do { try gain() } catch { print("ÉCHEC : \(error)") }
    case "processus":
        do { try processus() } catch { print("ÉCHEC : \(error)") }
    case "historique":
        do { try historique() } catch { print("ÉCHEC : \(error)") }
    case "modele":
        do { try await modele() } catch { print("ÉCHEC : \(error)") }
    default:
        print("commandes : liste, peripheriques, autorisation, demander, gain")
    }
    semaphore.signal()
}
// Une demande d'autorisation laissée sans réponse ne doit pas bloquer le banc.
let limite = Date().addingTimeInterval(90)
while semaphore.wait(timeout: .now()) == .timedOut {
    if Date() > limite { print("pas de réponse en 90 s — état \(AutorisationAudio.etat())"); break }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
