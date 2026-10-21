#!/bin/bash
# Banc d'essai de NuitKit : enrobe nuit-test dans un .app minimal (Info.plist avec
# NSAudioCaptureUsageDescription, signature ad hoc) pour que macOS puisse demander
# l'autorisation « Enregistrement audio du système ». Hors build de Trousse, jetable.
#   ./essai.sh run 20 nuit      ./essai.sh crash 10      ./essai.sh dsp
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product nuit-test >/dev/null
APP="${TMPDIR:-/tmp}/NuitEssai.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/nuit-test "$APP/Contents/MacOS/nuit-test"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.microapp.nuit-essai</string>
<key>CFBundleName</key><string>NuitEssai</string>
<key>CFBundleExecutable</key><string>nuit-test</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>Banc d'essai du stabilisateur audio.</string>
</dict></plist>
PL
codesign --force --sign - "$APP" >/dev/null 2>&1
exec "$APP/Contents/MacOS/nuit-test" "$@"
