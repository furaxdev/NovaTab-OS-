#!/usr/bin/env bash
#
# patch_setupwizard.sh — patche le texte/couleurs de SetupWizard.apk DÉJÀ COMPILÉ dans une
# ROM LineageOS existante (téléchargée, pas buildée depuis les sources), avec le branding
# FriteOS de overlay/. Alternative légère à scripts/build.sh (pas besoin des ~250 Go / du
# repo sync complet) — au prix d'un vrai risque décrit ci-dessous.
#
# ⚠️ RISQUE À COMPRENDRE AVANT D'UTILISER CE SCRIPT :
# Ce script décompile l'APK, modifie ses ressources, la recompile, puis la RESIGNE avec une
# clé de debug générée localement — forcément différente de la clé plateforme utilisée pour
# signer le reste de la ROM. Si SetupWizard partage l'UID système
# (android:sharedUserId="android.uid.system") ou dépend d'une permission signature-level
# vérifiée strictement, une signature différente peut la faire planter ou perdre des
# permissions au premier démarrage. C'est une technique de modding APK classique
# (apktool + jarsigner) qui fonctionne bien pour du texte/couleurs dans la plupart des cas
# sur Android 7.1, mais teste d'abord avec une sauvegarde TWRP complète, jamais en direct
# sur ta seule installation. L'APK original est toujours sauvegardé automatiquement avant
# tout remplacement (voir flash.sh setupwizard).
#
# Usage :
#   ./patch_setupwizard.sh extract <rom.zip> [sortie.apk]
#       Extrait SetupWizard.apk d'un zip de ROM déjà compilée (LineageOS 14.1).
#
#   ./patch_setupwizard.sh patch <SetupWizard.apk> [sortie-patched.apk]
#       Décompile l'APK, applique le branding de overlay/, recompile et signe.
#
#   ./patch_setupwizard.sh pull [sortie.apk]
#       Récupère SetupWizard.apk directement depuis une tablette déjà flashée (adb, root).
#
# Ensuite, installe le résultat avec :
#   ./flash.sh setupwizard SetupWizard-patched.apk

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYSTORE="$HOME/.friteos-debug.keystore"
KEYSTORE_ALIAS="friteosdebug"
KEYSTORE_PASS="friteos-debug"

log() { echo -e "\033[1;32m[friteos-patch]\033[0m $*"; }
err() { echo -e "\033[1;31m[friteos-patch]\033[0m $*" >&2; }

# ensure_cmd <commande> <paquet_apt>
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
  $0 extract <rom.zip> [sortie.apk]     Extrait SetupWizard.apk d'une ROM déjà compilée
  $0 patch <apk_in> [apk_out]           Décompile, applique le branding, recompile et signe
  $0 pull [sortie.apk]                  Récupère l'APK live depuis une tablette déjà flashée
EOF
  exit 1
}

cmd_extract() {
  local rom_zip="$1" out_apk="${2:-SetupWizard.apk}"
  ensure_cmd unzip unzip
  [ -f "$rom_zip" ] || { err "Fichier introuvable : $rom_zip"; exit 1; }

  local internal_path
  internal_path="$(unzip -Z1 "$rom_zip" | grep -iE 'setupwizard.*\.apk$' | head -n1)"

  if [ -z "$internal_path" ]; then
    if unzip -Z1 "$rom_zip" | grep -q 'system.new.dat'; then
      err "Ce zip est au format \"block-based\" (system.new.dat.br) : les fichiers ne sont"
      err "PAS accessibles directement dans le zip, ce script ne gère pas ce cas automatiquement."
      err ""
      err "Pour extraire quand même, il faut reconstruire system.img puis le monter :"
      err "  1. brotli -d system.new.dat.br -o system.new.dat"
      err "  2. sdat2img.py system.transfer.list system.new.dat system.img"
      err "     (script Python communautaire, cherche \"sdat2img\" sur GitHub)"
      err "  3. Monter system.img (loop mount ou 7z x system.img) et y trouver SetupWizard.apk"
      err "     (chemin typique : system/priv-app/SetupWizard/SetupWizard.apk)"
      err ""
      err "Alternative plus simple : utilise '$0 pull' après avoir flashé et démarré la ROM une"
      err "première fois (voir docs/CUSTOMIZATION.md — mais dans ce cas le premier écran custom"
      err "n'apparaîtra qu'après un wipe data, pas au tout premier boot)."
      exit 1
    fi
    err "Aucun SetupWizard*.apk trouvé dans $rom_zip."
    err "Structure de ROM inattendue — regarde 'unzip -l $rom_zip | grep -i setupwizard' pour investiguer."
    exit 1
  fi

  log "Trouvé : $internal_path"
  unzip -p "$rom_zip" "$internal_path" > "$out_apk"
  log "Extrait vers $out_apk"
}

cmd_pull() {
  local out_apk="${1:-SetupWizard.apk}"
  ensure_cmd adb android-tools-adb

  log "Recherche de SetupWizard.apk installé sur la tablette (adb)..."
  local remote_path
  remote_path="$(adb shell pm path org.lineageos.setupwizard 2>/dev/null | tr -d '\r' | sed 's/^package://')"
  if [ -z "$remote_path" ]; then
    err "org.lineageos.setupwizard introuvable via 'pm path' — la ROM utilise peut-être un autre nom de package."
    err "Essaie : adb shell pm list packages | grep -i setup"
    exit 1
  fi

  log "Trouvé sur la tablette : $remote_path"
  adb pull "$remote_path" "$out_apk"
  log "Récupéré vers $out_apk"
}

apply_overlay_resources() {
  # $1 = dossier décompilé (contient res/values/strings.xml et colors.xml)
  local decompiled="$1"
  ensure_cmd python3 python3

  python3 - "$decompiled" "$REPO_ROOT/overlay/packages/apps/SetupWizard/res/values" <<'PYEOF'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

decompiled = Path(sys.argv[1])
overlay_values = Path(sys.argv[2])

def merge_resource_file(target_path, overlay_path, tag):
    if not overlay_path.exists():
        return
    if not target_path.exists():
        print(f"  (absent, création : {target_path})")
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources></resources>\n')

    target_tree = ET.parse(target_path)
    target_root = target_tree.getroot()
    overlay_root = ET.parse(overlay_path).getroot()

    existing = {el.get("name"): el for el in target_root.findall(tag)}
    for el in overlay_root.findall(tag):
        name = el.get("name")
        if name in existing:
            existing[name].text = el.text
            print(f"  remplacé : <{tag} name=\"{name}\">")
        else:
            target_root.append(el)
            print(f"  ajouté    : <{tag} name=\"{name}\">")

    target_tree.write(target_path, encoding="utf-8", xml_declaration=True)

print("Application du branding FriteOS sur les ressources décompilées...")
merge_resource_file(decompiled / "res/values/strings.xml", overlay_values / "strings.xml", "string")
merge_resource_file(decompiled / "res/values/colors.xml", overlay_values / "colors.xml", "color")
PYEOF
}

ensure_keystore() {
  if [ -f "$KEYSTORE" ]; then
    return
  fi
  ensure_cmd keytool default-jdk
  log "Génération d'une clé de debug locale pour signer l'APK patché ($KEYSTORE)..."
  keytool -genkeypair -v \
    -keystore "$KEYSTORE" -alias "$KEYSTORE_ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$KEYSTORE_PASS" -keypass "$KEYSTORE_PASS" \
    -dname "CN=FriteOS Debug, O=FriteOS, C=FR" >/dev/null
}

cmd_patch() {
  local apk_in="$1" apk_out="${2:-${1%.apk}-patched.apk}"
  [ -f "$apk_in" ] || { err "Fichier introuvable : $apk_in"; exit 1; }

  ensure_cmd apktool apktool
  ensure_cmd jarsigner default-jdk

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT

  log "Décompilation de $apk_in..."
  if ! apktool d -f -o "$workdir/decompiled" "$apk_in" > "$workdir/apktool-decode.log" 2>&1; then
    err "Échec de la décompilation. Log :"
    tail -n 30 "$workdir/apktool-decode.log" >&2
    exit 1
  fi

  apply_overlay_resources "$workdir/decompiled"

  log "Recompilation..."
  if ! apktool b -o "$workdir/rebuilt.apk" "$workdir/decompiled" > "$workdir/apktool-build.log" 2>&1; then
    err "Échec de la recompilation. Log :"
    tail -n 30 "$workdir/apktool-build.log" >&2
    exit 1
  fi

  ensure_keystore

  log "Signature avec la clé de debug FriteOS (voir l'avertissement en tête de ce script)..."
  cp "$workdir/rebuilt.apk" "$apk_out"
  if ! jarsigner -sigalg SHA1withRSA -digestalg SHA1 \
      -keystore "$KEYSTORE" -storepass "$KEYSTORE_PASS" \
      "$apk_out" "$KEYSTORE_ALIAS" > "$workdir/jarsigner.log" 2>&1; then
    err "Échec de la signature. Log :"
    tail -n 30 "$workdir/jarsigner.log" >&2
    exit 1
  fi

  log "APK patché et signé : $apk_out"
  log "Installe-le avec : ./flash.sh setupwizard $apk_out"
}

[ $# -ge 1 ] || usage

case "$1" in
  extract)
    [ $# -ge 2 ] || usage
    cmd_extract "$2" "${3:-}"
    ;;
  patch)
    [ $# -ge 2 ] || usage
    cmd_patch "$2" "${3:-}"
    ;;
  pull)
    cmd_pull "${2:-}"
    ;;
  *)
    usage
    ;;
esac
