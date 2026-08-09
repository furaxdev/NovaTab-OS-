#!/usr/bin/env bash
#
# flash.sh — installe un recovery custom (TWRP) puis sideload la ROM NovaTab OS
# sur la Galaxy Tab 4 10.1" SM-T530.
#
# ATTENTION : les appareils Samsung n'utilisent PAS Fastboot mais le protocole Odin
# (Download Mode). Ce script utilise donc Heimdall (implémentation libre d'Odin) pour
# le recovery, puis `adb sideload` pour flasher la ROM elle-même une fois dans le recovery.
#
# Usage :
#   ./flash.sh recovery /chemin/vers/twrp-milletwifi.img.tar   # flash TWRP via Heimdall
#   ./flash.sh rom /chemin/vers/lineage-14.1-....zip           # sideload la ROM via ADB
#
# Prérequis : heimdall (paquet 'heimdall-flash' sous Debian/Ubuntu) et adb installés.

set -euo pipefail

log() { echo -e "\033[1;32m[novatab-flash]\033[0m $*"; }
err() { echo -e "\033[1;31m[novatab-flash]\033[0m $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Commande manquante : $1 (installe-la avant de continuer)"; exit 1; }
}

usage() {
  cat <<EOF
Usage:
  $0 recovery <fichier_twrp.img>   Flash TWRP en mode Download (via Heimdall)
  $0 rom <fichier_rom.zip>         Sideload la ROM via ADB (tablette doit être dans TWRP)
  $0 backup                        Sauvegarde /data via adb avant de flasher (recommandé)
EOF
  exit 1
}

confirm() {
  read -r -p "$1 [o/N] " reply
  [[ "$reply" =~ ^[oOyY]$ ]] || { log "Annulé."; exit 0; }
}

flash_recovery() {
  local img="$1"
  require_cmd heimdall
  [ -f "$img" ] || { err "Fichier introuvable : $img"; exit 1; }

  log "Assure-toi que la tablette est en Download Mode :"
  log "  Éteins-la, puis maintiens Volume bas + Home + Power, puis Volume haut pour confirmer."
  confirm "La tablette est-elle bien en Download Mode et branchée en USB ?"

  log "Flash du recovery via Heimdall..."
  heimdall flash --RECOVERY "$img" --no-reboot

  log "Recovery flashé. Redémarre manuellement en recovery (Volume haut + Home + Power) pour continuer."
}

sideload_rom() {
  local zip="$1"
  require_cmd adb
  [ -f "$zip" ] || { err "Fichier introuvable : $zip"; exit 1; }

  log "Assure-toi que la tablette est démarrée dans TWRP, menu 'Advanced > ADB Sideload'."
  confirm "La tablette est-elle en mode ADB Sideload dans TWRP ?"

  log "Sideload de la ROM ($zip)..."
  adb sideload "$zip"

  log "Sideload terminé. Reboote la tablette depuis le menu TWRP."
}

backup_data() {
  require_cmd adb
  log "Sauvegarde des données utilisateur (dossier interne) vers ./backup-$(date +%Y%m%d-%H%M%S)/"
  local dest="backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dest"
  adb pull /sdcard "$dest/sdcard" || err "Échec de la sauvegarde /sdcard (continue quand même si tu es sûr)"
  log "Sauvegarde terminée dans $dest/"
}

[ $# -ge 1 ] || usage

case "$1" in
  recovery)
    [ $# -eq 2 ] || usage
    flash_recovery "$2"
    ;;
  rom)
    [ $# -eq 2 ] || usage
    sideload_rom "$2"
    ;;
  backup)
    backup_data
    ;;
  *)
    usage
    ;;
esac
