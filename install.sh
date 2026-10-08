#!/bin/bash
# Compile et installe les Micro-app dans /Applications.
#
#   ./install.sh                 tout ce qui est compatible avec ce Mac
#   ./install.sh grab ports      seulement ces apps
#   ./install.sh --sans fancontrole   tout sauf celles-ci
#   ./install.sh --simulation    montre le plan sans rien compiler
#
# Ne demande jamais sudo. Le démon des ventilateurs s'installe à part :
#   ./fancontrole/install.sh     (dans un vrai Terminal)
set -uo pipefail
cd "$(dirname "$0")"

TOUTES=(trousse fancontrole ejecter purge eveil grab ports bande etagere)
choix=(); sans=(); simulation=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sans) sans+=("$2"); shift 2 ;;
    --simulation) simulation=1; shift ;;
    *) choix+=("$1"); shift ;;
  esac
done
[[ ${#choix[@]} -eq 0 ]] && choix=("${TOUTES[@]}")

major=$(sw_vers -productVersion | cut -d. -f1)
modele=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2}')

# La signature stable d'abord : sans elle, chaque reconstruction perd ses autorisations.
if [[ $simulation -eq 0 ]]; then
  ./Tools/identite.sh >/dev/null 2>&1 || echo "⚠️  identité de signature indisponible (cf. CLAUDE.md)"
  security list-keychains -d user | grep -q microapp.keychain || \
    security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db" "$HOME/Library/Keychains/microapp.keychain-db" 2>/dev/null
fi

ok=(); echec=(); ignore=()
for app in "${choix[@]}"; do
  raison=""
  [[ " ${sans[*]-} " == *" $app "* ]] && raison="exclue (--sans)"
  [[ $app == trousse && $major -lt 26 ]] && raison="exige macOS 26+"
  [[ $app == fancontrole && $modele == *"MacBook Air"* ]] && raison="MacBook Air sans ventilateur"
  [[ -f "$app/build.sh" ]] || raison="dossier introuvable"
  if [[ -n $raison ]]; then ignore+=("$app ($raison)"); continue; fi
  if [[ $simulation -eq 1 ]]; then ok+=("$app"); continue; fi
  echo; echo "━━ $app ━━"
  if (cd "$app" && ./build.sh --install); then ok+=("$app"); else echec+=("$app"); fi
done

echo; echo "━━ Bilan ━━"
echo "Installées : ${ok[*]-aucune}"
echo "Ignorées   : ${ignore[*]-aucune}"
echo "Échecs     : ${echec[*]-aucun}"
[[ " ${ok[*]-} " == *" fancontrole "* && $simulation -eq 0 ]] && \
  echo "→ Ventilateurs : lance maintenant ./fancontrole/install.sh dans un vrai Terminal (mot de passe admin)."
[[ ${#echec[@]} -eq 0 ]]
