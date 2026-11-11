#!/bin/sh
# Package the existing transparent V as macOS and iPad document icon resources.
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_icon="$repo_dir/apps/apple/Vow/AppIcon.icon/Assets/glyph.png"
resources="$repo_dir/apps/apple/Vow/Resources"
task_dir=$(mktemp -d)
trap 'rm -rf "$task_dir"' EXIT
iconset="$task_dir/VowDocument.iconset"
mkdir -p "$iconset" "$resources"
for points in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((points * scale))
    suffix=""
    if [ "$scale" -eq 2 ]; then suffix="@2x"; fi
    sips -z "$pixels" "$pixels" "$source_icon" \
      --out "$iconset/icon_${points}x${points}${suffix}.png" >/dev/null
  done
done
iconutil -c icns "$iconset" -o "$resources/VowDocument.icns"
for pixels in 64 320; do
  sips -z "$pixels" "$pixels" "$source_icon" \
    --out "$resources/VowDocument${pixels}.png" >/dev/null
done
