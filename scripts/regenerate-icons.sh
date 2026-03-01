#!/usr/bin/env bash
set -euo pipefail

# Regenerate raster icon assets from SVG sources.
# Requires: rsvg-convert (from librsvg) or falls back to sips (macOS built-in).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
DESIGN="$ROOT/design"
ANDROID_RES="$ROOT/android/app/src/main/res"
MACOS_RES="$ROOT/macos/ClipRelayMac/Resources"

# ─── Helpers ──────────────────────────────────────────────────────────────────

has_cmd() { command -v "$1" &>/dev/null; }

svg_to_png() {
  local svg="$1" out="$2" size="$3"
  if has_cmd rsvg-convert; then
    rsvg-convert -w "$size" -h "$size" "$svg" -o "$out"
  elif has_cmd sips; then
    # sips can't read SVG directly — need a temp conversion via qlmanage
    local tmp="/tmp/cliprelay-icon-$size.png"
    qlmanage -t -s "$size" -o /tmp "$svg" 2>/dev/null
    local ql_out="/tmp/$(basename "$svg").png"
    if [[ -f "$ql_out" ]]; then
      mv "$ql_out" "$out"
    else
      echo "  SKIP: sips/qlmanage could not convert $svg at ${size}px" >&2
      return 1
    fi
  else
    echo "  SKIP: no rsvg-convert or sips available" >&2
    return 1
  fi
}

# ─── Android mipmap icons ────────────────────────────────────────────────────

echo "=== Android mipmap icons ==="

declare -A DENSITIES=(
  [mdpi]=48
  [hdpi]=72
  [xhdpi]=96
  [xxhdpi]=144
  [xxxhdpi]=192
)

declare -A FG_SIZES=(
  [mdpi]=108
  [hdpi]=162
  [xhdpi]=216
  [xxhdpi]=324
  [xxxhdpi]=432
)

for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  dir="$ANDROID_RES/mipmap-$density"
  mkdir -p "$dir"

  size="${DENSITIES[$density]}"
  fg_size="${FG_SIZES[$density]}"

  echo "  $density: ic_launcher.png (${size}px)"
  svg_to_png "$DESIGN/logo-android-icon.svg" "$dir/ic_launcher.png" "$size" || true

  echo "  $density: ic_launcher_foreground.png (${fg_size}px)"
  svg_to_png "$DESIGN/logo-android-icon.svg" "$dir/ic_launcher_foreground.png" "$fg_size" || true
done

# ─── macOS StatusBar icons ───────────────────────────────────────────────────

echo "=== macOS StatusBar icons ==="
mkdir -p "$MACOS_RES"

echo "  StatusBarIcon.png (18px)"
svg_to_png "$DESIGN/logo-menubar.svg" "$MACOS_RES/StatusBarIcon.png" 18 || true

echo "  StatusBarIcon@2x.png (36px)"
svg_to_png "$DESIGN/logo-menubar.svg" "$MACOS_RES/StatusBarIcon@2x.png" 36 || true

# ─── macOS AppIcon.icns ─────────────────────────────────────────────────────

echo "=== macOS AppIcon.icns ==="

if has_cmd rsvg-convert && has_cmd iconutil; then
  ICONSET="/tmp/ClipRelay.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"

  for size in 16 32 128 256 512; do
    echo "  icon_${size}x${size}.png"
    rsvg-convert -w "$size" -h "$size" "$DESIGN/logo-full-dark.svg" -o "$ICONSET/icon_${size}x${size}.png"
    double=$((size * 2))
    echo "  icon_${size}x${size}@2x.png (${double}px)"
    rsvg-convert -w "$double" -h "$double" "$DESIGN/logo-full-dark.svg" -o "$ICONSET/icon_${size}x${size}@2x.png"
  done

  iconutil -c icns -o "$MACOS_RES/AppIcon.icns" "$ICONSET"
  rm -rf "$ICONSET"
  echo "  -> AppIcon.icns generated"
else
  echo "  SKIP: need rsvg-convert + iconutil for .icns generation"
fi

echo "=== Done ==="
