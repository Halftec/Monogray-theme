#!/bin/bash
# Add Monogray's "progressive blur" to a wallpaper: the top strip is
# blurred and tinted, then fades back into the sharp image, so the fully
# transparent bar still reads as frosted glass. This is the Omarchy version of
# the Figma wallpaper template in juxtopposed/Mystical-Blue-Theme.
#
#   tools/progressive-blur.sh <input> <output.jpg> [width] [height]
#
# Crops to fill width x height (default 2560x1440) first, so the strip always
# lands on the real top edge of the screen.
set -euo pipefail

in=${1:?usage: progressive-blur.sh <input> <output> [width] [height]}
out=${2:?usage: progressive-blur.sh <input> <output> [width] [height]}
W=${3:-2560}
H=${4:-1440}

command -v magick >/dev/null || { echo "ImageMagick (magick) is required" >&2; exit 1; }

# Strip geometry scales with height: solid blur for the bar, then a soft fade.
solid=$((H * 30 / 1440))
fade=$((H * 110 / 1440))

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

magick "$in" -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" +repage "$tmp/base.png"
magick "$tmp/base.png" -blur 0x24 -fill '#1c1c23' -colorize 20% "$tmp/blur.png"
magick -size "${W}x${H}" xc:black \
  \( -size "${W}x${fade}" gradient:white-black \) -geometry "+0+${solid}" -composite \
  \( -size "${W}x${solid}" xc:white \) -geometry +0+0 -composite \
  "$tmp/mask.png"
magick "$tmp/base.png" "$tmp/blur.png" "$tmp/mask.png" -composite -quality 92 "$out"
echo "wrote $out"
