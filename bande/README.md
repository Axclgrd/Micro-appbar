# Bande

Une vidéo entre, son audio sort — ou ce qui s'y dit. Rien d'autre.

Le geste est toujours le même : on lâche un fichier sur la fenêtre — ou sur
l'icône du Dock — et le résultat apparaît à côté de la vidéo d'origine. Pas de
réglage de qualité, pas de choix de codec, pas de fenêtre de progression
modale : trois boutons, parce qu'il n'y a que trois réponses utiles.

| | |
|---|---|
| **Audio d'origine** | la piste telle qu'elle est dans la vidéo, recopiée sans réencodage. Fichier `.m4a`. |
| **WAV transcription** | 16 kHz, mono, PCM 16 bits — ce qu'attendent les moteurs de transcription. Fichier `.wav`. |
| **Texte** | ce qui est dit, en toutes lettres. Fichier `.txt`. |

## Construction

```sh
./build.sh              # → build/Bande.app
./build.sh --install    # → /Applications, et lance
```

## Ce que ça sait faire

Ouvrir ce que macOS sait ouvrir : `.mp4`, `.mov`, `.m4v`, `.mp3`, `.wav`,
`.m4a`, `.aac`. Plusieurs fichiers d'un coup, traités l'un après l'autre. Un
dossier lâché sur la fenêtre vaut « toutes les vidéos qui sont dedans », sans
descendre dans les sous-dossiers.

Chaque ligne annonce sa durée et son codec avant même que son tour arrive, puis
dit ce qui a été fait : *copie sans perte*, *réencodé en AAC*, *converti
16 kHz mono*.

## Le texte

Une réunion d'une heure devient un fichier texte en quarante secondes, sans
qu'un octet quitte la machine : `SpeechAnalyzer`, le moteur de reconnaissance
vocale local de macOS 26, tourne à peu près quatre-vingts fois plus vite que le
temps réel sur Apple Silicon. Mesuré sur un appel de vingt et une minutes :
**dix-sept secondes**, quinze kilooctets de texte.

Le WAV 16 kHz mono que Bande produisait déjà n'était pas un hasard : c'est
exactement le format d'entrée du moteur (`bestAvailableAudioFormat` répond
« 16 kHz, mono, Int16 »). Le bouton **Texte** le fabrique dans un dossier
temporaire, le donne à transcrire, écrit le `.txt`, et efface le WAV — on a
demandé un texte, pas un texte et un WAV.

**La langue est reconnue toute seule.** Le moteur ne devine pas ce qui est
parlé, et rien dans un fichier vidéo ne le déclare. Bande part donc des langues
du système ; mais quand plusieurs sont installées, il transcrit quatre-vingt-dix
secondes avec chacune et garde le modèle qui est sûr de lui. Le bon modèle rend
0,97 de confiance moyenne, le mauvais 0,35 — sur « le serveur écoute sur le port
trois mille », le modèle anglais entend *« Le servere recoups y le portois
mill »*. L'écart ne laisse pas de place au doute. Un Mac réglé en anglais dont
le propriétaire filme en français est le cas courant, et c'est celui-là que la
mesure sauve.

**Ce que le texte n'est pas.** Il n'y a ni horodatage, ni séparation des
locuteurs : le moteur ne sait pas qui parle. Les noms propres et le jargon
passent mal — un ERP nommé « EBP » ressort en « BP », « Superset » en
« Super 7 ». Les nombres sont mis en chiffres et la ponctuation est ajoutée :
« trois mille » devient « 3000 ». Les paragraphes sont coupés là où le moteur a
entendu une pause, mais seulement quand la phrase est finie.

**macOS 26 minimum, pour ce bouton seul.** Bande reste une app macOS 14 : sur un
système plus ancien, les deux formats audio fonctionnent et le troisième le dit
en une phrase, plutôt que de rendre une erreur système. Quarante-cinq langues
sont prises en charge, dont le français dans quatre régions ; un modèle absent
se télécharge à la première utilisation, et la barre suit le téléchargement.

## Ce que ça ne sait pas faire

**Les conteneurs que macOS ne lit pas** — `.mkv`, `.webm`, `.avi`, `.wmv`,
`.flv`, `.ts`. AVFoundation ne les ouvre pas, et embarquer ffmpeg pour ça
coûterait soixante-dix mégaoctets et une licence. L'app les refuse en le disant,
plutôt que de rendre une erreur système à quatre chiffres.

**Le MP3.** macOS sait le lire, pas l'écrire : aucun encodeur MP3 n'est fourni
par le système. Le `.m4a` produit ici est son équivalent moderne — même poids,
meilleure qualité, lu partout.

## Détails d'implémentation

**La copie n'est pas une conversion.** Quand la piste est déjà en AAC — le cas
de presque toutes les vidéos — les échantillons compressés passent tels quels
de la vidéo au `.m4a`, sans jamais être décodés. Un film d'une heure sort en
une poignée de secondes, et le son est bit pour bit celui d'origine. Le
réencodage n'arrive que quand la piste ne rentre pas dans un `.m4a` : AC-3 d'un
Blu-ray, PCM d'un export de montage.

**Un seul moteur.** Copie, réencodage et conversion 16 kHz passent tous par le
même couple `AVAssetReader` → `AVAssetWriter`. Ce qui change d'un cas à l'autre,
ce sont les réglages de lecture et d'écriture : `nil` des deux côtés pour la
copie, LPCM décodé puis AAC pour le réencodage, LPCM 16 kHz mono pour le WAV.

**Le repli multicanal.** Une piste 5.1 doit être repliée avant d'être écrite en
stéréo ou en mono, et le convertisseur veut alors connaître la disposition des
canaux visée. Elle lui est donnée — mais certaines sources la font échouer, et
l'extraction est relancée une fois sans, plutôt que de s'arrêter sur un détail
de configuration.

**Une extraction à la fois.** En paralléliser deux ne gagne rien — le disque est
le goulot — et rendrait l'avancement illisible.

**Rien de partiel ne survit.** Une extraction interrompue, en échec ou annulée
efface son fichier de sortie. Un `.m4a` à moitié écrit n'a pas d'en-tête valide
et ne sert à personne. Une transcription annulée ne laisse ni `.txt` ni WAV de
travail : le texte n'est écrit qu'une fois complet, et d'un seul coup.

**Le fichier sort à côté de la vidéo**, avec le nom de la vidéo. Si ce nom est
pris, un numéro s'ajoute — rien n'est jamais écrasé. Quand la source est en
lecture seule — disque de sauvegarde, image disque, partage réseau — le pied de
fenêtre permet de fixer un dossier de destination, et l'app le dit avant de
tenter l'écriture plutôt qu'après avoir échoué.

## Ensuite

Les horodatages. Le moteur rend déjà la plage de temps de chaque segment — de
quoi écrire un `.srt` à côté du `.txt` pour sous-titrer la vidéo d'origine.
