#!/bin/bash
# Compile et assemble Ports.app.
#
#   ./build.sh              construit dans ./build
#   ./build.sh --install    construit puis installe dans /Applications
#
# Si Trousse tourne, cette app ne pose pas de seconde icône : elle lui demande
# d'ouvrir l'outil et se retire. Le bundle reste obligatoire — un binaire nu n'a
# ni identité, ni icône, ni réglages persistants.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG=release
APP="build/Ports.app"
INSTALL_DIR="/Applications"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

echo "==> Compilation"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/PortsApp

echo "==> Génération de l'icône"
mkdir -p build
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/Ports.iconset >/dev/null
iconutil -c icns build/Ports.iconset -o build/Ports.icns

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ports"
cp build/Ports.icns "$APP/Contents/Resources/Ports.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Ports</string>
    <key>CFBundleDisplayName</key>       <string>Ports</string>
    <key>CFBundleIdentifier</key>        <string>local.ports</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>Ports</string>
    <key>CFBundleIconFile</key>          <string>Ports</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>   <true/>
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
    pkill -f "Ports.app/Contents/MacOS/Ports" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/Ports.app"
    cp -R "$APP" "$INSTALL_DIR/Ports.app"
    touch "$INSTALL_DIR/Ports.app"
    echo "==> Lancement"
    open "$INSTALL_DIR/Ports.app"
    echo
    echo "✅ Ports installé dans $INSTALL_DIR et lancé."
else
    echo "==> Prêt : $APP"
    echo "    Lancer avec : open $APP"
    echo "    Installer   : ./build.sh --install"
fi
