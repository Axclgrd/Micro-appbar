#!/bin/bash
# Profil du Mac : ce que Claude lit avant d'installer ou de personnaliser.
# Lecture seule, aucune écriture, aucun sudo.
set -uo pipefail

macos=$(sw_vers -productVersion)
major=${macos%%.*}
puce=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
modele=$(sysctl -n hw.model)
nom=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2}')
arch=$(uname -m)

echo "== Mac =="
echo "Nom          : ${nom:-inconnu}"
echo "Identifiant  : $modele"
echo "Puce         : $puce ($arch)"
echo "macOS        : $macos"
echo

echo "== Outils de compilation =="
if xcode-select -p >/dev/null 2>&1; then echo "Command Line Tools : OK ($(xcode-select -p))"; else echo "Command Line Tools : MANQUANT → xcode-select --install"; fi
if command -v swift >/dev/null; then echo "Swift        : $(swift --version 2>&1 | head -1)"; else echo "Swift        : MANQUANT"; fi
command -v openssl >/dev/null && echo "openssl      : OK" || echo "openssl      : MANQUANT (signature stable impossible)"
echo

echo "== Signature (identité Micro-app) =="
if security find-identity -p codesigning 2>/dev/null | grep -q "Micro-app"; then echo "Identité     : présente"; else echo "Identité     : absente (sera créée par Tools/identite.sh)"; fi
if security list-keychains -d user | grep -q microapp.keychain; then echo "Search list  : OK"; else echo "Search list  : microapp.keychain absent de la liste (cf. CLAUDE.md, piège n°1)"; fi
echo

echo "== Compatibilité par app =="
echo "Trousse      : $([ "$major" -ge 26 ] && echo OK || echo "IGNORER (exige macOS 26+, ici $macos)")"
echo "Autres apps  : $([ "$major" -ge 14 ] && echo OK || echo "IGNORER (exige macOS 14+)")"
echo

echo "== Ventilateurs =="
case "$nom$modele" in
  *"MacBook Air"*|*MacBookAir*)
    echo "MacBook Air : AUCUN ventilateur → ne PAS installer fancontrole (inutile)." ;;
  *)
    echo "Ventilateurs probables → fancontrole utile."
    echo "Le nombre réel est lu dans la SMC (clé FNum) par l'app une fois lancée."
    [ -S /var/run/fancontrold.sock ] && echo "Démon fancontrold : actif" || echo "Démon fancontrold : non installé" ;;
esac
echo

echo "== Apps déjà installées =="
for a in FanControl Ejecter Purge Eveil Grab Trousse Ports Bande Etagere; do
  [ -d "/Applications/$a.app" ] && echo "  ✓ $a" || echo "  · $a"
done
