#!/usr/bin/env bash
# Build a self-contained Apple Silicon DMG using the existing frozen engine.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="1.0.0"
if [[ "${1:-}" != "--skip-build" ]]; then
  swift build -c release --product FairTicketMac
fi
BIN_DIR="${FAIRTICKET_BIN_DIR:-$(swift build -c release --show-bin-path)}"
STAGE="$ROOT/build/dmg-stage"
APP="$STAGE/FairTicketMac.app"
[[ -x "$ROOT/build/engine/run-sidecar" ]] || { echo '请先执行 script/build_engine.sh'; exit 1; }
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engine"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_DIR/FairTicketMac" "$APP/Contents/MacOS/FairTicketMac"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/build/engine/run-sidecar" "$APP/Contents/Resources/engine/"
for resource in "$BIN_DIR"/*.bundle; do
  [[ -d "$resource" ]] && cp -R "$resource" "$APP/Contents/Resources/"
done
cp "$ROOT/NOTICE.md" "$APP/Contents/Resources/"
cp -R "$ROOT/docs/licenses" "$APP/Contents/Resources/licenses"
cp "$ROOT/vendor/12306FairTicket/docs/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$ROOT/build/releases"
DMG="$ROOT/build/releases/FairTicketMac-$VERSION-macos-arm64.dmg"
hdiutil create -volname "FairTicketMac $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "$DMG"
