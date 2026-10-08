# Éveil

Empêcher le Mac de s'endormir, avec une fin prévue.

macOS ne propose que « empêcher la veille automatique lorsque l'écran est
éteint », sur secteur, tout ou rien, enfoui dans les réglages de batterie. Et
`caffeinate` en ligne de commande n'a pas d'interface, donc pas de moyen de
savoir s'il tourne encore.

Ici : une durée (30 min, 1 h, 2 h, 4 h, sans limite), le temps restant lisible
dans la barre de menus, et deux façons de finir proprement — l'échéance, ou la
fermeture d'une app qu'on désigne. Lancer un long build et choisir « tant que
Xcode tourne » suffit.

Deux modes, parce qu'ils ne servent pas à la même chose :

| | |
|---|---|
| **Veille système bloquée** (défaut) | pour un build, un téléchargement, un rendu. L'écran s'éteint normalement. |
| **Écran allumé aussi** | pour une présentation, une lecture, un tableau de bord. |

## Construction

```sh
./build.sh              # → build/Eveil.app
./build.sh --install    # → /Applications, et lance
```

## Détails d'implémentation

L'app pose une assertion d'alimentation IOKit — exactement celle que pose
`caffeinate`. Elle apparaît donc dans `pmset -g assertions` et le système la
traite comme n'importe quelle autre : rien n'est contourné, rien n'est bricolé.

`kIOPMAssertionTypePreventUserIdleSystemSleep` pour la veille système,
`kIOPMAssertionTypeNoDisplaySleep` quand on veut aussi garder l'écran. Changer
de mode en cours de session relâche l'assertion et en repose une : son type est
fixé à sa création.

L'assertion est relâchée à la fermeture de l'app — et si l'app est tuée, le
système la relâche pour elle. Aucun moyen de laisser la machine éveillée par
accident.
