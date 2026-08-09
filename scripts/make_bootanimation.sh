#!/usr/bin/env bash
#
# make_bootanimation.sh — génère un bootanimation.zip Android à partir d'images PNG,
# pour personnaliser l'écran de démarrage (après le splash bas-niveau du kernel, pendant
# le boot du système) de FriteOS.
#
# Ça ne remplace PAS le logo de boot bas-niveau (celui affiché avant même le kernel) —
# voir docs/CUSTOMIZATION.md pour la différence entre les deux et les limites sur le SM-T530.
#
# Usage :
#   ./make_bootanimation.sh <dossier_frames_png> <sortie.zip> [largeur] [hauteur] [fps]
#
# <dossier_frames_png> doit contenir des PNG numérotés (part0/0000.png, 0001.png, ...)
# ou un seul PNG pour une image statique en boucle.
#
# Résolution recommandée pour le SM-T530 (écran 1280x800) : 1280 800 (ou une résolution
# réduite type 800 500 pour un boot plus rapide sur ce matériel limité en RAM/GPU).

set -euo pipefail

log() { echo -e "\033[1;32m[friteos-bootanim]\033[0m $*"; }
err() { echo -e "\033[1;31m[friteos-bootanim]\033[0m $*" >&2; }

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

ensure_cmd zip

FRAMES_DIR="${1:?Usage: $0 <dossier_frames_png> <sortie.zip> [largeur] [hauteur] [fps]}"
OUT_ZIP="${2:?Usage: $0 <dossier_frames_png> <sortie.zip> [largeur] [hauteur] [fps]}"
WIDTH="${3:-1280}"
HEIGHT="${4:-800}"
FPS="${5:-24}"

[ -d "$FRAMES_DIR" ] || { err "Dossier introuvable : $FRAMES_DIR"; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

PART_DIR="$WORKDIR/part0"
mkdir -p "$PART_DIR"

png_count=$(find "$FRAMES_DIR" -maxdepth 1 -iname '*.png' | wc -l)
if [ "$png_count" -eq 0 ]; then
  err "Aucun PNG trouvé dans $FRAMES_DIR"
  exit 1
fi

log "Copie de $png_count frame(s) PNG..."
i=0
find "$FRAMES_DIR" -maxdepth 1 -iname '*.png' | sort | while read -r f; do
  cp "$f" "$PART_DIR/$(printf '%04d' "$i").png"
  i=$((i + 1))
done

cat > "$WORKDIR/desc.txt" <<EOF
$WIDTH $HEIGHT $FPS
p 0 0 part0
EOF

ABS_OUT_ZIP="$(cd "$(dirname "$OUT_ZIP")" && pwd)/$(basename "$OUT_ZIP")"
log "Création de l'archive $ABS_OUT_ZIP (stockage non compressé, requis par Android pour bootanimation)..."
rm -f "$ABS_OUT_ZIP"
( cd "$WORKDIR" && zip -q -X -0 -r "$ABS_OUT_ZIP" desc.txt part0 )

log "Terminé : $ABS_OUT_ZIP (${WIDTH}x${HEIGHT} @ ${FPS}fps, $png_count frame(s))"
log "Installe-le avec : ./flash.sh bootanimation $OUT_ZIP"
