#!/bin/bash
# Compile et assemble Fonte.app.
#
#   ./build.sh              construit dans ./build
#   ./build.sh --install    construit puis installe dans /Applications
#
# MenuBarExtra exige un vrai bundle applicatif. Le raccourci global aussi : les
# autorisations de capture d'écran sont accordées à un bundle identifié, pas à
# un binaire nu — sans bundle, macOS redemande l'autorisation à chaque lancement.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG=release
APP="build/Fonte.app"
INSTALL_DIR="/Applications"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

echo "==> Compilation"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/FonteApp

echo "==> Génération de l'icône"
mkdir -p build
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/Fonte.iconset >/dev/null
iconutil -c icns build/Fonte.iconset -o build/Fonte.icns

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Fonte"
cp build/Fonte.icns "$APP/Contents/Resources/Fonte.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Fonte</string>
    <key>CFBundleDisplayName</key>       <string>Fonte</string>
    <key>CFBundleIdentifier</key>        <string>local.fonte</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>Fonte</string>
    <key>CFBundleIconFile</key>          <string>Fonte</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <!-- Agent : pas d'icône dans le Dock, pas de menu applicatif. -->
    <key>LSUIElement</key>               <true/>
    <!-- « Ouvrir avec Fonte » et le lâcher d'une image sur l'app. -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>  <string>Image</string>
            <key>CFBundleTypeRole</key>  <string>Viewer</string>
            <key>LSHandlerRank</key>     <string>None</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
            </array>
        </dict>
    </array>
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
    pkill -f "Fonte.app/Contents/MacOS/Fonte" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/Fonte.app"
    cp -R "$APP" "$INSTALL_DIR/Fonte.app"
    touch "$INSTALL_DIR/Fonte.app"
    echo "==> Lancement"
    open "$INSTALL_DIR/Fonte.app"
    echo
    echo "✅ Fonte installé dans $INSTALL_DIR et lancé."
else
    echo "==> Prêt : $APP"
    echo "    Lancer avec : open $APP"
    echo "    Installer   : ./build.sh --install"
fi
