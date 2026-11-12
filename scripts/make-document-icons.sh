#!/bin/sh
# Render the V on an Apple document page for macOS and iPad file icons.
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_icon="$repo_dir/apps/apple/Vow/AppIcon.icon/Assets/glyph.png"
resources="$repo_dir/apps/apple/Vow/Resources"
task_dir=$(mktemp -d)
trap 'rm -rf "$task_dir"' EXIT
source_glyph="$source_icon"
source_icon="$task_dir/document.png"
xcrun swift "$repo_dir/scripts/render-document-icon.swift" "$source_glyph" "$source_icon"
iconset="$task_dir/VowReviewDocument.iconset"
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
iconutil -c icns "$iconset" -o "$resources/VowReviewDocument.icns"
for pixels in 64 320; do
  sips -z "$pixels" "$pixels" "$source_icon" \
    --out "$resources/VowReviewDocument${pixels}.png" >/dev/null
done

# Files on iPad supplies the document page and uses this image as its badge.
xcrun swift "$repo_dir/scripts/render-document-icon.swift" "$source_glyph" "$task_dir/badge.png" badge
for pixels in 64 320; do
  sips -z "$pixels" "$pixels" "$task_dir/badge.png" \
    --out "$resources/VowDocumentBadge${pixels}.png" >/dev/null
done
