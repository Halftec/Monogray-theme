#!/bin/bash
# Rebuild every wallpaper in theme/backgrounds/ from the generators.
# All of them are original, procedurally generated art (no third-party images).
#
#   tools/build-wallpapers.sh [python]    python needs numpy + pillow
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
PY=${1:-python3}
OUT=theme/backgrounds
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$PY" tools/make-cityscape.py "$tmp/city.png" --seed 7
"$PY" tools/make-cityscape.py "$tmp/fog.png" --seed 21 --fog 2.4 --no-moon --no-stars
"$PY" tools/make-landscape.py mountains "$tmp/mountains.png" --seed 3
"$PY" tools/make-landscape.py planet "$tmp/planet.png" --seed 3
tools/tint.sh "$tmp/city.png" "$tmp/city-blue.png"

rm -f "$OUT"/*
tools/progressive-blur.sh "$tmp/city.png" "$OUT/1-city-night.jpg"
tools/progressive-blur.sh "$tmp/fog.png" "$OUT/2-city-fog.jpg"
tools/progressive-blur.sh "$tmp/mountains.png" "$OUT/3-mountains.jpg"
tools/progressive-blur.sh "$tmp/planet.png" "$OUT/4-planet.jpg"
tools/progressive-blur.sh "$tmp/city-blue.png" "$OUT/5-city-blue.jpg"
