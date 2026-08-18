#!/usr/bin/env bash
#
# patch_branding.sh — patche SetupWizard.apk et LineageParts.apk (qui affichent "LineageOS"
# dans les paramètres et l'assistant de premier démarrage) pour les remplacer par FuraxOS,
# sur une ROM LineageOS 15.1 pour l'Xperia XZ (kagura, F8331).
#
# Même approche que ../scripts/patch_branding.sh (FritaxOS/Tab 4) :
#   apktool décompile → on écrase les strings avec l'overlay → apktool recompile → jarsigner signe.
#
# ⚠️ RISQUE : l'APK est resigné avec une clé de debug différente de la clé plateforme.
#    Ça fonctionne bien pour du texte/couleurs, mais garder une sauvegarde TWRP avant.
#
# Usage :
#   ./patch_branding.sh extract <rom.zip>           Extrait SetupWizard + LineageParts d'une ROM
#   ./patch_branding.sh patch <apk_in> [apk_out]    Patche un APK (branding FuraxOS)
#   ./patch_branding.sh pull [apk] [dest]            Pull un APK depuis le téléphone (adb)
#   ./patch_branding.sh patch-all                    Extrait + patche tout (SetupWizard + LineageParts)
#
# Ensuite :
#   ./flash.sh bootanimation <apk-patched>   (ou push manuel via TWRP si setupwizard)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OVERLAY_DIR="$REPO_ROOT/xperia/overlay/packages/apps/SetupWizard/res/values"

KEYSTORE="$HOME/.furaxos-debug.keystore"
KEYSTORE_ALIAS="furaxosdebug"
KEYSTORE_PASS="furaxos-debug"

APKTOOL_VERSION="2.9.3"
APKTOOL_JAR="$HOME/.cache/furaxos/apktool.jar"

log() { echo -e "\033[1;32m[furaxos-patch]\033[0m $*"; }
err() { echo -e "\033[1;31m[furaxos-patch]\033[0m $*" >&2; }

ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  if ! command -v apt-get >/dev/null 2>&1; then
    err "Commande manquante : $cmd, et apt-get n'est pas disponible."; exit 1
  fi
  log "Installation de $cmd via apt (paquet '$pkg')..."
  sudo apt-get update -qq && sudo apt-get install -y "$pkg"
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' toujours introuvable."; exit 1; }
}

ensure_apktool_jar() {
  [ -f "$APKTOOL_JAR" ] && return 0
  ensure_cmd java default-jdk
  ensure_cmd curl curl
  mkdir -p "$(dirname "$APKTOOL_JAR")"
  log "Téléchargement d'apktool $APKTOOL_VERSION..."
  local url="https://github.com/iBotPeaches/Apktool/releases/download/v${APKTOOL_VERSION}/apktool_${APKTOOL_VERSION}.jar"
  curl -fL --retry 3 -o "$APKTOOL_JAR" "$url" || { rm -f "$APKTOOL_JAR"; err "Échec du téléchargement."; exit 1; }
}

apktool() { ensure_apktool_jar; java -jar "$APKTOOL_JAR" "$@"; }

ensure_keystore() {
  [ -f "$KEYSTORE" ] && return 0
  ensure_cmd keytool default-jdk
  log "Génération du keystore de debug FuraxOS..."
  keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -alias "$KEYSTORE_ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$KEYSTORE_PASS" -keypass "$KEYSTORE_PASS" \
    -dname "CN=FuraxOS Debug, O=FuraxOS, C=FR"
}

usage() {
  cat <<EOF
Usage:
  $0 extract <rom.zip>              Extrait SetupWizard.apk et LineageParts.apk d'une ROM
  $0 patch <apk_in> [apk_out]      Patche un APK avec le branding FuraxOS
  $0 pull [chemin_tel] [dest.apk]  Pull un APK depuis le téléphone (adb)
  $0 patch-all <rom.zip>           Tout en une fois : extrait + patche SetupWizard + LineageParts
EOF
  exit 1
}

# Applique l'overlay de strings FuraxOS sur toutes les locales (values/, values-fr/, etc.)
apply_overlay_resources() {
  local decompiled="$1"
  ensure_cmd python3 python3

  python3 - "$decompiled" "$OVERLAY_DIR" <<'PYEOF'
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

decompiled = Path(sys.argv[1])
overlay_values = Path(sys.argv[2])

def merge_resource_file(target_path, overlay_path, tag):
    if not overlay_path.exists():
        return
    if not target_path.exists():
        return
    overlay_root = ET.parse(overlay_path).getroot()
    overlay_map = {el.get("name"): el for el in overlay_root.findall(tag)}
    if not overlay_map:
        return
    target_tree = ET.parse(target_path)
    target_root = target_tree.getroot()
    changed = 0
    for el in target_root.findall(tag):
        name = el.get("name")
        if name in overlay_map:
            el.text = overlay_map[name].text
            changed += 1
    if changed:
        ET.indent(target_tree, space="    ")
        target_tree.write(target_path, encoding="utf-8", xml_declaration=True)
        print(f"  Patché {changed} entrée(s) dans {target_path.relative_to(decompiled)}")

# Patche values/ et toutes les locales (values-fr/, values-en/, etc.)
for locale_dir in [decompiled / "res" / "values"] + sorted((decompiled / "res").glob("values-*")):
    if not locale_dir.is_dir():
        continue
    merge_resource_file(locale_dir / "strings.xml", overlay_values / "strings.xml", "string")
    merge_resource_file(locale_dir / "colors.xml", overlay_values / "colors.xml", "color")
PYEOF
}

# Remplace aussi les occurrences brutes de "LineageOS" dans les strings XML
replace_lineage_strings() {
  local decompiled="$1"
  ensure_cmd python3 python3

  python3 - "$decompiled" <<'PYEOF'
import sys, re
from pathlib import Path

decompiled = Path(sys.argv[1])
res = decompiled / "res"
replacements = [
    (r'\bLineageOS\b', 'FuraxOS'),
    (r'\bLineage OS\b', 'FuraxOS'),
    (r'\bLineage\b', 'FuraxOS'),
    (r'\bCyanogenMod\b', 'FuraxOS'),
    (r'\bCM\b(?=\s+(?:Settings|Version|version))', 'FuraxOS'),
]
count = 0
for xml_file in res.rglob("*.xml"):
    try:
        content = xml_file.read_text(encoding="utf-8")
    except Exception:
        continue
    new_content = content
    for pattern, replacement in replacements:
        new_content = re.sub(pattern, replacement, new_content)
    if new_content != content:
        xml_file.write_text(new_content, encoding="utf-8")
        count += 1
        print(f"  Remplacé dans {xml_file.relative_to(decompiled)}")
print(f"  {count} fichier(s) modifié(s)")
PYEOF
}

cmd_patch() {
  local apk_in="$1"
  local apk_out="${2:-${apk_in%.apk}-furaxos.apk}"
  [ -f "$apk_in" ] || { err "Fichier introuvable : $apk_in"; exit 1; }

  ensure_cmd java default-jdk
  ensure_keystore

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT

  log "Décompilation de $apk_in..."
  apktool d "$apk_in" -o "$workdir/decompiled" -f

  log "Application de l'overlay FuraxOS (strings/colors localisés)..."
  apply_overlay_resources "$workdir/decompiled"

  log "Remplacement des occurrences brutes de LineageOS/CyanogenMod..."
  replace_lineage_strings "$workdir/decompiled"

  log "Recompilation..."
  apktool b "$workdir/decompiled" -o "$workdir/unsigned.apk"

  log "Signature avec le keystore FuraxOS debug..."
  jarsigner -sigalg SHA256withRSA -digestalg SHA-256 \
    -keystore "$KEYSTORE" -storepass "$KEYSTORE_PASS" -keypass "$KEYSTORE_PASS" \
    "$workdir/unsigned.apk" "$KEYSTORE_ALIAS"

  cp "$workdir/unsigned.apk" "$apk_out"
  log "APK patché → $apk_out"
}

cmd_extract() {
  local rom_zip="$1"
  ensure_cmd unzip unzip
  [ -f "$rom_zip" ] || { err "Fichier introuvable : $rom_zip"; exit 1; }

  for name in SetupWizard LineageParts; do
    local internal
    internal="$(unzip -Z1 "$rom_zip" | grep -iE "${name}.*\.apk$" | head -n1)"
    if [ -n "$internal" ]; then
      log "Extraction de $name..."
      unzip -p "$rom_zip" "$internal" > "${name}.apk"
      log "→ ${name}.apk"
    else
      log "⚠️  $name non trouvé dans la ROM (peut être dans system.new.dat — extraction manuelle nécessaire)"
    fi
  done
}

cmd_pull() {
  local remote_path="${1:-/system/priv-app/SetupWizard/SetupWizard.apk}"
  local local_dest="${2:-$(basename "$remote_path")}"
  ensure_cmd adb android-tools-adb
  log "Pull de $remote_path..."
  adb pull "$remote_path" "$local_dest"
  log "→ $local_dest"
}

cmd_patch_all() {
  local rom_zip="$1"
  cmd_extract "$rom_zip"
  for apk in SetupWizard.apk LineageParts.apk; do
    [ -f "$apk" ] && cmd_patch "$apk" "${apk%.apk}-furaxos.apk"
  done
  log "Terminé. APKs patchés :"
  ls -lh ./*-furaxos.apk 2>/dev/null || true
  log "Installe-les depuis TWRP (avant le premier boot) :"
  log "  adb push SetupWizard-furaxos.apk /system/priv-app/SetupWizard/SetupWizard.apk"
  log "  adb push LineageParts-furaxos.apk /system/priv-app/LineageParts/LineageParts.apk"
}

[ $# -ge 1 ] || usage
case "$1" in
  extract)   [ $# -ge 2 ] || usage; cmd_extract "$2" ;;
  patch)     [ $# -ge 2 ] || usage; cmd_patch "$2" "${3:-}" ;;
  pull)      cmd_pull "${2:-}" "${3:-}" ;;
  patch-all) [ $# -ge 2 ] || usage; cmd_patch_all "$2" ;;
  *)         usage ;;
esac
