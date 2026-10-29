#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/.build/dmg-dd"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"

xcodebuild \
  -project "$ROOT/GeoSpoofer.xcodeproj" \
  -scheme GeoSpoofer \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build

APP="$(find "$DERIVED/Build/Products/Release" -name 'GeoSpoofer.app' -maxdepth 1 -print -quit)"
if [[ -z "$APP" ]]; then
  echo "Release app was not built." >&2
  exit 1
fi

mkdir -p "$DIST"
rm -f "$DIST/GeoSpoofer.dmg"
cp -R "$APP" "$STAGE/GeoSpoofer.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname GeoSpoofer -srcfolder "$STAGE" -ov -format UDZO "$DIST/GeoSpoofer.dmg"
echo "Wrote $DIST/GeoSpoofer.dmg"
