# Micro-app

Petits utilitaires macOS en Swift + SwiftUI, sans dépendance : ventilateurs, éjection de disques,
espace disque, veille, OCR, ports, audio, étagère de fichiers, le tout regroupé dans une barre de menus (Trousse).
Voir [ROADMAP.md](ROADMAP.md) pour le détail de chaque outil.

## Installation avec Claude (recommandé)

```
git clone <url-du-depot> Micro-app
cd Micro-app
claude
```

Puis dis : **« installe les Micro-app sur ce Mac »**. Claude lit [CLAUDE.md](CLAUDE.md), analyse le Mac
(modèle, puce, macOS, ventilateurs), choisit les apps adaptées, les compile, les signe et te guide
pour les autorisations. Il adapte aussi FanControl aux capteurs de ton Mac.

## Installation à la main

Prérequis : macOS 14+ (26+ pour Trousse), Command Line Tools (`xcode-select --install`).

```
./scripts/diagnostic.sh        # profil du Mac
./install.sh --simulation      # le plan
./install.sh                   # tout ce qui est compatible
./install.sh grab ports        # seulement certaines apps
./fancontrole/install.sh       # démon ventilateurs, dans un vrai Terminal
```
