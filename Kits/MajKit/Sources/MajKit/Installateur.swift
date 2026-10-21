import Foundation

/// Où vivent les traces d'une mise à jour.
enum Chemins {
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trousse/maj", isDirectory: true)
    }
    static var journal: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Trousse-MiseAJour.log")
    }
    static var verrou: URL { support.appendingPathComponent("verrou", isDirectory: true) }
    static var script: URL { support.appendingPathComponent("maj-installer.sh") }
    static var resultat: URL { support.appendingPathComponent("resultat") }
    static var derniere: URL { support.appendingPathComponent("derniere.log") }
}

/// Le journal lisible depuis le panneau (et depuis Console).
enum Journal {
    static func ecrire(_ ligne: String) {
        let date = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
        let texte = "[\(date)] \(ligne)\n"
        let url = Chemins.journal
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(texte.utf8))
        } else {
            try? texte.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Les dernières lignes. Le fichier est tronqué au-delà de 1 Mo.
    static func lire(lignes: Int = 60) -> String {
        guard let texte = try? String(contentsOf: Chemins.journal, encoding: .utf8) else {
            return "Le journal est vide."
        }
        return texte.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(lignes).joined(separator: "\n")
    }

    static func tronquer() {
        let url = Chemins.journal
        guard let taille = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              taille > 1_000_000,
              let texte = try? String(contentsOf: url, encoding: .utf8) else { return }
        let fin = texte.split(separator: "\n").suffix(500).joined(separator: "\n") + "\n"
        try? fin.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Un seul build à la fois, entre processus : un dossier qu'on crée de façon
/// atomique, avec le pid de son titulaire. Un titulaire mort laisse un verrou
/// périmé, qu'on reprend.
enum Verrou {
    static var actif: Bool {
        guard FileManager.default.fileExists(atPath: Chemins.verrou.path) else { return false }
        let pid = titulaire
        if pid > 0, vivant(pid) { return true }
        // Le dossier vient peut-être d'être créé, le pid pas encore écrit.
        if pid <= 0, let date = (try? FileManager.default.attributesOfItem(
            atPath: Chemins.verrou.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < 5 { return true }
        return false
    }

    private static var titulaire: Int32 {
        let texte = try? String(contentsOf: Chemins.verrou.appendingPathComponent("pid"), encoding: .utf8)
        return Int32(texte?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    private static func vivant(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func prendre() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: Chemins.support, withIntermediateDirectories: true)
        for _ in 0..<2 {
            do {
                try fm.createDirectory(at: Chemins.verrou, withIntermediateDirectories: false)
                try? "\(getpid())".write(
                    to: Chemins.verrou.appendingPathComponent("pid"), atomically: true, encoding: .utf8)
                return true
            } catch {
                if actif { return false }
                try? fm.removeItem(at: Chemins.verrou)   // périmé
            }
        }
        return false
    }

    static func liberer() {
        try? FileManager.default.removeItem(at: Chemins.verrou)
    }
}

/// Le bilan écrit par le script quand il a fini.
struct Resultat: Equatable, Sendable {
    var date: Date
    var commit: String
    var ok: [String]
    var echec: [String]
    var ventilateurs: Bool
    var erreurs: [String]

    var reussi: Bool { echec.isEmpty }

    static func lire() -> Resultat? {
        guard let texte = try? String(contentsOf: Chemins.resultat, encoding: .utf8) else { return nil }
        var valeurs: [String: String] = [:]
        for ligne in texte.split(separator: "\n") {
            guard let i = ligne.firstIndex(of: "=") else { continue }
            valeurs[String(ligne[..<i])] = String(ligne[ligne.index(after: i)...])
        }
        guard let t = valeurs["date"].flatMap(TimeInterval.init) else { return nil }
        func liste(_ cle: String) -> [String] {
            (valeurs[cle] ?? "").split(separator: " ").map(String.init)
        }
        let echec = liste("echec")
        var erreurs: [String] = []
        if !echec.isEmpty, let log = try? String(contentsOf: Chemins.derniere, encoding: .utf8) {
            let lignes = log.split(separator: "\n").map(String.init)
            erreurs = Array(lignes.filter { $0.contains("error:") }.prefix(6))
            if erreurs.isEmpty { erreurs = Array(lignes.suffix(6)) }
        }
        return Resultat(date: Date(timeIntervalSince1970: t), commit: valeurs["commit"] ?? "",
                        ok: liste("ok"), echec: echec,
                        ventilateurs: valeurs["ventilateurs"] == "1", erreurs: erreurs)
    }
}

/// Le script de reconstruction, lancé détaché.
///
/// Trousse ne peut pas remplacer son propre bundle pendant qu'elle tourne :
/// `build.sh --install` la ferme puis la relance. Ce qui doit survivre à cette
/// fermeture, c'est donc un processus à part, qui n'a pas Trousse pour parent
/// de vie. Il tient le verrou, reconstruit les apps une à une avec
/// `./install.sh <app>` (jamais sudo, jamais le démon des ventilateurs),
/// journalise, et écrit son bilan.
enum Installateur {
    static let script = #"""
    #!/bin/bash
    # Écrit par MajKit (Trousse). usage : maj-installer.sh DEPOT COMMIT app...
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
    DEPOT="$1"; COMMIT="$2"; shift 2
    SUPPORT="$HOME/Library/Application Support/Trousse/maj"
    LOG="$HOME/Library/Logs/Trousse-MiseAJour.log"
    RUN="$SUPPORT/derniere.log"
    mkdir -p "$SUPPORT/verrou" "$(dirname "$LOG")"
    trap '' HUP
    echo $$ > "$SUPPORT/verrou/pid"
    trap 'rm -rf "$SUPPORT/verrou"' EXIT
    : > "$RUN"
    ecrire() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" | tee -a "$LOG" >> "$RUN"; }
    ok=(); echec=()
    ecrire "Reconstruction : $*"
    if ! cd "$DEPOT"; then
      ecrire "Dépôt introuvable : $DEPOT"
      echec=("$@")
    else
      for app in "$@"; do
        ecrire "── $app ──"
        ./install.sh "$app" > "$RUN.app" 2>&1
        rc=$?
        tee -a "$LOG" < "$RUN.app" >> "$RUN"
        if [ $rc -eq 0 ]; then ok+=("$app"); ecrire "$app : installée"
        else echec+=("$app"); ecrire "$app : ÉCHEC (code $rc), l'ancienne version reste en place"; fi
      done
    fi
    rm -f "$RUN.app"
    {
      echo "date=$(date +%s)"
      echo "commit=$COMMIT"
      echo "ok=${ok[*]-}"
      echo "echec=${echec[*]-}"
      echo "ventilateurs=${MAJ_VENTILATEURS:-0}"
    } > "$SUPPORT/resultat.tmp" && mv "$SUPPORT/resultat.tmp" "$SUPPORT/resultat"
    ecrire "Fin : ok=[${ok[*]-}] échec=[${echec[*]-}]"
    """#

    /// Lance le script, détaché. Le verrou doit déjà être pris par l'appelant.
    static func lancer(depot: Depot, commit: String, apps: [String], ventilateurs: Bool) throws {
        try FileManager.default.createDirectory(at: Chemins.support, withIntermediateDirectories: true)
        try script.write(to: Chemins.script, atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        p.arguments = ["/bin/bash", Chemins.script.path, depot.chemin, commit] + apps
        var env = ProcessInfo.processInfo.environment
        env["MAJ_VENTILATEURS"] = ventilateurs ? "1" : "0"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }
}
