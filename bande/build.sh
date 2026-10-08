#!/bin/bash
# Compile et assemble Bande.app.
#
#   ./build.sh              construit dans ./build
#   ./build.sh --install    construit puis installe dans /Applications
set -euo pipefail

cd "$(dirname "$0")"
CONFIG=release
APP="build/Bande.app"
INSTALL_DIR="/Applications"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

echo "==> Compilation"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/BandeApp

echo "==> Génération de l'icône"
mkdir -p build
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/Bande.iconset >/dev/null
iconutil -c icns build/Bande.iconset -o build/Bande.icns

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bande"
cp build/Bande.icns "$APP/Contents/Resources/Bande.icns"

# CFBundleDocumentTypes est ce qui rend l'icône du Dock réceptive : sans cette
# déclaration, macOS refuse le lâcher d'une vidéo sur l'app.
#
# Les chaînes NS*UsageDescription sont le texte affiché quand le fichier audio
# doit être écrit sur le Bureau, dans Documents, dans Téléchargements ou sur un
# disque externe. Sans elles, le système refuse l'écriture sans rien demander.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Bande</string>
    <key>CFBundleDisplayName</key>       <string>Bande</string>
    <key>CFBundleIdentifier</key>        <string>local.bande</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>Bande</string>
    <key>CFBundleIconFile</key>          <string>Bande</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>  <string>Vidéo</string>
            <key>CFBundleTypeRole</key>  <string>Viewer</string>
            <key>LSHandlerRank</key>     <string>None</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.audiovisual-content</string>
            </array>
        </dict>
    </array>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Pour écrire l'audio à côté d'une vidéo posée sur le Bureau.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Pour écrire l'audio à côté d'une vidéo rangée dans Documents.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Pour écrire l'audio à côté d'une vidéo téléchargée.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Pour lire les vidéos rangées sur un disque externe.</string>
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
    pkill -f "Bande.app/Contents/MacOS/Bande" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/Bande.app"
    cp -R "$APP" "$INSTALL_DIR/Bande.app"
    touch "$INSTALL_DIR/Bande.app"
    echo "==> Lancement"
    open "$INSTALL_DIR/Bande.app"
    echo
    echo "✅ Bande installé dans $INSTALL_DIR et lancé."
else
    echo "==> Prêt : $APP"
    echo "    Lancer avec : open $APP"
    echo "    Installer   : ./build.sh --install"
fi
