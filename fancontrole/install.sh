#!/bin/bash
# Installe fancontrold comme LaunchDaemon système.
#
# Lancer simplement : ./install.sh
# Le script s'élève lui-même — via sudo s'il a un terminal, sinon via la
# fenêtre d'authentification de macOS (utile quand il est lancé sans TTY).
set -euo pipefail

LABEL="local.fancontrold"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
DEST="/usr/local/libexec/fancontrold"
SOCKET="/var/run/fancontrold.sock"

# UID réel de l'utilisateur : c'est lui qui possédera le socket, pour que seul
# son compte puisse piloter les ventilateurs. Il doit traverser l'élévation,
# donc on se le repasse explicitement en argument plutôt que de compter sur
# SUDO_UID (absent quand l'élévation passe par osascript).
REAL_UID=""
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uid) REAL_UID="${2:-}"; shift 2 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done
[[ -n "$REAL_UID" ]] || REAL_UID="${SUDO_UID:-$(id -u)}"

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
PROJECT_DIR="$(dirname "$SELF")"

# ---------------------------------------------------------------- élévation
if [[ $EUID -ne 0 ]]; then
    if [[ -t 0 ]]; then
        echo "==> Élévation via sudo (le démon doit tourner en root)"
        exec sudo "$SELF" --uid "$REAL_UID"
    fi

    echo "==> Pas de terminal disponible — fenêtre d'authentification macOS"
    echo "    (autorise dans la boîte de dialogue qui vient de s'ouvrir)"
    # `do shell script … with administrator privileges` exécute en root et
    # affiche le dialogue système. Les apostrophes protègent les espaces du
    # chemin ("My Passport").
    osascript -e "do shell script \"'${SELF}' --uid ${REAL_UID} 2>&1\" with administrator privileges"
    exit $?
fi

# ------------------------------------------------------------------- racine
OWNER_NAME=$(id -un "$REAL_UID" 2>/dev/null || echo "uid $REAL_UID")
cd "$PROJECT_DIR"

echo "==> Compilation (en tant que $OWNER_NAME)"
# -H pour que HOME pointe sur le compte utilisateur : SwiftPM y met son cache.
sudo -H -u "#${REAL_UID}" /usr/bin/swift build -c release
BIN="$(sudo -H -u "#${REAL_UID}" /usr/bin/swift build -c release --show-bin-path)/fancontrold"

if [[ ! -x "$BIN" ]]; then
    echo "❌ Binaire introuvable : $BIN"
    exit 1
fi

echo "==> Arrêt d'une éventuelle instance précédente"
launchctl bootout system "$PLIST" 2>/dev/null || true

echo "==> Installation du binaire dans $DEST"
mkdir -p "$(dirname "$DEST")"
install -m 755 -o root -g wheel "$BIN" "$DEST"

echo "==> Écriture de $PLIST"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DEST}</string>
        <string>--owner</string>
        <string>${REAL_UID}</string>
    </array>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>StandardErrorPath</key><string>/var/log/fancontrold.log</string>
</dict>
</plist>
PLISTEOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

echo "==> Chargement du démon"
launchctl bootstrap system "$PLIST"

# Le socket est créé de façon asynchrone après le démarrage du démon.
for _ in $(seq 1 20); do
    [[ -S "$SOCKET" ]] && break
    sleep 0.25
done

if [[ -S "$SOCKET" ]]; then
    echo
    echo "✅ Démon actif — socket possédé par ${OWNER_NAME}"
    echo "   Ouvre le menu FanControl : le curseur est débloqué."
    echo "   Journal : /var/log/fancontrold.log"
else
    echo
    echo "❌ Le socket n'est pas apparu."
    echo "--- /var/log/fancontrold.log ---"
    tail -20 /var/log/fancontrold.log 2>/dev/null || echo "(journal vide)"
    exit 1
fi
