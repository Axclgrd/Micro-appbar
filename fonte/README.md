# Fonte

Un raccourci, une zone à l'écran, et Claude te dit quelle police c'est.

Reconnaître une police, aujourd'hui, c'est une capture, un site d'identification,
un envoi, des publicités, et une liste de noms sans explication. Fonte garde le
geste de Grab — la même croix, le même raccourci — et rend une réponse
argumentée : les propositions classées avec leur probabilité, les lettres qui
les désignent, et le texte capturé recomposé dans la police — vérifiée sur le
vrai fichier quand on peut se le procurer.

`⌥⇧⌘F` par défaut (modifiable dans le panneau parmi quatre combinaisons). Une
image glissée dans la fenêtre, ou ouverte par `⌘O`, marche aussi.

## Construction

```sh
./build.sh              # → build/Fonte.app
./build.sh --install    # → /Applications, et lance
```

Au premier usage, macOS demande l'autorisation d'enregistrement de l'écran. Il
faut la donner puis relancer l'app.

L'analyse demande **Claude Code**, connecté au moins une fois (`claude` dans
Terminal). C'est lui qui installe les Micro-app, il est donc déjà là.

## Comment Fonte reconnaît une police

Reconnaître une police de mémoire ne suffit pas : sur une photo, Claude
hésitait entre cinq linéales et donnait 20 % à chacune. Fonte procède donc comme
un typographe, en trois temps.

1. **Regarder de près.** Vision (sur le Mac, sans réseau) trouve les lignes de
   texte. Les plus grandes sont redressées, remises à l'horizontale et agrandies.
2. **Proposer** — *un seul appel à Claude, c'est tout ce que coûte une capture.*
   Claude reçoit la capture et les agrandissements, et propose jusqu'à dix
   polices, sosies libres compris. Celles qu'on peut se procurer sont
   téléchargées pour l'aperçu.
3. **Vérifier avec Claude** — *bouton, sur demande, second appel plus lourd.*
   Le Mac compose la ligne capturée dans toutes ses polices et les 100 polices
   Fontshare, et garde la meilleure ; avec les deux premières propositions,
   cela fait trois polices, composées **juste sous la ligne capturée, à la même
   hauteur de lettres**, avec deux mesures (largeur relative, formes communes).
   Claude compare et tranche. C'est ce qui rattrape Clash Display ou General
   Sans, que Claude ne propose pas de mémoire. Les polices payantes restent
   « Non comparées ».

Mesuré sur 24 images de polices connues (perspective, flou, JPEG) :

| Méthode | 1ʳᵉ proposition juste | Confiance quand c'est juste | Durée |
|---|---|---|---|
| Un appel (analyse seule) | 17 / 24 | 30 à 60 % | ~15 s |
| + vérification, ligne sous ligne | 22 / 24 | 75 à 90 % | ~27 s |
| + tri visuel et mesures (3 polices seulement) | 21 / 24 + Clash Display rattrapée | 70 à 90 % | ~36 s |

Les deux dernières lignes sont à égalité aux variations près (un même cas
change d'un essai à l'autre). Les échecs restants sont des polices display
(Syne, Clash Display, Archivo Black) sur des mots courts. Sur des photos floues
en perspective, Fonte reste prudent et le dit.

Essayés et écartés : la recherche web (deux minutes, rien trouvé), un second
tour de vérification, le catalogue des polices donné à Claude (sans gain).

Les polices téléchargées sont gardées dans
`~/Library/Application Support/Micro-app/Fonte/Polices` : elles donnent un
aperçu, et « Installer la police » les copie dans `~/Library/Fonts`. Seuls des
noms de polices partent vers Google Fonts et Fontshare ; la capture ne va qu'à
Claude.

Une image peut aussi être ouverte avec Fonte (glissée sur l'icône, « Ouvrir
avec », `open -a Fonte image.png`) ; si Trousse tourne, c'est elle qui l'analyse.

## Choix qui comptent

**Claude Code plutôt que l'API.** Pas de clé à saisir ni de secret à ranger :
l'analyse passe par le compte déjà connecté, comme une session ordinaire. Chaque
appel est verrouillé — aucun outil (`--tools ""`), aucune personnalisation
(`--safe-mode`), aucune session gardée — et la réponse est validée contre un
schéma JSON avant de revenir. Le modèle est Claude Opus 5.5 : reconnaître une
police se joue sur des détails d'un pixel, et Sonnet confondait les familles
voisines.

**Un aperçu seulement dans la vraie police.** Quand on a pu se procurer une
proposition, la fiche montre le texte capturé dans son dessin. Sinon, rien n'est
montré à sa place : un aperçu dans une police voisine ferait croire à une
ressemblance qui n'existe pas.

**Des probabilités, pas un verdict.** Deux Bodoni numériques se ressemblent à un
empattement près. Claude donne un pourcentage honnête par proposition, dit ce
qui limite l'identification (trop peu de lettres, lettrage dessiné) et propose
des équivalents libres quand la bonne est payante.

## Détails d'implémentation

La requête part d'un fichier, pas d'un tube : Claude Code lit son entrée jusqu'à
la fin, et un fichier se termine tout seul. Écrire dans un tube pendant qu'on
lit l'autre demanderait deux fils, et un processus mort avant d'avoir tout lu
tuerait l'app d'un SIGPIPE.

L'historique — images et réponses — vit dans
`~/Library/Application Support/Micro-app/Fonte`, partagé avec Trousse : une
seule des deux tourne à la fois, et il doit suivre l'outil, pas l'app qui
l'héberge. Les soixante dernières analyses sont gardées.

Le raccourci global est celui de `Commun`, partagé avec Grab. Chaque outil y a
sa signature (« GRAB », « FONT ») : dans Trousse, qui les héberge tous deux,
frapper l'un ne déclenche pas l'autre.
