import Commun
import Foundation

/// Ce qui se passe si on supprime. C'est la seule chose qui compte pour
/// décider, donc la seule qu'on met en avant.
enum Impact: Int, Sendable, Hashable, Comparable {
    /// L'outil régénère tout seul, sans qu'on ait à y penser.
    case none
    /// Il faut relancer une commande, et souvent télécharger.
    case rebuild
    /// À regarder avant de cocher : le contenu peut ne pas être régénérable.
    case care

    static func < (lhs: Impact, rhs: Impact) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .none:    return "Sans impact"
        case .rebuild: return "À reconstruire"
        case .care:    return "À vérifier"
        }
    }

    /// Reprend l'échelle de gravité de fancontrole : vert, jaune, orange.
    var severity: Int {
        switch self {
        case .none:    return 1
        case .rebuild: return 2
        case .care:    return 3
        }
    }
}

/// Un motif d'artefact reconnu, et tout ce qu'on sait en dire.
///
/// Les trois phrases (`what`, `breaks`, `recovery`) ne sont pas de la
/// documentation : ce sont elles qui remplacent la question « est-ce que je
/// peux supprimer ça ? ». Une règle sans elles n'a rien à faire ici.
struct Rule: Identifiable, Sendable, Hashable {
    let id: String
    /// Nom exact du dossier à reconnaître.
    let directory: String
    /// Fichiers frères qui prouvent le contexte. Un dossier `target` n'est un
    /// artefact Rust que s'il y a un `Cargo.toml` à côté ; ailleurs, c'est le
    /// dossier de travail de quelqu'un.
    let siblings: [String]
    let impact: Impact
    let what: String
    let breaks: String
    let recovery: String

    func matches(directoryAt url: URL) -> Bool {
        guard url.lastPathComponent == directory else { return false }
        guard !siblings.isEmpty else { return true }
        let parent = url.deletingLastPathComponent()
        return siblings.contains {
            FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path)
        }
    }
}

enum Catalog {

    /// Motifs cherchés dans les dossiers de projets.
    static let project: [Rule] = [
        Rule(id: "node_modules", directory: "node_modules", siblings: ["package.json"],
             impact: .rebuild,
             what: "Les dépendances installées du projet, telles que npm, pnpm ou yarn les a écrites sur le disque.",
             breaks: "Le projet ne démarre plus et ne compile plus tant que les dépendances ne sont pas réinstallées.",
             recovery: "Une réinstallation depuis le lock file. Il faut du réseau, et quelques minutes."),

        Rule(id: "next", directory: ".next", siblings: ["package.json"],
             impact: .none,
             what: "Le cache de compilation de Next.js : pages compilées, bundles, images optimisées.",
             breaks: "Rien. Le prochain démarrage est simplement plus lent, le temps de recompiler.",
             recovery: "Se recrée tout seul au prochain `next dev` ou `next build`."),

        Rule(id: "nuxt", directory: ".nuxt", siblings: ["package.json"],
             impact: .none,
             what: "Le dossier de travail de Nuxt, régénéré à chaque démarrage.",
             breaks: "Rien.",
             recovery: "Recréé au prochain lancement du serveur de développement."),

        Rule(id: "sveltekit", directory: ".svelte-kit", siblings: ["package.json"],
             impact: .none,
             what: "Le dossier généré par SvelteKit : types, manifeste, sortie intermédiaire.",
             breaks: "Rien.",
             recovery: "Recréé au prochain `vite dev` ou `svelte-kit sync`."),

        Rule(id: "astro", directory: ".astro", siblings: ["package.json"],
             impact: .none,
             what: "Le cache d'Astro : types générés et métadonnées de contenu.",
             breaks: "Rien.",
             recovery: "Recréé au prochain démarrage."),

        Rule(id: "turbo", directory: ".turbo", siblings: ["package.json"],
             impact: .none,
             what: "Le cache de Turborepo, qui évite de refaire deux fois la même tâche.",
             breaks: "Rien. Les tâches déjà faites seront refaites une fois.",
             recovery: "Se remplit tout seul à la prochaine exécution."),

        Rule(id: "parcel", directory: ".parcel-cache", siblings: ["package.json"],
             impact: .none,
             what: "Le cache du bundler Parcel.",
             breaks: "Rien. Premier build plus lent.",
             recovery: "Recréé au prochain build."),

        Rule(id: "expo", directory: ".expo", siblings: ["package.json"],
             impact: .none,
             what: "L'état local d'Expo : cache du bundler et métadonnées de l'appareil de test.",
             breaks: "Rien côté code. Il faudra rescanner le QR code au prochain lancement.",
             recovery: "Recréé au prochain `expo start`."),

        Rule(id: "swiftpm", directory: ".build", siblings: ["Package.swift"],
             impact: .none,
             what: "Le dossier de compilation de SwiftPM : objets, binaires, dépendances clonées.",
             breaks: "Rien. Le prochain `swift build` repart de zéro.",
             recovery: "Recompilation complète, plus le reclonage des dépendances s'il y en a."),

        Rule(id: "cargo", directory: "target", siblings: ["Cargo.toml"],
             impact: .none,
             what: "Le dossier de compilation de Cargo. C'est presque toujours le plus gros d'un projet Rust.",
             breaks: "Rien.",
             recovery: "Recompilation complète au prochain `cargo build`, sans réseau (le registre est ailleurs)."),

        Rule(id: "pods", directory: "Pods", siblings: ["Podfile"],
             impact: .rebuild,
             what: "Les dépendances CocoaPods installées dans le projet Xcode.",
             breaks: "Le projet Xcode ne compile plus : les pods référencés sont absents.",
             recovery: "`pod install` dans le dossier du projet. Réseau nécessaire."),

        Rule(id: "gradle", directory: ".gradle", siblings: ["build.gradle", "build.gradle.kts", "settings.gradle"],
             impact: .none,
             what: "L'état local de Gradle pour ce projet : caches de configuration et démons.",
             breaks: "Rien.",
             recovery: "Recréé au prochain build. La première compilation sera plus longue."),

        Rule(id: "venv", directory: ".venv", siblings: ["requirements.txt", "pyproject.toml", "setup.py"],
             impact: .rebuild,
             what: "L'environnement virtuel Python du projet, avec ses paquets installés.",
             breaks: "Les commandes du projet ne trouvent plus leurs dépendances.",
             recovery: "Recréer l'environnement puis réinstaller les paquets. Réseau nécessaire."),

        Rule(id: "pycache", directory: "__pycache__", siblings: [],
             impact: .none,
             what: "Le bytecode Python compilé, écrit à côté de chaque module.",
             breaks: "Rien.",
             recovery: "Réécrit automatiquement au prochain import."),

        Rule(id: "pytest", directory: ".pytest_cache", siblings: [],
             impact: .none,
             what: "Le cache de pytest : derniers échecs, durées de test.",
             breaks: "Rien.",
             recovery: "Recréé à la prochaine exécution des tests."),

        Rule(id: "ruff", directory: ".ruff_cache", siblings: [],
             impact: .none,
             what: "Le cache de l'analyseur Ruff.",
             breaks: "Rien.",
             recovery: "Recréé à la prochaine analyse."),

        Rule(id: "mypy", directory: ".mypy_cache", siblings: [],
             impact: .none,
             what: "Le cache d'analyse de types de mypy.",
             breaks: "Rien.",
             recovery: "Recréé à la prochaine analyse."),

        Rule(id: "terraform", directory: ".terraform", siblings: ["main.tf"],
             impact: .rebuild,
             what: "Les fournisseurs et modules téléchargés par Terraform.",
             breaks: "Plus aucune commande Terraform ne fonctionne dans ce dossier.",
             recovery: "`terraform init`. Réseau nécessaire. L'état distant n'est pas touché."),

        Rule(id: "composer", directory: "vendor", siblings: ["composer.json"],
             impact: .rebuild,
             what: "Les dépendances PHP installées par Composer.",
             breaks: "Le projet ne s'exécute plus : l'autoloader est absent.",
             recovery: "`composer install`. Réseau nécessaire."),

        // Volontairement classé « à vérifier » : c'est le seul motif de cette
        // liste dont le contenu peut être la seule copie de quelque chose.
        Rule(id: "dist", directory: "dist", siblings: ["package.json"],
             impact: .care,
             what: "Le résultat d'un build. Souvent régénérable — mais c'est aussi, parfois, exactement ce qui est déployé ou publié.",
             breaks: "Rien si le build est reproductible. Tout, si ce dossier était la seule copie de la version en ligne.",
             recovery: "Relancer le build du projet. À ne cocher qu'après avoir vérifié que c'est bien le cas."),
    ]

    /// Emplacements fixes, hors des projets. Chemins relatifs au dossier
    /// personnel : l'app ne va jamais chercher ailleurs.
    static let caches: [(path: String, rule: Rule)] = [
        ("Library/Developer/Xcode/DerivedData",
         Rule(id: "deriveddata", directory: "DerivedData", siblings: [], impact: .none,
              what: "Les produits de compilation de tous les projets Xcode déjà ouverts. Le plus gros gisement d'espace d'un Mac de développeur.",
              breaks: "Rien. Xcode recompile au prochain build.",
              recovery: "Recréé automatiquement, projet par projet.")),

        ("Library/Developer/Xcode/iOS DeviceSupport",
         Rule(id: "devicesupport", directory: "iOS DeviceSupport", siblings: [], impact: .care,
              what: "Les symboles système des iPhone et iPad que tu as branchés, une version par appareil.",
              breaks: "Rien tout de suite. Au prochain branchement, Xcode reste bloqué plusieurs minutes sur « Preparing debugger support ».",
              recovery: "Retéléchargé depuis l'appareil au branchement suivant.")),

        ("Library/Developer/CoreSimulator/Caches",
         Rule(id: "simcaches", directory: "CoreSimulator/Caches", siblings: [], impact: .none,
              what: "Les caches des simulateurs iOS.",
              breaks: "Rien.",
              recovery: "Recréés au prochain lancement d'un simulateur.")),

        ("Library/Caches/Homebrew",
         Rule(id: "brew", directory: "Homebrew", siblings: [], impact: .none,
              what: "Les archives téléchargées par Homebrew lors des installations et mises à jour.",
              breaks: "Rien. Les paquets installés ne sont pas touchés.",
              recovery: "Retéléchargé à la prochaine installation.")),

        (".npm/_cacache",
         Rule(id: "npmcache", directory: "_cacache", siblings: [], impact: .none,
              what: "Le cache de téléchargement de npm, partagé par tous les projets.",
              breaks: "Rien. Les node_modules installés ne sont pas touchés.",
              recovery: "Se remplit à nouveau au prochain `npm install`.")),

        ("Library/Caches/Yarn",
         Rule(id: "yarncache", directory: "Yarn", siblings: [], impact: .none,
              what: "Le cache de téléchargement de Yarn.",
              breaks: "Rien.",
              recovery: "Se remplit à nouveau à la prochaine installation.")),

        ("Library/Caches/go-build",
         Rule(id: "gobuild", directory: "go-build", siblings: [], impact: .none,
              what: "Le cache de compilation de Go.",
              breaks: "Rien. La prochaine compilation sera plus lente.",
              recovery: "Recréé automatiquement.")),

        ("Library/Caches/pip",
         Rule(id: "pipcache", directory: "pip", siblings: [], impact: .none,
              what: "Le cache de téléchargement de pip.",
              breaks: "Rien.",
              recovery: "Se remplit à nouveau au prochain `pip install`.")),

        ("Library/Caches/ms-playwright",
         Rule(id: "playwright", directory: "ms-playwright", siblings: [], impact: .care,
              what: "Les navigateurs complets téléchargés par Playwright — Chromium, Firefox, WebKit.",
              breaks: "Les tests Playwright échouent tant que les navigateurs ne sont pas réinstallés.",
              recovery: "`npx playwright install`. Environ un gigaoctet à retélécharger.")),

        ("Library/Caches/typescript",
         Rule(id: "tscache", directory: "typescript", siblings: [], impact: .none,
              what: "Les définitions de types téléchargées automatiquement par l'éditeur.",
              breaks: "Rien.",
              recovery: "Retéléchargées à la demande.")),

        (".gradle/caches",
         Rule(id: "gradlecaches", directory: "caches", siblings: [], impact: .rebuild,
              what: "Le cache global de Gradle : dépendances Java et Android téléchargées.",
              breaks: "Rien tout de suite, mais le prochain build repart de zéro.",
              recovery: "Retéléchargé au prochain build. Réseau nécessaire, et c'est long.")),

        (".cargo/registry/cache",
         Rule(id: "cargocache", directory: "cache", siblings: [], impact: .none,
              what: "Les archives des crates téléchargées par Cargo.",
              breaks: "Rien.",
              recovery: "Retéléchargées à la prochaine compilation qui en a besoin.")),
    ]

    // MARK: Magasins pnpm

    /// Où en est un magasin pnpm donné.
    enum StoreState: Sendable {
        /// Celui que pnpm utilise aujourd'hui.
        case active
        /// Format abandonné : un magasin plus récent existe à côté.
        case oldFormat(newest: String)
        /// Bon format, mais pas là où `store-dir` pointe.
        case elsewhere(configured: String)
    }

    /// Un magasin pnpm n'est pas un motif fixe : c'est un cas d'espèce.
    ///
    /// pnpm en sème plusieurs au fil des ans — l'emplacement par défaut a
    /// changé, le format aussi, et un magasin supplémentaire apparaît sur le
    /// disque des projets quand celui qui est configuré vit ailleurs. Les
    /// classer tous « à reconstruire » serait faux : la plupart sont morts et
    /// plus personne ne peut s'en servir. On juge donc chacun sur son format et
    /// son emplacement, et le texte le dit.
    static func pnpmStore(display: String, version: String, state: StoreState) -> Rule {
        switch state {
        case .active:
            return Rule(
                id: "pnpm-\(display)", directory: display, siblings: [], impact: .rebuild,
                what: "Le magasin pnpm actif (format \(version)) : une seule copie de chaque version de chaque paquet, partagée par tous les projets.",
                breaks: "Rien pour les projets déjà installés — leurs node_modules restent en place.",
                recovery: "Toute nouvelle installation retélécharge depuis le réseau. `pnpm store prune` fait le même ménage en ne retirant que ce que plus aucun projet n'utilise : à essayer avant de tout supprimer.")

        case .oldFormat(let newest):
            return Rule(
                id: "pnpm-\(display)", directory: display, siblings: [], impact: .none,
                what: "Un magasin pnpm au format \(version), laissé en place par une ancienne version de pnpm. Un magasin \(newest) existe à côté.",
                breaks: "Rien. pnpm ne lit que le format le plus récent : celui-ci n'est plus adressable par aucune commande.",
                recovery: "Rien à reconstruire — ce format appartient à une version de pnpm qui n'est plus installée.")

        case .elsewhere(let configured):
            return Rule(
                id: "pnpm-\(display)", directory: display, siblings: [], impact: .care,
                what: "Un magasin pnpm au format courant, mais hors de l'emplacement configuré (\(configured)). Reliquat d'un ancien réglage, ou magasin créé automatiquement sur le disque des projets.",
                breaks: "Rien si plus aucun projet n'y renvoie. La ligne « dont partagés » le dit sans ambiguïté : à zéro, aucun node_modules de ce disque n'est relié à ce magasin.",
                recovery: "Si un projet s'en servait encore, sa prochaine installation retéléchargera ses paquets.")
        }
    }
}
