import Commun
import Foundation

/// Un processus qui tient le volume ouvert, et empêche donc l'éjection.
struct Blocker: Identifiable, Sendable, Hashable {
    let pid: pid_t
    let command: String
    /// Un fichier ouvert parmi d'autres : c'est lui qui fait comprendre
    /// *pourquoi* ce processus tient le disque.
    let sample: String?
    let count: Int

    var id: pid_t { pid }
}

/// Résultat d'une action, tel qu'on l'affiche.
struct Outcome: Sendable {
    let ok: Bool
    let message: String
}

/// Les actions sur les disques : éjecter, forcer, remonter, et nommer ce qui
/// bloque. Isolé sur son acteur — chaque appel bloque plusieurs centaines de
/// millisecondes.
actor DiskAgent {

    func eject(_ diskID: String) -> Outcome {
        outcome(Shell.run(Shell.diskutil, ["eject", "/dev/\(diskID)"]),
                success: "Disque éjecté. Tu peux débrancher.")
    }

    /// Démonter sans couper l'alimentation.
    ///
    /// La nuance que macOS n'expose nulle part : « Éjecter » retire le
    /// périphérique, et il faut débrancher-rebrancher pour le revoir ;
    /// démonter libère juste les volumes, le disque reste là et se remonte
    /// d'un clic. C'est ce qu'on veut avant un Time Machine, un fsck, ou
    /// simplement pour cesser d'indexer un disque sans le débrancher.
    func unmount(_ diskID: String) -> Outcome {
        outcome(Shell.run(Shell.diskutil, ["unmountDisk", "/dev/\(diskID)"]),
                success: "Volumes démontés. Le disque reste branché.")
    }

    /// Éjection forcée : on démonte sans attendre l'accord des processus, puis
    /// on éjecte. À ne proposer qu'après un échec, et jamais en premier —
    /// une écriture en cours est perdue.
    func forceEject(_ diskID: String) -> Outcome {
        let unmount = Shell.run(Shell.diskutil, ["unmountDisk", "force", "/dev/\(diskID)"])
        guard unmount.ok else {
            return outcome(unmount, success: "")
        }
        return outcome(Shell.run(Shell.diskutil, ["eject", "/dev/\(diskID)"]),
                       success: "Disque éjecté de force.")
    }

    /// Remonter un disque éjecté mais toujours branché — ce que macOS ne
    /// propose nulle part, alors que le disque est là, alimenté, à un appel
    /// système de distance.
    func mount(_ diskID: String) -> Outcome {
        outcome(Shell.run(Shell.diskutil, ["mountDisk", "/dev/\(diskID)"]),
                success: "Disque remonté.")
    }

    /// Qui tient le volume.
    ///
    /// `lsof` reçoit un point de montage : il liste alors tout ce qui est
    /// ouvert sur ce système de fichiers, y compris les répertoires courants
    /// de shells — la cause la plus fréquente, et la plus invisible.
    ///
    /// Limite assumée : sans privilège root, `lsof` ne voit pas les processus
    /// des autres utilisateurs. Un blocage par `mds_stores` (Spotlight) ou par
    /// Time Machine sort donc une liste vide ; c'est l'interface qui le dit.
    func blockers(under mountPoints: [String]) -> [Blocker] {
        var found: [pid_t: Blocker] = [:]
        let me = getpid()

        for mountPoint in mountPoints {
            let result = Shell.run(Shell.lsof, ["-w", "-n", "-P", "-F", "pcn", "--", mountPoint])
            // `lsof` sort 1 dès qu'un fichier lui échappe : la sortie reste
            // exploitable, on ne teste donc pas le code de retour.
            var pid: pid_t?
            var command = ""
            var count = 0
            var sample: String?

            func flush() {
                guard let pid, pid != me, !command.isEmpty else { return }
                let existing = found[pid]
                found[pid] = Blocker(
                    pid: pid,
                    command: command,
                    sample: existing?.sample ?? sample,
                    count: (existing?.count ?? 0) + count
                )
            }

            for line in result.text.split(separator: "\n", omittingEmptySubsequences: true) {
                let value = String(line.dropFirst())
                switch line.first {
                case "p":
                    flush()
                    pid = pid_t(value)
                    command = ""
                    count = 0
                    sample = nil
                case "c":
                    command = value
                case "n":
                    count += 1
                    if sample == nil, value.hasPrefix(mountPoint) {
                        // Chemin relatif au volume : « agr/Micro-app » se lit,
                        // « /Volumes/My Passport/agr/Micro-app » se subit.
                        let relative = String(value.dropFirst(mountPoint.count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        sample = relative.isEmpty ? nil : relative
                    }
                default:
                    break
                }
            }
            flush()
        }

        return found.values.sorted { $0.count > $1.count }
    }

    private func outcome(_ result: Shell.Result, success: String) -> Outcome {
        guard result.ok else {
            let raw = result.err.isEmpty ? result.text : result.err
            let line = raw.split(separator: "\n").first.map(String.init) ?? "Échec"
            return Outcome(ok: false, message: line)
        }
        return Outcome(ok: true, message: success)
    }
}
