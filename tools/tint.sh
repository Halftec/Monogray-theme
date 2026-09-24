#!/bin/bash
# Map a grayscale wallpaper onto a dark->light color ramp (duotone).
#
#   tools/tint.sh <input> <output> [dark] [light]
#
# Defaults are Monogray's darkest background and a pale version of its accent.
set -euo pipefail
in=${1:?usage: tint.sh <input> <output> [dark] [light]}
out=${2:?usage: tint.sh <input> <output> [dark] [light]}
dark=${3:-#0b0c14}
light=${4:-#d6e2ff}
magick "$in" -colorspace gray -colorspace sRGB +level-colors "$dark,$light" "$out"
echo "wrote $out"
