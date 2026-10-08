# Étagère

Une tablette sous l'encoche, où poser ce qui n'a pas encore de place.

On attrape un fichier n'importe où, on monte vers le haut de l'écran, on lâche.
Il attend là — à travers les changements d'app, de bureau et les redémarrages —
jusqu'à ce qu'on le reprenne d'un glissé vers sa destination.

C'est la réponse au geste le plus bête de macOS : déplacer quelque chose entre
deux fenêtres qui ne sont jamais visibles en même temps. Pas un lecteur, pas des
widgets : une étagère.

## Construction

```sh
./build.sh              # → build/Etagere.app
./build.sh --install    # → /Applications, et lance
```

## Le geste

| | |
|---|---|
| **Poser** | glisser jusqu'au bord haut de l'écran, sous l'encoche, et lâcher |
| **Reprendre** | glisser l'objet de la tablette vers sa destination — il quitte l'étagère si quelqu'un l'a reçu, il y reste si le glisser a été abandonné |
| **Revoir** | poser le curseur sur l'encoche : la tablette sort au bout d'un tiers de seconde, si quelque chose y attend |
| **Ouvrir** | double-clic sur un objet |
| **Retirer** | clic droit sur un objet, ou la liste dans le panneau de réglages |

Au tout premier lancement, la tablette sort une seconde d'elle-même. Un outil
qui n'existe que sous l'encoche et ne se manifeste qu'au glisser est
parfaitement invisible pour qui ne connaît pas le geste.

## Ce qu'elle garde

**Des chemins, pas des copies.** Poser un fichier ne le déplace pas, ne le
duplique pas : l'étagère retient où il est. On peut donc y laisser un dossier de
vingt gigaoctets sans y penser. Un signet accompagne chaque chemin, ce qui
rattrape le cas courant du fichier simplement renommé ou rangé ailleurs entre
deux sessions. Quand plus rien ne répond, l'objet reste visible, barré et rouge :
le faire disparaître tout seul laisserait croire à un bug de l'étagère plutôt
qu'à une suppression.

**Douze objets, pas plus.** Au treizième, le plus ancien s'en va. Une étagère où
l'on empile sans jamais retirer redevient le bureau qu'on fuyait.

**Ce qui n'a pas de fichier derrière lui est matérialisé.** Une image ou un texte
venus d'un navigateur n'existent nulle part sur le disque. Les refuser casserait
la promesse — « on attrape quelque chose, on monte, on lâche » — et les garder en
mémoire donnerait une étagère vide au premier redémarrage, sans explication. Ils
sont donc écrits dans `~/Library/Application Support/Étagère/Dépôt`, que le
panneau de réglages sait ouvrir : une image devient un PNG, un texte un `.txt`,
un lien web un `.webloc` que le Finder sait ouvrir.

Les glissers *promis* — une pièce jointe de Mail, une photo de Photos — ne sont
pas pris en charge dans cette version : ils passent par `NSFilePromiseReceiver`,
qui demande un dossier de destination avant même de savoir ce qu'on reçoit.

## Les animations

Elles ne sont pas une décoration : elles sont l'outil. Trois règles les tiennent
— **tout part de l'encoche et y retourne**, **rien ne dépasse le quart de
seconde**, **aucun son**.

| | |
|---|---|
| **L'éveil** | l'encoche s'épaissit de trois points, lentement, en retard. Une main qui se lève au fond de la classe. |
| **L'ouverture** | la tablette se déplie *depuis* l'encoche, 0,24 s, sans rebond. Le contenu descend avec le tiroir : elle ne peut pas apparaître au milieu de rien. |
| **L'accueil** | une place se creuse sous le curseur, les objets déjà posés s'écartent. 0,18 s. |
| **La pose** | l'objet tombe de neuf points, dépasse de trois et demi, se pose. Une ombre naît pendant la chute. **C'est le seul rebond de tout l'outil** : il dit « c'est fait ». |
| **Le repli** | 0,14 s, contre 0,24 pour l'ouverture. Ouvrir invite ; fermer ne doit pas se faire attendre. |
| **La reprise** | l'objet attrapé se soulève, son ombre se creuse, les autres referment le trou. |
| **Le souvenir** | tablette fermée, objets en attente : un renflement minuscule sous l'encoche. Assez pour s'en souvenir, pas assez pour y penser. |

**« Réduire les animations » rend le tout instantané**, sans retirer une seule
fonction : l'étagère se comporte exactement pareil, elle ne raconte simplement
plus le trajet.

## Détails d'implémentation

### Savoir qu'un glisser a commencé ailleurs — sans autorisation

La spécification demandait que l'encoche s'épaississe *dès qu'un fichier est
soulevé, où que ce soit*. C'était le point à trancher, et il l'a été à la mesure
plutôt qu'au raisonnement. **C'est faisable, et sans demander la moindre
autorisation.**

- Un moniteur global `NSEvent` sur les évènements **souris** fonctionne sans
  l'autorisation d'accessibilité — vérifié sur cette machine avec
  `AXIsProcessTrusted()` à `false`. C'est le **clavier** qui est protégé, pas la
  souris ; d'où la différence avec Grab, dont le raccourci passe par Carbon
  précisément pour éviter cette autorisation.
- Le **presse-papier de glisser** (`NSPasteboard(name: .drag)`) voit son compteur
  de modifications avancer dès qu'une app — n'importe laquelle — ouvre une
  session de glisser. Mesuré : compteur 8 → 9 au démarrage d'une session dans un
  autre processus.

D'où la règle : au clic, on retient le compteur ; tant que le bouton est tenu,
s'il a bougé, c'est qu'un glisser est né de ce clic-là. **Le contenu du
presse-papier n'est jamais lu** — seulement son compteur, qui n'est qu'un entier
et ne déclenche aucune demande de confidentialité. Le sondage ne tourne que
pendant qu'un bouton est enfoncé : souris au repos, l'outil ne coûte rien.

Si ce mécanisme venait à ne rien donner, rien n'est perdu : l'éveil se
déclencherait alors au moment où le glisser entre dans la zone sensible, ce qui
est la deuxième moitié du même dispositif.

**Aucune autorisation système n'est demandée par cet outil.**

### La fenêtre grandit et rétrécit

Une fenêtre invisible qui resterait grande en permanence en haut de l'écran
avalerait les clics destinés à la fenêtre du dessous — le pire défaut possible
pour un outil censé se faire oublier. La fenêtre fait donc **220 × 43 points au
repos**, s'élargit quand un glisser est détecté, et prend sa taille pleine quand
la tablette s'ouvre. Hors de sa zone utile, `hitTest` rend `nil` : la réserve
d'ombre sur les côtés laisse passer les clics.

Le cadre **saute**, il ne s'anime pas : c'est le contenu qui se déplie. Animer un
cadre de fenêtre à soixante images par seconde saccade, et le pli sortirait du
cadre pendant la moitié du trajet.

### La géométrie de l'encoche

Elle n'est pas devinée. `NSScreen.auxiliaryTopLeftArea` et `auxiliaryTopRightArea`
donnent les deux zones utilisables de part et d'autre du boîtier de la caméra ;
l'encoche est exactement ce qui reste entre elles. Sur ce MacBook Pro : **220 ×
38 points, avec 790 points libres de chaque côté**.

Cette fenêtre **couvre l'encoche**, et c'est délibéré : trente-huit points où
aucun clic ne sert à rien font une cible de glisser gratuite. Le bourrelet, lui,
remonte de deux points *derrière* l'encoche — invisible à l'écran, mais garantie
qu'aucune couture d'un demi-pixel n'apparaisse au raccord.

**Sur un écran sans encoche**, la tablette se pose au centre du bord haut, juste
*sous* la barre des menus, qu'il ne faut surtout pas recouvrir. La bande sensible
y est plus épaisse — quatorze points au lieu de cinq — parce qu'il n'y a plus de
boîtier de caméra pour offrir une cible gratuite.

Une capture d'écran ne montre jamais l'encoche : macOS y compose le fond d'écran,
que le boîtier cache physiquement. Un bourrelet parfaitement collé à l'encoche y
paraît donc flotter sur le fond d'écran. Ce n'est pas un défaut du dessin, c'est
la capture.

### La reprise en AppKit, pas en SwiftUI

`.onDrag` démarre bien un glisser mais ne dit jamais comment il finit. Sans cette
fin, impossible de savoir si l'objet a été reçu — et un objet retiré de l'étagère
alors que le glisser a été abandonné en route, c'est une perte silencieuse. D'où
une `NSView` de poignée, qui attend le seuil de glisser avant d'ouvrir la session
pour que le double-clic reste possible.

### Une seule étagère à la fois

Deux tablettes sous la même encoche se disputeraient la place et garderaient
chacune leur propre liste. L'app autonome s'efface donc devant Trousse dès la
construction du module, sans attendre que sa coquille de barre de menus le fasse :
la tablette, elle, se poserait avant.
