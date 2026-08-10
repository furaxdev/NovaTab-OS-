#!/usr/bin/env bash
#
# ultra_powersave.sh — équivalent maison du "Mode ultra économie d'énergie" que certaines
# marques proposent (écran en niveaux de gris, animations coupées, luminosité/veille réduites,
# sync en arrière-plan coupée, apps tierces non essentielles désactivées). Fonctionne via
# adb shell settings/pm — pas besoin de root ni de recompiler, le shell adb a le droit
# d'écrire les settings "secure"/"global" et de désactiver des apps, contrairement à une
# app normale. Le launcher/écran d'accueil se vide de lui-même : les apps désactivées
# n'apparaissent simplement plus dedans, comme sur les vrais modes ultra des constructeurs.
#
# Usage :
#   ./ultra_powersave.sh on     Active le mode ultra économie d'énergie
#   ./ultra_powersave.sh off    Restaure les réglages normaux

set -euo pipefail

WORKDIR_STATE="$HOME/.cache/fritaxos"

log() { echo -e "\033[1;32m[fritaxos-powersave]\033[0m $*"; }
err() { echo -e "\033[1;31m[fritaxos-powersave]\033[0m $*" >&2; }

ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  if ! command -v apt-get >/dev/null 2>&1; then
    err "Commande manquante : $cmd, et apt-get n'est pas disponible pour l'installer automatiquement."
    exit 1
  fi
  log "Commande manquante : $cmd — installation via apt (paquet '$pkg')..."
  sudo apt-get update -qq && sudo apt-get install -y "$pkg"
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' toujours introuvable."; exit 1; }
}

# Liste BLANCHE : ces apps tierces (installées, pas les apps système) restent actives en
# mode ultra. TOUT le reste des apps tierces (pm list packages -3) est désactivé (réversible).
# C'est ce mécanisme — pas un launcher spécial — qui fait que l'écran d'accueil devient
# minimal chez Huawei : les apps désactivées disparaissent simplement du launcher.
# Ajoute ici toute app tierce que tu veux garder utilisable en mode ultra (vérifie le nom
# exact du package avec : adb shell pm list packages -3).
ESSENTIAL_PACKAGES=(
  com.teslacoilsw.launcher   # Nova Launcher — jamais désactiver, sinon plus d'écran d'accueil
  com.android.vending        # Play Store (au cas où listé en -3 sur cette build)
)

is_essential() {
  local pkg="$1"
  for e in "${ESSENTIAL_PACKAGES[@]}"; do
    [ "$pkg" = "$e" ] && return 0
  done
  return 1
}

enable_ultra() {
  log "Activation du mode ultra économie d'énergie..."

  log "Écran en niveaux de gris (daltonizer monochrome)..."
  adb shell settings put secure accessibility_display_daltonizer_enabled 1
  adb shell settings put secure accessibility_display_daltonizer 0

  log "Animations coupées..."
  adb shell settings put global window_animation_scale 0
  adb shell settings put global transition_animation_scale 0
  adb shell settings put global animator_duration_scale 0

  log "Luminosité réduite au minimum, luminosité auto désactivée..."
  adb shell settings put system screen_brightness_mode 0
  adb shell settings put system screen_brightness 10

  log "Veille écran raccourcie à 15s..."
  adb shell settings put system screen_off_timeout 15000

  log "Rotation auto désactivée..."
  adb shell settings put system accelerometer_rotation 0

  log "Synchronisation en arrière-plan désactivée..."
  adb shell settings put global master_sync 0 || adb shell content update --uri content://settings/global --bind name:s:master_sync --bind value:s:0 >/dev/null 2>&1 || true

  log "Scan WiFi permanent désactivé (scan seulement quand l'écran est allumé)..."
  adb shell settings put global wifi_scan_always_enabled 0

  log "Désactivation de toutes les apps tierces non listées dans ESSENTIAL_PACKAGES..."
  local disabled_list="$WORKDIR_STATE/disabled-packages.txt"
  mkdir -p "$(dirname "$disabled_list")"
  : > "$disabled_list"
  while read -r pkg; do
    pkg="${pkg#package:}"
    [ -z "$pkg" ] && continue
    is_essential "$pkg" && continue
    adb shell am force-stop "$pkg" >/dev/null 2>&1 || true
    if adb shell pm disable-user --user 0 "$pkg" >/dev/null 2>&1; then
      echo "$pkg" >> "$disabled_list"
    fi
  done < <(adb shell pm list packages -3 | tr -d '\r')

  log "$(wc -l < "$disabled_list" | tr -d ' ') app(s) désactivée(s) — liste sauvegardée dans $disabled_list pour le off."
  log "Mode ultra économie d'énergie activé. Pour revenir en arrière : ./ultra_powersave.sh off"
}

disable_ultra() {
  log "Désactivation du mode ultra économie d'énergie (retour aux réglages normaux)..."

  adb shell settings put secure accessibility_display_daltonizer_enabled 0

  adb shell settings put global window_animation_scale 1
  adb shell settings put global transition_animation_scale 1
  adb shell settings put global animator_duration_scale 1

  adb shell settings put system screen_brightness_mode 1

  adb shell settings put system screen_off_timeout 60000

  adb shell settings put system accelerometer_rotation 1

  adb shell settings put global master_sync 1

  adb shell settings put global wifi_scan_always_enabled 1

  local disabled_list="$WORKDIR_STATE/disabled-packages.txt"
  if [ -f "$disabled_list" ]; then
    log "Réactivation des apps désactivées par le dernier 'on' ($(wc -l < "$disabled_list" | tr -d ' ') app(s))..."
    while read -r pkg; do
      [ -z "$pkg" ] && continue
      adb shell pm enable --user 0 "$pkg" >/dev/null 2>&1 || true
    done < "$disabled_list"
    rm -f "$disabled_list"
  else
    log "Aucune liste d'apps désactivées trouvée (mode déjà off, ou jamais activé sur cette machine)."
  fi

  log "Réglages normaux restaurés."
}

usage() {
  cat <<EOF
Usage:
  $0 on     Active le mode ultra économie d'énergie (gris, animations coupées, veille courte...)
  $0 off    Restaure les réglages normaux
EOF
  exit 1
}

[ $# -eq 1 ] || usage
ensure_cmd adb android-tools-adb

case "$1" in
  on)  enable_ultra ;;
  off) disable_ultra ;;
  *)   usage ;;
esac
