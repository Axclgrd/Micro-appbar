# Éjecter

Éjection propre des disques externes, depuis la barre de menus.

Ce que macOS ne fait pas, et que celui-ci fait :

- **Dire qui bloque.** Quand l'éjection échoue, le système affiche « le disque
  n'a pas été éjecté » et s'arrête là. Ici, les processus fautifs sont listés
  avec le fichier qu'ils tiennent ouvert, et un bouton pour les fermer.
- **Distinguer démonter et éjecter.** « Éjecter » retire le périphérique : il
  faut débrancher-rebrancher pour le revoir. « Démonter » libère les volumes en
  laissant le disque alimenté — il se remonte d'un clic.
- **Remonter un disque en veille.** Un disque branché mais non monté n'apparaît
  nulle part dans le Finder. Il apparaît ici, avec son bouton.
- **Voir les images disque oubliées.** Les `.dmg` d'installeurs montés en
  `nobrowse` sont invisibles du Finder, et restent montés des semaines.

## Construction

```sh
./build.sh              # → build/Ejecter.app
./build.sh --install    # → /Applications, et lance
```

Aucune dépendance, aucun privilège : tout ce que fait l'app, l'utilisateur
connecté a déjà le droit de le faire.

## Détails d'implémentation

**On éjecte un disque, pas un volume.** Sur un disque APFS externe,
`/Volumes/X` est un volume (`disk7s1`) d'un conteneur synthétisé (`disk7`) posé
sur une partition (`disk6s2`) du disque physique (`disk6`). L'app remonte cette
chaîne via `diskutil list -plist external` pour agir sur le bon nœud.

**`diskutil` plutôt que DiskArbitration**, parce que c'est la seule source qui
voie aussi les disques branchés mais démontés — précisément l'état qu'on veut
pouvoir défaire.

**Limite connue** : sans privilège root, `lsof` ne voit pas les processus des
autres utilisateurs. Un blocage par Spotlight (`mds_stores`) ou Time Machine
donne donc une liste vide ; l'interface le dit au lieu de laisser croire que
personne ne tient le disque.
