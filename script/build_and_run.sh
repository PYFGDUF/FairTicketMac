#!/usr/bin/env bash
#
# Build the SwiftPM executable, assemble a real .app bundle around it, and launch.
#
# SwiftPM alone produces a bare Mach-O binary.  A macOS GUI app needs a bundle so
# the window server, the menu bar and the Dock treat it as a regular application
# instead of a background process, so this script lays out Contents/ by hand.
#
#   ./script/build_and_run.sh              build and launch
#   ./script/build_and_run.sh --no-launch  build only, print the bundle path
#   CONFIG=release ./script/build_and_run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP_NAME="FairTicketMac"
BUNDLE="$ROOT/build/$APP_NAME.app"

cd "$ROOT"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "error: 找不到构建产物 $BIN" >&2
  exit 1
fi

echo "==> assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# The icon is referenced by CFBundleIconFile, so it has to sit next to the plist.
# Regenerate it with ./script/make_icon.sh after a palette change.
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
else
  echo "==> no AppIcon.icns; run ./script/make_icon.sh to give the app an icon"
fi

# SwiftPM resource bundles.  FairTicketUI keeps the captured capabilities snapshot and
# the login-QR fixture, and `Bundle.module` *fatal-errors* when its bundle is missing —
# so a hand-assembled .app that skips this copy crashes the moment a preview or a demo
# scenario reads a resource.
COPIES=0
for bundle in "$BIN_DIR"/*.bundle; do
  [[ -e "$bundle" ]] || continue
  cp -R "$bundle" "$BUNDLE/Contents/Resources/"
  COPIES=$((COPIES + 1))
done
if [[ "$COPIES" == "0" ]]; then
  echo "warning: no SwiftPM resource bundles found in $BIN_DIR" >&2
else
  echo "==> embedded $COPIES resource bundle(s)"
fi

# The frozen engine, when it has been built, is what makes the bundle self-contained:
# EngineLocator finds Contents/Resources/engine/run-sidecar before any checkout, so
# copying it here is what turns a development build into a shippable one.
ENGINE="$ROOT/build/engine/run-sidecar"
if [[ -x "$ENGINE" ]]; then
  echo "==> embedding frozen engine"
  mkdir -p "$BUNDLE/Contents/Resources/engine"
  cp "$ENGINE" "$BUNDLE/Contents/Resources/engine/run-sidecar"
else
  echo "==> no frozen engine; the app will run the development checkout"
  echo "    (run ./script/build_engine.sh to embed one)"
fi

# Ad-hoc signature: enough for local use and for the window server to trust the
# bundle.  Distribution would need a Developer ID identity instead.
codesign --force --sign - "$BUNDLE" >/dev/null

if [[ "${1:-}" == "--no-launch" ]]; then
  echo "bundle: $BUNDLE"
  exit 0
fi

echo "==> launching"
open "$BUNDLE"