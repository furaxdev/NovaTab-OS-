#!/usr/bin/env bash
#
# download.sh — télécharge tout ce qu'il faut pour flasher FuraxOS sur le Sony Xperia XZ
# (F8331, kagura) : GApps (automatique), TWRP + ROM (liens XDA, manuel).
#
# Usage :
#   ./download.sh [dossier_de_sortie]
#   (défaut : ~/Téléchargements/furaxos-xperia)

set -uo pipefail

OUT_DIR="${1:-$HOME/Téléchargements/furaxos-xperia}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

if [ -t 1 ]; then
  C_STEP='\033[1;36m'; C_INFO='\033[0;90m'; C_WAIT='\033[1;33m'
  C_OK='\033[1;32m'; C_ERR='\033[1;31m'; C_RESET='\033[0m'
else
  C_STEP=''; C_INFO=''; C_WAIT=''; C_OK=''; C_ERR=''; C_RESET=''
fi

log()  { printf "${C_STEP}==>${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_OK}  ✓${C_RESET} %s\n" "$*"; }
info() { printf "${C_INFO}    %s${C_RESET}\n" "$*"; }
err()  { printf "${C_ERR}  ✗${C_RESET} %s\n" "$*" >&2; }
warn() { printf "${C_WAIT}  !${C_RESET} %s\n" "$*"; }

ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  if ! command -v apt-get >/dev/null 2>&1; then
    err "Commande manquante : $cmd"; exit 1
  fi
  log "Installation de $cmd..."
  sudo apt-get update -qq && sudo apt-get install -y "$pkg"
}

download_file() {
  local url="$1" dest="$2" label="${3:-$dest}"
  if [ -f "$dest" ]; then
    ok "$label déjà présent, téléchargement ignoré."
    return 0
  fi
  log "Téléchargement de $label..."
  ensure_cmd curl curl
  if curl -fL --retry 3 --progress-bar -o "$dest.tmp" "$url"; then
    mv "$dest.tmp" "$dest"
    ok "$label → $dest"
  else
    rm -f "$dest.tmp"
    err "Échec du téléchargement de $url"
    return 1
  fi
}

wait_for_file() {
  local dest="$1" label="$2"
  if [ -f "$dest" ]; then
    ok "$label déjà présent."
    return 0
  fi
  warn "$label introuvable : $dest"
  warn "Télécharge-le manuellement (voir lien ci-dessus) et place-le dans :"
  warn "  $dest"
  warn "Appuie sur Entrée une fois le fichier en place (Ctrl+C pour annuler)."
  read -r _
  if [ -f "$dest" ]; then
    ok "$label détecté."
  else
    err "Fichier toujours absent : $dest"
    exit 1
  fi
}

echo ""
printf "${C_STEP}FuraxOS — Téléchargement des fichiers pour Xperia XZ (kagura/F8331)${C_RESET}\n"
printf "${C_INFO}Dossier de sortie : $OUT_DIR${C_RESET}\n"
echo ""

# ─── 1. GApps — téléchargement automatique depuis opengapps.org ──────────────
log "GApps (ARM64, Android 8.1, variante pico)..."
GAPPS_DEST="$OUT_DIR/open_gapps-arm64-8.1-pico.zip"
GAPPS_URL="https://sourceforge.net/projects/opengapps/files/arm64/current/open_gapps-arm64-8.1-pico.zip/download"
if [ -f "$GAPPS_DEST" ]; then
  ok "GApps déjà présent, téléchargement ignoré."
else
  log "Téléchargement depuis sourceforge (opengapps.org)..."
  ensure_cmd curl curl
  if curl -fL --retry 3 --progress-bar -o "$GAPPS_DEST.tmp" "$GAPPS_URL"; then
    mv "$GAPPS_DEST.tmp" "$GAPPS_DEST"
    ok "GApps → $GAPPS_DEST"
  else
    rm -f "$GAPPS_DEST.tmp"
    err "Échec du téléchargement GApps. Va sur https://opengapps.org/ :"
    info "  Platform : ARM64 | Android : 8.1 | Variant : pico"
    info "  Puis place le zip dans : $GAPPS_DEST"
  fi
fi

echo ""

# ─── 2. TWRP pour kagura — téléchargement automatique depuis dl.twrp.me ──────
log "TWRP 3.7.0 pour kagura (Xperia XZ F8331)..."
TWRP_DEST="$OUT_DIR/twrp-3.7.0_9-0-kagura.img"
TWRP_URL="https://dl.twrp.me/kagura/twrp-3.7.0_9-0-kagura.img"
download_file "$TWRP_URL" "$TWRP_DEST" "TWRP 3.7.0 kagura"

echo ""

# ─── 3. ROM LineageOS 15.1 — build non-officielle (Bitti09 / XDA) ────────────
log "ROM LineageOS 15.1 pour kagura (build non-officielle)..."
ROM_DEST="$OUT_DIR/lineage-15.1-kagura.zip"
info "Page XDA : https://forum.xda-developers.com/xperia-xz/development"
info "Cherche 'LineageOS 15 kagura Bitti09' ou 'LineageOS F8331'"
info "Prends la build la plus récente (.zip) — c'est un sideload TWRP, pas un flashable Odin"
wait_for_file "$ROM_DEST" "ROM LineageOS 15.1 kagura"

echo ""

# ─── Récap ───────────────────────────────────────────────────────────────────
echo ""
printf "${C_OK}Tous les fichiers sont prêts :${C_RESET}\n"
ls -lh "$OUT_DIR/"*.{zip,img} 2>/dev/null | awk '{print "  " $5 "  " $9}'

echo ""
printf "${C_STEP}Prochaine étape — installe tout automatiquement :${C_RESET}\n"
printf "  ${C_INFO}cd %s${C_RESET}\n" "$(dirname "$(dirname "$0")")"
printf "  ${C_INFO}./scripts/install.sh %s %s %s${C_RESET}\n" \
  "$TWRP_DEST" "$ROM_DEST" "$GAPPS_DEST"
echo ""
printf "${C_WAIT}N'oublie pas la sauvegarde avant de débloquer le bootloader !${C_RESET}\n"
printf "${C_INFO}  adb pull /sdcard ~/Sauvegardes/xperia-sdcard${C_RESET}\n"
printf "${C_INFO}  adb backup -apk -shared -all -f ~/Sauvegardes/xperia-xz-apps.ab${C_RESET}\n"
echo ""
