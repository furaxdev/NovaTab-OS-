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

set -euo pipefail

DEVICE="milletwifi"
BRANCH="cm-14.1"
BUILD_TYPE="userdebug"
WORKDIR="${NOVATAB_WORKDIR:-$HOME/novatab-build}"
JOBS="${NOVATAB_JOBS:-$(nproc)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo -e "\033[1;32m[novatab]\033[0m $*"; }
err() { echo -e "\033[1;31m[novatab]\033[0m $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Commande manquante : $1"; exit 1; }
}

install_deps() {
  log "Installation des dépendances de build (nécessite sudo)..."
  sudo apt-get update
  sudo apt-get install -y \
    git-core gnupg flex bison build-essential zip curl zlib1g-dev \
    libc6-dev-i386 x11proto-core-dev libx11-dev lib32z1-dev \
    libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig \
    python3 python-is-python3 openjdk-8-jdk bc rsync
}

install_repo_tool() {
  if ! command -v repo >/dev/null 2>&1; then
    log "Installation de l'outil 'repo'..."
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
    log "Initialisation du manifest LineageOS ($BRANCH)..."
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --depth=1
  fi

  mkdir -p .repo/local_manifests
  cp "$REPO_ROOT/manifests/roomservice.xml" .repo/local_manifests/roomservice.xml

  log "Sync des sources (ça va prendre du temps, ~50-100 Go)..."
  repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
}

extract_vendor_blobs() {
  if [ -d "device/samsung/milletwifi" ] && [ -f "device/samsung/milletwifi/extract-files.sh" ]; then
    if [ -z "${SKIP_VENDOR_EXTRACT:-}" ]; then
      log "Pense à extraire les blobs vendor depuis ta tablette avant de continuer :"
      log "  adb pull / puis device/samsung/milletwifi/extract-files.sh"
      log "(export SKIP_VENDOR_EXTRACT=1 pour ignorer ce rappel)"
    fi
  fi
}

apply_branding() {
  if [ -n "${SKIP_BRANDING:-}" ]; then
    log "SKIP_BRANDING défini, branding NovaTab OS (overlay SetupWizard) non appliqué."
    return
  fi

  log "Application du branding NovaTab OS (overlay SetupWizard + vendor.mk)..."
  mkdir -p "vendor/novatab"
  cp -r "$REPO_ROOT/overlay" "vendor/novatab/overlay"
  cp "$REPO_ROOT/vendor/novatab/vendor.mk" "vendor/novatab/vendor.mk"

  local device_mk="device/samsung/milletwifi/device.mk"
  local inherit_line='$(call inherit-product, vendor/novatab/vendor.mk)'

  if [ ! -f "$device_mk" ]; then
    err "device.mk introuvable ($device_mk) — le device tree milletwifi a peut-être une structure différente."
    err "Ajoute manuellement cette ligne dans son device.mk : $inherit_line"
    return
  fi

  if grep -qF "$inherit_line" "$device_mk"; then
    log "vendor/novatab/vendor.mk déjà inclus dans $device_mk."
  else
    echo "" >> "$device_mk"
    echo "# NovaTab OS branding (ajouté par scripts/build.sh)" >> "$device_mk"
    echo "$inherit_line" >> "$device_mk"
    log "Ligne d'inclusion ajoutée à $device_mk."
    log "Si le build échoue à cause de ça, vérifie que ce device.mk existe bien à cet emplacement"
    log "et que la syntaxe correspond à ce que ce device tree attend (voir docs/CUSTOMIZATION.md)."
  fi
}

build() {
  log "Lancement du build pour $DEVICE ($BUILD_TYPE)..."
  source build/envsetup.sh
  breakfast "$DEVICE"
  brunch "$DEVICE"
}

main() {
  require_cmd curl
  require_cmd git

  install_deps
  install_repo_tool
  sync_sources
  extract_vendor_blobs
  apply_branding
  build

  OUT_DIR="$WORKDIR/out/target/product/$DEVICE"
  log "Build terminé. Zip attendu dans : $OUT_DIR/lineage-*.zip"
  ls -la "$OUT_DIR"/lineage-*.zip 2>/dev/null || err "Zip non trouvé, vérifie les logs de build ci-dessus."
}

main "$@"
