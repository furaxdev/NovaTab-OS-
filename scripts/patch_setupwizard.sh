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
#       Extrait SetupWizard.apk d'un zip de ROM déjà compilée (LineageOS 14.1). Extrait aussi
#       au passage les framework-res (AOSP + CM/LineageOS platform) si trouvés, pour que
#       `patch` puisse résoudre les attributs de ressources spécifiques à LineageOS.
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

# Le paquet apt "apktool" (Debian/Ubuntu) est repackagé sans ses binaires aapt/aapt2
# embarqués (contraintes de licence) et retombe sur l'aapt système, souvent bien trop
# récent/incompatible avec les APK Android 7.1 — d'où l'usage du jar officiel à la place.
APKTOOL_VERSION="2.9.3"
APKTOOL_JAR="$HOME/.cache/friteos/apktool.jar"

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

# ensure_apktool_jar — télécharge le jar officiel d'apktool (pas le paquet apt cassé).
ensure_apktool_jar() {
  [ -f "$APKTOOL_JAR" ] && return 0
  ensure_cmd java default-jdk
  ensure_cmd curl curl

  mkdir -p "$(dirname "$APKTOOL_JAR")"
  log "Téléchargement d'apktool $APKTOOL_VERSION (jar officiel, pas le paquet apt)..."
  local url="https://github.com/iBotPeaches/Apktool/releases/download/v${APKTOOL_VERSION}/apktool_${APKTOOL_VERSION}.jar"
  if ! curl -fL --retry 3 -o "$APKTOOL_JAR" "$url"; then
    rm -f "$APKTOOL_JAR"
    err "Échec du téléchargement d'apktool depuis $url"
    exit 1
  fi
}

apktool() {
  ensure_apktool_jar
  java -jar "$APKTOOL_JAR" "$@"
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

# sdat2img_reconstruct <transfer.list> <system.new.dat> <sortie system.img>
# Réimplémentation autonome de l'algorithme sdat2img (format block-based d'Android,
# transfer.list v1-v4) : rejoue uniquement les commandes "new" pour reconstruire les blocs
# de données réels — "erase"/"zero" sont ignorées car sans contenu de fichier utile ici.
sdat2img_reconstruct() {
  local transfer_list="$1" new_dat="$2" out_img="$3"
  ensure_cmd python3 python3

  python3 - "$transfer_list" "$new_dat" "$out_img" <<'PYEOF'
import sys

transfer_list, new_dat, out_img = sys.argv[1], sys.argv[2], sys.argv[3]
BLOCK_SIZE = 4096

with open(transfer_list) as f:
    lines = [l.strip() for l in f if l.strip()]

version = int(lines[0])
total_blocks = int(lines[1])
cmd_start = 4 if version >= 2 else 2  # v2+ a 2 lignes de stash-count à ignorer
commands = lines[cmd_start:]

with open(out_img, "wb") as out:
    out.truncate(total_blocks * BLOCK_SIZE)

    with open(new_dat, "rb") as dat:
        for line in commands:
            parts = line.split(" ", 1)
            if len(parts) != 2 or parts[0] != "new":
                continue
            tokens = [int(x) for x in parts[1].split(",")]
            num_ranges = tokens[0] // 2
            ranges = tokens[1:]
            with open(out_img, "r+b") as out2:
                for i in range(num_ranges):
                    start, end = ranges[2 * i], ranges[2 * i + 1]
                    length = end - start
                    data = dat.read(length * BLOCK_SIZE)
                    out2.seek(start * BLOCK_SIZE)
                    out2.write(data)

print(f"system.img reconstruit : {total_blocks * BLOCK_SIZE} octets")
PYEOF
}

# e2cp_safe <system.img> <chemin interne> <sortie>
# e2cp d'e2tools ne renvoie PAS un code de sortie fiable quand le fichier n'existe pas
# (il imprime juste "not found" et sort en 0) — on vérifie donc la présence réelle du
# fichier extrait plutôt que son exit code.
e2cp_safe() {
  local img="$1" internal_path="$2" out="$3"
  rm -f "$out"
  e2cp "$img:$internal_path" "$out" >/dev/null 2>&1
  [ -s "$out" ]
}

cmd_extract() {
  local rom_zip="$1" out_apk="${2:-SetupWizard.apk}"
  ensure_cmd unzip unzip
  [ -f "$rom_zip" ] || { err "Fichier introuvable : $rom_zip"; exit 1; }

  local out_dir
  out_dir="$(cd "$(dirname "$out_apk")" && pwd)"
  local fw_out="$out_dir/framework-res.apk"
  local cm_fw_out="$out_dir/cm-platform-res.apk"

  local internal_path
  internal_path="$(unzip -Z1 "$rom_zip" | grep -iE 'setupwizard.*\.apk$' | head -n1)"

  if [ -n "$internal_path" ]; then
    log "Trouvé : $internal_path"
    unzip -p "$rom_zip" "$internal_path" > "$out_apk"
    log "Extrait vers $out_apk"

    # Best-effort : si la ROM contient aussi des fichiers system/ à plat, tente de récupérer
    # les framework-res pour patch (pas grave si absent, patch s'en passera si pas nécessaire).
    local fw_path cm_fw_path
    fw_path="$(unzip -Z1 "$rom_zip" | grep -E '(^|/)framework-res\.apk$' | head -n1)"
    cm_fw_path="$(unzip -Z1 "$rom_zip" | grep -E '(^|/)(org\.(cyanogenmod|lineageos)\.platform-res)\.apk$' | head -n1)"
    [ -n "$fw_path" ] && unzip -p "$rom_zip" "$fw_path" > "$fw_out" 2>/dev/null
    [ -n "$cm_fw_path" ] && unzip -p "$rom_zip" "$cm_fw_path" > "$cm_fw_out" 2>/dev/null
    return
  fi

  if ! unzip -Z1 "$rom_zip" | grep -q 'system.new.dat'; then
    err "Aucun SetupWizard*.apk trouvé dans $rom_zip."
    err "Structure de ROM inattendue — regarde 'unzip -l $rom_zip | grep -i setupwizard' pour investiguer."
    exit 1
  fi

  log "Zip au format \"block-based\" (system.new.dat[.br]) — reconstruction automatique de system.img..."
  ensure_cmd e2cp e2tools

  local workdir
  workdir="$(mktemp -d)"
  trap "rm -rf '$workdir'" EXIT

  local transfer_list_path new_dat_path compressed=0
  transfer_list_path="$(unzip -Z1 "$rom_zip" | grep -E 'system\.transfer\.list$' | head -n1)"
  new_dat_path="$(unzip -Z1 "$rom_zip" | grep -E 'system\.new\.dat\.br$' | head -n1)"
  if [ -n "$new_dat_path" ]; then
    compressed=1
  else
    # Certaines ROM plus anciennes n'ont pas de compression brotli : system.new.dat brut.
    new_dat_path="$(unzip -Z1 "$rom_zip" | grep -E 'system\.new\.dat$' | head -n1)"
  fi

  if [ -z "$transfer_list_path" ] || [ -z "$new_dat_path" ]; then
    err "system.transfer.list ou system.new.dat[.br] introuvable dans le zip malgré la détection block-based."
    err "Regarde 'unzip -l $rom_zip' pour investiguer la structure exacte."
    exit 1
  fi

  unzip -p "$rom_zip" "$transfer_list_path" > "$workdir/system.transfer.list"

  if [ "$compressed" -eq 1 ]; then
    ensure_cmd brotli brotli
    unzip -p "$rom_zip" "$new_dat_path" > "$workdir/system.new.dat.br"
    log "Décompression brotli..."
    brotli -d "$workdir/system.new.dat.br" -o "$workdir/system.new.dat"
  else
    log "system.new.dat non compressé, extraction directe..."
    unzip -p "$rom_zip" "$new_dat_path" > "$workdir/system.new.dat"
  fi

  log "Reconstruction de system.img (peut prendre une minute)..."
  sdat2img_reconstruct "$workdir/system.transfer.list" "$workdir/system.new.dat" "$workdir/system.img"

  log "Recherche de SetupWizard.apk dans system.img (via e2tools, sans mount)..."
  local candidate found=""
  for candidate in \
    "priv-app/LineageSetupWizard/LineageSetupWizard.apk" \
    "app/LineageSetupWizard/LineageSetupWizard.apk" \
    "priv-app/SetupWizard/SetupWizard.apk" \
    "app/SetupWizard/SetupWizard.apk"; do
    if e2cp_safe "$workdir/system.img" "$candidate" "$out_apk"; then
      found="$candidate"
      break
    fi
  done

  if [ -z "$found" ]; then
    err "SetupWizard.apk introuvable aux emplacements habituels dans system.img."
    err "Cherche manuellement avec : e2ls $workdir/system.img:priv-app/ | grep -i setup"
    err "(le zip temporaire a été nettoyé — relance la commande pour investiguer si besoin)"
    exit 1
  fi

  log "Trouvé : system/$found"
  log "Extrait vers $out_apk"

  # Best-effort, comme pour le cas "zip à plat" ci-dessus.
  e2cp_safe "$workdir/system.img" "framework/framework-res.apk" "$fw_out" || true
  e2cp_safe "$workdir/system.img" "framework/org.cyanogenmod.platform-res.apk" "$cm_fw_out" \
    || e2cp_safe "$workdir/system.img" "framework/org.lineageos.platform-res.apk" "$cm_fw_out" || true
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

  ensure_cmd jarsigner default-jdk

  local workdir
  workdir="$(mktemp -d)"
  trap "rm -rf '$workdir'" EXIT

  # Si extract a trouvé des framework-res à côté de l'APK, on les enregistre auprès
  # d'apktool — nécessaire pour résoudre les attributs/ressources spécifiques à
  # LineageOS/CM (ex: android:allowViaWhitelist), sinon la recompilation échoue.
  local apk_dir
  apk_dir="$(cd "$(dirname "$apk_in")" && pwd)"
  for fw in "$apk_dir/framework-res.apk" "$apk_dir/cm-platform-res.apk"; do
    if [ -f "$fw" ]; then
      log "Enregistrement du framework $(basename "$fw") auprès d'apktool..."
      apktool if "$fw" > "$workdir/apktool-if-$(basename "$fw").log" 2>&1 \
        || log "(échec non bloquant, voir $workdir/apktool-if-$(basename "$fw").log)"
    fi
  done

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
    if grep -q "attribute.*not found\|resource identifier found" "$workdir/apktool-build.log"; then
      err ""
      err "Cause probable : cet APK référence des attributs spécifiques à un framework OEM/LineageOS"
      err "(ex: org.cyanogenmod.platform-res.apk ou org.lineageos.platform-res.apk) qui n'a pas été"
      err "trouvé/enregistré. Si extract n'a pas pu le récupérer automatiquement, place-le manuellement"
      err "à côté de $apk_in sous le nom cm-platform-res.apk et relance."
    fi
    exit 1
  fi

  ensure_keystore

  # SHA1withRSA est désactivé par défaut sur les JDK récents (jarsigner traiterait l'APK
  # comme non signé) — SHA-256 est le standard actuel, largement supporté depuis Android 4.3.
  log "Signature avec la clé de debug FriteOS (voir l'avertissement en tête de ce script)..."
  cp "$workdir/rebuilt.apk" "$apk_out"
  if ! jarsigner -sigalg SHA256withRSA -digestalg SHA-256 \
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
