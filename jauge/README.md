# Jauge

La consommation de ton abonnement Claude, sans ouvrir `/usage` : la session de
5 h et la semaine, en deux anneaux, avec le pourcentage de la session en badge
dans la barre de menus.

- **Remise à zéro** : dans combien de temps, et à quelle heure.
- **Rythme** : « à ce rythme, pleine vers 17 h 40 », calculé sur les 45
  dernières minutes de la session.
- **Alertes** : une notification à 80, 90 et 100 %, pour la session comme pour
  la semaine, une seule fois par seuil et par fenêtre. Et une autre quand une
  session presque pleine repart à zéro.

## D'où viennent les chiffres

Claude Code reçoit de l'API, à chaque réponse, l'état des limites du compte, et
le passe à sa **ligne d'état** (`rate_limits.five_hour`, `rate_limits.seven_day`).
Jauge se branche là : Claude Code appelle `Jauge --statusline`, qui garde le
relevé dans `~/Library/Application Support/Micro-app/Jauge/usage.json` et rend
la ligne affichée sous le prompt (`Session 42 % · semaine 61 % · Opus 5.5`).

Ce sont donc les vrais pourcentages du compte, pas une estimation à partir de
tokens comptés. Pas de jeton lu dans le trousseau, pas d'appel réseau, pas de
sondage : l'app surveille le dossier et ne se réveille que quand Claude Code y
écrit. Contrepartie assumée : la jauge bouge quand Claude Code sert. Une fenêtre
dont l'heure de remise est passée s'affiche à zéro en attendant le relevé
suivant.

## Branchement

```sh
./build.sh --install
/Applications/Jauge.app/Contents/MacOS/Jauge --brancher
```

`--brancher` ajoute `statusLine` à `~/.claude/settings.json` et garde l'ancien
fichier dans `settings.json.avant-jauge`. Si une autre ligne d'état est déjà
réglée, Jauge refuse d'y toucher et le dit. Le panneau propose aussi le bouton
« Brancher Claude Code » tant que ce n'est pas fait.
