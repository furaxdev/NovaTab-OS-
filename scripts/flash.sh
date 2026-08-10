#!/usr/bin/env bash
#
# flash.sh — installe un recovery custom (TWRP) puis sideload la ROM FritaxOS
# sur la Galaxy Tab 4 10.1" SM-T530.
#
# ATTENTION : les appareils Samsung n'utilisent PAS Fastboot mais le protocole Odin
# (Download Mode). Ce script utilise donc Heimdall (implémentation libre d'Odin) pour
# le recovery, puis `adb sideload` pour flasher la ROM elle-même une fois dans le recovery.
#
# Usage :
#   ./flash.sh recovery /chemin/vers/twrp-matissewifi.img.tar   # flash TWRP via Heimdall
#   ./flash.sh rom /chemin/vers/lineage-14.1-....zip           # sideload la ROM via ADB
#   ./flash.sh gapps /chemin/vers/open_gapps-arm-7.1-pico.zip  # sideload GApps via ADB
#   ./flash.sh bootanimation /chemin/vers/bootanimation.zip    # pousse un boot animation custom
#
# Prérequis : heimdall et adb. S'ils sont absents, ce script les installe automatiquement
# via apt (paquets 'heimdall-flash' et 'android-tools-adb' sous Debian/Ubuntu).
#
# Ordre recommandé pour une install complète avec GApps + splash custom :
#   1. ./flash.sh recovery twrp-matissewifi.img
#   2. (reboot en recovery)
#   3. ./flash.sh rom lineage-14.1-....zip
#   4. ./flash.sh gapps open_gapps-arm-7.1-pico.zip   (sans reboot entre les deux, toujours dans TWRP)
#   5. reboot système, puis ./flash.sh bootanimation bootanimation.zip (voir docs/CUSTOMIZATION.md)

set -euo pipefail

log() { echo -e "\033[1;32m[fritaxos-flash]\033[0m $*"; }
err() { echo -e "\033[1;31m[fritaxos-flash]\033[0m $*" >&2; }

# ensure_cmd <commande> <paquet_apt>
# Installe automatiquement via apt si la commande n'est pas déjà présente.
ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0

  if ! command -v apt-get >/dev/null 2>&1; then
    err "Commande manquante : $cmd, et apt-get n'est pas disponible pour l'installer automatiquement."
    exit 1
  fi

  log "Commande manquante : $cmd — installation via apt (paquet '$pkg')..."
  if ! sudo apt-get update -qq || ! sudo apt-get install -y "$pkg"; then
    err "Échec de l'installation de '$pkg'. Installe-le manuellement puis relance."
    exit 1
  fi

  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' toujours introuvable après l'installation de '$pkg'."; exit 1; }
}

usage() {
  cat <<EOF
Usage:
  $0 recovery <fichier_twrp.img>       Flash TWRP en mode Download (via Heimdall)
  $0 rom <fichier_rom.zip>             Sideload la ROM via ADB (tablette doit être dans TWRP)
  $0 gapps <fichier_gapps.zip>         Sideload un package GApps via ADB (juste après la ROM, dans TWRP)
  $0 bootanimation <fichier.zip>       Pousse un bootanimation.zip custom (système déjà démarré + root, ou via TWRP)
  $0 setupwizard <apk> [chemin]        Remplace SetupWizard par une version patchée (voir patch_branding.sh), AVANT le 1er boot
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
  ensure_cmd heimdall heimdall-flash
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
  ensure_cmd adb android-tools-adb
  [ -f "$zip" ] || { err "Fichier introuvable : $zip"; exit 1; }

  log "Assure-toi que la tablette est démarrée dans TWRP, menu 'Advanced > ADB Sideload'."
  confirm "La tablette est-elle en mode ADB Sideload dans TWRP ?"

  log "Sideload de la ROM ($zip)..."
  adb sideload "$zip"

  log "Sideload terminé. Reboote la tablette depuis le menu TWRP."
}

sideload_gapps() {
  local zip="$1"
  ensure_cmd adb android-tools-adb
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
  ensure_cmd adb android-tools-adb
  [ -f "$zip" ] || { err "Fichier introuvable : $zip"; exit 1; }

  log "Deux méthodes possibles :"
  log "  a) Système déjà démarré + accès root (adb root / su) :"
  log "     adb push $zip /system/media/bootanimation.zip"
  log "  b) Depuis TWRP (système monté, avant premier boot) : même commande, TWRP a déjà les droits."
  confirm "La tablette est-elle prête (root actif, ou dans TWRP avec /system monté) ?"

  adb push "$zip" /sdcard/bootanimation.zip
  local copy_cmd="mount -o rw,remount /system 2>/dev/null; cp /sdcard/bootanimation.zip /system/media/bootanimation.zip && chmod 644 /system/media/bootanimation.zip"

  # TWRP (et souvent un adb root sur système déjà démarré) donnent un shell déjà root,
  # sans forcément fournir de binaire 'su' — on tente donc d'abord la copie directe.
  if adb shell "$copy_cmd" >/dev/null 2>&1 && adb shell "[ -f /system/media/bootanimation.zip ]" >/dev/null 2>&1; then
    log "bootanimation.zip installé (shell déjà root). Reboot pour voir le résultat."
  elif adb shell "su -c '$copy_cmd'" >/dev/null 2>&1 && adb shell "[ -f /system/media/bootanimation.zip ]" >/dev/null 2>&1; then
    log "bootanimation.zip installé via 'su'. Reboot pour voir le résultat."
  else
    err "Installation automatique impossible (ni shell root direct, ni 'su' disponible)."
    log "Copie manuelle nécessaire :"
    log "  Depuis TWRP : File Manager > copier /sdcard/bootanimation.zip vers /system/media/bootanimation.zip"
    log "  Ou : adb shell puis 'mount -o rw,remount /system' avant de copier."
    exit 1
  fi
}

push_setupwizard() {
  local apk="$1" remote_path="${2:-/system/priv-app/SetupWizard/SetupWizard.apk}"
  ensure_cmd adb android-tools-adb
  [ -f "$apk" ] || { err "Fichier introuvable : $apk"; exit 1; }

  log "Remplace l'APK SetupWizard déjà compilé par une version patchée (branding FritaxOS)."
  log "Voir scripts/patch_branding.sh pour générer ce fichier, et lire l'avertissement en tête de ce script."
  log "Chemin système ciblé : $remote_path"
  log ""
  log "IMPORTANT : ça ne prend effet proprement qu'AVANT le premier démarrage (depuis TWRP,"
  log "juste après avoir flashé la ROM, avant de wipe data/cache et de booter). Si le système"
  log "a déjà tourné une fois, l'assistant de configuration ne se relance pas sans un wipe data."
  confirm "Es-tu dans TWRP, juste après avoir flashé la ROM, avant le premier boot ?"

  local copy_cmd="mount -o rw,remount /system 2>/dev/null; cp /sdcard/SetupWizard-patched.apk '$remote_path' && chmod 644 '$remote_path'"
  local backup_name="backup-setupwizard-$(date +%Y%m%d-%H%M%S).apk"

  log "Sauvegarde de l'APK original avant remplacement..."
  if adb pull "$remote_path" "$backup_name" >/dev/null 2>&1; then
    log "Original sauvegardé dans ./$backup_name (au cas où)."
  else
    err "Impossible de sauvegarder l'original (chemin peut-être incorrect : $remote_path)."
    confirm "Continuer quand même sans sauvegarde ?"
  fi

  adb push "$apk" /sdcard/SetupWizard-patched.apk

  if adb shell "$copy_cmd" >/dev/null 2>&1 && adb shell "[ -f '$remote_path' ]" >/dev/null 2>&1; then
    log "SetupWizard patché installé. Pense à wipe data/cache avant de booter si pas déjà fait."
  elif adb shell "su -c \"$copy_cmd\"" >/dev/null 2>&1 && adb shell "[ -f '$remote_path' ]" >/dev/null 2>&1; then
    log "SetupWizard patché installé via 'su'. Pense à wipe data/cache avant de booter si pas déjà fait."
  else
    err "Installation automatique impossible (ni shell root direct, ni 'su' disponible)."
    log "Copie manuelle nécessaire depuis TWRP : File Manager > copier /sdcard/SetupWizard-patched.apk vers $remote_path"
    exit 1
  fi
}

backup_data() {
  ensure_cmd adb android-tools-adb
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
  setupwizard)
    [ $# -ge 2 ] || usage
    push_setupwizard "$2" "${3:-}"
    ;;
  backup)
    backup_data
    ;;
  *)
    usage
    ;;
esac
