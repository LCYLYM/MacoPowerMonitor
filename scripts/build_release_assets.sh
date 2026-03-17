#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacoPowerMonitor"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
RELEASES_DIR="$DIST_DIR/releases"

cd "$ROOT_DIR"

./scripts/package_app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
ZIP_NAME="$APP_NAME-v$VERSION-macos.zip"
ZIP_PATH="$RELEASES_DIR/$ZIP_NAME"
CHECKSUM_PATH="$ZIP_PATH.sha256"

mkdir -p "$RELEASES_DIR"
rm -f "$ZIP_PATH" "$CHECKSUM_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "$CHECKSUM_PATH"

echo "Release assets:"
echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
