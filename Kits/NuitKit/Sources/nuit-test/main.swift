import CoreAudio
import Darwin
import Dispatch
import Foundation
import NuitKit

// Banc d'essai en ligne de commande. Voir essai.sh pour l'enrober dans un .app
// (la demande d'autorisation audio exige un Info.plist).
//
//   nuit-test dsp                 traitement hors ligne d'un signal synthétique
//   nuit-test info                 sortie par défaut, quelqu'un joue-t-il ?
//   nuit-test run [s] [nuit|doux]  tap + traitement pendant s secondes (20 par défaut)
//   nuit-test crash [s]            comme run, puis kill -9 de soi-même : le son doit revenir

func db(_ x: Float) -> String { x > 1e-6 ? String(format: "%6.1f", 20 * log10f(x)) : "  -inf" }
let args = CommandLine.arguments
nonisolated(unsafe) var sources: [DispatchSourceProtocol] = []
let cmd = args.count > 1 ? args[1] : "info"

func reglage(_ nom: String) -> Dynamique.Reglage {
    var r = Dynamique.Reglage()
    if nom == "doux" { r.ratio = 2.5; r.genou = 10; r.relache = 250; r.plafond = -10; r.nivelleur = false }
    return r
}

switch cmd {
case "dsp":
    // Dialogue à −26 dBFS (crête), puis explosion à 0 dBFS, puis dialogue, puis générique fort à −8.
    let sr = 48000.0
    func ton(_ amp: Float, _ s: Double, _ f: Double = 220) -> [Float] {
        (0..<Int(s * sr)).map { amp * sinf(Float(2 * Double.pi * f * Double($0) / sr)) }
    }
    for (nom, r) in [("nuit", reglage("nuit")), ("doux", reglage("doux"))] {
        let d = Dynamique()
        d.configurer(sampleRate: sr, reglage: r)
        let segments: [(String, [Float])] = [
            ("dialogue -26", ton(0.05, 3)), ("explosion 0 dB", ton(1.0, 0.5, 60)),
            ("dialogue -26", ton(0.05, 3)), ("générique -8", ton(0.4, 6)), ("dialogue -26", ton(0.05, 4)),
        ]
        print("== préréglage \(nom)")
        for (n, sig) in segments {
            let out = d.traiterHorsLigne(sig)
            let crete = out.suffix(sig.count / 2).map(abs).max() ?? 0   // seconde moitié : régime établi
            let pic = out.map(abs).max() ?? 0
            let ci = sig.map(abs).max() ?? 0
            print(String(format: "  %-16@ entrée %@ dB  sortie (établie) %@ dB  pic absolu %@ dB", n as NSString, db(ci), db(crete), db(pic)))
        }
    }

case "info":
    print("PID \(getpid()), quelqu'un joue : \(PriseSysteme.quelquUnJoue())")

case "run", "crash":
    let duree = args.count > 2 ? Double(args[2]) ?? 20 : 20
    let prise = PriseSysteme()
    prise.reglageCourant = reglage(args.count > 3 ? args[3] : "nuit")
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler { prise.arreter(); print("\ntap détruit"); exit(0) }
        src.resume()
        withExtendedLifetime(src) {}
        sources.append(src)
    }
    do { try prise.demarrer() } catch { print("ÉCHEC : \(error)"); prise.arreter(); exit(1) }
    print("tap actif sur « \(prise.nomSortie) » : \(Int(prise.debit)) Hz, tampon \(prise.tailleTampon) images, latence matérielle ≈ \(String(format: "%.1f", prise.latenceMaterielMs)) ms, anticipation limiteur \(Dynamique.anticipation) ms")
    let d = prise.dynamique
    var t = 0.0
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
    timer.setEventHandler {
        t += 0.5
        print(String(format: "t=%4.1fs  appels=%6d  non-nuls=%9d  entrée %@ dB  sortie %@ dB  réduction %4.1f dB  décalage IOProc %.2f ms  joue=%@",
                     t, d.appels, d.echantillonsNonNuls, db(d.crêteEntree), db(d.crêteSortie), d.reductionMax, d.latenceMs,
                     PriseSysteme.quelquUnJoue() ? "oui" : "non"))
        d.remettreMesures()
        if cmd == "crash" && t >= duree { print("kill -9 de moi-même, sans nettoyage"); kill(getpid(), SIGKILL) }
        if t >= duree { prise.arreter(); print("tap détruit proprement"); exit(0) }
    }
    timer.resume()
    sources.append(timer)
    dispatchMain()

case "restes":
    // Taps et appareils « Nuit » encore vivants dans le système ?
    func liste(_ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var n: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &n) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(n) / 4)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &n, &ids)
        return ids
    }
    func nom(_ o: AudioObjectID) -> String {
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var c: Unmanaged<CFString>?
        var n = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(o, &a, 0, nil, &n, &c) == noErr, let c else { return "?" }
        return c.takeRetainedValue() as String
    }
    let taps = liste(kAudioHardwarePropertyTapList)
    let devs = liste(kAudioHardwarePropertyDevices).map(nom).filter { $0 == "Nuit" }
    print("taps vivants : \(taps.count) \(taps.map(nom)), appareils « Nuit » visibles : \(devs.count)")

default:
    print("commandes : dsp | info | run [s] [nuit|doux] | crash [s] | restes")
}
