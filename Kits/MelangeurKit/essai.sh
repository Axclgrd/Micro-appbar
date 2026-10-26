#!/bin/bash
# Banc d'essai de MelangeurKit : enrobe melangeur-test dans un .app minimal
# (Info.plist avec NSAudioCaptureUsageDescription, signature stable de la
# famille) et le lance par LaunchServices, pour que macOS attribue la demande
# d'autorisation au banc et non au terminal. Hors build, jetable.
#   ./essai.sh liste    ./essai.sh peripheriques    ./essai.sh gain
set -euo pipefail
cd "$(dirname "$0")"
# Debug : le banc lit les types internes du kit (`@testable import`).
swift build --product melangeur-test >/dev/null
APP="${TMPDIR:-/tmp}/MelangeurEssai.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/debug/melangeur-test "$APP/Contents/MacOS/melangeur-test"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.microapp.melangeur-essai</string>
<key>CFBundleName</key><string>MelangeurEssai</string>
<key>CFBundleExecutable</key><string>melangeur-test</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>Banc d'essai du mélangeur : mesure le gain appliqué à un son de test.</string>
</dict></plist>
PL
# Signature stable : l'autorisation accordée au banc survit aux reconstructions.
../../Tools/identite.sh --signer "$APP" >/dev/null 2>&1 || codesign --force --sign - "$APP" >/dev/null 2>&1
LOG="$(mktemp -t melangeur-essai)"
# `open -W` perd parfois la course avec une commande qui finit en quelques
# millisecondes : son code de retour ne dit rien, le journal si.
open -W -n --stdout "$LOG" --stderr "$LOG" "$APP" --args "$@" 2>/dev/null || true
sleep 0.3
cat "$LOG"; rm -f "$LOG"
