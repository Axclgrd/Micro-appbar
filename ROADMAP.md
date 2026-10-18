# Micro-app

Petits utilitaires macOS, un par dossier. Même identité : Swift + SwiftUI, verre
liquide, aucune dépendance, un `build.sh` qui produit un `.app` signé ad hoc.

Principe : chaque outil comble un manque réel de macOS, tient en quelques
centaines de lignes, et ne tourne que quand on le regarde.

## Fait

- [x] **fancontrole** — températures SMC et pilotage des ventilateurs (barre de menus + démon root)
- [x] **ejecter** — éjection propre des disques externes, dit *qui* bloque et remonte sans débrancher
- [x] **purge** — récupère l'espace disque des artefacts de build, en expliquant l'impact de chaque suppression
- [x] **eveil** — empêcher la veille, avec une fin prévue : durée, ou fermeture d'une app désignée
- [x] **grab** — raccourci → sélection à l'écran → texte OCR dans le presse-papier
- [x] **jauge** — la consommation de l'abonnement Claude, session de 5 h et semaine,
      en anneaux et en badge dans la barre de menus, avec le rythme (« pleine vers
      17 h 40 ») et des alertes à 80, 90 et 100 %. Les chiffres viennent de la ligne
      d'état de Claude Code, ou d'un relevé Haiku minuscule (0,0002 $) quand elle se tait.
- [x] **fonte** — raccourci → sélection à l'écran → Claude reconnaît la police : propositions
      classées avec leur probabilité, les lettres qui les désignent, un aperçu dans la
      vraie police, et sur demande une vérification ligne sous ligne contre les fichiers
      de Google Fonts et Fontshare. L'analyse passe par
      Claude Code, déjà présent sur chaque Mac de la famille : aucune clé à saisir.
- [x] **trousse** — l'app centrale : elle tient la barre du haut, on y compose les
      groupes d'outils et ce qui reste masqué (macOS 26+, verre liquide natif).
      Les sept outils y sont entrés, et chacun garde son app autonome.
- [x] **ports** — qu'est-ce qui tourne sur le 3000 : le process, le projet, depuis
      quand, ce que l'arrêter coûte, et un QR pour ouvrir le site sur le téléphone
- [x] **transcription** — troisième sortie de `bande`, en tête et par défaut : une
      vidéo entre, le texte sort. Moteur de reconnaissance vocale local de macOS,
      rien qui quitte la machine, aucune autorisation. La langue est choisie en
      comparant la confiance des modèles installés, parce que suivre l'ordre du
      système transcrivait du français avec le modèle anglais.
- [x] **bande** — une vidéo entre, son audio sort : copie sans perte en `.m4a`, ou WAV 16 kHz prêt à transcrire
- [x] **étagère** — une tablette sous l'encoche : on monte un fichier, on lâche,
      il attend là à travers les apps, les bureaux et les redémarrages

## Ensuite

- [ ] **Micro** — mute micro global au raccourci, avec témoin en barre de menus
- [ ] **Teinte** — pipette avec historique, sortie hex / oklch / variable Tailwind
- [ ] **Finder** — bascules fichiers cachés, barre de chemin, `.DS_Store` off sur réseau, « terminal ici »

## En attente d'une décision

- [ ] **Épingle** — garder une fenêtre au-dessus des autres. **Pas faisable proprement** :
  macOS n'expose aucune API publique pour changer le niveau d'une fenêtre qui
  appartient à une autre app. `NSWindow.level` ne vaut que pour les siennes, et
  l'API d'accessibilité sait déplacer et redimensionner une fenêtre, pas la
  faire flotter. Restent deux voies, toutes deux coûteuses :
  API privées du serveur de fenêtres (`CGSSetWindowLevel`, cassable à chaque
  version de macOS), ou un miroir — une fenêtre flottante qui recopie en continu
  le contenu de la fenêtre visée, ce qui exige l'autorisation d'enregistrement
  d'écran et ne rend pas la copie cliquable.

## Plus tard

- [ ] **Média** — ce qui reste hors de portée d'AVFoundation : heic→webp, mov→gif,
      compression PDF, et la lecture des conteneurs que macOS ignore (mkv, webm).
      Demande ffmpeg embarqué — soixante-dix mégaoctets, à peser.
- [ ] **Résidus** — désinstalleur qui traque ce qui reste dans `~/Library`
- [ ] **Réveil** — qui consomme le réseau, et quel process réveille le Mac la nuit (`pmset -g log`)

## Écarté (déjà natif)

Historique du presse-papier (Spotlight sur Tahoe), tuilage de fenêtres,
renommage par lot dans le Finder, gestionnaire de mots de passe, Live Text.

**Batterie** rejoint cette liste : la limite de charge est native sur Apple
Silicon, et les cycles comme la santé sont dans Réglages système › Batterie.

## Conventions

| | |
|---|---|
| Cible | macOS 14+, Swift 6, SwiftPM sans dépendance |
| Construction | `./build.sh` → `build/Nom.app`, `./build.sh --install` → `/Applications` |
| Icône | générée par code dans `Tools/makeicon.swift` (squircle + verre teinté) |
| Barre de menus | `LSUIElement`, panneau de 300 pt, sondage ralenti quand le panneau est fermé |
| Fenêtre | app classique quand l'outil demande à lire avant d'agir |
| Langue | interface et commentaires en français |
| Structure | `Kits/` tient les bibliothèques — un outil y est écrit une fois, `trousse` et son app autonome le consomment |
