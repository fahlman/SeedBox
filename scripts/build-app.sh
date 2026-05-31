#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Seed Box"
EXECUTABLE_NAME="SeedBox"
CONFIGURATION="${CONFIGURATION:-release}"
SANDBOX="${SANDBOX:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/$CONFIGURATION/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Sources/SeedBox/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR"
fi

CODESIGN_ARGS=(--force --deep --sign "$CODESIGN_IDENTITY")

if [[ "$SANDBOX" == "1" ]]; then
  CODESIGN_ARGS+=(--entitlements "$ROOT_DIR/Packaging/Sandbox.entitlements")
fi

/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
