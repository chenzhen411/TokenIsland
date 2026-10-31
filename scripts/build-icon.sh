#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

output="${1:-$PWD/dist/AppIcon.icns}"
staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/TokenIsland-icon.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
iconset="$staging_directory/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$output")"

# Native 1x and Retina representations, generated from the transparent master.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" Resources/AppIcon.png \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$output"
echo "Icon: $output"
