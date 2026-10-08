#!/bin/bash
# Identité de signature locale, partagée par toutes les Micro-app.
#
# Pourquoi elle existe.
#
# Une signature ad hoc n'a pas d'identité : son exigence désignée — ce que macOS
# mémorise quand on accorde une autorisation — est le hash du binaire, sans même
# l'identifiant de l'app :
#
#     designated => cdhash H"32831cf49102c7e9597d4eb4aee46a95cad72755"
#
# Donc au premier changement de code, le hash change, et macOS voit une app
# qu'il n'a jamais vue. L'autorisation accordée ne s'applique plus — mais
# l'interrupteur reste allumé dans les Réglages système, parce qu'il affiche
# l'ancienne entrée. On croit alors que macOS ment, ou que l'app est cassée.
#
# Avec un certificat auto-signé, l'exigence devient :
#
#     designated => identifier "local.grab" and certificate leaf = H"6b9849…"
#
# Elle ne dépend plus du contenu du binaire. L'autorisation est accordée une
# fois et survit à toutes les reconstructions, de toutes les apps signées par
# ce certificat.
#
# Ce que ça touche : rien de personnel. Le certificat vit dans son propre
# trousseau, jamais dans le trousseau de connexion, et la confiance est
# déclarée dans ce trousseau seulement. Tout s'annule avec `--oublier`.
#
#   ./Tools/identite.sh            crée l'identité si elle manque, affiche son nom
#   ./Tools/identite.sh --chemin   affiche le chemin du trousseau
#   ./Tools/identite.sh --signer X signe le bundle X avec l'identité (usage des build.sh)
#   ./Tools/identite.sh --oublier  efface l'identité et son trousseau

set -euo pipefail

NOM="Micro-app"
TROUSSEAU="$HOME/Library/Keychains/microapp.keychain-db"
SECRET="$HOME/Library/Keychains/microapp.motdepasse"

creer() {
    local dir mdp
    dir=$(mktemp -d)
    mdp=$(openssl rand -hex 24)
    printf '%s' "$mdp" > "$SECRET"
    chmod 600 "$SECRET"

    security create-keychain -p "$mdp" "$TROUSSEAU"
    # Sans réglage, un trousseau se reverrouille au bout de quelques minutes et
    # la compilation suivante échoue sur un message qui ne dit pas pourquoi.
    security set-keychain-settings "$TROUSSEAU"
    security unlock-keychain -p "$mdp" "$TROUSSEAU"

    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$dir/cle.pem" -out "$dir/cert.pem" -subj "/CN=$NOM" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

    # Format hérité imposé : OpenSSL 3 chiffre le PKCS#12 d'une façon que le
    # Security framework de macOS ne sait pas relire, et l'import échoue sur un
    # « wrong password? » qui n'a rien à voir avec le mot de passe.
    openssl pkcs12 -export -out "$dir/id.p12" \
        -inkey "$dir/cle.pem" -in "$dir/cert.pem" \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1 \
        -passout "pass:$mdp" 2>/dev/null

    security import "$dir/id.p12" -k "$TROUSSEAU" -P "$mdp" -T /usr/bin/codesign -A >/dev/null
    # Sans confiance déclarée, codesign ne tient pas l'identité pour valide.
    security add-trusted-cert -r trustRoot -k "$TROUSSEAU" "$dir/cert.pem"

    rm -rf "$dir"
}

# Prépare l'identité et déverrouille son trousseau. Renvoie faux plutôt que de
# faire échouer le build : une machine sans openssl doit encore pouvoir compiler.
preparer() {
    local mdp
    [[ -f "$TROUSSEAU" && -f "$SECRET" ]] || creer || return 1
    mdp=$(cat "$SECRET")
    security unlock-keychain -p "$mdp" "$TROUSSEAU" 2>/dev/null || return 1

    # Déverrouiller le trousseau ne suffit pas : sans liste de partition, macOS
    # ouvre une fenêtre « codesign wants to access key "id" » à chaque
    # signature. On déclare ici, une fois, que les outils de signature ont le
    # droit d'utiliser la clé — avec le mot de passe qu'on possède déjà, donc
    # sans rien demander à personne. Idempotent : réparé aussi pour un
    # trousseau créé avant que cette ligne existe.
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "$mdp" "$TROUSSEAU" >/dev/null 2>&1 || true

    security find-identity -v -p codesigning "$TROUSSEAU" | grep -q "\"$NOM\"" || return 1
}

case "${1:-}" in
    --oublier)
        security delete-keychain "$TROUSSEAU" 2>/dev/null || true
        rm -f "$SECRET"
        echo "Identité oubliée. Les build.sh repassent en signature ad hoc."
        exit 0
        ;;

    # Le point d'entrée des build.sh. Signer ici plutôt que dans chaque script
    # évite que l'un d'eux retombe en ad hoc sans qu'on s'en aperçoive — et une
    # seule app signée ad hoc suffit à faire réapparaître le problème.
    --signer)
        APP="${2:?usage: identite.sh --signer <bundle>}"

        # Une signature interrompue (fenêtre du trousseau annulée, Ctrl-C)
        # laisse un fichier « .cstemp » à côté du binaire. codesign refuse
        # ensuite de signer, sur un « invalid or unsupported format for
        # signature » qui n'a rien à voir avec le format. On balaie avant.
        find "$APP" -name "*.cstemp" -delete 2>/dev/null || true

        if preparer; then
            # --deep est déprécié et inutile ici : le bundle n'a pas de code
            # imbriqué, juste un binaire lié statiquement. L'identifiant vient
            # du CFBundleIdentifier du bundle, que codesign lit tout seul.
            if codesign --force --sign "$NOM" --keychain "$TROUSSEAU" "$APP" 2>/dev/null; then
                echo "    signé « $NOM » — les autorisations survivent aux reconstructions"
                exit 0
            fi
        fi
        codesign --force --sign - "$APP" 2>/dev/null \
            && echo "    ⚠️  identité indisponible : signature ad hoc." \
            && echo "        Les autorisations système seront à réaccorder à chaque build." \
            || echo "    ⚠️  signature impossible."
        exit 0
        ;;
esac

if ! preparer; then
    echo "identité introuvable dans $TROUSSEAU" >&2
    exit 1
fi

if [[ "${1:-}" == "--chemin" ]]; then
    echo "$TROUSSEAU"
else
    echo "$NOM"
    security find-identity -v -p codesigning "$TROUSSEAU" | sed -n '1p'
fi
