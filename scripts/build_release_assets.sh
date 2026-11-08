#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacoPowerMonitor"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
RELEASES_DIR="$DIST_DIR/releases"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
ARCH="arm64"

cd "$ROOT_DIR"

./scripts/package_app.sh
SKIP_PACKAGE_APP=1 ./scripts/build_dmg.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
ZIP_NAME="$APP_NAME-v$VERSION-macos.zip"
ZIP_PATH="$RELEASES_DIR/$ZIP_NAME"
CHECKSUM_PATH="$ZIP_PATH.sha256"
DMG_NAME="$APP_NAME-v$VERSION-macos.dmg"
DMG_RELEASE_PATH="$RELEASES_DIR/$DMG_NAME"
DMG_CHECKSUM_PATH="$DMG_RELEASE_PATH.sha256"
PORTABLE_NAME="$APP_NAME-v$VERSION-macos-$ARCH"
PORTABLE_EXECUTABLE="$DIST_DIR/$PORTABLE_NAME"
PORTABLE_ZIP_NAME="$PORTABLE_NAME.zip"
PORTABLE_ZIP_PATH="$RELEASES_DIR/$PORTABLE_ZIP_NAME"
PORTABLE_CHECKSUM_PATH="$PORTABLE_ZIP_PATH.sha256"

SKIP_BUILD=1 ./scripts/build_portable_executable.sh

if [[ ! -f "$PORTABLE_EXECUTABLE" ]]; then
  echo "Portable executable not found at $PORTABLE_EXECUTABLE" >&2
  exit 1
fi

mkdir -p "$RELEASES_DIR"
rm -f "$ZIP_PATH" "$CHECKSUM_PATH" "$DMG_RELEASE_PATH" "$DMG_CHECKSUM_PATH" "$PORTABLE_ZIP_PATH" "$PORTABLE_CHECKSUM_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "$CHECKSUM_PATH"
cp "$DMG_PATH" "$DMG_RELEASE_PATH"
shasum -a 256 "$DMG_RELEASE_PATH" | awk '{print $1}' > "$DMG_CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent "$PORTABLE_EXECUTABLE" "$PORTABLE_ZIP_PATH"
shasum -a 256 "$PORTABLE_ZIP_PATH" | awk '{print $1}' > "$PORTABLE_CHECKSUM_PATH"

echo "Release assets:"
echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
echo "$DMG_RELEASE_PATH"
echo "$DMG_CHECKSUM_PATH"
echo "$PORTABLE_ZIP_PATH"
echo "$PORTABLE_CHECKSUM_PATH"
