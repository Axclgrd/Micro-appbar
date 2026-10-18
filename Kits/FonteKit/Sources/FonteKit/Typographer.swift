import CoreText
import Foundation

/// L'identification, confiée à Claude Code — et vérifiée sur les vraies polices.
///
/// Claude Code plutôt que l'API, parce qu'il est déjà là : c'est lui qui
/// installe les Micro-app, il est donc présent et connecté sur chaque Mac de
/// la famille. Pas de clé à saisir, pas de secret à ranger.
///
/// Reconnaître une police de mémoire ne suffit pas : sur une photo, Claude
/// hésite entre cinq linéales et donne 20 % à chacune. L'analyse se fait donc
/// en trois temps, comme le ferait un typographe :
///
/// 1. **Regarder de près.** Vision trouve les lignes de texte ; on les
///    redresse et on les agrandit (`Reading`).
/// 2. **Proposer.** Claude examine la capture et ses agrandissements, et
///    propose jusqu'à huit polices, sosies libres compris.
/// 3. **Vérifier.** Chaque proposition qu'on peut se procurer — installée,
///    Google Fonts, Fontshare (`Library`) — est composée avec le texte de la
///    capture, et Claude compare lettre à lettre avant de trancher.
///
/// Chaque appel est verrouillé : aucun outil sauf la recherche web quand elle
/// est demandée, aucune personnalisation (`--safe-mode`), aucune session
/// gardée, et une réponse validée contre un schéma JSON.
enum Typographer {

    enum Failure: Error, Sendable {
        case missing
        case timeout
        case failed(String)

        var message: String {
            switch self {
            case .missing:
                "Claude Code est introuvable sur ce Mac. Installe-le, ouvre `claude` une fois dans Terminal pour te connecter, puis réessaie."
            case .timeout:
                "Claude n'a pas répondu en \(Int(Typographer.limit / 60)) minutes. Réessaie : la capture est gardée."
            case .failed(let reason):
                reason
            }
        }
    }

    /// Ce que l'analyse s'autorise. Par défaut, un seul appel à Claude : c'est
    /// le coût qu'on paie à chaque capture. La vérification sur les vraies
    /// polices est un second appel, plus lourd (une image par police), qu'on
    /// ne lance que sur demande — `verify`.
    struct Method: Sendable {
        var zooms = true
        var compare = false
        var web = false
        var screen = true
        var effort = "medium"
    }

    /// Opus 5.5 : reconnaître une police se joue sur des détails d'un pixel,
    /// et c'est là que la vision fait la différence — Sonnet confondait les
    /// familles voisines.
    static let model = "claude-opus-5-5"
    static let limit: TimeInterval = 180

    /// Une app lancée depuis le Finder n'hérite pas du PATH du shell : on
    /// cherche Claude Code aux endroits où ses installeurs le posent.
    static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: Analyse

    /// Ce que le Mac voit de la capture avant d'écrire à Claude : lignes,
    /// agrandissements, et le message qui les porte.
    private struct Looked {
        let lines: [Reading.Line]
        let zooms: [Reading.Zoom]
        let blocks: [[String: Any]]
    }

    private static func look(_ png: Data, zooms wanted: Bool) -> Looked {
        let cg = Reading.image(png)
        let lines = cg.map(Reading.lines) ?? []
        let zooms = wanted ? (cg.map { Reading.zooms(of: $0, lines: lines) } ?? []) : []
        var blocks: [[String: Any]] = [text("Capture :"), image(png)]
        for (index, zoom) in zooms.filter({ !$0.redundant }).enumerated() {
            blocks += [text("Agrandissement \(index + 1), redressé : « \(zoom.text) »"), image(zoom.png)]
        }
        return Looked(lines: lines, zooms: zooms, blocks: blocks)
    }

    /// Bloquant : à appeler hors du fil principal. `progress` décrit l'étape
    /// en cours, pour que l'attente ait un sens.
    ///
    /// Un appel à Claude, plus les polices proposées téléchargées pour
    /// l'aperçu. Rien n'est comparé : c'est `verify`, sur demande.
    static func identify(_ png: Data, method: Method = Method(),
                         progress: @Sendable (String) -> Void = { _ in }) -> Result<Verdict, Failure> {
        guard let claude = locate() else { return .failure(.missing) }

        progress("Lecture des lignes de texte…")
        let looked = look(png, zooms: method.zooms)

        progress(method.web ? "Claude examine les lettres et cherche la source…" : "Claude examine les lettres…")
        let proposal: Verdict
        switch ask(claude, looked.blocks + [text("Propose les polices de cette capture.")],
                   instructions: method.web ? proposeInstructions + webInstructions : proposeInstructions,
                   schema: schema(max: 10), effort: method.effort, web: method.web) {
        case .failure(let failure): return .failure(failure)
        case .success(let payload):
            guard let verdict = try? JSONDecoder().decode(Verdict.self, from: payload) else {
                return .failure(.failed("La réponse de Claude ne suit pas le format attendu."))
            }
            proposal = verdict
        }

        progress("Recherche des polices proposées…")
        let faces = resolve(proposal.candidates.map { ($0.family, $0.style) })
        guard method.compare, !faces.isEmpty else { return .success(finish(proposal, faces: faces, verified: false)) }

        switch verify(claude, proposal: proposal, looked: looked, faces: faces, method: method, progress: progress) {
        case .success(let verdict): return .success(verdict)
        case .failure: return .success(finish(proposal, faces: faces, verified: false))
        }
    }

    /// La vérification sur les vraies polices : un second appel à Claude, à la
    /// demande. On ne dessine que trois polices — les deux premières
    /// propositions qu'on peut se procurer, et la meilleure du tri visuel —
    /// pour que le message reste court.
    static func verify(_ png: Data, proposal: Verdict, method: Method = Method(),
                       progress: @Sendable (String) -> Void = { _ in }) -> Result<Verdict, Failure> {
        guard let claude = locate() else { return .failure(.missing) }
        progress("Lecture des lignes de texte…")
        let looked = look(png, zooms: method.zooms)
        progress("Recherche des polices proposées…")
        let faces = resolve(proposal.candidates.prefix(6).map { ($0.family, $0.style) })
        return verify(claude, proposal: proposal, looked: looked, faces: Array(faces.prefix(2)), method: method, progress: progress)
    }

    private static func verify(_ claude: URL, proposal: Verdict, looked: Looked, faces start: [Library.Face],
                               method: Method, progress: @Sendable (String) -> Void) -> Result<Verdict, Failure> {
        var faces = start

        // Le tri visuel rattrape ce que Claude n'a pas proposé : la police du
        // Mac ou de Fontshare qui se superpose le mieux.
        if method.screen, let line = looked.zooms.first {
            progress("Tri visuel parmi les polices du Mac et de Fontshare…")
            // La première fois, Fontshare se télécharge : une centaine de
            // fichiers, gardés ensuite.
            let (weight, italic) = Style.parse(proposal.best?.style ?? "Regular")
            let known = Set(faces.map { Library.key($0.family) })
            let pool = Library.pool(weight: weight, italic: italic).filter { !known.contains(Library.key($0.family)) }
            faces += Screening.closest(to: line, among: pool, count: 1).map { face in
                var face = face
                face.screened = true
                return face
            }
        }
        guard !faces.isEmpty else {
            return .failure(.failed("Aucune des polices proposées n'a pu être dessinée : rien à comparer. Les payantes n'ont pas de fichier."))
        }

        progress("Claude compare avec \(faces.count) polices réelles…")
        let sample = sampleLines(zooms: looked.zooms, lines: looked.lines, transcription: proposal.text)
        switch compare(claude, looked: looked, sample: sample, faces: faces, proposal: proposal, method: method) {
        case .failure(let failure): return .failure(failure)
        case .success(let verdict):
            let known = resolve(verdict.candidates.map { ($0.family, $0.style) })
            return .success(finish(verdict, faces: faces + known, verified: true))
        }
    }

    /// Une planche par police, puis le jugement de Claude.
    private static func compare(_ claude: URL, looked: Looked, sample: [String], faces: [Library.Face],
                                proposal: Verdict, method: Method) -> Result<Verdict, Failure> {
        let zooms = looked.zooms
        // La capture et la police l'une sous l'autre quand on a une ligne
        // lisible ; sinon, le texte seul dans la police.
        let specimens: [(face: Library.Face, png: Data)] = faces.compactMap { face in
            let picture = zooms.isEmpty
                ? Reading.specimen(sample, font: face.font)
                : Reading.comparison(zooms, font: face.font)
            return picture.map { (face, $0) }
        }
        guard !specimens.isEmpty else { return .failure(.failed("Aucune planche de comparaison n'a pu être composée.")) }

        var blocks = looked.blocks
        for (index, specimen) in specimens.enumerated() {
            blocks += [text("Rendu \(index + 1) :"), image(specimen.png)]
        }
        let rendered = specimens.enumerated().map { index, specimen in
            let face = specimen.face
            let fit = zooms.first.flatMap { Screening.fit(of: face, on: $0) }
            let measure = fit.map {
                " — largeur \(Int(($0.width * 100).rounded())) % de la capture, formes communes \(Int(($0.overlap * 100).rounded())) %"
            } ?? ""
            return "- Rendu \(index + 1) : \(face.family), graisse \(face.weight)\(face.italic ? " italique" : "") (\(face.origin.label)\(face.screened ? ", trouvée par le tri visuel" : ""))\(measure)"
        }
        let drawn = Set(specimens.map { Library.key($0.face.family) })
        let unrendered = proposal.candidates
            .filter { !drawn.contains(Library.key($0.family)) }
            .map { "- \($0.family) \($0.style) (\($0.license.rawValue)) : \($0.evidence)" }
        blocks.append(text("""
        Correspondance des rendus :
        \(rendered.joined(separator: "\n"))

        Propositions de ta première analyse qu'on n'a pas dessinées (payantes, introuvables, ou hors des trois essayées) :
        \(unrendered.isEmpty ? "- aucune" : unrendered.joined(separator: "\n"))

        Analyse précédente : \(proposal.classification). \(proposal.note)

        Compare et donne le verdict final.
        """))

        switch ask(claude, blocks, instructions: compareInstructions, schema: schema(max: 5),
                   effort: method.effort, web: false) {
        case .failure(let failure): return .failure(failure)
        case .success(let payload):
            guard let verdict = try? JSONDecoder().decode(Verdict.self, from: payload) else {
                return .failure(.failed("La réponse de Claude ne suit pas le format attendu."))
            }
            return .success(verdict)
        }
    }

    /// Le texte à composer : celui des agrandissements, sinon les lignes
    /// lues par Vision, sinon la transcription de Claude. Deux lignes au plus,
    /// assez courtes pour rester lisibles côte à côte.
    private static func sampleLines(zooms: [Reading.Zoom], lines: [Reading.Line], transcription: String) -> [String] {
        var texts = zooms.map(\.text)
        if texts.isEmpty { texts = lines.sorted { $0.height > $1.height }.map(\.text) }
        if texts.isEmpty { texts = transcription.split(whereSeparator: \.isNewline).map(String.init) }
        let cleaned = texts.map { String($0.trimmingCharacters(in: .whitespaces).prefix(34)) }.filter { !$0.isEmpty }
        return Array(cleaned.prefix(2)).isEmpty ? ["Aa Gg Rr Qq 0123"] : Array(cleaned.prefix(2))
    }

    /// Les propositions qu'on peut se procurer, sans doublon, en parallèle :
    /// chacune peut demander un téléchargement.
    private static func resolve(_ candidates: [(family: String, style: String)]) -> [Library.Face] {
        let slots = Library.Slots(count: candidates.count)
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            slots.set(index, Library.face(family: candidates[index].family, style: candidates[index].style))
        }
        var seen = Set<String>()
        return slots.values.compactMap { $0 }.filter {
            seen.insert("\(Library.key($0.family))-\($0.weight)-\($0.italic)").inserted
        }
    }

    /// Les candidates qu'on a pu dessiner portent leur provenance : la fiche
    /// peut alors montrer l'aperçu et proposer l'installation.
    private static func finish(_ verdict: Verdict, faces: [Library.Face], verified: Bool) -> Verdict {
        var verdict = verdict
        verdict.verified = verified
        for index in verdict.candidates.indices {
            let wanted = Library.key(verdict.candidates[index].family)
            if let face = faces.first(where: { Library.key($0.family) == wanted }) {
                verdict.candidates[index].origin = face.origin
            }
        }
        return verdict
    }

    // MARK: Consignes

    private static let proposeInstructions = """
    Tu es typographe. On te montre une capture d'écran, puis des agrandissements redressés de ses lignes de texte. Identifie la police.

    Méthode :
    1. Lis le texte.
    2. Classe le caractère : linéale géométrique, grotesque, néo-grotesque, humaniste, didone, garalde, réale, mécane, scripte, monospace, display.
    3. Observe les glyphes qui départagent les familles proches : a, g, G, R, Q, J, M, e, t, y, k, les chiffres, la ponctuation. Regarde les terminaisons, le contraste, l'axe, la hauteur d'x, la largeur, l'ouverture des contre-formes et la forme des points.
    4. Compare avec les familles voisines et tranche sur ces détails.

    Les agrandissements peuvent rester penchés ou déformés quand le texte est photographié sur un objet : une inclinaison due à la perspective n'est pas un italique. Si la capture mélange plusieurs polices, identifie celle du texte principal (le plus grand) et signale l'autre dans `note`.

    Tes propositions seront ensuite vérifiées : celles qu'on peut se procurer (polices installées sur macOS, Google Fonts, Fontshare) seront composées avec le même texte et comparées à la capture. Donc :
    - Propose de 4 à 10 polices, de la plus probable à la moins probable. Ratisse large : une police absente de ta liste ne sera jamais vérifiée.
    - Pense d'abord aux polices les plus employées qui collent au style, puis aux sosies.
    - Si tes meilleures pistes sont payantes, ajoute aussi les sosies libres les plus proches : ce sont eux qu'on pourra dessiner.
    - `family` contient le nom de famille exact, tel qu'il apparaît dans un menu de polices ou sur Google Fonts : « Helvetica Neue », « Plus Jakarta Sans », « Inter ». N'y mets ni fonderie, ni graisse, ni parenthèses.
    - `style` indique la graisse et le style visibles, en mots de menu seulement, sans commentaire : « Light », « SemiBold Italic ».

    Règles de réponse :
    - `text` recopie le texte lu en respectant la casse.
    - `classification` tient en 2 à 5 mots.
    - `confidence` est une probabilité honnête en pourcentage. Le total ne dépasse pas 100.
    - `evidence` cite les détails de lettres réellement visibles dans l'image.
    - `license` vaut `free` pour une police gratuite et open source, `system` pour une police livrée avec macOS ou Windows, `commercial` pour une police payante et `unknown` si tu ne sais pas.
    - `alternatives` liste des polices libres proches (Google Fonts, Fontshare).
    - `note` signale ce qui limite l'identification : lettrage dessiné, logo retouché, trop peu de lettres. Laisse ce champ vide s'il n'y a rien à dire.
    - Écris en français, en phrases courtes.
    """

    private static let webInstructions = """

    Recherche web :
    - Si le texte est une marque, un produit ou un titre, une recherche peut retrouver la police créditée : Fonts In Use, Behance, la page de la marque, un article de design.
    - Fais au plus trois recherches, et seulement si elles peuvent trancher. Une police créditée par une source fiable l'emporte sur ton impression visuelle, à condition que les lettres concordent.
    - Si tu trouves la source, dis-le dans `note`.
    """

    private static let compareInstructions = """
    Tu es typographe. Tu reçois une capture d'écran et ses agrandissements, puis une planche par police candidate. Les candidates viennent de ta première analyse, et quelques-unes d'un tri visuel automatique qui a cherché, parmi les polices du Mac et de Fontshare, celles qui se superposent le mieux à la capture ; ce tri se trompe parfois, juge-les comme les autres (« Rendu 1 », « Rendu 2 »…). Sur chaque planche, chaque ligne capturée est en haut, et la même ligne composée dans la police candidate est juste en dessous, en noir, à la même hauteur de lettres et alignée à gauche. Les rendus sont exacts : ils viennent des vrais fichiers de police.

    Méthode :
    1. Sur chaque planche, compare la ligne du bas à celle du haut, lettre par lettre. Si c'est la bonne police, les deux lignes se superposent presque : mêmes largeurs de lettres, mêmes formes. Regarde : la forme du a, du g, du e, du R, du t ; la coupe des terminaisons (horizontale, verticale, oblique) ; la largeur des lettres ; la hauteur d'x ; le contraste ; l'ouverture des contre-formes ; les points et les chiffres.
       Une ligne composée nettement plus large ou plus étroite que la capture désigne une autre police, sauf si l'écart vient seulement des espaces entre les lettres.
       Chaque rendu est accompagné de deux mesures faites par l'ordinateur sur la première ligne : sa largeur par rapport à la capture (100 % quand elles se superposent) et la part de formes communes une fois les largeurs égalisées. Ce sont des indices, pas des preuves : le flou, la perspective et un interlettrage modifié les faussent. Mais un écart de largeur de plus de 6 %, ou une part de formes nettement plus faible que celle du meilleur rendu, doit te faire douter de la police. Une police qui se superpose à la fois par la largeur et par les formes mérite d'être regardée en premier.
    2. Ignore ce qui vient de la photo ou de la mise en page : perspective et inclinaison, flou, couleurs, compression, interlettrage, et un léger écart de graisse.
    3. Tranche :
       - Un rendu identique sur les lettres décisives est la police. Donne-lui une confiance élevée (de 75 à 95).
       - Un rendu qui diffère sur une lettre décisive n'est pas la police, même s'il ressemble globalement. Par exemple : « a » à un étage au lieu de deux, terminaisons obliques au lieu d'horizontales, « G » sans éperon. Descends-le nettement.
       - Les propositions qu'on n'a pas pu dessiner ne sont pas vérifiées. Place-les en tête seulement si aucun rendu ne correspond, avec une confiance modérée.
       - Tu peux ajouter une police absente de la liste si les rendus t'orientent vers elle.

    Règles de réponse :
    - De 1 à 5 polices, de la plus probable à la moins probable.
    - `family` contient le nom de famille exact, sans fonderie ni graisse. `style` indique la graisse et le style visibles dans la capture, en mots de menu seulement, sans commentaire : « Light », « Bold Italic ».
    - `text` recopie le texte lu en respectant la casse.
    - `classification` tient en 2 à 5 mots.
    - `confidence` est une probabilité honnête en pourcentage. Le total ne dépasse pas 100.
    - `evidence` dit quelles lettres confirment ou écartent la police. Ne mentionne pas les numéros de rendu : le lecteur ne les voit pas.
    - `license` vaut `free`, `system`, `commercial` ou `unknown`.
    - `alternatives` liste des polices libres proches.
    - `note` résume en une phrase ce que la comparaison a montré, et ce qui limite encore l'identification.
    - Écris en français, en phrases courtes.
    """

    static func schema(max: Int) -> String {
        """
        {"type":"object","additionalProperties":false,
         "properties":{
          "text":{"type":"string"},
          "classification":{"type":"string"},
          "candidates":{"type":"array","minItems":1,"maxItems":\(max),"items":{
            "type":"object","additionalProperties":false,
            "properties":{
              "family":{"type":"string"},
              "foundry":{"type":"string"},
              "style":{"type":"string"},
              "confidence":{"type":"integer","minimum":0,"maximum":100},
              "evidence":{"type":"string"},
              "license":{"type":"string","enum":["free","commercial","system","unknown"]}},
            "required":["family","foundry","style","confidence","evidence","license"]}},
          "alternatives":{"type":"array","items":{"type":"string"}},
          "note":{"type":"string"}},
         "required":["text","classification","candidates","alternatives","note"]}
        """
    }

    // MARK: Appel

    private static func text(_ string: String) -> [String: Any] {
        ["type": "text", "text": string]
    }

    private static func image(_ png: Data) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]
    }

    /// Un appel à Claude Code : un message, une réponse au schéma imposé,
    /// rendue telle quelle (JSON).
    private static func ask(_ claude: URL, _ content: [[String: Any]], instructions: String,
                            schema: String, effort: String, web: Bool) -> Result<Data, Failure> {
        let work = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "fonte", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let request = work.appending(path: "\(UUID().uuidString).jsonl")
        let prompt = work.appending(path: "\(UUID().uuidString).txt")
        let log = work.appending(path: "\(UUID().uuidString).log")
        defer {
            for file in [request, prompt, log] { try? FileManager.default.removeItem(at: file) }
        }

        // Le message part d'un fichier plutôt que d'un tube : Claude Code lit
        // son entrée jusqu'à la fin, et un fichier se termine tout seul. Écrire
        // dans un tube pendant qu'on lit l'autre demanderait deux fils — et un
        // processus mort avant d'avoir tout lu tuerait l'app d'un SIGPIPE.
        //
        // La consigne passe elle aussi par un fichier : `Process` décompose
        // les accents de ses arguments, et Claude lirait un français truffé
        // d'accents combinants.
        let line: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
        guard var message = try? JSONSerialization.data(withJSONObject: line) else {
            return .failure(.failed("Impossible de préparer la requête."))
        }
        message.append(0x0A)
        guard (try? message.write(to: request)) != nil,
              (try? instructions.write(to: prompt, atomically: true, encoding: .utf8)) != nil,
              FileManager.default.createFile(atPath: log.path, contents: nil),
              let input = FileHandle(forReadingAtPath: request.path),
              let errors = FileHandle(forWritingAtPath: log.path)
        else { return .failure(.failed("Impossible de préparer la requête dans \(work.path).")) }

        let process = Process()
        process.executableURL = claude
        process.currentDirectoryURL = work
        // La recherche web est le seul outil jamais permis : Claude ne lit ni
        // n'écrit rien sur le Mac.
        let tools = web ? ["--tools", "WebSearch", "--allowedTools", "WebSearch"] : ["--tools", ""]
        process.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--safe-mode",
            "--no-session-persistence",
            "--model", model,
            "--effort", effort,
            "--system-prompt-file", prompt.path,
            "--json-schema", schema,
        ] + tools
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                               "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let start = Date()
        do {
            try process.run()
        } catch {
            return .failure(.failed("Claude Code n'a pas pu démarrer : \(error.localizedDescription)"))
        }

        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        if process.terminationReason == .uncaughtSignal, Date().timeIntervalSince(start) >= limit - 1 {
            return .failure(.timeout)
        }
        return interpret(data, status: process.terminationStatus,
                         log: (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    // MARK: Réponse

    /// Le flux se termine par une ligne `result`, la seule qui compte : elle
    /// porte soit la sortie structurée, soit l'erreur.
    private static func interpret(_ data: Data, status: Int32, log: String) -> Result<Data, Failure> {
        let lines = data.split(separator: 0x0A)
        let result = lines.reversed().lazy
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
            .first { $0["type"] as? String == "result" }

        guard let result else {
            let detail = log.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.failed(detail.isEmpty
                ? "Claude Code s'est arrêté sans répondre (code \(status))."
                : "Claude Code s'est arrêté sans répondre : \(detail.suffix(300))"))
        }

        if result["is_error"] as? Bool == true || result["subtype"] as? String != "success" {
            let reason = (result["result"] as? String)
                ?? (result["errors"] as? [String])?.joined(separator: " ")
                ?? "erreur sans détail"
            // Le cas le plus probable sur un Mac neuf : jamais connecté.
            let hint = reason.localizedCaseInsensitiveContains("login")
                || reason.localizedCaseInsensitiveContains("auth")
                ? " Ouvre `claude` dans Terminal pour te connecter." : ""
            return .failure(.failed("Claude a refusé l'analyse : \(reason)\(hint)"))
        }

        // La sortie structurée d'abord ; à défaut, le texte du résultat, qui
        // contient le même JSON.
        let payload: Data? = if let structured = result["structured_output"] {
            try? JSONSerialization.data(withJSONObject: structured)
        } else {
            (result["result"] as? String)?.data(using: .utf8)
        }
        guard let payload else {
            return .failure(.failed("La réponse de Claude ne suit pas le format attendu."))
        }
        return .success(payload)
    }
}
