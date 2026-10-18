# Micro-app — guide d'installation pour Claude

Ce dépôt contient une suite de petits utilitaires macOS (Swift/SwiftUI, sans dépendance).
Quand l'utilisateur te demande « installe les apps » sur un Mac, suis ce guide. Réponds en français.

## Les apps

| Dossier | App | Rôle | macOS min | Particularité |
|---|---|---|---|---|
| `trousse` | Trousse | Barre de menus centrale qui regroupe les outils | **26** | Optionnelle, les autres restent autonomes |
| `fancontrole` | FanControl | Températures SMC + ventilateurs | 14 | **Démon root**, dépend du Mac (voir plus bas) |
| `ejecter` | Ejecter | Éjection propre des disques | 14 | Autorisation Accès complet au disque possible |
| `purge` | Purge | Libère l'espace des artefacts de build | 14 | |
| `eveil` | Eveil | Empêche la veille avec une fin prévue | 14 | |
| `grab` | Grab | Sélection écran → OCR → presse-papier | 14 | Enregistrement d'écran + raccourci |
| `fonte` | Fonte | Sélection écran → police reconnue par Claude, vérifiée sur les vraies polices | 14 | Enregistrement d'écran + raccourci, exige Claude Code et le réseau (Google Fonts, Fontshare) |
| `jauge` | Jauge | Consommation de l'abonnement Claude (session 5 h, semaine) et alertes | 14 | Branche la ligne d'état de Claude Code (voir étape 7) |
| `ports` | Ports | Qui tourne sur le port 3000 | 14 | |
| `bande` | Bande | Vidéo → audio / transcription locale | 14 | |
| `etagere` | Etagere | Tablette de fichiers sous l'encoche | 14 | Plutôt pour un Mac avec encoche |

`Kits/` contient les bibliothèques partagées : ne jamais déplacer un dossier d'app hors du dépôt, les `Package.swift` pointent vers `../Kits`.

## Procédure

1. **Profil du Mac** : lance `./scripts/diagnostic.sh` et lis le résultat en entier.
2. **Prérequis** : si les Command Line Tools manquent, `xcode-select --install` (l'utilisateur valide la fenêtre), puis relance le diagnostic.
3. **Choix des apps** : propose la liste adaptée à ce Mac et demande confirmation si un doute existe (voir « Adaptation »). Ne demande pas pour ce qui est évident.
4. **Plan** : `./install.sh --simulation` pour montrer ce qui sera fait.
5. **Installation** : `./install.sh` (ou `./install.sh grab ports`, ou `./install.sh --sans etagere`). Aucun sudo n'est nécessaire.
6. **Ventilateurs** : si FanControl est installé, `./fancontrole/install.sh` demande un mot de passe admin. **Ne le lance pas toi-même** : il exige un vrai terminal (TTY) et échoue depuis un shell d'outil. Dis à l'utilisateur de taper `! ./fancontrole/install.sh` ou de l'ouvrir dans Terminal.app.
7. **Autorisations** (Réglages système › Confidentialité) : à guider à la main, aucune ne s'accorde par script.
   - Grab : Enregistrement d'écran, Accessibilité si le raccourci global ne répond pas.
   - Ejecter / Purge : Accès complet au disque si des dossiers sont refusés.
   - Fonte : Enregistrement d'écran. L'analyse passe par Claude Code (`claude -p`), qui doit être connecté : lance `claude` une fois dans Terminal si Fonte signale un refus.
   - Jauge : demande l'accord de l'utilisateur, puis `/Applications/Jauge.app/Contents/MacOS/Jauge --brancher`. Cela ajoute `statusLine` à `~/.claude/settings.json` (copie gardée dans `settings.json.avant-jauge`) ; si une autre ligne d'état existe, Jauge refuse d'y toucher. Notifications : à autoriser au premier lancement.
8. **Vérification** : relance `./scripts/diagnostic.sh`, toutes les apps voulues doivent apparaître cochées. Vérifie qu'elles sont lancées dans la barre de menus.

## Pièges connus

1. **Signature ad hoc silencieuse.** Si `build.sh` affiche `⚠️ identité indisponible`, le trousseau `microapp.keychain-db` n'est pas dans la search list. Sans identité stable, les autorisations sont perdues à chaque reconstruction. Correction :
   ```
   security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db" "$HOME/Library/Keychains/microapp.keychain-db"
   ```
   `./install.sh` le fait déjà, mais vérifie si le message apparaît. L'identité est créée par machine par `Tools/identite.sh` (trousseau et mot de passe locaux dans `~/Library/Keychains/`, jamais commités).
2. **Dossier avec espace** : le disque s'appelle parfois « My Passport ». Toujours mettre les chemins entre guillemets.
3. **Démon ventilateurs** : `fancontrold` tourne en root (LaunchDaemon `local.fancontrold`, socket `/var/run/fancontrold.sock`, journal `/var/log/fancontrold.log`). Retrait : `./fancontrole/uninstall.sh`, les ventilateurs repassent en auto.
4. **App déjà lancée** : `build.sh --install` ferme l'ancienne instance avant de remplacer le bundle, c'est normal.

## Adaptation selon le Mac

C'est ici que tu personnalises. Lis `diagnostic.sh` et décide :

- **MacBook Air** : aucun ventilateur. N'installe pas `fancontrole` (`install.sh` l'ignore déjà).
- **Mac sans encoche** (Mac mini, Mac Studio, iMac, MacBook Air/Pro avant 2021) : `etagere` est peu utile, propose de la sauter.
- **macOS < 26** : pas de `trousse` (verre liquide natif), les autres apps marchent dès macOS 14.
- **macOS < 14** : rien ne se compile, dis-le à l'utilisateur.
- **Intel** : non testé. Compile, mais FanControl s'appuie sur des clés SMC Apple Silicon. Préviens.

### Personnaliser FanControl pour ce Mac

Les ventilateurs se lisent par la SMC (clé `FNum` pour le nombre, `F0Ac/F0Tg/F0Mn/F0Mx` pour vitesse, cible, min, max). Le **nombre de ventilateurs et leurs bornes RPM** sont donc détectés tout seuls. En revanche les **clés de température** sont écrites pour un MacBook Pro M2 Pro dans `Kits/SMCKit/Sources/SMCKit/Thermal.swift` (`performanceCoreKeys`, `efficiencyCoreKeys`, `gpuKeys`, `batteryKeys`, `chassisKeys`). Le code ne garde que les clés présentes, mais une puce différente (M3, M4, Ultra…) peut avoir d'autres noms.

Marche à suivre :
1. Installe et lance FanControl, ouvre le menu. Si des groupes de températures manquent ou sont à zéro, c'est le signe de clés absentes.
2. Liste les clés SMC réelles du Mac (en lecture seule, via `SMCKit`) : cherche celles qui commencent par `Tp`, `Te`, `Tg`, `TB`, `Ts`, et note lesquelles retournent une valeur entre 5 et 115 °C.
3. Ajoute-les aux tableaux de `Thermal.swift` (n'enlève jamais les anciennes, elles servent aux autres Mac), puis `cd fancontrole && ./build.sh --install`.
4. Seuils : `Frais <60`, `Normal <75`, `Tiède <90`, `Chaud <100`, `Throttling ≥100` °C. Un Mac Studio refroidit mieux qu'un portable, ajuste seulement si l'utilisateur le demande.
5. Presets du curseur (`FanPanel.swift`) : Silencieux 0 %, Équilibré 35 %, Frais 65 %, Max 100 % de la plage min→max du Mac. Modifie les ratios selon la préférence (« je veux plus silencieux » → baisse Équilibré).

Les apps n'écrivent jamais dans la SMC sans le démon, et le démon remet le mode auto à l'arrêt (SIGTERM). Ne contourne pas ce comportement.

## Règles pour Claude

- Les builds se font sur le Mac cible, jamais d'app compilée commitée (`build/` et `.build/` sont ignorés).
- Ne modifie pas les `build.sh` ni `Tools/identite.sh` pour une particularité d'une machine : l'écart est local (trousseau, autorisations).
- Ne publie rien (push, release) sans demande explicite de l'utilisateur.
- Après toute personnalisation, rebuild l'app concernée seulement, pas tout.
- En cas d'échec de build, montre l'erreur réelle de `swift build` et ne retombe pas sur une signature ad hoc sans le dire.

## Design

Toute modification d'interface suit le skill `.claude/skills/apple-hig/` (HIG d'Apple + Liquid Glass, sources en texte exact dans `sources/`) et le vocabulaire partagé `Kits/Commun/Sources/Commun/Design.swift`. Le verre n'est utilisé que sur la couche fonctionnelle, avec repli matériau avant macOS 26.
