import Foundation

// Ce qu'on peut faire, pas seulement ce qu'on mesure.
//
// Un moniteur qui affiche « mémoire : 94 % » laisse son lecteur devant la
// question qu'il se posait déjà. Le conseil nomme la cause — une application,
// un chiffre — et l'action qui la lèverait.
//
// Deux garde-fous :
//
// - **Jamais plus de trois conseils**, les plus graves d'abord. Une liste de
//   dix recommandations n'est plus un conseil, c'est un tableau de bord de
//   plus à lire.
// - **Rien d'inventé.** Chaque phrase s'appuie sur une valeur mesurée dans ce
//   relevé-ci. Pas de « pensez à redémarrer de temps en temps ».

public struct Conseil: Identifiable, Sendable, Equatable {
    public let id: String
    public let symbol: String
    /// 0 information, 1 à surveiller, 2 agir maintenant.
    public let severity: Int
    public let text: String
}

enum Conseils {

    static func pour(_ snapshot: Snapshot, apps: [AppUsage]) -> [Conseil] {
        var liste: [Conseil] = []
        let memory = snapshot.memory

        let gourmandeRAM = apps.max { $0.memory < $1.memory }
        let gourmandeCPU = apps.max { $0.cpu < $1.cpu }

        // MARK: Mémoire — la ressource dont le manque se sent vraiment.

        if memory.pression == .critique {
            var phrase = "Mémoire saturée : macOS compresse (\(Chiffre.octets(memory.compressed))) "
                + "et écrit sur le disque pour tenir. Tout devient lent."
            if let app = gourmandeRAM, app.memory > 1 << 30 {
                phrase += " \(app.name) en tient \(Chiffre.octets(app.memory)) : c'est là qu'il y a le plus à récupérer."
            }
            liste.append(Conseil(id: "ram-critique", symbol: "memorychip.fill",
                                 severity: 2, text: phrase))
        } else if memory.pression == .elevee {
            var phrase = "La mémoire commence à manquer — macOS comprime pour faire tenir tout le monde."
            if let app = gourmandeRAM, app.memory > 2 << 30 {
                phrase += " Fermer \(app.name) rendrait \(Chiffre.octets(app.memory))."
            }
            liste.append(Conseil(id: "ram-elevee", symbol: "memorychip",
                                 severity: 1, text: phrase))
        } else if memory.swapUsed > 2 << 30 {
            // Pression normale mais beaucoup de swap : c'est la trace d'un pic
            // passé, pas un problème présent. Le dire évite l'inquiétude.
            liste.append(Conseil(
                id: "swap-residuel", symbol: "clock.arrow.circlepath", severity: 0,
                text: "\(Chiffre.octets(memory.swapUsed)) traînent encore sur le disque (swap), "
                    + "reste d'une charge passée. La mémoire respire de nouveau : rien à faire, "
                    + "le prochain redémarrage nettoiera."))
        }

        // MARK: Une application qui monopolise.

        if let app = gourmandeCPU, app.cpu >= 0.45 {
            liste.append(Conseil(
                id: "cpu-monopole", symbol: "cpu.fill", severity: 1,
                text: "\(app.name) prend \(Chiffre.part(app.cpu)) de la machine à lui seul. "
                    + (app.processes > 1 ? "Réparti sur \(app.processes) processus. " : "")
                    + "S'il n'est pas censé travailler, c'est lui qu'il faut regarder."))
        }

        if let app = gourmandeRAM, app.processes >= 20, app.memory > 2 << 30,
           memory.pression == .normale {
            liste.append(Conseil(
                id: "processus-nombreux", symbol: "square.stack.3d.up", severity: 0,
                text: "\(app.name) tient \(app.processes) processus pour \(Chiffre.octets(app.memory)). "
                    + "Chaque onglet ou fenêtre en ouvre un : en fermer quelques-uns se sent tout de suite."))
        }

        // MARK: Disque.

        if let disk = snapshot.disk {
            let libre = Double(disk.free) / Double(disk.total)
            if libre < 0.10 {
                liste.append(Conseil(
                    id: "disque-plein", symbol: "internaldrive.fill", severity: 2,
                    text: "Il ne reste que \(Chiffre.disque(disk.free)) sur \(disk.name) "
                        + "(\(Chiffre.part(libre))). En dessous de 10 %, macOS n'a plus de place "
                        + "pour la mémoire virtuelle : Purge récupère les artefacts de build."))
            } else if libre < 0.15 {
                liste.append(Conseil(
                    id: "disque-juste", symbol: "internaldrive", severity: 1,
                    text: "\(Chiffre.disque(disk.free)) libres sur \(disk.name). "
                        + "Purge sait où se cachent les gros artefacts de build."))
            }
        }

        // MARK: Chaleur — le processeur à fond finit toujours en ventilateurs.

        if snapshot.cpu.total >= 0.80 {
            liste.append(Conseil(
                id: "cpu-chaleur", symbol: "thermometer.high", severity: 1,
                text: "Les \(snapshot.cpu.cores) cœurs tournent à \(Chiffre.part(snapshot.cpu.total)). "
                    + "Le Mac va chauffer et les ventilateurs monter : c'est normal, "
                    + "FanControl montre jusqu'où."))
        }

        if liste.isEmpty {
            liste.append(Conseil(
                id: "calme", symbol: "checkmark.circle.fill", severity: 0,
                text: "Rien à signaler : le processeur a de la marge et la mémoire respire."))
        }

        return Array(liste.sorted { $0.severity > $1.severity }.prefix(3))
    }
}
