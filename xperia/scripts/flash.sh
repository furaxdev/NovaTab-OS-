#!/usr/bin/env bash
#
# flash.sh — installe un recovery custom (TWRP) puis sideload la ROM FuraxOS
# sur le Sony Xperia XZ F8331 (kagura).
#
# Contrairement à la Tab 4 (Odin/Heimdall), le Xperia XZ utilise Fastboot (standard
# Android) pour le recovery, puis `adb sideload` pour la ROM une fois dans TWRP.
#
# Usage :
#   ./flash.sh unlock                                        # rappel des étapes de déblocage bootloader
#   ./flash.sh recovery /chemin/vers/twrp-kagura.img          # flash TWRP via fastboot
#   ./flash.sh rom /chemin/vers/lineage-15.1-....zip          # sideload la ROM via ADB
#   ./flash.sh gapps /chemin/vers/open_gapps-arm-8.1-....zip  # sideload GApps via ADB
#   ./flash.sh bootanimation /chemin/vers/bootanimation.zip   # pousse un boot animation custom
#
# Prérequis : fastboot et adb (paquet 'android-tools-fastboot'/'android-tools-adb').
#
# Ordre recommandé pour une install complète :
#   1. SAUVEGARDE d'abord (voir ../README.md) — le déblocage bootloader efface /data.
#   2. ./flash.sh unlock          (rappel des étapes, l'unlock lui-même se fait via fastboot)
#   3. ./flash.sh recovery twrp-kagura.img
#   4. (reboot en recovery)
#   5. ./flash.sh rom lineage-15.1-....zip
#   6. ./flash.sh gapps open_gapps-arm-8.1-....zip   (sans reboot entre les deux, toujours dans TWRP)
#   7. reboot système, puis ../scripts/restore_backup.sh pour tout remettre

set -euo pipefail

log() { echo -e "\033[1;32m[furaxos-flash]\033[0m $*"; }
err() { echo -e "\033[1;31m[furaxos-flash]\033[0m $*" >&2; }

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

usage() {
  cat <<EOF
Usage:
  $0 unlock                            Rappel des étapes de déblocage bootloader (efface /data)
  $0 recovery <fichier_twrp.img>       Flash TWRP en mode Fastboot
  $0 rom <fichier_rom.zip>             Sideload la ROM via ADB (téléphone doit être dans TWRP)
  $0 gapps <fichier_gapps.zip>         Sideload un package GApps via ADB (juste après la ROM, dans TWRP)
  $0 bootanimation <fichier.zip>       Pousse un bootanimation.zip custom
EOF
  exit 1
}

confirm() {
  read -r -p "$1 [o/N] " reply
  [[ "$reply" =~ ^[oOyY]$ ]] || { log "Annulé."; exit 0; }
}

remind_unlock() {
  log "Étapes de déblocage bootloader (Sony, officiel) :"
  log "  1. *#06# sur le téléphone pour noter l'IMEI."
  log "  2. https://developer.sony.com/develop/open-devices/get-started/unlock-bootloader/"
  log "     -> compte + IMEI -> code 0x..."
  log "  3. Options développeur : active 'Débogage USB' et 'Déverrouillage OEM'."
  log "  4. Éteins le téléphone, puis maintiens Volume haut en branchant l'USB (mode Fastboot)."
  log "  5. fastboot oem unlock 0x<ton_code>"
  err "ATTENTION : l'étape 5 efface /data automatiquement. Sauvegarde AVANT (voir ../README.md)."
}

flash_recovery() {
  local img="$1"
  ensure_cmd fastboot android-tools-fastboot
  [ -f "$img" ] || { err "Fichier introuvable : $img"; exit 1; }

  log "Assure-toi que le téléphone est en mode Fastboot :"
  log "  Éteins-le, puis maintiens Volume haut en branchant le câble USB."
  confirm "Le téléphone est-il bien en mode Fastboot et branché en USB ?"

  log "Flash du recovery via fastboot..."
  fastboot flash recovery "$img"

  log "Recovery flashé. Redémarre manuellement en recovery pour continuer"
  log "(généralement : maintenir Volume bas juste après avoir quitté fastboot, sinon"
  log "utilise le menu Fastboot lui-même s'il propose 'Recovery mode')."
}

sideload_rom() {
  local zip="$1"
  ensure_cmd adb android-tools-adb
  [ -f "$zip" ] || { err "Fichier introuvable : $zip"; exit 1; }

  log "Assure-toi que le téléphone est démarré dans TWRP, menu 'Advanced > ADB Sideload'."
  confirm "Le téléphone est-il en mode ADB Sideload dans TWRP ?"

  log "Sideload de la ROM ($zip)..."
  adb sideload "$zip"

  log "Sideload terminé. Reboote le téléphone depuis le menu TWRP."
}

sideload_gapps() {
  local zip="$1"
  ensure_cmd adb android-tools-adb
  [ -f "$zip" ] || { err "Fichier introuvable : $zip"; exit 1; }

  log "GApps doit être flashé JUSTE APRÈS la ROM, sans reboot entre les deux, toujours dans TWRP."
  confirm "Es-tu bien dans TWRP juste après avoir flashé la ROM (Advanced > ADB Sideload) ?"

  log "Sideload de GApps ($zip)..."
  adb sideload "$zip"

  log "GApps installé. Tu peux maintenant reboot le système."
}

push_bootanimation() {
  local zip="$1"
  ensure_cmd adb android-tools-adb
  [ -f "$zip" ] || { err "Fichier introuvable : $zip"; exit 1; }

  log "Deux méthodes possibles :"
  log "  a) Système déjà démarré + root (adb root / su) :"
  log "     adb push $zip /system/media/bootanimation.zip"
  log "  b) Depuis TWRP (système monté, avant premier boot) : même commande."
  confirm "Le téléphone est-il prêt (root actif, ou dans TWRP avec /system monté) ?"

  adb push "$zip" /sdcard/bootanimation.zip
  local copy_cmd="mount -o rw,remount /system 2>/dev/null; cp /sdcard/bootanimation.zip /system/media/bootanimation.zip && chmod 644 /system/media/bootanimation.zip"

  if adb shell "$copy_cmd" >/dev/null 2>&1 && adb shell "[ -f /system/media/bootanimation.zip ]" >/dev/null 2>&1; then
    log "bootanimation.zip installé (shell déjà root). Reboot pour voir le résultat."
  elif adb shell "su -c '$copy_cmd'" >/dev/null 2>&1 && adb shell "[ -f /system/media/bootanimation.zip ]" >/dev/null 2>&1; then
    log "bootanimation.zip installé via 'su'. Reboot pour voir le résultat."
  else
    err "Installation automatique impossible (ni shell root direct, ni 'su' disponible)."
    log "Copie manuelle nécessaire depuis TWRP : File Manager > copier /sdcard/bootanimation.zip vers /system/media/bootanimation.zip"
    exit 1
  fi
}

[ $# -ge 1 ] || usage

case "$1" in
  unlock)
    remind_unlock
    ;;
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
  *)
    usage
    ;;
esac
