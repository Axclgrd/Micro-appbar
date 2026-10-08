#!/bin/bash
# Compile et assemble Purge.app.
#
#   ./build.sh              construit dans ./build
#   ./build.sh --install    construit puis installe dans /Applications
set -euo pipefail

cd "$(dirname "$0")"
CONFIG=release
APP="build/Purge.app"
INSTALL_DIR="/Applications"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

echo "==> Compilation"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/PurgeApp

echo "==> Génération de l'icône"
mkdir -p build
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/Purge.iconset >/dev/null
iconutil -c icns build/Purge.iconset -o build/Purge.icns

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Purge"
cp build/Purge.icns "$APP/Contents/Resources/Purge.icns"

# Les chaînes NS*UsageDescription sont le texte que macOS affiche quand
# l'analyse atteint le Bureau, les Documents ou un volume externe. Sans elles,
# le système refuse l'accès sans rien demander, et l'analyse rend un total faux.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Purge</string>
    <key>CFBundleDisplayName</key>       <string>Purge</string>
    <key>CFBundleIdentifier</key>        <string>local.purge</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>Purge</string>
    <key>CFBundleIconFile</key>          <string>Purge</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Pour mesurer les artefacts de build posés sur le Bureau.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Pour mesurer les artefacts de build de tes projets.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Pour mesurer les artefacts de build des projets téléchargés.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Pour analyser les projets rangés sur un disque externe.</string>
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
    pkill -f "Purge.app/Contents/MacOS/Purge" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/Purge.app"
    cp -R "$APP" "$INSTALL_DIR/Purge.app"
    touch "$INSTALL_DIR/Purge.app"
    echo "==> Lancement"
    open "$INSTALL_DIR/Purge.app"
    echo
    echo "✅ Purge installé dans $INSTALL_DIR et lancé."
else
    echo "==> Prêt : $APP"
    echo "    Lancer avec : open $APP"
    echo "    Installer   : ./build.sh --install"
fi
