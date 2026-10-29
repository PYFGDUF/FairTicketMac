#!/usr/bin/env bash
#
# Build Resources/AppIcon.icns from the drawn master PNG.
#
#   ./script/make_icon.sh
#
# The icon is rendered from the app's own brand tokens by script/make_icon.swift, so
# it can be regenerated instead of being an opaque binary nobody can adjust.  Re-run
# it after a palette change; build_and_run.sh copies the .icns into the bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT/build/icon/AppIcon-1024.png"
ICONSET="$ROOT/build/icon/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"

mkdir -p "$ROOT/build/icon"
echo "==> 渲染 1024pt 主图"
swift "$ROOT/script/make_icon.swift" "$MASTER" >/dev/null

echo "==> 生成 iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
# The sizes iconutil expects; @2x entries are the doubled pixel sizes.
while read -r size name; do
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

echo "==> 打包 icns"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "icon: $OUT ($(du -h "$OUT" | cut -f1))"