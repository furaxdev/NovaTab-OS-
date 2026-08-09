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
#   ./flash.sh gapps /chemin/vers/open_gapps-arm-7.1-pico.zip  # sideload GApps via ADB
#   ./flash.sh bootanimation /chemin/vers/bootanimation.zip    # pousse un boot animation custom
#
# Prérequis : heimdall (paquet 'heimdall-flash' sous Debian/Ubuntu) et adb installés.
#
# Ordre recommandé pour une install complète avec GApps + splash custom :
#   1. ./flash.sh recovery twrp-milletwifi.img
#   2. (reboot en recovery)
#   3. ./flash.sh rom lineage-14.1-....zip
#   4. ./flash.sh gapps open_gapps-arm-7.1-pico.zip   (sans reboot entre les deux, toujours dans TWRP)
#   5. reboot système, puis ./flash.sh bootanimation bootanimation.zip (voir docs/CUSTOMIZATION.md)

set -euo pipefail

log() { echo -e "\033[1;32m[novatab-flash]\033[0m $*"; }
err() { echo -e "\033[1;31m[novatab-flash]\033[0m $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Commande manquante : $1 (installe-la avant de continuer)"; exit 1; }
}

usage() {
  cat <<EOF
Usage:
  $0 recovery <fichier_twrp.img>       Flash TWRP en mode Download (via Heimdall)
  $0 rom <fichier_rom.zip>             Sideload la ROM via ADB (tablette doit être dans TWRP)
  $0 gapps <fichier_gapps.zip>         Sideload un package GApps via ADB (juste après la ROM, dans TWRP)
  $0 bootanimation <fichier.zip>       Pousse un bootanimation.zip custom (système déjà démarré + root, ou via TWRP)
  $0 backup                            Sauvegarde /data via adb avant de flasher (recommandé)
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

sideload_gapps() {
  local zip="$1"
  require_cmd adb
  [ -f "$zip" ] || { err "Fichier introuvable : $zip"; exit 1; }

  log "GApps doit être flashé JUSTE APRÈS la ROM, sans reboot entre les deux, toujours dans TWRP."
  log "Vu la RAM limitée du SM-T530 (1,5 Go), privilégie une variante 'pico' ou 'nano' de GApps"
  log "(ex: open_gapps-arm-7.1-pico.zip) — les variantes 'stock'/'super' saturent la RAM."
  confirm "Es-tu bien dans TWRP juste après avoir flashé la ROM (Advanced > ADB Sideload) ?"

  log "Sideload de GApps ($zip)..."
  adb sideload "$zip"

  log "GApps installé. Tu peux maintenant reboot le système."
}

push_bootanimation() {
  local zip="$1"
  require_cmd adb
  [ -f "$zip" ] || { err "Fichier introuvable : $zip"; exit 1; }

  log "Deux méthodes possibles :"
  log "  a) Système déjà démarré + accès root (adb root / su) :"
  log "     adb push $zip /system/media/bootanimation.zip"
  log "  b) Depuis TWRP (système monté, avant premier boot) : même commande, TWRP a déjà les droits."
  confirm "La tablette est-elle prête (root actif, ou dans TWRP avec /system monté) ?"

  adb push "$zip" /sdcard/bootanimation.zip
  if adb shell "su -c 'cp /sdcard/bootanimation.zip /system/media/bootanimation.zip && chmod 644 /system/media/bootanimation.zip'" 2>/dev/null; then
    log "bootanimation.zip installé via root. Reboot pour voir le résultat."
  else
    log "Root non détecté via 'su' — copie manuelle nécessaire."
    log "Depuis TWRP : File Manager > copier /sdcard/bootanimation.zip vers /system/media/bootanimation.zip"
    log "Ou : adb shell puis 'mount -o rw,remount /system' avant de copier."
  fi
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
  gapps)
    [ $# -eq 2 ] || usage
    sideload_gapps "$2"
    ;;
  bootanimation)
    [ $# -eq 2 ] || usage
    push_bootanimation "$2"
    ;;
  backup)
    backup_data
    ;;
  *)
    usage
    ;;
esac
