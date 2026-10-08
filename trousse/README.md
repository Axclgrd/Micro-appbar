# Trousse

Une app qui tient la barre du haut, et les petits outils qui vivent dedans.

Six utilitaires, c'étaient six icônes imposées dans la barre des menus, six
identités à autoriser, six mises à jour. Ici c'est **une** app : elle crée
autant d'icônes que tu as composé de groupes, tu décides de leurs noms, de ce
qu'elles contiennent, et de ce qui n'apparaît pas du tout.

Un outil masqué n'est pas désinstallé : Grab n'a besoin que de son raccourci,
il n'a aucune raison d'occuper une place permanente.

## Construction

```sh
./build.sh              # → build/Trousse.app
./build.sh --install    # → /Applications, et lance
```

**macOS 26 minimum.** C'est la seule app de la famille à monter si haut : le
verre liquide natif — `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` —
n'existe pas avant. Les autres restent en macOS 14.

## Comment c'est fait

Un **module** fournit quatre choses et rien d'autre : un nom, un symbole, une
ligne d'état, un panneau. Son moteur — sockets en écoute, lecture du SMC,
montage des disques — ne sait pas que la trousse existe.

```swift
protocol Module: AnyObject {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    var summary: String { get }
    func activate()      // sonde tant qu'on le regarde
    func idle()          // et rien du tout sinon
    func makePanel() -> AnyView
}
```

Le catalogue est statique : la trousse n'a pas de greffons, elle a des modules
qu'on ajoute en recompilant. C'est ce qui permet de garder **une seule identité,
une seule signature, une seule autorisation**.

## Le verre, tel qu'Apple le prescrit

Le verre liquide n'habille que ce qui **flotte au-dessus** du contenu. Les
règles suivies ici :

| | |
|---|---|
| **Couche de navigation seulement** | la barre d'actions flottante de la fenêtre est en verre. Les cartes de groupes sont du contenu : matériau opaque, jamais de verre. |
| **Jamais de verre sur du verre** | le popover du système en pose déjà — les panneaux de la barre n'en remettent pas. |
| **`GlassEffectContainer`** | les éléments de verre voisins y sont groupés : le verre ne sait pas échantillonner du verre, il lui faut une région commune. |
| **Une seule teinte** | l'action principale, et elle seule. Quand tout est teinté, plus rien ne ressort. |
| **`.regular` partout** | `.clear` est réservé aux fonds photo ou vidéo, et les deux ne se mélangent jamais. |
| **Accessibilité** | Réduire la transparence, Augmenter le contraste et Réduire les animations sont gérés par le système, sans une ligne de code. |

`.interactive()` n'est pas utilisé : c'est un retour au toucher, propre à iOS.

## Les huit outils

| | |
|---|---|
| **Ventilateurs** | températures SMC et pilotage des ventilateurs |
| **Éjecter** | éjection propre des disques externes, dit *qui* bloque |
| **Éveil** | empêcher la veille, avec une fin prévue |
| **Ports** | qu'est-ce qui tourne sur le 3000, et ce que l'arrêter coûte |
| **Purge** | l'espace pris par les artefacts de build |
| **Bande** | une vidéo entre, son audio sort |
| **Grab** | raccourci → sélection → texte OCR dans le presse-papier |
| **Étagère** | une tablette sous l'encoche, où poser ce qui change de fenêtre |

Au premier lancement ils sont rangés en deux groupes — **Machine**
(ventilateurs, disques, veille) et **Travail** (ports, purge, bande) — et Grab
est masqué, puisque son raccourci suffit. Ce n'est qu'une proposition : tout se
déplace dans la fenêtre de réglages.

### Ports — qu'est-ce qui tourne sur le 3000 ?

Trois verdicts, comme dans Purge :

| | |
|---|---|
| **à toi** | un serveur de développement — node, vite, uvicorn… C'est ce qu'on vient récupérer. |
| **attention** | une autre application. L'arrêter marche, mais fait plus que libérer le port. |
| **système** | un service de macOS. On explique, on ne tue pas. |

Deux cas méritaient d'être nommés, parce qu'ils font perdre des heures :

- **Les ports 5000 et 7000 sont pris par le récepteur AirPlay de macOS.** C'est
  la vraie raison du « port 5000 already in use » sur un Mac. Il se coupe dans
  Réglages système › Général › AirDrop et Handoff, pas en tuant un process.
- **Docker publie les ports du dehors.** Le process qui tient le 5432, c'est
  `com.docker.backend`, pas Postgres. L'arrêter coupe Docker en entier — d'où
  le verdict *attention* et le renvoi vers `docker stop`.

Chaque serveur qui t'appartient affiche un **QR code** de son adresse sur le
réseau local : viser avec le téléphone évite de taper une IP à la main.

`SIGTERM` d'abord — un serveur bien élevé ferme ses connexions et retire son
fichier de verrou. `SIGKILL` ne laisse rien.

## Chacun garde son app

Aucune app n'a disparu. `Eveil.app`, `Ejecter.app`, `Grab.app`, `Purge.app`,
`Bande.app`, `Ports.app`, `Etagere.app` et `FanControl.app` existent toujours et fonctionnent
seules — sur une machine sans Trousse, ou si tu n'en veux qu'une.

Elles ne contiennent pourtant aucune copie du code : l'outil vit dans sa
bibliothèque (`Kits/EveilKit`, `Kits/EtagereKit`…), et les deux hôtes affichent
**le même panneau, le même objet**. Une correction faite une fois vaut pour les
deux.

**Trousse a la priorité.** Si elle tourne, une app autonome ne pose pas de
seconde icône : elle lui demande d'ouvrir l'outil et se retire. Deux icônes pour
le même outil, avec deux sondages et deux panneaux qui peuvent se contredire, ne
rendrait service à personne. Même règle pour Purge et Bande : c'est la fenêtre
de Trousse qui s'ouvre, pas une seconde.

Le signal passe par une notification distribuée, pas par les notifications de
lancement de `NSWorkspace` — celles-ci ne couvrent pas les apps agent, et
Trousse en est une. C'est donc Trousse qui s'annonce.

Les réglages vivent dans un domaine commun, `local.microapp` : cocher « garder
l'écran allumé » dans l'app autonome d'Éveil, c'est le cocher dans Trousse.

## Détails d'implémentation

**`libproc`, pas `lsof`.** `lsof` liste chaque socket deux fois (IPv4 puis
IPv6), tronque les noms de process à neuf caractères — `com.docke` pour
`com.docker.backend` — et coûte un sous-processus à chaque sondage. `libproc`
donne la même chose en direct, dédoublonné et complet. Portée : les process de
l'utilisateur courant, sans jamais demander root.

**Un outil fermé ne coûte rien.** Le sondage démarre à l'ouverture d'un panneau
et s'arrête à sa fermeture. Barre au repos = aucun timer.

**Une icône de secours.** Sans aucun groupe, l'app n'aurait plus d'icône — ni
dans la barre, ni dans le Dock puisqu'elle est un agent. Une icône apparaît
alors pour rouvrir les réglages.

**Un module nouvellement compilé rejoint le premier groupe** plutôt que de
rester invisible sans que rien ne le dise.

**Supprimer un groupe ne supprime pas ses outils** : ils passent en masqués, où
on peut les reprendre.

**Un badge par groupe, ou aucun.** Le temps restant d'Éveil et la température
des ventilateurs s'affichent à côté de l'icône du groupe qui les contient —
mais seulement si un seul outil du groupe en réclame un. À plusieurs, rien ne
désignerait celui à montrer : une icône qui afficherait tantôt 62°, tantôt 40m,
serait pire que muette. Le panneau, lui, les donne tous les deux.

Le suivi est par observation, pas par horloge : le badge se repeint quand
l'outil change d'état, et un groupe dont rien ne bouge ne coûte rien.
