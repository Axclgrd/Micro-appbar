# Purge

Récupère l'espace disque pris par les artefacts de build — et dit, pour chaque
ligne, ce que la suppression coûte.

Ce n'est pas un nettoyeur. Un nettoyeur promet des gigaoctets et laisse deviner
ce qu'il efface. Ici, chaque élément trouvé répond à trois questions avant
qu'on coche quoi que ce soit :

- **Ce que c'est** — le rôle de ce dossier pour l'outil qui l'a créé.
- **Ce que ça casse** — l'effet immédiat de la suppression, s'il y en a un.
- **Comment ça revient** — la commande exacte, déduite du projet (`pnpm install`
  si le lock file est celui de pnpm, jamais `npm install` par défaut).

Trois verdicts, et c'est le verdict qui décide de ce qui est coché d'avance :

| | |
|---|---|
| **Sans impact** | l'outil régénère tout seul. Coché par défaut. |
| **À reconstruire** | il faut relancer une commande, souvent avec du réseau. |
| **À vérifier** | le contenu n'est peut-être pas régénérable. Jamais coché d'avance. |

## Construction

```sh
./build.sh              # → build/Purge.app
./build.sh --install    # → /Applications, et lance
```

## Ce qu'il cherche

Dans les dossiers qu'on lui donne : `node_modules`, `.next`, `.nuxt`,
`.svelte-kit`, `.astro`, `.turbo`, `.parcel-cache`, `.expo`, `.build` (SwiftPM),
`target` (Cargo), `Pods`, `.gradle`, `.venv`, `__pycache__`, `.pytest_cache`,
`.ruff_cache`, `.mypy_cache`, `.terraform`, `vendor` (Composer), `dist`.

Aux emplacements fixes : DerivedData, iOS DeviceSupport, caches de Homebrew,
npm, pnpm, Yarn, pip, Go, Gradle, Cargo, TypeScript et Playwright.

Un motif ne compte que si le contexte le confirme : `target` n'est un artefact
Rust que s'il y a un `Cargo.toml` à côté, `node_modules` n'est un artefact npm
que s'il y a un `package.json`. Sinon, c'est le dossier de travail de quelqu'un.

## Détails d'implémentation

**Deux temps.** Repérer les dossiers prend quelques dizaines de millisecondes ;
les peser prend des minutes. Le repérage donne donc immédiatement le nombre
d'éléments, puis la pesée avance en parallèle et publie chaque résultat dès
qu'il tombe.

**Découpe adaptative.** Un seul dossier peut monopoliser toute l'analyse — le
magasin pnpm dépasse le million de fichiers. Sa ramification utile étant trois
niveaux plus bas (`store/v10/files/00…ff`), le scanner descend jusqu'à avoir de
quoi occuper tous les fils au lieu de se fier à la forme du premier niveau. Sur
50 Go d'artefacts, l'analyse passe de 1 min 41 à 20 s.

**Les magasins pnpm sont jugés un par un.** pnpm en sème plusieurs au fil des
ans : l'emplacement par défaut a changé (`~/.pnpm-store` puis
`~/Library/pnpm/store`), le format aussi (`v3` puis `v10`), et un magasin
supplémentaire apparaît à la racine du disque des projets quand celui qui est
configuré vit sur un autre volume. Purge lit `store-dir` dans la configuration
de pnpm, compare format et emplacement, et classe chacun : *sans impact* pour un
format qu'aucune version de pnpm ne lit plus, *à vérifier* pour un magasin au
bon format mais hors de l'emplacement configuré, *à reconstruire* pour le seul
qui serve encore.

**Liens durs.** Quand le magasin pnpm vit sur le même volume que les projets,
ses fichiers *sont* ceux des `node_modules` : les compter deux fois
promettrait un espace impossible à rendre. Chaque élément indique donc sa part
partagée, et le pied de fenêtre prévient quand la sélection en contient.

**Taille allouée, pas taille logique.** C'est l'espace qu'on récupère
réellement, blocs partiels et forks compris. Sur un `node_modules`, l'écart se
compte en centaines de mégaoctets.

**La suppression est définitive** et ne passe pas par la corbeille : sur un
disque presque plein, un déplacement vers la corbeille ne rend rien. Elle est
confirmée par une boîte de dialogue, et tout chemin trop court pour être autre
chose qu'une racine est refusé par `Deleter`, quoi qu'il arrive en amont.
