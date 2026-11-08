#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacoPowerMonitor"
DIST_DIR="$ROOT_DIR/dist"
APP_CONSTANTS_PATH="$ROOT_DIR/Sources/MacoPowerMonitor/Support/AppConstants.swift"
ARCH="arm64"
BUILD_TRIPLE="${MACO_BUILD_TRIPLE:-arm64-apple-macosx13.0}"

if [[ "$BUILD_TRIPLE" != arm64-* ]]; then
  echo "Portable builds must target arm64, got: $BUILD_TRIPLE" >&2
  exit 1
fi

cd "$ROOT_DIR"

APP_VERSION="$(awk -F'"' '/appVersion/ { print $2; exit }' "$APP_CONSTANTS_PATH")"
if [[ -z "$APP_VERSION" ]]; then
  echo "Could not determine app version from $APP_CONSTANTS_PATH" >&2
  exit 1
fi

BUILD_ARGS=(-c release --triple "$BUILD_TRIPLE")
if [[ -n "${SDKROOT:-}" ]]; then
  BUILD_ARGS+=(--sdk "$SDKROOT")
fi
if [[ "${MACO_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  BUILD_ARGS+=(--disable-sandbox)
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  swift build "${BUILD_ARGS[@]}"
fi

BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
EXECUTABLE_PATH="$BIN_PATH/$APP_NAME"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Release executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

PORTABLE_EXECUTABLE="$DIST_DIR/$APP_NAME-v$APP_VERSION-macos-$ARCH"

rm -rf "$PORTABLE_EXECUTABLE"
mkdir -p "$DIST_DIR"
cp "$EXECUTABLE_PATH" "$PORTABLE_EXECUTABLE"
chmod +x "$PORTABLE_EXECUTABLE"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$PORTABLE_EXECUTABLE"
  codesign --verify --strict --verbose=2 "$PORTABLE_EXECUTABLE"
fi

if ! file "$PORTABLE_EXECUTABLE" | grep -q "Mach-O 64-bit executable $ARCH"; then
  echo "Portable executable has an unexpected architecture" >&2
  exit 1
fi

UNEXPECTED_DEPENDENCIES="$(otool -L "$PORTABLE_EXECUTABLE" | tail -n +2 | awk '{print $1}' | grep -Ev '^/System/Library/|^/usr/lib/' || true)"
if [[ -n "$UNEXPECTED_DEPENDENCIES" ]]; then
  echo "Portable executable has non-system dependencies:" >&2
  echo "$UNEXPECTED_DEPENDENCIES" >&2
  exit 1
fi

if nm -nm "$PORTABLE_EXECUTABLE" | grep -E 'prunedHistory|chartBuckets|PowerHistoryStore' >/dev/null; then
  echo "Portable executable still contains the legacy in-memory history implementation" >&2
  exit 1
fi
if ! nm -nm "$PORTABLE_EXECUTABLE" | grep 'PowerHistoryEngine' >/dev/null; then
  echo "Portable executable does not contain PowerHistoryEngine" >&2
  exit 1
fi

echo "Built portable executable:"
echo "$PORTABLE_EXECUTABLE"
