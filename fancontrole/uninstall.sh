#!/bin/bash
# Retire fancontrold. Les ventilateurs repassent en automatique : le démon
# restaure le mode auto sur SIGTERM avant de rendre la main.
set -euo pipefail

LABEL="local.fancontrold"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if [[ $EUID -ne 0 ]]; then
    if [[ -t 0 ]]; then
        exec sudo "$SELF"
    fi
    # Sans terminal : dialogue d'authentification macOS (cf. install.sh).
    osascript -e "do shell script \"'${SELF}' 2>&1\" with administrator privileges"
    exit $?
fi

echo "==> Déchargement"
launchctl bootout system "$PLIST" 2>/dev/null || true
sleep 1

rm -f "$PLIST" /usr/local/libexec/fancontrold /var/run/fancontrold.sock

echo "✅ Démon retiré, ventilateurs rendus à macOS."
