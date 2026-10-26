#!/bin/bash
# Compile et assemble Pouls.app.
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
APP="build/Pouls.app"
INSTALL_DIR="/Applications"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

echo "==> Compilation"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/PoulsApp

echo "==> Génération de l'icône"
mkdir -p build
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/Pouls.iconset >/dev/null
iconutil -c icns build/Pouls.iconset -o build/Pouls.icns

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pouls"
cp build/Pouls.icns "$APP/Contents/Resources/Pouls.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Pouls</string>
    <key>CFBundleDisplayName</key>       <string>Pouls</string>
    <key>CFBundleIdentifier</key>        <string>local.pouls</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>Pouls</string>
    <key>CFBundleIconFile</key>          <string>Pouls</string>
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
    pkill -f "Pouls.app/Contents/MacOS/Pouls" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/Pouls.app"
    cp -R "$APP" "$INSTALL_DIR/Pouls.app"
    touch "$INSTALL_DIR/Pouls.app"
    echo "==> Lancement"
    open "$INSTALL_DIR/Pouls.app"
    echo
    echo "✅ Pouls installé dans $INSTALL_DIR et lancé."
else
    echo "==> Prêt : $APP"
    echo "    Lancer avec : open $APP"
    echo "    Installer   : ./build.sh --install"
fi
