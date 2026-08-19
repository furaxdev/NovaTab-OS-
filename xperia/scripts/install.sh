#!/usr/bin/env bash
#
# install.sh — installe FuraxOS sur le Sony Xperia XZ (F8331, kagura) en une commande :
# TWRP (fastboot) + ROM + GApps (optionnel). Attend automatiquement que le téléphone soit
# dans le bon mode à chaque étape.
#
# ⚠️ Le bootloader DOIT être débloqué AVANT de lancer ce script.
#    Voir : ./flash.sh unlock (rappel des étapes Sony)
#
# Usage :
#   ./install.sh <twrp.img> <rom.zip> [gapps.zip]
#
# Exemple (avec download.sh) :
#   ./install.sh ~/Téléchargements/furaxos-xperia/twrp-3.7.0_9-0-kagura.img \
#                ~/Téléchargements/furaxos-xperia/lineage-15.0-kagura.zip \
#                ~/Téléchargements/furaxos-xperia/open_gapps-arm64-8.1-pico.zip

set -uo pipefail

if [ -t 1 ]; then
  C_STEP='\033[1;36m'; C_INFO='\033[0;90m'; C_WAIT='\033[1;33m'
  C_OK='\033[1;32m'; C_ERR='\033[1;31m'; C_RESET='\033[0m'
else
  C_STEP=''; C_INFO=''; C_WAIT=''; C_OK=''; C_ERR=''; C_RESET=''
fi

log()  { printf "${C_STEP}[%3d%%]${C_RESET} %s\n" "$1" "$2"; }
err()  { printf "${C_ERR}ERREUR :${C_RESET} %s\n" "$*" >&2; }
info() { printf "${C_INFO}        %s${C_RESET}\n" "$*"; }

ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  if ! command -v apt-get >/dev/null 2>&1; then
    err "Commande manquante : $cmd"; exit 1
  fi
  echo "        Installation de $cmd via apt..."
  sudo apt-get update -qq && sudo apt-get install -y "$pkg"
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' toujours introuvable."; exit 1; }
}

usage() {
  cat <<EOF
Usage: $0 <twrp.img> <rom.zip> [gapps.zip]

  twrp.img     TWRP à flasher (ex: twrp-3.7.0_9-0-kagura.img)
  rom.zip      ROM LineageOS à installer (ex: lineage-15.0-kagura.zip)
  gapps.zip    GApps optionnel (ex: open_gapps-arm64-8.1-pico.zip)

⚠️  Le bootloader doit être débloqué AVANT : ./flash.sh unlock
EOF
  exit 1
}

wait_for_fastboot() {
  local n=0
  while ! fastboot devices 2>/dev/null | grep -q fastboot; do
    printf "\r${C_WAIT}        En attente mode Fastboot... (%ds, Ctrl+C pour annuler)${C_RESET}" "$n"
    sleep 1; n=$((n+1))
  done
  printf "\r${C_OK}        Téléphone détecté en mode Fastboot.               ${C_RESET}\n"
}

wait_for_adb_state() {
  local pattern="$1" n=0
  while ! adb devices | tail -n +2 | grep -qE "$pattern"; do
    printf "\r${C_WAIT}        En attente... (%ds, Ctrl+C pour annuler)${C_RESET}" "$n"
    sleep 1; n=$((n+1))
  done
  printf "\r${C_OK}        Téléphone détecté.                                ${C_RESET}\n"
}

fail() { err "Échec pendant : $1"; exit 1; }

main() {
  [ $# -ge 2 ] || usage
  local twrp_img="$1" rom_zip="$2" gapps_zip="${3:-}"

  log 5 "Vérification des fichiers..."
  [ -f "$twrp_img" ] || { err "TWRP introuvable : $twrp_img"; exit 1; }
  [ -f "$rom_zip" ]  || { err "ROM introuvable : $rom_zip"; exit 1; }
  [ -n "$gapps_zip" ] && [ ! -f "$gapps_zip" ] && { err "GApps introuvable : $gapps_zip"; exit 1; }
  ensure_cmd fastboot android-tools-fastboot
  ensure_cmd adb android-tools-adb
  info "TWRP  : $twrp_img"
  info "ROM   : $rom_zip"
  info "GApps : ${gapps_zip:-non fournis, ignorés}"

  log 10 "Éteins le téléphone, puis maintiens Volume haut en branchant l'USB (mode Fastboot)."
  wait_for_fastboot

  log 30 "Flash du recovery TWRP..."
  fastboot flash recovery "$twrp_img" || fail "flash TWRP"
  info "TWRP flashé."

  log 40 "Redémarre en recovery (Volume bas juste après avoir branché, ou via le menu Fastboot)."
  wait_for_adb_state '(device|recovery)$'

  log 55 "Dans TWRP : Advanced > ADB Sideload — glisse pour activer."
  wait_for_adb_state 'sideload$'
  info "Sideload de la ROM..."
  adb sideload "$rom_zip" || fail "sideload ROM"

  if [ -n "$gapps_zip" ]; then
    log 75 "Retourne dans TWRP : Advanced > ADB Sideload (sans reboot !)."
    wait_for_adb_state 'sideload$'
    info "Sideload de GApps..."
    adb sideload "$gapps_zip" || fail "sideload GApps"
  fi

  log 90 "Dans TWRP : Wipe > Format Data (tape 'yes') puis reboot System."
  log 100 "Terminé ! FuraxOS démarre. Lance ensuite patch_branding.sh pour cacher LineageOS."
  info "Pour restaurer tes données : ./restore_backup.sh <apps.ab> <dossier-sdcard>"
}

main "$@"
