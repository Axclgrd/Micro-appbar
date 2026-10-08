import AVFoundation
import Foundation
import Speech

// Transcription locale, avec le moteur de macOS 26 et rien d'autre.
//
// `SpeechAnalyzer` + `SpeechTranscriber` remplacent `SFSpeechRecognizer`, qui
// était taillé pour la dictée : une minute d'audio, une session à la fois, et
// un aller-retour serveur dès que le modèle local manquait. Le nouveau moteur
// lit un fichier entier, ne sort pas de la machine, et tourne environ
// quatre-vingts fois plus vite que le temps réel sur Apple Silicon.
//
// Le prix : il n'existe pas avant macOS 26. Bande cible macOS 14 et son app
// autonome aussi — tout est donc derrière `#available`, et le repli est une
// phrase qui explique, pas une erreur système.
//
// Le format d'entrée tombe juste : `SpeechAnalyzer.bestAvailableAudioFormat`
// répond « 16 kHz, mono, Int16 », c'est-à-dire exactement le WAV que Bande
// produisait déjà pour `.speech`. Il n'y a rien à convertir de plus.

enum TranscriptionError: LocalizedError {
    /// Le système est trop ancien : le moteur n'existe pas, point.
    case tooOld
    /// Le moteur existe mais la machine ne le porte pas.
    case unavailable
    case unsupportedLanguage(String)
    case download(String)
    /// Le fichier a été lu jusqu'au bout sans qu'un seul mot en sorte.
    case silent
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .tooOld:
            "La transcription demande macOS 26. Sur ce Mac, Bande sait extraire l'audio, pas le texte."
        case .unavailable:
            "Ce Mac ne prend pas en charge la transcription locale."
        case .unsupportedLanguage(let language):
            "Le moteur de transcription ne connaît pas le \(language). Change la langue du système pour une langue qu'il gère."
        case .download(let why):
            "Le modèle de langue n'a pas pu être téléchargé : \(why)"
        case .silent:
            "Aucune parole reconnue : la piste est muette, ou ce n'est pas de la voix."
        case .failure(let why):
            why
        }
    }
}

enum Transcriber {

    /// Sert à l'interface : dire *avant* le dépôt que le bouton ne mènera
    /// nulle part vaut mieux que de le dire après une extraction complète.
    static var isSupported: Bool {
        if #available(macOS 26, *) { Engine.isSupported } else { false }
    }

    /// Rend le texte parlé d'un fichier audio. Le fichier doit être lisible par
    /// AVFoundation ; le WAV 16 kHz mono de `.speech` est le cas prévu.
    static func run(
        _ audio: URL,
        duration: Double,
        note: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        guard #available(macOS 26, *) else { throw TranscriptionError.tooOld }
        return try await Engine.run(audio, duration: duration, note: note, progress: progress)
    }
}

// MARK: - Moteur

@available(macOS 26, *)
private enum Engine {

    static var isSupported: Bool { SpeechTranscriber.isAvailable }

    static func run(
        _ audio: URL,
        duration: Double,
        note: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        guard SpeechTranscriber.isAvailable else { throw TranscriptionError.unavailable }

        let locale = try await language(spokenIn: audio, note: note)
        note("transcription en \(name(of: locale))…")
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await install(transcriber, named: locale, note: note, progress: progress)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: audio)
        } catch {
            throw TranscriptionError.failure("Audio illisible : \(error.localizedDescription)")
        }

        let segments = try await listen(to: file, with: transcriber, duration: duration, progress: progress)
        let text = assemble(segments)
        guard !text.isEmpty else { throw TranscriptionError.silent }
        return text
    }

    // MARK: Langue

    /// Le moteur ne devine pas la langue parlée, et rien dans un fichier vidéo
    /// ne la déclare de façon fiable. Deux indices, dans cet ordre :
    ///
    ///   • les langues du système, telles que l'utilisateur les a rangées ;
    ///   • la voix elle-même, quand plusieurs de ces langues sont déjà
    ///     installées. Un Mac réglé en anglais par quelqu'un qui filme en
    ///     français est le cas courant, et suivre l'ordre du système y rend
    ///     une bouillie plutôt qu'un texte.
    static func language(
        spokenIn audio: URL,
        note: @escaping @Sendable (String) -> Void
    ) async throws -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        guard !supported.isEmpty else { throw TranscriptionError.unavailable }
        let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })

        let candidates = shortlist(among: supported, installed: installed)
        guard let first = candidates.first else {
            let wanted = Locale.preferredLanguages.first ?? Locale.current.identifier(.bcp47)
            throw TranscriptionError.unsupportedLanguage(name(of: Locale(identifier: wanted)))
        }

        // Peser une langue coûte une transcription. On ne compare donc que les
        // modèles déjà sur le disque, et seulement si la langue du système en
        // fait partie : sinon il n'y a rien d'équitable à comparer, et l'ordre
        // du système reste le meilleur pari.
        let ready = candidates.filter { installed.contains($0.identifier(.bcp47)) }
        guard ready.count > 1, installed.contains(first.identifier(.bcp47)) else { return first }

        note("reconnaissance de la langue…")
        return try await weigh(Array(ready.prefix(maximumCandidates)), on: audio) ?? first
    }

    /// Une langue par candidat, jamais deux régions de la même : distinguer le
    /// français de France du français de Belgique au son n'a pas de sens, et
    /// doublerait le coût de la mesure pour rien.
    static func shortlist(among supported: [Locale], installed: Set<String>) -> [Locale] {
        var result: [Locale] = []
        var seen: Set<String> = []

        func add(_ locale: Locale) {
            guard let code = locale.language.languageCode?.identifier, seen.insert(code).inserted else { return }
            result.append(locale)
        }

        for tag in Locale.preferredLanguages {
            if let match = pick(tag, among: supported, installed: installed) { add(match) }
        }
        // Une langue installée que le système ne réclame pas reste un candidat
        // plausible : on ne l'a pas téléchargée par hasard.
        for locale in supported where installed.contains(locale.identifier(.bcp47)) {
            add(locale)
        }
        return result
    }

    /// `SpeechTranscriber.supportedLocale(equivalentTo:)` n'est pas utilisé ici :
    /// mesuré sur macOS 27, il répond `fr-CA` pour « fr » et `en-NZ` pour « en ».
    /// Les régions de référence de CLDR — que Foundation porte déjà dans
    /// `maximalIdentifier` — donnent `fr-FR` et `en-US`, ce qu'on attend.
    static func pick(_ tag: String, among supported: [Locale], installed: Set<String>) -> Locale? {
        let asked = Locale.Language(identifier: tag)
        guard let code = asked.languageCode?.identifier else { return nil }

        let family = supported.filter { $0.language.languageCode?.identifier == code }
        guard !family.isEmpty else { return nil }

        if let exact = family.first(where: { $0.identifier(.bcp47) == Locale(identifier: tag).identifier(.bcp47) }) {
            return exact
        }
        if let region = asked.region?.identifier,
           let same = family.first(where: { $0.region?.identifier == region }) {
            return same
        }
        let home = Locale.Language(identifier: code).maximalIdentifier.split(separator: "-").last.map(String.init)
        if let home, let canonical = family.first(where: { $0.region?.identifier == home }) {
            return canonical
        }
        // À défaut de région, autant prendre un modèle déjà sur le disque
        // plutôt que d'imposer un téléchargement pour la même langue.
        return family.first { installed.contains($0.identifier(.bcp47)) } ?? family.first
    }

    /// Le nom de la langue en toutes lettres : « français », pas « fr-FR ».
    /// La table de noms est celle du français, pas celle du système : toute
    /// l'interface de Bande est en français, et « transcription en French »
    /// n'y aurait aucun sens.
    private static let french = Locale(identifier: "fr_FR")

    static func name(of locale: Locale) -> String {
        guard let code = locale.language.languageCode?.identifier,
              let name = french.localizedString(forLanguageCode: code)
        else { return locale.identifier(.bcp47) }
        return name
    }

    // MARK: Pesée des langues

    /// Au-delà de trois, la mesure coûte plus qu'elle ne rapporte : les langues
    /// suivantes sont, par construction, celles que l'utilisateur réclame le
    /// moins.
    static let maximumCandidates = 3

    /// Quatre-vingt-dix secondes suffisent à reconnaître une langue, et coûtent
    /// une seconde au lieu d'une minute sur un enregistrement d'une heure.
    static let sampleSeconds = 90.0

    /// Le bon modèle est sûr de lui, le mauvais bafouille. Mesuré sur une phrase
    /// française : 0,97 de confiance moyenne avec le modèle français, 0,35 avec
    /// l'anglais — qui rend « Le servere recoups y le portois mill ». Sur
    /// quatre-vingt-dix secondes d'un vrai appel, l'anglais ne rend rien du tout.
    /// L'écart ne laisse pas de place au doute.
    static func weigh(_ locales: [Locale], on audio: URL) async throws -> Locale? {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("bande-langue-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sample = (try? shorten(audio, into: workspace)) ?? audio

        var best: (locale: Locale, score: Double)?
        for locale in locales {
            try Task.checkCancellation()
            let score = await confidence(of: locale, on: sample)
            if score > (best?.score ?? 0) { best = (locale, score) }
        }
        return best?.locale
    }

    /// Recopie le début du fichier. `AVAudioFile` convertit tout seul du tampon
    /// flottant qu'il rend vers les entiers 16 bits du WAV d'origine.
    static func shorten(_ audio: URL, into workspace: URL) throws -> URL? {
        let source = try AVAudioFile(forReading: audio)
        let format = source.processingFormat
        let wanted = sampleSeconds * format.sampleRate
        // Un fichier déjà court se pèse tel quel : le tronquer ne gagne rien.
        guard Double(source.length) > wanted, wanted > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(wanted)) else { return nil }
        try source.read(into: buffer, frameCount: AVAudioFrameCount(wanted))

        let url = workspace.appendingPathComponent("extrait").appendingPathExtension("wav")
        let destination = try AVAudioFile(forWriting: url, settings: source.fileFormat.settings)
        try destination.write(from: buffer)
        return url
    }

    /// La confiance moyenne d'un modèle sur un extrait. Un modèle qui ne
    /// reconnaît rien vaut zéro — c'est déjà une réponse.
    static func confidence(of locale: Locale, on audio: URL) async -> Double {
        let preset = SpeechTranscriber.Preset(
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.transcriptionConfidence])
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)
        do {
            let file = try AVAudioFile(forReading: audio)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let collector = Task { () -> (Double, Int) in
                var total = 0.0
                var count = 0
                for try await result in transcriber.results where result.isFinal {
                    for run in result.text.runs {
                        guard let score = run.attributes[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self]
                        else { continue }
                        total += score
                        count += 1
                    }
                }
                return (total, count)
            }
            // Si le départ échoue, le collecteur attendrait des résultats qui
            // ne viendront jamais : il est coupé dans tous les cas.
            defer { collector.cancel() }
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let (total, count) = try await collector.value
            return count > 0 ? total / Double(count) : 0
        } catch {
            return 0
        }
    }

    // MARK: Modèle

    /// `AssetInventory.status` répond `.supported` pour un modèle pourtant
    /// installé — mesuré sur macOS 27 avec `fr-FR` présent. La seule réponse
    /// fiable est la requête d'installation elle-même : `nil` veut dire « rien
    /// à faire », et c'est sur elle qu'on se règle.
    static func install(
        _ transcriber: SpeechTranscriber,
        named locale: Locale,
        note: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let request: AssetInstallationRequest?
        do {
            request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        } catch {
            throw TranscriptionError.download(error.localizedDescription)
        }
        guard let request else { return }

        note("téléchargement du modèle \(name(of: locale))…")
        // Le téléchargement peut peser plusieurs centaines de mégaoctets. Sa
        // progression prend la barre pendant ce temps — qui repart donc en
        // arrière une fois le modèle en place — parce qu'une barre immobile
        // pendant trois minutes se lit comme une app plantée.
        let watcher = Watcher(request.progress, progress)
        defer { watcher.stop() }
        do {
            try await request.downloadAndInstall()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriptionError.download(error.localizedDescription)
        }
    }

    // MARK: Écoute

    /// Le moteur rend des segments au fil de l'eau. On ne garde que les
    /// définitifs : les autres sont des brouillons qu'il réécrit lui-même.
    static func listen(
        to file: AVAudioFile,
        with transcriber: SpeechTranscriber,
        duration: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [String] {
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collector = Task {
            var segments: [String] = []
            for try await result in transcriber.results where result.isFinal {
                segments.append(String(result.text.characters))
                // Chaque segment porte la plage de temps qu'il couvre : c'est
                // un avancement gratuit et exact, sans compter les octets.
                let end = result.range.end.seconds
                if duration > 0, end.isFinite {
                    progress(min(1, max(0, end / duration)))
                }
            }
            return segments
        }
        // Même précaution qu'à la pesée : aucun collecteur ne survit à la
        // sortie de cette fonction, quelle qu'en soit la porte.
        defer { collector.cancel() }

        do {
            return try await withTaskCancellationHandler {
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                return try await collector.value
            } onCancel: {
                collector.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.failure("Transcription interrompue : \(error.localizedDescription)")
        }
    }

    // MARK: Mise en forme

    /// Bout à bout, les segments font un mur de plusieurs milliers de
    /// caractères. Ils sont coupés là où le moteur a entendu une pause — mais
    /// seulement quand la phrase est finie, sinon on couperait en plein milieu
    /// d'une proposition.
    static func assemble(_ segments: [String]) -> String {
        var paragraphs: [String] = []
        var current = ""
        for segment in segments {
            current += segment
            guard let last = current.trimmingCharacters(in: .whitespacesAndNewlines).last,
                  ".!?…".contains(last) else { continue }
            append(current, to: &paragraphs)
            current = ""
        }
        append(current, to: &paragraphs)
        return paragraphs.joined(separator: "\n\n")
    }

    private static func append(_ text: String, to paragraphs: inout [String]) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        paragraphs.append(clean)
    }
}

// MARK: - Suivi d'un téléchargement

/// `Progress` ne parle qu'en KVO, et son observation doit être retirée avant sa
/// libération. Un petit objet dédié évite d'éparpiller ce cycle de vie.
private final class Watcher: NSObject, @unchecked Sendable {
    private let progress: Progress
    private let report: @Sendable (Double) -> Void
    private var token: NSKeyValueObservation?

    init(_ progress: Progress, _ report: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
        self.report = report
        super.init()
        token = progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
            report(progress.fractionCompleted)
        }
    }

    func stop() {
        token?.invalidate()
        token = nil
    }
}
