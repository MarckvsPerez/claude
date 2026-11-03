#!/usr/bin/env bash
# Genera 4 camas pixel-art con fal.ai para la zona de descanso de la oficina de SKY.
# Cada cama son 2 llamadas de pago a fal.ai (imagen con nano-banana-pro y quitar fondo con bria).
# Las descripciones de abajo se envían a fal.ai; no incluyen nada del proyecto.
#
# Uso: scripts/generate-beds.sh   (pide FAL_KEY sin mostrarla si no está en el entorno)

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${FAL_KEY:-}" ]]; then
  read -rsp "FAL_KEY de fal.ai (no se mostrará ni se guardará): " FAL_KEY
  echo
fi
export FAL_KEY

OUT=public/worlds/cozy-startup/world_assets/props
BASE="single bed seen from directly above, top-down, pillow at the top edge, blanket covering the lower two thirds, simple wooden frame, small office nap room bed, no people"

declare -a BEDS=(
  "green:dark forest green blanket, white pillow"
  "orange:warm orange blanket, white pillow"
  "beige:cream beige blanket, white pillow"
  "grey:soft light grey blanket, white pillow"
)

for bed in "${BEDS[@]}"; do
  color="${bed%%:*}"
  detail="${bed#*:}"
  target="$OUT/prop_13_bed_${color}.png"
  if [[ -f "$target" ]]; then
    echo "Ya existe $target; bórrala si quieres regenerarla."
    continue
  fi
  echo "== Cama $color"
  node node_modules/@miniverse/generate/dist/cli.js object \
    --prompt "$BASE, $detail" \
    --output "$target"
done

echo
echo "Listo. Avisa en el chat para colocar las camas en la escena."
