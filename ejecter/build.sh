#!/bin/bash
# Compile et assemble Ejecter.app.
#
#   ./build.sh              construit dans ./build
#   ./build.sh --install    construit puis installe dans /Applications
#
# MenuBarExtra exige un vrai bundle applicatif : lancé comme simple binaire, le
# processus n'obtient pas de connexion au serveur de fenêtres et l'icône
# n'apparaît jamais dans la barre de menus.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG=release
APP="build/Ejecter.app"
INSTALL_DIR="/Applications"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

echo "==> Compilation"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/EjecterApp

echo "==> Génération de l'icône"
mkdir -p build
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/Ejecter.iconset >/dev/null
iconutil -c icns build/Ejecter.iconset -o build/Ejecter.icns

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ejecter"
cp build/Ejecter.icns "$APP/Contents/Resources/Ejecter.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Ejecter</string>
    <key>CFBundleDisplayName</key>       <string>Éjecter</string>
    <key>CFBundleIdentifier</key>        <string>local.ejecter</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>Ejecter</string>
    <key>CFBundleIconFile</key>          <string>Ejecter</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
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
    pkill -f "Ejecter.app/Contents/MacOS/Ejecter" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/Ejecter.app"
    cp -R "$APP" "$INSTALL_DIR/Ejecter.app"
    touch "$INSTALL_DIR/Ejecter.app"
    echo "==> Lancement"
    open "$INSTALL_DIR/Ejecter.app"
    echo
    echo "✅ Éjecter installé dans $INSTALL_DIR et lancé."
else
    echo "==> Prêt : $APP"
    echo "    Lancer avec : open $APP"
    echo "    Installer   : ./build.sh --install"
fi
