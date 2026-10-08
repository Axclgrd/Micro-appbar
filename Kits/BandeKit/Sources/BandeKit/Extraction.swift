import Commun
import AVFoundation
import Foundation

// Extraction de la piste audio d'une vidéo, avec AVFoundation seul.
//
// Deux chemins, un seul moteur (AVAssetReader → AVAssetWriter) :
//
//   • Copie — les échantillons compressés passent tels quels de la vidéo au
//     .m4a. Ni décodage ni réencodage : c'est un transvasement, quelques
//     secondes pour un film, et le son est bit pour bit celui d'origine.
//   • Conversion — quand la piste ne rentre pas dans un .m4a (AC-3, PCM…) ou
//     quand on vise le WAV de transcription, les échantillons sont décodés,
//     rééchantillonnés, puis réécrits.
//
// Ce que macOS ne sait pas lire, personne ici ne le lira : les conteneurs
// Matroska, AVI et WebM sont refusés proprement plutôt qu'à moitié traités.

// MARK: - Formats de sortie

enum Format: String, CaseIterable, Identifiable, Sendable {
    /// Ce qui est dit, en toutes lettres. Passe par `.speech`, puis par le
    /// moteur de reconnaissance vocale de macOS.
    ///
    /// En tête, et par défaut : c'est ce qu'on vient chercher neuf fois sur
    /// dix. L'audio reste à un clic pour les fois où c'est le son qu'on veut.
    /// L'ordre des cas est celui des boutons — les valeurs stockées ne
    /// dépendent pas de lui, un réglage déjà enregistré reste valide.
    case text
    /// La piste d'origine, recopiée sans perte quand c'est possible.
    case original
    /// Ce qu'attend un moteur de transcription : 16 kHz, mono, PCM 16 bits.
    /// Rarement utile en soi depuis que `.text` existe, mais c'est l'étape
    /// intermédiaire, et la sortir permet de la donner à un autre moteur.
    case speech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Audio d'origine"
        case .speech:   "WAV transcription"
        case .text:     "Texte"
        }
    }

    var detail: String {
        switch self {
        case .original: "La piste telle quelle, sans réencodage — fichier .m4a"
        case .speech:   "16 kHz mono, prêt pour la transcription — fichier .wav"
        case .text:     "Ce qui est dit, transcrit sur le Mac — fichier .txt"
        }
    }

    var fileExtension: String {
        switch self {
        case .original: "m4a"
        case .speech:   "wav"
        case .text:     "txt"
        }
    }

    /// Ce que l'écrivain d'AVFoundation produit. Le texte n'en est pas : c'est
    /// son étape audio, `.speech`, qui passe par là.
    var fileType: AVFileType {
        switch self {
        case .original:      .m4a
        case .speech, .text: .wav
        }
    }

    /// Le suffixe évite qu'un WAV de travail se confonde avec l'audio complet.
    /// Le `.txt` n'en a pas besoin : aucun autre format ne porte cette
    /// extension, le nom de la vidéo suffit.
    var suffix: String {
        switch self {
        case .original, .text: ""
        case .speech:          "-16k"
        }
    }
}

/// Comment la piste est réellement sortie — l'app le dit, parce que « copié »
/// et « réencodé » n'ont pas la même valeur.
enum Method: Sendable {
    case copy, reencode, convert, transcribe

    var label: String {
        switch self {
        case .copy:       "copie sans perte"
        case .reencode:   "réencodé en AAC"
        case .convert:    "converti 16 kHz mono"
        case .transcribe: "transcrit sur le Mac"
        }
    }
}

// MARK: - Ce qu'on sait du fichier avant d'agir

struct Probe: Sendable {
    let duration: Double
    let codec: String
    let channels: Int
    let sampleRate: Double
    /// La piste peut-elle entrer telle quelle dans un .m4a ?
    let copyable: Bool

    var summary: String {
        var parts = [codec, Self.channelWord(channels)]
        if sampleRate > 0 {
            parts.append("\(Int((sampleRate / 1000).rounded())) kHz")
        }
        return parts.joined(separator: " · ")
    }

    static func channelWord(_ n: Int) -> String {
        switch n {
        case 1: "mono"
        case 2: "stéréo"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(n) canaux"
        }
    }
}

struct Output: Sendable {
    let url: URL
    let method: Method
    let bytes: Int64
}

enum ExtractionError: LocalizedError {
    /// Un conteneur qu'AVFoundation ne sait pas ouvrir, quoi qu'il contienne.
    case foreign(String)
    /// Un format connu, mais un fichier qui ne s'ouvre pas.
    case unreadable
    case noAudio
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .foreign(let ext):
            "macOS ne sait pas lire les fichiers \(ext) — convertis-le en MP4 d'abord."
        case .unreadable:
            "Fichier illisible : il est abîmé, incomplet, ou ce n'est pas une vidéo."
        case .noAudio:
            "Cette vidéo n'a pas de piste audio."
        case .failure(let why):
            why
        }
    }
}

// MARK: - Moteur

enum Extractor {

    /// Les conteneurs qu'AVFoundation ne lit pas. Les nommer permet de le dire
    /// avant même d'ouvrir le fichier, plutôt que de rendre une erreur -11828.
    static let foreignContainers: Set<String> = ["mkv", "webm", "avi", "flv", "ogv", "wmv", "rmvb", "vob", "mpg", "mpeg", "ts"]

    // MARK: Lecture des métadonnées

    static func inspect(_ source: URL) async throws -> Probe {
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let track = try await audioTrack(of: asset, source: source)
        return try await describe(asset: asset, track: track)
    }

    private static func audioTrack(of asset: AVURLAsset, source: URL) async throws -> AVAssetTrack {
        let ext = source.pathExtension.lowercased()
        if foreignContainers.contains(ext) {
            throw ExtractionError.foreign(ext.uppercased())
        }
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw ExtractionError.unreadable
        }
        guard let track = tracks.first else { throw ExtractionError.noAudio }
        return track
    }

    private static func describe(asset: AVURLAsset, track: AVAssetTrack) async throws -> Probe {
        let duration = try await asset.load(.duration).seconds
        let formats = try await track.load(.formatDescriptions)
        guard let format = formats.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else {
            return Probe(duration: duration, codec: "inconnu", channels: 2, sampleRate: 0, copyable: false)
        }
        return Probe(
            duration: duration.isFinite ? duration : 0,
            codec: codecName(basic.mFormatID),
            channels: Int(basic.mChannelsPerFrame),
            sampleRate: basic.mSampleRate,
            copyable: copyableFormats.contains(basic.mFormatID)
        )
    }

    /// Ce qu'un conteneur MP4/M4A accepte sans réencodage.
    private static let copyableFormats: Set<AudioFormatID> = [
        kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
        kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD, kAudioFormatMPEG4AAC_Spatial,
        kAudioFormatAppleLossless,
    ]

    private static func codecName(_ id: AudioFormatID) -> String {
        switch id {
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_Spatial: "AAC"
        case kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_ELD: "AAC-HE"
        case kAudioFormatAppleLossless: "ALAC"
        case kAudioFormatLinearPCM: "PCM"
        case kAudioFormatMPEGLayer3: "MP3"
        case kAudioFormatAC3, kAudioFormatEnhancedAC3: "AC-3"
        case kAudioFormatOpus: "Opus"
        case kAudioFormatFLAC: "FLAC"
        case kAudioFormatAMR, kAudioFormatAMR_WB: "AMR"
        default: fourCharCode(id)
        }
    }

    private static func fourCharCode(_ id: AudioFormatID) -> String {
        let bytes = [UInt8(truncatingIfNeeded: id >> 24), UInt8(truncatingIfNeeded: id >> 16),
                     UInt8(truncatingIfNeeded: id >> 8), UInt8(truncatingIfNeeded: id)]
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "inconnu" : text
    }

    // MARK: Extraction

    static func extract(
        _ source: URL,
        to format: Format,
        in folder: URL?,
        note: @escaping @Sendable (String) -> Void = { _ in },
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Output {
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let track = try await audioTrack(of: asset, source: source)
        let probe = try await describe(asset: asset, track: track)

        if format == .text {
            return try await transcribe(source: source, asset: asset, track: track, probe: probe,
                                        in: folder, note: note, progress: progress)
        }

        let method: Method = switch format {
        case .speech: .convert
        case .original: probe.copyable ? .copy : .reencode
        case .text: .transcribe   // traité plus haut
        }

        let destination = try destination(for: source, format: format, in: folder)
        try await convert(asset: asset, track: track, probe: probe, method: method,
                          format: format, destination: destination, progress: progress)

        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Output(url: destination, method: method, bytes: Int64(size))
    }

    /// Le tag de canaux aide le convertisseur à replier une piste 5.1. Il
    /// arrive qu'il soit refusé selon la source : on réessaie sans, plutôt
    /// que d'échouer sur un détail de configuration.
    private static func convert(
        asset: AVURLAsset,
        track: AVAssetTrack,
        probe: Probe,
        method: Method,
        format: Format,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        do {
            try await run(asset: asset, track: track, probe: probe, method: method,
                          format: format, destination: destination, layout: true, progress: progress)
        } catch let error as ExtractionError {
            guard method != .copy else { throw error }
            try? FileManager.default.removeItem(at: destination)
            try await run(asset: asset, track: track, probe: probe, method: method,
                          format: format, destination: destination, layout: false, progress: progress)
        }
    }

    // MARK: Transcription

    /// La part de la barre d'avancement qui revient à l'extraction du WAV.
    /// Mesuré sur un appel de vingt et une minutes : 1,1 s pour le WAV, 17,4 s
    /// en tout. Le passe-plat ne coûte presque rien — c'est le moteur de
    /// reconnaissance qui travaille.
    private static let extractionShare = 0.08

    /// Le moteur de reconnaissance lit un fichier audio, pas une vidéo. Le WAV
    /// 16 kHz mono que Bande sait déjà produire est exactement son format
    /// d'entrée — il sert donc de passe-plat, dans un dossier temporaire qui
    /// disparaît avec lui : on a demandé un texte, pas un texte et un WAV.
    private static func transcribe(
        source: URL,
        asset: AVURLAsset,
        track: AVAssetTrack,
        probe: Probe,
        in folder: URL?,
        note: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Output {
        let destination = try destination(for: source, format: .text, in: folder)

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("bande-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        } catch {
            throw ExtractionError.failure("Dossier de travail impossible à créer : \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: workspace) }

        note("extraction de l'audio…")
        let scratch = workspace.appendingPathComponent("audio").appendingPathExtension("wav")
        try await convert(asset: asset, track: track, probe: probe, method: .convert,
                          format: .speech, destination: scratch) { progress($0 * extractionShare) }

        note("transcription…")
        let text = try await Transcriber.run(scratch, duration: probe.duration, note: note) { value in
            progress(extractionShare + value * (1 - extractionShare))
        }

        // Rien de partiel ne survit : le .txt n'est créé qu'une fois le texte
        // complet en main, et l'écriture est atomique.
        try Task.checkCancellation()
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw ExtractionError.failure("Le texte n'a pas pu être écrit : \(error.localizedDescription)")
        }

        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Output(url: destination, method: .transcribe, bytes: Int64(size))
    }

    private static func run(
        asset: AVURLAsset,
        track: AVAssetTrack,
        probe: Probe,
        method: Method,
        format: Format,
        destination: URL,
        layout: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ExtractionError.failure("Lecture impossible : \(error.localizedDescription)")
        }
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: destination, fileType: format.fileType)
        } catch {
            throw ExtractionError.failure("Écriture impossible dans \(destination.deletingLastPathComponent().lastPathComponent) : \(error.localizedDescription)")
        }

        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput

        if method == .copy {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let hint = try? await track.load(.formatDescriptions).first
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
        } else {
            let channels = method == .convert ? 1 : min(2, max(1, probe.channels))
            let rate = method == .convert ? 16_000 : encodableRate(probe.sampleRate)
            output = AVAssetReaderAudioMixOutput(
                audioTracks: [track],
                audioSettings: pcmSettings(rate: rate, channels: channels, layout: layout))
            input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: method == .convert
                    ? pcmSettings(rate: rate, channels: channels, layout: layout)
                    : aacSettings(rate: rate, channels: channels))
        }
        output.alwaysCopiesSampleData = false
        input.expectsMediaDataInRealTime = false

        guard reader.canAdd(output) else { throw ExtractionError.failure("Cette piste audio ne peut pas être lue.") }
        reader.add(output)
        guard writer.canAdd(input) else { throw ExtractionError.failure("Cette piste audio ne rentre pas dans un .\(format.fileExtension).") }
        writer.add(input)

        let pump = Pump(reader: reader, output: output, writer: writer, input: input, duration: probe.duration)
        do {
            try await pump.run(progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: Réglages

    private static func pcmSettings(rate: Int, channels: Int, layout: Bool) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        if layout, let data = channelLayout(channels) {
            settings[AVChannelLayoutKey] = data
        }
        return settings
    }

    private static func aacSettings(rate: Int, channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels >= 2 ? 192_000 : 128_000,
        ]
    }

    private static func channelLayout(_ channels: Int) -> Data? {
        var layout = AudioChannelLayout()
        switch channels {
        case 1: layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        case 2: layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        default: return nil
        }
        return withUnsafeBytes(of: &layout) { Data($0) }
    }

    /// L'encodeur AAC n'accepte que les fréquences normalisées. Une source
    /// exotique est ramenée à 44,1 kHz plutôt que de faire échouer l'encodage.
    private static func encodableRate(_ rate: Double) -> Int {
        let standard = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000]
        let value = Int(rate.rounded())
        return standard.contains(value) ? value : 44100
    }

    // MARK: Destination

    static func destination(for source: URL, format: Format, in folder: URL?) throws -> URL {
        let directory = folder ?? source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + format.suffix
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(format.fileExtension)
            index += 1
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw ExtractionError.failure("Dossier en lecture seule : \(directory.lastPathComponent). Choisis une autre destination.")
        }
        return candidate
    }
}

// MARK: - Pompe

/// Transvase les échantillons d'une piste vers le fichier de sortie.
///
/// Les objets d'AVFoundation ne traversent pas les frontières de concurrence de
/// Swift 6. Ils sont donc enfermés ici, et tout ce qui les touche passe par une
/// seule file série.
private final class Pump: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderOutput
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let duration: Double
    private let queue = DispatchQueue(label: "local.bande.pump", qos: .userInitiated)
    private let lock = NSLock()
    private var closing = false   // plus personne n'a le droit d'annuler
    private var resumed = false   // la continuation a déjà été rendue
    private var reported = 0.0

    init(reader: AVAssetReader, output: AVAssetReaderOutput,
         writer: AVAssetWriter, input: AVAssetWriterInput, duration: Double) {
        self.reader = reader
        self.output = output
        self.writer = writer
        self.input = input
        self.duration = duration
    }

    func run(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard reader.startReading() else {
            throw ExtractionError.failure(reader.error?.localizedDescription ?? "Lecture impossible.")
        }
        guard writer.startWriting() else {
            throw ExtractionError.failure(writer.error?.localizedDescription ?? "Écriture impossible.")
        }
        writer.startSession(atSourceTime: .zero)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                input.requestMediaDataWhenReady(on: queue) { [self] in
                    while input.isReadyForMoreMediaData {
                        guard let buffer = output.copyNextSampleBuffer() else {
                            finish(continuation)
                            return
                        }
                        guard input.append(buffer) else {
                            abort(continuation, writer.error?.localizedDescription ?? "Écriture interrompue.")
                            return
                        }
                        report(buffer, to: progress)
                    }
                }
            }
        } onCancel: {
            stop()
        }
    }

    /// Fin de piste : il reste à distinguer un vrai bout de fichier d'une
    /// lecture qui s'est arrêtée en chemin.
    private func finish(_ continuation: CheckedContinuation<Void, Error>) {
        input.markAsFinished()
        switch reader.status {
        case .failed:
            abort(continuation, reader.error?.localizedDescription ?? "Lecture interrompue.")
        case .cancelled:
            lock.withLock { closing = true }
            writer.cancelWriting()
            settle(continuation, .failure(CancellationError()))
        default:
            lock.withLock { closing = true }
            writer.finishWriting { [self] in
                if writer.status == .completed {
                    settle(continuation, .success(()))
                } else {
                    settle(continuation, .failure(ExtractionError.failure(
                        writer.error?.localizedDescription ?? "Le fichier n'a pas pu être fermé.")))
                }
            }
        }
    }

    private func abort(_ continuation: CheckedContinuation<Void, Error>, _ why: String) {
        lock.withLock { closing = true }
        reader.cancelReading()
        if writer.status == .writing { writer.cancelWriting() }
        settle(continuation, .failure(ExtractionError.failure(why)))
    }

    private func stop() {
        let allowed = lock.withLock { !closing }
        guard allowed else { return }
        reader.cancelReading()
    }

    private func settle(_ continuation: CheckedContinuation<Void, Error>, _ result: Result<Void, Error>) {
        let first = lock.withLock {
            defer { resumed = true }
            return !resumed
        }
        guard first else { return }
        continuation.resume(with: result)
    }

    /// Un point d'avancement par pour-cent : au-delà, on inonde l'interface
    /// pour un pixel de barre.
    private func report(_ buffer: CMSampleBuffer, to progress: @Sendable (Double) -> Void) {
        guard duration > 0 else { return }
        let seconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard seconds.isFinite else { return }
        let value = min(1, max(0, seconds / duration))
        guard value - reported >= 0.01 else { return }
        reported = value
        progress(value)
    }
}
