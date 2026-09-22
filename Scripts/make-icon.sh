#!/usr/bin/env bash
# Turn the app icon artwork into Support/AppIcon.icns, which Scripts/bundle.sh puts in the app.
#
# Usage: Scripts/make-icon.sh path/to/icon-1024.png
#
# The artwork is a 1024 x 1024 PNG following Apple's macOS icon grid: the shape fills the
# 824 x 824 rounded rectangle centered on the canvas, with transparency around it. Every size
# macOS asks for is scaled down from it with sips; iconutil packs them.
set -euo pipefail

source_png="${1:?usage: $0 path/to/icon-1024.png}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

width="$(sips -g pixelWidth "$source_png" | awk '/pixelWidth/ { print $2 }')"
height="$(sips -g pixelHeight "$source_png" | awk '/pixelHeight/ { print $2 }')"
if [[ "$width" != 1024 || "$height" != 1024 ]]; then
    echo "error: $source_png is ${width} x ${height}; it must be 1024 x 1024" >&2
    exit 64
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
iconset="$scratch/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_png" --out "$iconset/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$source_png" --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil --convert icns --output "$root/Support/AppIcon.icns" "$iconset"
echo "Wrote Support/AppIcon.icns. Rebuild with 'make run' to see it."
