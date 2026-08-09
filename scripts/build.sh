#!/usr/bin/env bash
#
# build.sh — build NovaTab OS (LineageOS 14.1) pour la Galaxy Tab 4 10.1" SM-T530 (milletwifi)
#
# À lancer sur une machine Linux avec :
#   - >= 250 Go d'espace disque libre
#   - >= 16 Go de RAM (32 Go recommandé)
#   - Ubuntu 22.04 / 20.04 de préférence
#
# Ce script NE tourne PAS correctement sur un runner GitHub Actions hébergé gratuit
# (disque et temps insuffisants). Voir .github/workflows/build.yml pour l'option
# self-hosted runner.
#
# Interface : par défaut, affiche une barre de progression TUI (whiptail) et redirige
# toute la sortie verbeuse (apt, repo sync, brunch, ...) vers un fichier de log — pas de
# spam dans le terminal. En cas d'échec, les dernières lignes pertinentes du log sont
# affichées. Désactive la TUI avec NOVATAB_NO_TUI=1 (retombe sur des logs texte classiques,
# toujours redirigés vers le fichier de log).

set -uo pipefail

DEVICE="milletwifi"
BRANCH="cm-14.1"
BUILD_TYPE="userdebug"
WORKDIR="${NOVATAB_WORKDIR:-$HOME/novatab-build}"
JOBS="${NOVATAB_JOBS:-$(nproc)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LOG_DIR="$WORKDIR/logs"
RUN_LOG="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"

log() { echo -e "\033[1;32m[novatab]\033[0m $*"; }
err() { echo -e "\033[1;31m[novatab]\033[0m $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Commande manquante : $1"; exit 1; }
}

# ---------------------------------------------------------------------------
# Étapes de build (logique métier, inchangée) — toute leur sortie est redirigée
# vers $RUN_LOG par l'orchestrateur plus bas, jamais affichée directement.
# ---------------------------------------------------------------------------

install_deps() {
  sudo apt-get update
  sudo apt-get install -y \
    git-core gnupg flex bison build-essential zip curl zlib1g-dev \
    libc6-dev-i386 x11proto-core-dev libx11-dev lib32z1-dev \
    libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig \
    python3 python-is-python3 openjdk-8-jdk bc rsync whiptail
}

install_repo_tool() {
  if ! command -v repo >/dev/null 2>&1; then
    mkdir -p "$HOME/bin"
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
    chmod a+x "$HOME/bin/repo"
    export PATH="$HOME/bin:$PATH"
  fi
}

sync_sources() {
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"

  if [ ! -d ".repo" ]; then
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --depth=1
  fi

  mkdir -p .repo/local_manifests
  cp "$REPO_ROOT/manifests/roomservice.xml" .repo/local_manifests/roomservice.xml

  repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
}

extract_vendor_blobs() {
  if [ -d "device/samsung/milletwifi" ] && [ -f "device/samsung/milletwifi/extract-files.sh" ]; then
    if [ -z "${SKIP_VENDOR_EXTRACT:-}" ]; then
      echo "Pense à extraire les blobs vendor depuis ta tablette avant de continuer :"
      echo "  adb pull / puis device/samsung/milletwifi/extract-files.sh"
      echo "(export SKIP_VENDOR_EXTRACT=1 pour ignorer ce rappel)"
    fi
  fi
}

apply_branding() {
  if [ -n "${SKIP_BRANDING:-}" ]; then
    echo "SKIP_BRANDING défini, branding NovaTab OS (overlay SetupWizard) non appliqué."
    return
  fi

  mkdir -p "vendor/novatab"
  cp -r "$REPO_ROOT/overlay" "vendor/novatab/overlay"
  cp "$REPO_ROOT/vendor/novatab/vendor.mk" "vendor/novatab/vendor.mk"

  local device_mk="device/samsung/milletwifi/device.mk"
  local inherit_line='$(call inherit-product, vendor/novatab/vendor.mk)'

  if [ ! -f "$device_mk" ]; then
    echo "device.mk introuvable ($device_mk) — le device tree milletwifi a peut-être une structure différente."
    echo "Ajoute manuellement cette ligne dans son device.mk : $inherit_line"
    return
  fi

  if grep -qF "$inherit_line" "$device_mk"; then
    echo "vendor/novatab/vendor.mk déjà inclus dans $device_mk."
  else
    echo "" >> "$device_mk"
    echo "# NovaTab OS branding (ajouté par scripts/build.sh)" >> "$device_mk"
    echo "$inherit_line" >> "$device_mk"
    echo "Ligne d'inclusion ajoutée à $device_mk."
  fi
}

build() {
  source build/envsetup.sh
  breakfast "$DEVICE"
  brunch "$DEVICE"
}

# ---------------------------------------------------------------------------
# Orchestration : TUI whiptail (par défaut) ou logs texte compacts, au choix.
# Dans les deux cas, la sortie brute des commandes va dans $RUN_LOG, jamais
# directement dans le terminal — seule une ligne de statut par étape s'affiche.
# ---------------------------------------------------------------------------

GAUGE_FD=3
HEARTBEAT_PID=""
USE_TUI=1

[ -t 1 ] || USE_TUI=0
[ -n "${NOVATAB_NO_TUI:-}" ] && USE_TUI=0

gauge_update() {
  # $1 = pourcentage, $2 = message
  printf 'XXX\n%s\n%s\nXXX\n' "$1" "$2" >&$GAUGE_FD
}

start_heartbeat() {
  # Réémet le même pourcentage avec le temps écoulé, pour les étapes longues
  # (repo sync, brunch) où il n'y a pas de vraie progression mesurable.
  local percent="$1" label="$2"
  ( local start=$SECONDS
    while true; do
      sleep 5
      gauge_update "$percent" "$label ($(( SECONDS - start ))s écoulées)"
    done
  ) &
  HEARTBEAT_PID=$!
  disown "$HEARTBEAT_PID" 2>/dev/null || true
}

stop_heartbeat() {
  if [ -n "$HEARTBEAT_PID" ]; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
    HEARTBEAT_PID=""
  fi
}

fail_step() {
  local label="$1"
  stop_heartbeat
  if [ "$USE_TUI" -eq 1 ]; then
    exec {GAUGE_FD}>&-
  fi
  err "Échec pendant : $label"
  err "Dernières lignes du log complet ($RUN_LOG) :"
  tail -n 40 "$RUN_LOG" >&2
  exit 1
}

# run_step <pourcentage> <label> <fonction> [args...]
run_step() {
  local percent="$1" label="$2"; shift 2
  if [ "$USE_TUI" -eq 1 ]; then
    gauge_update "$percent" "$label"
  else
    log "$label"
  fi

  if ! "$@" >>"$RUN_LOG" 2>&1; then
    fail_step "$label"
  fi
}

run_long_step() {
  # Comme run_step, mais avec un battement de cœur (temps écoulé) pendant l'exécution.
  local percent="$1" label="$2"; shift 2
  if [ "$USE_TUI" -eq 1 ]; then
    gauge_update "$percent" "$label"
    start_heartbeat "$percent" "$label"
  else
    log "$label (peut prendre longtemps, voir $RUN_LOG pour le détail)"
  fi

  if ! "$@" >>"$RUN_LOG" 2>&1; then
    fail_step "$label"
  fi
  stop_heartbeat
}

main() {
  require_cmd curl
  require_cmd git

  mkdir -p "$LOG_DIR"
  log "Log complet de ce build : $RUN_LOG"

  if [ "$USE_TUI" -eq 1 ] && ! command -v whiptail >/dev/null 2>&1; then
    log "whiptail absent, installation rapide pour la barre de progression..."
    sudo apt-get install -y whiptail >>"$RUN_LOG" 2>&1 || USE_TUI=0
  fi

  if [ "$USE_TUI" -eq 1 ]; then
    exec {GAUGE_FD}> >(whiptail --title "NovaTab OS — build ($DEVICE)" \
      --gauge "Initialisation..." 10 74 0)
  fi

  run_step        5  "Installation des dépendances (apt)..."          install_deps
  run_step       10  "Installation de l'outil 'repo'..."              install_repo_tool
  run_long_step  15  "Sync des sources LineageOS (repo sync)..."      sync_sources
  run_step       65  "Vérification des blobs vendor..."               extract_vendor_blobs
  run_step       70  "Application du branding NovaTab OS..."          apply_branding
  run_long_step  75  "Compilation (breakfast + brunch)..."            build

  if [ "$USE_TUI" -eq 1 ]; then
    gauge_update 100 "Terminé !"
    sleep 1
    exec {GAUGE_FD}>&-
  fi

  OUT_DIR="$WORKDIR/out/target/product/$DEVICE"
  log "Build terminé. Zip attendu dans : $OUT_DIR/lineage-*.zip"
  ls -la "$OUT_DIR"/lineage-*.zip 2>/dev/null || err "Zip non trouvé, vérifie $RUN_LOG."
}

trap stop_heartbeat EXIT INT TERM

main "$@"
