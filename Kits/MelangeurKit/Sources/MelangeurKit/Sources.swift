import AppKit
import CoreAudio
import Darwin
import Foundation

/// Une source de son, vue comme l'utilisateur la voit : une application, pas
/// la poignée de processus qu'elle fait parler à CoreAudio.
public struct SourceAudio: Identifiable, Equatable, Sendable {
    /// Clé stable d'un lancement à l'autre : c'est elle qui retrouve le
    /// réglage enregistré. L'identifiant du bundle, ou le nom du binaire.
    public let id: String
    public let nom: String
    /// Le processus responsable : l'application elle-même, pas son assistant.
    public let pid: pid_t
    public let bundlePath: String?
    /// Tous les objets-processus CoreAudio de l'application. Un tap sur la
    /// liste entière règle l'application entière, onglets et assistants compris.
    public let processus: [AudioObjectID]
    public let joue: Bool
    /// Elle capte une entrée : micro, ou interface audio.
    public let ecoute: Bool
    /// Un service de macOS plutôt qu'une application qu'on a ouverte.
    public let systeme: Bool
    public let navigateur: Bool
}

@MainActor
enum Sources {

    /// Tout ce qui a ouvert une session CoreAudio, regroupé par application.
    ///
    /// Le regroupement repose sur le *processus responsable*. Un onglet Safari
    /// ne joue pas lui-même : c'est `com.apple.WebKit.GPU` qui parle à
    /// CoreAudio, et ce processus n'appartient à aucun bundle `.app`. Mais le
    /// noyau sait qui l'a lancé et pour qui il travaille — Safari, Mail, ou une
    /// feuille de partage —, et c'est ce lien que lit `responsable(de:)`.
    static func lister() -> [SourceAudio] {
        let moi = getpid()
        var groupes: [String: (nom: String, pid: pid_t, bundle: String?, processus: [AudioObjectID],
                              joue: Bool, ecoute: Bool, systeme: Bool, navigateur: Bool)] = [:]

        let objets: [AudioObjectID] = CA.tableau(CA.systeme, kAudioHardwarePropertyProcessObjectList)
        for objet in objets {
            guard let pid: pid_t = CA.lire(objet, kAudioProcessPropertyPID), pid > 0 else { continue }
            let responsable = responsable(de: pid)
            // Nous-mêmes : se reprendre, ce serait rejouer sa propre sortie à
            // l'infini.
            guard pid != moi, responsable != moi else { continue }

            let joue = (CA.lire(objet, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0
            let ecoute = (CA.lire(objet, kAudioProcessPropertyIsRunningInput) as UInt32? ?? 0) != 0
            let chemin = cheminExecutable(pid)
            let fiche = identite(pid: pid, responsable: responsable, objet: objet, chemin: chemin)

            if var g = groupes[fiche.cle] {
                g.processus.append(objet)
                g.joue = g.joue || joue
                g.ecoute = g.ecoute || ecoute
                groupes[fiche.cle] = g
            } else {
                groupes[fiche.cle] = (fiche.nom, fiche.pid, fiche.bundle, [objet], joue, ecoute,
                                      fiche.systeme, Self.navigateurs.contains(fiche.cle))
            }
        }

        return groupes.map { cle, g in
            SourceAudio(id: cle, nom: g.nom, pid: g.pid, bundlePath: g.bundle,
                        processus: g.processus.sorted(), joue: g.joue, ecoute: g.ecoute,
                        systeme: g.systeme, navigateur: g.navigateur)
        }
        .sorted { a, b in
            if a.joue != b.joue { return a.joue }
            return a.nom.localizedStandardCompare(b.nom) == .orderedAscending
        }
    }

    // MARK: Identité

    private struct Fiche {
        let cle: String
        let nom: String
        let pid: pid_t
        let bundle: String?
        let systeme: Bool
    }

    private static func identite(pid: pid_t, responsable: pid_t, objet: AudioObjectID, chemin: String) -> Fiche {
        // Le simulateur iOS fait parler une douzaine de démons (SpringBoard,
        // services audio) sous la tutelle de CoreSimulator. Pour qui règle le
        // son, c'est « le simulateur », une ligne.
        if chemin.contains("CoreSimulator") || chemin.contains(".simruntime") {
            let simulateur = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.iphonesimulator").first
            return Fiche(cle: "simulateur", nom: "Simulateur",
                         pid: simulateur?.processIdentifier ?? responsable,
                         bundle: simulateur?.bundleURL?.path, systeme: false)
        }

        // L'application responsable, puis le processus lui-même s'il en est une.
        for candidat in responsable != pid ? [responsable, pid] : [pid] {
            guard let app = NSRunningApplication(processIdentifier: candidat),
                  app.activationPolicy != .prohibited,
                  let bundle = app.bundleIdentifier,
                  let url = app.bundleURL,
                  // Un service XPC (le processus graphique de WebKit, par
                  // exemple) s'enregistre comme une app, mais n'en est pas une.
                  url.pathExtension == "app"
            else { continue }
            // Un assistant Electron s'enregistre parfois lui aussi, avec son
            // propre identifiant. S'il vit dans le bundle d'une autre app,
            // c'est à elle qu'il appartient.
            if let exterieur = bundleExterieur(url.path), exterieur != url.path { break }
            return fiche(cle: bundle,
                         nom: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                         pid: candidat, bundle: url.path)
        }

        // Ni l'un ni l'autre : un assistant ou une extension que macOS ne
        // rattache à personne (les « Helper » d'Electron, les `.appex`). Le
        // chemin, lui, ne ment pas : on remonte au bundle `.app` qui le contient.
        if let exterieur = bundleExterieur(chemin) {
            let id = Bundle(path: exterieur)?.bundleIdentifier
            let ouverte = id.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            let nom = ouverte?.localizedName ?? FileManager.default.displayName(atPath: exterieur)
            return fiche(cle: id ?? nom, nom: nom, pid: ouverte?.processIdentifier ?? responsable,
                         bundle: exterieur)
        }

        // Un service : on le nomme quand on sait ce qu'il fait, sinon on garde
        // le nom du binaire, plutôt que de l'escamoter.
        let binaire = (chemin as NSString).lastPathComponent
        let bundle = CA.chaine(objet, kAudioProcessPropertyBundleID) ?? ""
        let nom = Self.services[binaire] ?? Self.services[bundle] ?? (binaire.isEmpty ? bundle : binaire)
        return Fiche(cle: "systeme:\(nom)", nom: nom, pid: responsable, bundle: nil, systeme: true)
    }

    /// Une application rangée dans `/System/Library` (Centre de contrôle,
    /// Siri, le carillon de charge) est un service, pas une application qu'on
    /// a ouverte. `/System/Applications`, lui, contient Musique et Messages.
    ///
    /// Les services sont regroupés par nom : Siri parle par trois processus,
    /// on n'en montre qu'un.
    private static func fiche(cle: String, nom: String, pid: pid_t, bundle: String?) -> Fiche {
        // `contains` et non `hasPrefix` : WebKit et Safari vivent dans un
        // cryptex, `/System/Cryptexes/OS/System/Library/…`.
        let systeme = bundle?.contains("/System/Library/") ?? false
        let nomAffiche = systeme ? (Self.services[cle] ?? nom) : nom
        return Fiche(cle: systeme ? "systeme:\(nomAffiche)" : cle, nom: nomAffiche,
                     pid: pid, bundle: bundle, systeme: systeme)
    }

    /// Le bundle `.app` le plus extérieur d'un chemin, hors du système.
    private static func bundleExterieur(_ chemin: String) -> String? {
        var parties: [String] = []
        for partie in (chemin as NSString).pathComponents {
            parties.append(partie)
            if partie.hasSuffix(".app") {
                let trouve = NSString.path(withComponents: parties)
                return trouve.contains("/System/Library/") ? nil : trouve
            }
        }
        return nil
    }

    /// Ce que sont les services audio de macOS, pour qui ne lit pas les noms
    /// de démons. Même esprit que les notes de Ports et de Pouls : une table
    /// courte, écrite à la main.
    static let services: [String: String] = [
        "systemsoundserverd":       "Sons du système",
        "PowerChime":               "Carillon de charge",
        "corespeechd":              "Dictée et « Dis Siri »",
        "assistantd":               "Siri",
        "SiriNCService":            "Siri",
        "avconferenced":            "FaceTime",
        "callservicesd":            "Appels",
        "universalaccessd":         "Accessibilité",
        "heard":                    "Accessibilité auditive",
        "ControlCenter":            "Centre de contrôle",
        "mediaremoted":             "Contrôles multimédias",
        "audiomxd":                 "Moteur audio du système",
        "AirPlayXPCHelper":         "AirPlay",
        "audioaccessoryd":          "Accessoires audio",
        "ContinuityCaptureAgent":   "Caméra de continuité",
        "com.apple.audio.Core-Audio-Driver-Service.helper": "Pilotes audio",
        "com.apple.speech.speechsynthesisd": "Synthèse vocale",
        "systemstats":              "Mesures du système",
        "PerfPowerServices":        "Mesures du système",
        "com.apple.Siri":           "Siri",
        "com.apple.controlcenter":  "Centre de contrôle",
        "com.apple.PowerChime":     "Carillon de charge",
        // WebKit au service d'un démon (feuille de partage, analyse de
        // texte) : du contenu web affiché par le système lui-même.
        "com.apple.WebKit.GPU":     "Contenu web du système",
        "com.apple.WebKit.WebContent": "Contenu web du système",
    ]

    /// Les navigateurs : leurs onglets passent tous par un même processus
    /// audio, donc ne se règlent qu'ensemble. On le dit sur leur ligne.
    static let navigateurs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition", "company.thebrowser.Browser",
        "company.thebrowser.dia", "com.kagi.kagimacOS", "app.zen-browser.zen",
    ]

    // MARK: Lectures noyau

    /// `responsibility_get_pid_responsible_for_pid` : une fonction de libsystem
    /// sans en-tête public, mais présente depuis macOS 10.14 et utilisée par
    /// le Moniteur d'activité lui-même. Lecture seule. Absente, on retombe sur
    /// le processus lui-même — on perd le regroupement, pas la fonction.
    private static let fonctionResponsable: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbole = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                  "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbole, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func responsable(de pid: pid_t) -> pid_t {
        guard let f = fonctionResponsable else { return pid }
        let r = f(pid)
        return r > 0 ? r : pid
    }

    private static func cheminExecutable(_ pid: pid_t) -> String {
        var tampon = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &tampon, UInt32(tampon.count)) > 0 else { return "" }
        return String(decoding: tampon.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
