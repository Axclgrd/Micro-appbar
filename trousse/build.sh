#!/bin/bash
# Compile et assemble Trousse.app.
#
#   ./build.sh              construit dans ./build
#   ./build.sh --install    construit puis installe dans /Applications
#
# La trousse tient la barre du haut : elle crée autant d'icônes que l'utilisateur
# a composé de groupes. Un vrai bundle est donc obligatoire — un binaire nu n'a
# ni identité, ni icône, ni réglages persistants.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG=release
APP="build/Trousse.app"
INSTALL_DIR="/Applications"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

echo "==> Compilation"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/TrousseApp

echo "==> Génération de l'icône"
mkdir -p build
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/Trousse.iconset >/dev/null
iconutil -c icns build/Trousse.iconset -o build/Trousse.icns

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Trousse"
cp build/Trousse.icns "$APP/Contents/Resources/Trousse.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Trousse</string>
    <key>CFBundleDisplayName</key>       <string>Trousse</string>
    <key>CFBundleIdentifier</key>        <string>local.trousse</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>Trousse</string>
    <key>CFBundleIconFile</key>          <string>Trousse</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <!-- Le verre liquide natif n'existe pas avant macOS 26. -->
    <key>LSMinimumSystemVersion</key>    <string>26.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSAppleEventsUsageDescription</key><string>Trousse met Apple Music en pause quand le micro des AirPods est utilisé, puis la reprend.</string>
    <key>NSAudioCaptureUsageDescription</key><string>Trousse reprend le son des applications pour régler leur volume une à une (Mélangeur) et pour lisser le son du Mac la nuit (Nuit).</string>
    <!-- Agent : pas d'icône dans le Dock, pas de menu applicatif. -->
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
    pkill -f "Trousse.app/Contents/MacOS/Trousse" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/Trousse.app"
    cp -R "$APP" "$INSTALL_DIR/Trousse.app"
    touch "$INSTALL_DIR/Trousse.app"
    echo "==> Lancement"
    open "$INSTALL_DIR/Trousse.app"
    echo
    echo "✅ Trousse installé dans $INSTALL_DIR et lancé."
else
    echo "==> Prêt : $APP"
    echo "    Lancer avec : open $APP"
    echo "    Installer   : ./build.sh --install"
fi
