#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacoPowerMonitor"
PRODUCT_NAME="Maco Power Monitor"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
BACKGROUND_PATH="$ROOT_DIR/Assets/Brand/dmg-background.png"
VOLUME_ICON_PATH="$ROOT_DIR/Assets/Brand/VolumeIcon.icns"

cd "$ROOT_DIR"

if [[ "${SKIP_PACKAGE_APP:-0}" != "1" ]]; then
  ./scripts/package_app.sh
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Packaged app not found at $APP_DIR" >&2
  exit 1
fi

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  echo "DMG background not found at $BACKGROUND_PATH" >&2
  exit 1
fi

if [[ ! -f "$VOLUME_ICON_PATH" ]]; then
  echo "DMG volume icon not found at $VOLUME_ICON_PATH" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d "$DIST_DIR/dmg-build.XXXXXX")"
STAGING_DIR="$TEMP_DIR/staging"
RW_DMG_PATH="$TEMP_DIR/$APP_NAME-temp.dmg"
MOUNT_POINT="/Volumes/$PRODUCT_NAME"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

customize_finder_window() {
  osascript <<EOF &
tell application "Finder"
  tell disk "$PRODUCT_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {140, 120, 1140, 760}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 112
    set text size of theViewOptions to 14
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {300, 345}
    set position of item "Applications" of container window to {760, 345}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

  local script_pid=$!
  local elapsed=0
  local max_wait=20
  local exit_code=0

  while kill -0 "$script_pid" >/dev/null 2>&1; do
    if (( elapsed >= max_wait )); then
      kill "$script_pid" >/dev/null 2>&1 || true
      wait "$script_pid" >/dev/null 2>&1 || true
      echo "Finder customization timed out; continuing with default DMG layout." >&2
      return 0
    fi
    sleep 1
    ((elapsed+=1))
  done

  wait "$script_pid" || exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "Finder customization failed; continuing with default DMG layout." >&2
  fi
}

mkdir -p "$STAGING_DIR/.background"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$BACKGROUND_PATH" "$STAGING_DIR/.background/background.png"
cp "$VOLUME_ICON_PATH" "$STAGING_DIR/.VolumeIcon.icns"

hdiutil create \
  -quiet \
  -volname "$PRODUCT_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  "$RW_DMG_PATH"

DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG_PATH" | awk '/Apple_HFS/ {print $1; exit}')"
if [[ -z "$DEVICE" ]]; then
  echo "Failed to mount temporary DMG" >&2
  exit 1
fi

if [[ -f "$MOUNT_POINT/.VolumeIcon.icns" ]]; then
  SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns"
fi
SetFile -a C "$MOUNT_POINT"
customize_finder_window

sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

rm -f "$DMG_PATH"
hdiutil convert \
  -quiet \
  "$RW_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH"

echo "Built DMG:"
echo "$DMG_PATH"
