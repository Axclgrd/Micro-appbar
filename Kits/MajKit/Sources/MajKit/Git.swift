import Foundation

/// Ce que git a répondu.
struct SortieGit: Sendable {
    let code: Int32
    let out: String
    let err: String

    var ok: Bool { code == 0 }

    /// L'erreur réelle de git, telle quelle : c'est elle qu'on montre.
    var message: String {
        let texte = (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
        return texte.isEmpty ? "git a échoué (code \(code))" : texte
    }
}

/// Lance git, sans jamais bloquer le fil principal ni attendre un mot de passe.
enum Git {
    static func executer(_ args: [String], dans racine: URL, delai: TimeInterval = 90) async -> SortieGit {
        await Task.detached(priority: .utility) { lancer(args, racine, delai) }.value
    }

    private static func lancer(_ args: [String], _ racine: URL, _ delai: TimeInterval) -> SortieGit {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", racine.path] + args
        var env = ProcessInfo.processInfo.environment
        // Jamais d'invite : une question posée à personne bloquerait pour toujours.
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LC_ALL"] = "C"
        if env["GIT_SSH_COMMAND"] == nil {
            env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=20"
        }
        p.environment = env
        let sortie = Pipe(), erreur = Pipe()
        p.standardOutput = sortie
        p.standardError = erreur
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return SortieGit(code: -1, out: "", err: "git est introuvable : \(error.localizedDescription)")
        }

        let garde = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + delai, execute: garde)

        nonisolated(unsafe) var erreurs = Data()
        let groupe = DispatchGroup()
        groupe.enter()
        DispatchQueue.global().async {
            erreurs = erreur.fileHandleForReading.readDataToEndOfFile()
            groupe.leave()
        }
        let sorties = sortie.fileHandleForReading.readDataToEndOfFile()
        groupe.wait()
        p.waitUntilExit()
        garde.cancel()

        var err = String(decoding: erreurs, as: UTF8.self)
        if p.terminationReason == .uncaughtSignal && p.terminationStatus == SIGTERM {
            err = "Délai dépassé (\(Int(delai)) s) : \(err)"
        }
        return SortieGit(code: p.terminationStatus, out: String(decoding: sorties, as: UTF8.self), err: err)
    }
}

struct ErreurMaj: Error, LocalizedError {
    let texte: String
    init(_ texte: String) { self.texte = texte }
    var errorDescription: String? { texte }
}

struct Commit: Identifiable, Equatable, Sendable {
    let id: String
    let auteur: String
    let sujet: String
}

/// L'état du dépôt par rapport à `origin/main`, à un instant donné.
struct Examen: Sendable {
    var branche: String
    var local: String
    var distant: String
    var devant: Int
    var derriere: Int
    var commits: [Commit]
    /// Fichiers suivis modifiés localement (les fichiers non suivis ne comptent
    /// pas : git refuse tout seul de les écraser).
    var modifies: [String]
    /// Fichiers que la mise à jour changerait.
    var changes: [String]
}

/// Le dépôt cloné d'où viennent les sources.
struct Depot: Equatable, Sendable {
    static let remote = "origin"
    static let branche = "main"

    let racine: URL
    var chemin: String { racine.path }

    static func valide(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent(".git").path)
            && fm.fileExists(atPath: url.appendingPathComponent("install.sh").path)
            && fm.fileExists(atPath: url.appendingPathComponent("trousse/build.sh").path)
    }

    /// Retrouve le dépôt. Trois pistes, de la plus sûre à la plus fragile :
    /// le chemin que l'utilisateur a désigné ; le chemin des sources au moment
    /// de la compilation (`#filePath` est absolu, et la trousse est toujours
    /// compilée depuis le dépôt) ; le dossier d'où le bundle a été construit.
    static func chercher(memorise: String?, source: String = #filePath,
                         bundle: URL = Bundle.main.bundleURL) -> Depot? {
        var pistes: [URL] = []
        if let memorise, !memorise.isEmpty { pistes.append(URL(fileURLWithPath: memorise)) }
        for depart in [URL(fileURLWithPath: source), bundle] {
            var url = depart
            for _ in 0..<8 {
                url = url.deletingLastPathComponent()
                pistes.append(url)
            }
        }
        return pistes.first(where: valide).map { Depot(racine: $0.standardizedFileURL) }
    }

    // MARK: Opérations

    private func git(_ args: String..., delai: TimeInterval = 90) async -> SortieGit {
        await Git.executer(args, dans: racine, delai: delai)
    }

    /// `git fetch` de la seule branche suivie.
    func recuperer() async throws {
        let r = await git("fetch", "--quiet", Self.remote,
                          "+refs/heads/\(Self.branche):refs/remotes/\(Self.remote)/\(Self.branche)")
        guard r.ok else { throw ErreurMaj("git fetch a échoué : \(r.message)") }
    }

    func examiner() async throws -> Examen {
        let distantRef = "\(Self.remote)/\(Self.branche)"
        let branche = await git("rev-parse", "--abbrev-ref", "HEAD")
        guard branche.ok else { throw ErreurMaj("Dépôt illisible : \(branche.message)") }
        let local = await git("rev-parse", "HEAD")
        let distant = await git("rev-parse", "--verify", distantRef)
        guard local.ok, distant.ok else {
            throw ErreurMaj("\(distantRef) est introuvable : \(distant.message)")
        }
        let compte = await git("rev-list", "--left-right", "--count", "HEAD...\(distantRef)")
        let nombres = compte.out.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard compte.ok, nombres.count == 2 else {
            throw ErreurMaj("Comparaison impossible avec \(distantRef) : \(compte.message)")
        }
        let log = await git("log", "-n", "50", "--format=%h%x1f%an%x1f%s", "HEAD..\(distantRef)")
        let commits = log.out.split(separator: "\n").compactMap { ligne -> Commit? in
            let p = ligne.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            return p.count == 3 ? Commit(id: p[0], auteur: p[1], sujet: p[2]) : nil
        }
        let statut = await git("status", "--porcelain", "--untracked-files=no")
        let modifies = statut.out.split(separator: "\n").map { String($0.dropFirst(3)) }
        let diff = await git("diff", "--name-only", "HEAD...\(distantRef)")
        let changes = diff.out.split(separator: "\n").map(String.init)
        return Examen(
            branche: branche.out.trimmingCharacters(in: .whitespacesAndNewlines),
            local: local.out.trimmingCharacters(in: .whitespacesAndNewlines),
            distant: distant.out.trimmingCharacters(in: .whitespacesAndNewlines),
            devant: nombres[0], derriere: nombres[1],
            commits: commits, modifies: modifies, changes: changes)
    }

    /// Avance en fast-forward, jamais autrement : si l'historique a divergé,
    /// git refuse et on le dit.
    func avancer() async throws {
        let r = await git("merge", "--ff-only", "\(Self.remote)/\(Self.branche)")
        guard r.ok else { throw ErreurMaj("Fast-forward impossible : \(r.message)") }
    }
}

extension Examen {
    /// Pourquoi on ne touchera à rien, ou nil si la voie est libre.
    var blocage: String? {
        if branche != Depot.branche {
            return "Le dépôt est sur la branche « \(branche) » : seule \(Depot.branche) est suivie."
        }
        if devant > 0 && derriere > 0 {
            return "L'historique local a divergé de \(Depot.remote)/\(Depot.branche) (\(devant) commit(s) local, \(derriere) distant). Fast-forward uniquement : rien n'est fait."
        }
        if !modifies.isEmpty {
            let liste = modifies.prefix(3).joined(separator: ", ")
            let suite = modifies.count > 3 ? "…" : ""
            return "Modifications locales non commitées (\(modifies.count) fichier(s) : \(liste)\(suite)). Rien n'est fait tant qu'elles existent."
        }
        return nil
    }
}
