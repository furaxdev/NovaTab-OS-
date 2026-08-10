#!/usr/bin/env bash
#
# ultra_powersave.sh — équivalent maison du "Mode ultra économie d'énergie" que certaines
# marques proposent (écran en niveaux de gris, animations coupées, luminosité/veille réduites,
# sync en arrière-plan coupée). Fonctionne via adb shell settings — pas besoin de root ni de
# recompiler, le shell adb a le droit d'écrire les settings "secure"/"global" contrairement à
# une app normale.
#
# Usage :
#   ./ultra_powersave.sh on     Active le mode ultra économie d'énergie
#   ./ultra_powersave.sh off    Restaure les réglages normaux

set -euo pipefail

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

# Apps non essentielles désactivées (pm disable-user, réversible) pendant le mode ultra —
# pas juste tuées une fois : empêchées de redémarrer en fond tant que le mode est actif.
# Pas les apps système, ni le lanceur/clavier/paramètres/Play Store.
NON_ESSENTIAL_PACKAGES=(
  com.google.android.youtube
  com.google.android.apps.maps
  com.candyroom.clubcraft
  com.cyanogenmod.eleven
  org.cyanogenmod.audiofx
)

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

  log "Désactivation des apps non essentielles (empêchées de tourner en fond, réversible)..."
  for pkg in "${NON_ESSENTIAL_PACKAGES[@]}"; do
    adb shell am force-stop "$pkg" >/dev/null 2>&1 || true
    adb shell pm disable-user --user 0 "$pkg" >/dev/null 2>&1 || true
  done

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

  log "Réactivation des apps non essentielles..."
  for pkg in "${NON_ESSENTIAL_PACKAGES[@]}"; do
    adb shell pm enable --user 0 "$pkg" >/dev/null 2>&1 || true
  done

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
