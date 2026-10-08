# Grab

Un raccourci, une zone à l'écran, et le texte est dans le presse-papier.

macOS sait lire le texte d'une image depuis Sequoia — mais il faut d'abord
prendre la capture, l'ouvrir dans Aperçu, sélectionner, copier. Quatre gestes
là où il en faut un.

`⌥⇧⌘T` par défaut (modifiable dans le panneau parmi quatre combinaisons). La
sélection est celle du système : même croix, espace pour viser une fenêtre,
Échap pour annuler.

## Construction

```sh
./build.sh              # → build/Grab.app
./build.sh --install    # → /Applications, et lance
```

Au premier usage, macOS demande l'autorisation d'enregistrement de l'écran. Il
faut la donner puis relancer l'app — c'est le fonctionnement du système, pas un
oubli.

## Deux choix qui comptent

**La correction linguistique est désactivée par défaut.** Vision sait rattraper
les mots abîmés d'un texte de prose, mais ce qu'on capture à l'écran c'est le
plus souvent du code, un identifiant, un message d'erreur — et là, la correction
réécrit. Le réglage est dans le panneau, avec ce qu'il change dit en une phrase.

**La sélection est déléguée à `screencapture`.** C'est l'outil du système : même
comportement multi-écran, mêmes touches, aucune surprise. Réécrire une sélection
maison serait plus long, moins bon, et dépaysant.

## Détails d'implémentation

Le raccourci global passe par Carbon (`RegisterEventHotKey`). C'est daté, mais
c'est la seule API publique qui capte une combinaison hors premier plan sans
autorisation d'accessibilité. L'alternative — un moniteur global `NSEvent` —
demanderait à l'utilisateur de confier la lecture de *toutes* ses frappes pour
une seule combinaison.

L'ordre des lignes est celui rendu par Vision, qui suit déjà le sens de lecture.
Un tri maison par ordonnée paraît plus rigoureux mais casse les tableaux, où
deux cellules d'une même ligne n'ont pas exactement la même hauteur.
