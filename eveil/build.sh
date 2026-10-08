#!/bin/bash
# Compile et assemble Eveil.app.
#
#   ./build.sh              construit dans ./build
#   ./build.sh --install    construit puis installe dans /Applications
set -euo pipefail

cd "$(dirname "$0")"
CONFIG=release
APP="build/Eveil.app"
INSTALL_DIR="/Applications"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

echo "==> Compilation"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/EveilApp

echo "==> Génération de l'icône"
mkdir -p build
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/Eveil.iconset >/dev/null
iconutil -c icns build/Eveil.iconset -o build/Eveil.icns

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Eveil"
cp build/Eveil.icns "$APP/Contents/Resources/Eveil.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Eveil</string>
    <key>CFBundleDisplayName</key>       <string>Éveil</string>
    <key>CFBundleIdentifier</key>        <string>local.eveil</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>Eveil</string>
    <key>CFBundleIconFile</key>          <string>Eveil</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSUIElement</key>               <true/>
</dict>
</plist>
PLIST

# Signature : identité locale stable, partagée par toutes les Micro-app.
#
# Surtout pas ad hoc. Une signature ad hoc n'a pas d'identité — l'autorisation
# que macOS mémorise (écran, accessibilité) est alors attachée au hash du
# binaire, donc perdue à chaque reconstruction. L'interrupteur, lui, reste
# allumé dans les Réglages : l'app paraît autorisée et ne l'est pas.
echo "==> Signature"
"$(cd "$(dirname "$0")/.." && pwd)/Tools/identite.sh" --signer "$APP"

if [[ $DO_INSTALL -eq 1 ]]; then
    echo "==> Installation dans $INSTALL_DIR"
    pkill -f "Eveil.app/Contents/MacOS/Eveil" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/Eveil.app"
    cp -R "$APP" "$INSTALL_DIR/Eveil.app"
    touch "$INSTALL_DIR/Eveil.app"
    echo "==> Lancement"
    open "$INSTALL_DIR/Eveil.app"
    echo
    echo "✅ Éveil installé dans $INSTALL_DIR et lancé."
else
    echo "==> Prêt : $APP"
fi
