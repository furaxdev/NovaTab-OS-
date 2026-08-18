#!/usr/bin/env bash
#
# restore_backup.sh — restaure sur le téléphone une sauvegarde faite avant le déblocage
# du bootloader (apps+données via `adb backup`, fichiers via `adb pull`).
#
# À lancer UNE FOIS FuraxOS installé et démarré (voir ../README.md).
#
# Usage :
#   ./restore_backup.sh <apps-and-data.ab> <dossier_sdcard_pull>
#
# Exemple :
#   ./restore_backup.sh ~/Sauvegardes/xperia-xz-apps.ab ~/Sauvegardes/xperia-sdcard

set -euo pipefail

log() { echo -e "\033[1;32m[furaxos-restore]\033[0m $*"; }
err() { echo -e "\033[1;31m[furaxos-restore]\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m[furaxos-restore]\033[0m $*"; }

ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  if ! command -v apt-get >/dev/null 2>&1; then
    err "Commande manquante : $cmd, et apt-get n'est pas disponible pour l'installer automatiquement."
    exit 1
  fi
  log "Installation de $cmd via apt (paquet '$pkg')..."
  sudo apt-get update -qq && sudo apt-get install -y "$pkg"
}

AB_FILE="${1:?Usage: $0 <apps-and-data.ab> <dossier_sdcard_pull>}"
SDCARD_DIR="${2:?Usage: $0 <apps-and-data.ab> <dossier_sdcard_pull>}"

[ -f "$AB_FILE" ] || { err "Fichier introuvable : $AB_FILE"; exit 1; }
[ -d "$SDCARD_DIR" ] || { err "Dossier introuvable : $SDCARD_DIR"; exit 1; }

ensure_cmd adb android-tools-adb

log "Vérification de la connexion adb..."
adb devices | tail -n +2 | grep -q device || { err "Aucun appareil détecté. Branche le téléphone et autorise le débogage USB."; exit 1; }

log "Restauration des apps + données (adb restore)..."
warn "Regarde l'écran du téléphone : appuie sur 'Restaurer mes données' pour continuer."
adb restore "$AB_FILE"
log "Restauration apps+données terminée."

log "Renvoi des fichiers (photos, musique, downloads...) vers le téléphone..."
# adb pull crée <dest>/sdcard/... — on repousse ce contenu vers /sdcard sur le téléphone.
local_src="$SDCARD_DIR"
[ -d "$SDCARD_DIR/sdcard" ] && local_src="$SDCARD_DIR/sdcard"
adb push "$local_src/." /sdcard/ || warn "Certains fichiers n'ont pas pu être renvoyés (permissions), le reste a été restauré."

log "Restauration complète terminée."
