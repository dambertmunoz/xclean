#!/usr/bin/env bash
#
# make-icons.sh — render assets/logo.svg into a macOS .icns (app icon, all
# Finder/Dock sizes) and assets/menubar-icon.svg into a Retina PNG used
# as a template image in the status bar.
#
# Uses macOS Quick Look (qlmanage) for SVG → PNG because ImageMagick's
# built-in MSVG renderer silently drops stroke-width / stroke-color
# attributes. qlmanage backs onto WebKit and renders correctly.
#
# Outputs (copied into xclean.app/Contents/Resources/ by build-app.sh):
#   build/icons/xclean.icns
#   build/icons/menubar.png    (22×22, 1×)
#   build/icons/menubar@2x.png (44×44, 2×)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/assets"
OUT="$ROOT/build/icons"
ICONSET="$OUT/xclean.iconset"
TMP="$(mktemp -d -t xclean-icons)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v qlmanage >/dev/null 2>&1; then
  echo "error: qlmanage missing (should be /usr/bin/qlmanage on macOS)" >&2
  exit 1
fi
if ! command -v iconutil >/dev/null 2>&1; then
  echo "error: iconutil missing" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$ICONSET"

# Render the source SVG once per pixel size and rename qlmanage's
# fixed `<file>.png` output into the iconset's `icon_NxN[@2x].png`
# naming convention.
render_logo() {
  local px="$1" out_name="$2"
  rm -rf "$TMP/render"
  mkdir -p "$TMP/render"
  qlmanage -t -s "$px" -o "$TMP/render" "$ASSETS/logo.svg" >/dev/null 2>&1
  mv "$TMP/render/logo.svg.png" "$ICONSET/$out_name"
}

echo "→ rendering logo PNGs via qlmanage"
SIZES=(16 32 128 256 512)
for s in "${SIZES[@]}"; do
  s2=$((s * 2))
  render_logo "$s"  "icon_${s}x${s}.png"
  render_logo "$s2" "icon_${s}x${s}@2x.png"
done

echo "→ assembling xclean.icns"
iconutil --convert icns --output "$OUT/xclean.icns" "$ICONSET"

echo "→ rendering menu bar template (22×22 + 44×44)"
rm -rf "$TMP/render"
mkdir -p "$TMP/render"
qlmanage -t -s 22 -o "$TMP/render" "$ASSETS/menubar-icon.svg" >/dev/null 2>&1
mv "$TMP/render/menubar-icon.svg.png" "$OUT/menubar.png"
qlmanage -t -s 44 -o "$TMP/render" "$ASSETS/menubar-icon.svg" >/dev/null 2>&1
mv "$TMP/render/menubar-icon.svg.png" "$OUT/menubar@2x.png"

ls -la "$OUT"
