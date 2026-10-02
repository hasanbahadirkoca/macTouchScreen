#!/usr/bin/env bash
# Builds TouchRemap.app (universal), signs it ad-hoc and packs it as .zip and .dmg in build/.
# Usage: scripts/bundle.sh [version]   (default: 0.0.0-dev)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0-dev}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-$(date +%Y%m%d%H%M)}"
APP="build/TouchRemap.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/TouchRemap"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TouchRemap"
cp Support/AppIcon.icns "$APP/Contents/Resources/"
cp -R Support/Localization/*.lproj "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Support/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --deep --sign - --identifier com.hasanbahadirkoca.TouchRemap "$APP"
codesign --verify --strict "$APP"

rm -f "build/TouchRemap-$VERSION.zip" "build/TouchRemap-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "build/TouchRemap-$VERSION.zip"

STAGE="build/dmg"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "TouchRemap $VERSION" -srcfolder "$STAGE" -ov -format UDZO "build/TouchRemap-$VERSION.dmg"
rm -rf "$STAGE"

echo "Built $APP, build/TouchRemap-$VERSION.zip, build/TouchRemap-$VERSION.dmg"
