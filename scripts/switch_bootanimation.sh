#!/usr/bin/env bash
#
# switch_bootanimation.sh — bascule le bootanimation.zip actif sur la tablette parmi
# plusieurs fichiers déjà présents en local (ex: Pikachu, Bulbizarre...). Ne contient et
# n'ajoute aucun asset au dépôt — c'est un simple sélecteur/pousseur de fichiers déjà sur
# ta machine, voir scripts/make_bootanimation.sh pour en générer.
#
# Usage :
#   ./switch_bootanimation.sh add <nom> <chemin/vers/bootanimation.zip>
#       Enregistre un zip sous un nom court pour le retrouver facilement plus tard.
#   ./switch_bootanimation.sh list
#       Liste les bootanimations enregistrées.
#   ./switch_bootanimation.sh apply <nom>
#       Reboot en recovery, pousse le zip choisi vers /system/media/bootanimation.zip,
#       attend ta confirmation pour reboot système (même flow que install.sh : texte pur,
#       attente auto de la tablette, pas de TUI).

set -uo pipefail

STORE_DIR="$HOME/.cache/fritaxos/bootanimations"
mkdir -p "$STORE_DIR"

if [ -t 1 ]; then
  C_STEP='\033[1;36m'; C_INFO='\033[0;90m'; C_WAIT='\033[1;33m'; C_OK='\033[1;32m'; C_ERR='\033[1;31m'; C_RESET='\033[0m'
else
  C_STEP=''; C_INFO=''; C_WAIT=''; C_OK=''; C_ERR=''; C_RESET=''
fi

log() { printf "${C_STEP}==>${C_RESET} %s\n" "$*"; }
err() { printf "${C_ERR}ERREUR :${C_RESET} %s\n" "$*" >&2; }
info() { printf "${C_INFO}    %s${C_RESET}\n" "$*"; }

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

wait_for_adb_state() {
  local pattern="$1" n=0
  while ! adb devices | tail -n +2 | grep -qE "$pattern"; do
    printf "\r${C_WAIT}    En attente de la tablette... (%ds, Ctrl+C pour annuler)${C_RESET}" "$n"
    sleep 1
    n=$((n + 1))
  done
  printf "\r${C_OK}    Tablette détectée.                                    ${C_RESET}\n"
}

cmd_add() {
  local name="$1" src="$2"
  [ -f "$src" ] || { err "Fichier introuvable : $src"; exit 1; }
  cp "$src" "$STORE_DIR/$name.zip"
  log "Enregistré : $name -> $STORE_DIR/$name.zip"
}

cmd_list() {
  log "Bootanimations enregistrées dans $STORE_DIR :"
  local found=0
  for f in "$STORE_DIR"/*.zip; do
    [ -e "$f" ] || continue
    found=1
    info "$(basename "$f" .zip)  ($(du -h "$f" | cut -f1))"
  done
  [ "$found" -eq 0 ] && info "(aucune — utilise 'add' pour en enregistrer une)"
}

cmd_apply() {
  local name="$1"
  local zip="$STORE_DIR/$name.zip"
  [ -f "$zip" ] || { err "Aucune bootanimation enregistrée sous ce nom : $name (voir 'list')"; exit 1; }

  ensure_cmd adb android-tools-adb

  log "Reboot en recovery..."
  adb reboot recovery >/dev/null 2>&1 || true
  wait_for_adb_state '(device|recovery)$'

  log "Montage de /system en écriture..."
  adb shell "mount /system; mount -o rw,remount /system"

  log "Envoi de $name.zip..."
  adb push "$zip" /sdcard/bootanimation.zip
  adb shell "cp /sdcard/bootanimation.zip /system/media/bootanimation.zip; chmod 644 /system/media/bootanimation.zip"

  if adb shell "[ -f /system/media/bootanimation.zip ] && echo OK" | grep -q OK; then
    log "Bootanimation '$name' installée."
  else
    err "La copie a échoué — vérifie manuellement dans TWRP."
    exit 1
  fi

  log "Retourne dans TWRP > Reboot > System pour voir le résultat."
}

usage() {
  cat <<EOF
Usage:
  $0 add <nom> <chemin/vers/bootanimation.zip>   Enregistre un zip sous un nom court
  $0 list                                          Liste les bootanimations enregistrées
  $0 apply <nom>                                   Bascule la tablette sur cette bootanimation
EOF
  exit 1
}

[ $# -ge 1 ] || usage
case "$1" in
  add)   [ $# -eq 3 ] || usage; cmd_add "$2" "$3" ;;
  list)  cmd_list ;;
  apply) [ $# -eq 2 ] || usage; cmd_apply "$2" ;;
  *)     usage ;;
esac
