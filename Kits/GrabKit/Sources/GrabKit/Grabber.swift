import Commun
import AppKit
import CoreGraphics
import Observation
import Vision

/// La capture, la reconnaissance, et le presse-papier.
@MainActor
@Observable
final class Grabber {

    /// Partagée avec le délégué d'application, qui doit pouvoir rallumer
    /// l'icône quand on relance l'app.
    static let shared = Grabber()

    /// L'icône dans la barre de menus.
    ///
    /// Elle est facultative : le raccourci global fonctionne sans elle, et sur
    /// un écran à encoche chaque icône permanente est une place prise à une
    /// autre. Masquée, on la retrouve en relançant Grab.
    var showIcon = true {
        didSet { Shared.defaults.set(!showIcon, forKey: "hideIcon") }
    }

    private(set) var text: String?
    private(set) var status: String?
    private(set) var working = false
    private(set) var captures = 0

    /// Correction linguistique de Vision : elle rattrape les mots abîmés d'un
    /// texte de prose, mais réécrit volontiers un identifiant ou une commande.
    /// D'où le réglage, et son défaut à *désactivé* — ce qu'on capture le plus
    /// souvent à l'écran, c'est du code et des messages d'erreur.
    var languageCorrection = false {
        didSet { Shared.defaults.set(languageCorrection, forKey: "correction") }
    }

    var shortcut: Shortcut {
        didSet {
            Shared.defaults.set(shortcut.id, forKey: "shortcut")
            hotkeyWorks = Hotkey.shared.register(shortcut)
        }
    }

    /// Faux quand la combinaison est déjà prise par une autre app.
    private(set) var hotkeyWorks = true

    /// Une capture a-t-elle *prouvé* que l'autorisation manque ?
    ///
    /// C'est une preuve, pas une supposition — et la nuance est tout le sujet.
    /// `CGPreflightScreenCaptureAccess()` semblait fait pour ça, mais il ment
    /// deux fois : il garde son résultat en cache pour toute la durée du
    /// processus (une fois qu'il a répondu « non », il répond « non » jusqu'au
    /// relancement, même après qu'on a coché la case), et il répond « non »
    /// pour une app signée ad hoc dont le binaire a changé depuis l'octroi.
    /// L'utilisateur voyait alors « autorisation manquante » devant une case
    /// cochée, sans aucun moyen de s'en sortir.
    ///
    /// Ne reste vrai que si une vraie capture est revenue vide. Redevient faux
    /// à la première qui aboutit.
    private(set) var captureDenied = false

    /// Le nom de l'app qui héberge l'outil — « Grab » lancée seule, « Trousse »
    /// quand c'est elle qui l'affiche. C'est ce nom-là qu'il faut chercher dans
    /// les Réglages système, pas celui de l'outil.
    static var host: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "cette app"
    }

    /// Relit l'autorisation — mais dans un seul sens.
    ///
    /// Un préflight positif est une bonne nouvelle sûre : il efface le refus
    /// constaté. Un préflight négatif ne prouve rien (voir `captureDenied`),
    /// alors on l'ignore : c'est la capture qui tranchera.
    func refreshPermission() {
        if CGPreflightScreenCaptureAccess() { captureDenied = false }
    }

    /// Demande l'autorisation, sans ouvrir les Réglages.
    ///
    /// Ça sert à deux choses. La première fois, macOS affiche sa fenêtre. Mais
    /// surtout : **une app qui n'a jamais demandé n'apparaît pas du tout** dans
    /// Réglages système › Enregistrement de l'écran. Sans cet appel, on
    /// enverrait l'utilisateur cocher une ligne absente de la liste.
    func askQuietly() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        CGRequestScreenCaptureAccess()
        refreshPermission()
    }

    /// Demande l'autorisation et ouvre le bon panneau des réglages. macOS
    /// n'affiche sa fenêtre qu'une fois par app : passé ce refus, seul le
    /// panneau des réglages permet de revenir en arrière.
    /// Efface le refus constaté, sans rien vérifier.
    ///
    /// La porte de sortie : après avoir coché la case, l'utilisateur reprend la
    /// main d'un clic et la capture suivante retranchera. Rien ici ne peut
    /// rester bloqué sur un verdict périmé.
    func clearDenial() {
        captureDenied = false
        status = nil
    }

    func requestPermission() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    init() {
        showIcon = !Shared.defaults.bool(forKey: "hideIcon")
        languageCorrection = Shared.defaults.bool(forKey: "correction")
        shortcut = Shortcut.named(Shared.defaults.string(forKey: "shortcut"))
        hotkeyWorks = Hotkey.shared.register(shortcut)
        Hotkey.shared.onFire = { [weak self] in
            Task { await self?.capture() }
        }
    }

    func capture() async {
        guard !working else { return }

        // On tente toujours, sans demander la permission de demander. Aucun
        // pré-test n'est fiable ici, et un pré-test qui se trompe bloque un
        // outil qui marche. `Recognizer` sait reconnaître un vrai refus après
        // coup — c'est lui qui tranche.
        working = true
        defer { working = false }
        status = nil

        let correction = languageCorrection
        let result = await Task.detached(priority: .userInitiated) {
            Recognizer.run(correction: correction)
        }.value

        switch result {
        case .cancelled:
            status = "Capture annulée."
        case .empty:
            status = "Aucun texte reconnu dans la sélection."
        case .denied:
            captureDenied = true
            status = "La capture est revenue vide : macOS n'autorise pas \(Self.host) à lire l'écran."
        case .text(let value):
            captureDenied = false
            text = value
            captures += 1
            copy()
            let lines = value.split(separator: "\n").count
            status = "\(lines) ligne\(lines > 1 ? "s" : "") copiée\(lines > 1 ? "s" : "")."
        }
    }

    func copy() {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func forget() {
        text = nil
        status = nil
    }
}

/// Le travail hors du main actor : sélection à l'écran puis reconnaissance.
enum Recognizer {

    enum Outcome: Sendable {
        case text(String)
        case empty
        case cancelled
        case denied
    }

    static func run(correction: Bool) -> Outcome {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "grab-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }

        // On délègue la sélection à `screencapture` : c'est l'outil du système,
        // donc exactement la même croix, les mêmes touches (espace pour une
        // fenêtre, Échap pour annuler) et le même comportement multi-écran que
        // ⇧⌘4. Réécrire ça serait plus long, moins bon, et dépaysant.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-o", "-t", "png", file.path]
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .denied
        }
        process.waitUntilExit()

        // Échap pendant la sélection : le processus sort proprement sans
        // écrire de fichier. C'est la seule façon de distinguer l'annulation.
        guard FileManager.default.fileExists(atPath: file.path) else { return .cancelled }
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0 else { return .denied }

        // Un refus d'autorisation ne ressemble pas à un refus : `screencapture`
        // écrit un PNG valide, entièrement noir, et sort sans erreur. Vision n'y
        // trouve alors rien et on afficherait « aucun texte reconnu » — en
        // accusant l'OCR d'un problème de permission. On regarde donc l'image
        // avant de la lire.
        if isBlank(file) { return .denied }

        return read(file, correction: correction)
    }

    /// L'image est-elle uniformément noire ?
    ///
    /// C'est la signature d'une capture refusée. Une vraie sélection, même sur
    /// un fond sombre, porte toujours quelques nuances : du texte, une bordure,
    /// un dégradé. On échantillonne une grille plutôt que tous les pixels — il
    /// suffit d'une seule valeur non noire pour conclure.
    static func isBlank(_ file: URL) -> Bool {
        guard let image = NSImage(contentsOf: file),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return false }

        let stepX = max(1, bitmap.pixelsWide / 32)
        let stepY = max(1, bitmap.pixelsHigh / 32)
        for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.redComponent > 0.04 || color.greenComponent > 0.04 || color.blueComponent > 0.04 {
                    return false
                }
            }
        }
        return true
    }

    /// La reconnaissance seule, séparée de la capture pour rester vérifiable
    /// sur une image quelconque.
    static func read(_ file: URL, correction: Bool) -> Outcome {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Le français d'abord : c'est la langue des captures d'écran d'ici, et
        // l'ordre de cette liste pondère le choix de Vision.
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.usesLanguageCorrection = correction

        do {
            try VNImageRequestHandler(url: file).perform([request])
        } catch {
            return .empty
        }

        // On garde l'ordre rendu par Vision : il suit déjà le sens de lecture,
        // et un tri maison par ordonnée casserait les lignes d'un tableau.
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? .empty : .text(text)
    }
}
