#!/usr/bin/env bash
#
# install.sh — installe l'essentiel de FriteOS en une seule commande : recovery, ROM,
# SetupWizard patché (optionnel) et GApps (optionnel). Sortie texte pure (pas de TUI) :
# juste les étapes et un pourcentage. Attend automatiquement que la tablette soit
# connectée dans le bon mode à chaque étape, au lieu de te demander d'appuyer sur Entrée
# à l'aveugle — tu n'as qu'à faire les actions physiques (bouton, menu TWRP) demandées.
#
# Usage :
#   ./install.sh <twrp.img> <rom.zip> [setupwizard-patched.apk] [gapps.zip]
#
# Voir README.md pour où trouver ces fichiers, et docs/CUSTOMIZATION.md pour le détail
# de chaque étape (GApps, SetupWizard patché, etc).

set -uo pipefail

if [ -t 1 ]; then
  C_STEP='\033[1;36m'   # cyan gras : pourcentage/étape
  C_INFO='\033[0;90m'   # gris : info secondaire
  C_WAIT='\033[1;33m'   # jaune : en attente de la tablette
  C_OK='\033[1;32m'     # vert : détecté / succès
  C_ERR='\033[1;31m'    # rouge : erreur
  C_RESET='\033[0m'
else
  C_STEP='' C_INFO='' C_WAIT='' C_OK='' C_ERR='' C_RESET=''
fi

log() { printf "${C_STEP}[%3d%%]${C_RESET} %s\n" "$1" "$2"; }
err() { printf "${C_ERR}ERREUR :${C_RESET} %s\n" "$*" >&2; }
info() { printf "${C_INFO}        %s${C_RESET}\n" "$*"; }

# ensure_cmd <commande> <paquet_apt>
ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0

  if ! command -v apt-get >/dev/null 2>&1; then
    err "Commande manquante : $cmd, et apt-get n'est pas disponible pour l'installer automatiquement."
    exit 1
  fi

  echo "        Commande manquante : $cmd — installation via apt (paquet '$pkg')..."
  if ! sudo apt-get update -qq || ! sudo apt-get install -y "$pkg"; then
    err "Échec de l'installation de '$pkg'. Installe-le manuellement puis relance."
    exit 1
  fi
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' toujours introuvable après l'installation de '$pkg'."; exit 1; }
}

usage() {
  cat <<EOF
Usage: $0 <twrp.img> <rom.zip> [setupwizard-patched.apk] [gapps.zip]

  twrp.img                    Recovery TWRP à flasher (obligatoire)
  rom.zip                     ROM LineageOS à installer (obligatoire)
  setupwizard-patched.apk     APK SetupWizard patché (optionnel, voir patch_branding.sh)
  gapps.zip                   Package GApps, ex: open_gapps-arm-7.1-pico (optionnel)
EOF
  exit 1
}

# wait_for_heimdall — bloque jusqu'à ce que la tablette soit détectée en Download Mode.
wait_for_heimdall() {
  local n=0
  while ! heimdall detect >/dev/null 2>&1; do
    printf "\r${C_WAIT}        En attente... (%ds, Ctrl+C pour annuler)${C_RESET}" "$n"
    sleep 1
    n=$((n + 1))
  done
  printf "\r${C_OK}        Tablette détectée en Download Mode.            ${C_RESET}\n"
}

# wait_for_adb_state <motif> <message d'attente>
# Bloque jusqu'à ce qu'un device adb dont l'état matche <motif> (grep -E) soit visible.
wait_for_adb_state() {
  local pattern="$1" n=0
  while ! adb devices | tail -n +2 | grep -qE "$pattern"; do
    printf "\r${C_WAIT}        En attente... (%ds, Ctrl+C pour annuler)${C_RESET}" "$n"
    sleep 1
    n=$((n + 1))
  done
  printf "\r${C_OK}        Tablette détectée.                              ${C_RESET}\n"
}

fail_step() {
  err "Échec pendant : $1"
  exit 1
}

main() {
  [ $# -ge 2 ] || usage
  local twrp_img="$1" rom_zip="$2" setupwizard_apk="${3:-}" gapps_zip="${4:-}"

  log 5 "Vérification des fichiers..."
  [ -f "$twrp_img" ] || { err "Recovery introuvable : $twrp_img"; exit 1; }
  [ -f "$rom_zip" ] || { err "ROM introuvable : $rom_zip"; exit 1; }
  [ -n "$setupwizard_apk" ] && [ ! -f "$setupwizard_apk" ] && { err "APK SetupWizard introuvable : $setupwizard_apk"; exit 1; }
  [ -n "$gapps_zip" ] && [ ! -f "$gapps_zip" ] && { err "GApps introuvable : $gapps_zip"; exit 1; }
  ensure_cmd heimdall heimdall-flash
  ensure_cmd adb android-tools-adb
  info "OK. SetupWizard patché : ${setupwizard_apk:-non fourni, ignoré}"
  info "GApps : ${gapps_zip:-non fournies, ignorées}"

  log 15 "Éteins la tablette, puis Download Mode : Volume bas + Home + Power, puis Volume haut pour confirmer."
  wait_for_heimdall

  log 30 "Flash du recovery (TWRP)..."
  heimdall flash --RECOVERY "$twrp_img" --no-reboot || fail_step "flash du recovery"

  log 40 "Redémarre manuellement en recovery : Volume haut + Home + Power."
  wait_for_adb_state '(device|recovery)$'

  log 55 "Dans TWRP : Advanced > ADB Sideload."
  wait_for_adb_state 'sideload$'
  info "Sideload de la ROM ($rom_zip)..."
  adb sideload "$rom_zip" || fail_step "sideload de la ROM"

  if [ -n "$setupwizard_apk" ]; then
    log 65 "Sideload terminé. Reviens au menu principal TWRP (bouton retour)."
    wait_for_adb_state '(device|recovery)$'
    info "Installation du SetupWizard patché..."
    local remote_path="/system/priv-app/LineageSetupWizard/LineageSetupWizard.apk"
    adb push "$setupwizard_apk" /sdcard/SetupWizard-patched.apk || fail_step "push du SetupWizard patché"
    local copy_cmd="mount -o rw,remount /system 2>/dev/null; cp /sdcard/SetupWizard-patched.apk '$remote_path' && chmod 644 '$remote_path'"
    if ! adb shell "$copy_cmd" >/dev/null 2>&1 || ! adb shell "[ -f '$remote_path' ]" >/dev/null 2>&1; then
      err "Échec de l'installation automatique du SetupWizard patché — chemin peut-être différent sur cette ROM."
      err "Installe-le manuellement avec : ./scripts/flash.sh setupwizard $setupwizard_apk"
    fi
  fi

  if [ -n "$gapps_zip" ]; then
    log 80 "Retourne dans Advanced > ADB Sideload."
    wait_for_adb_state 'sideload$'
    info "Sideload de GApps ($gapps_zip)..."
    adb sideload "$gapps_zip" || fail_step "sideload de GApps"
  fi

  log 95 "Retourne au menu principal TWRP, fais Wipe > Format Data (et Cache), puis reboot système."
  log 100 "Terminé. Une fois démarré, ./scripts/flash.sh bootanimation pour le splash custom."
}

main "$@"
