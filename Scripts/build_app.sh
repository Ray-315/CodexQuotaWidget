#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CodexQuotaWidget"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$MACOS_DIR/$APP_NAME"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICNS_PATH="$BUILD_DIR/AppIcon.icns"

SDK_CANDIDATES=(
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk"
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk"
  "/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk"
  "/Library/Developer/CommandLineTools/SDKs/MacOSX14.sdk"
  "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
)

SDK_PATH=""
for candidate in "${SDK_CANDIDATES[@]}"; do
  if [[ -d "$candidate" ]]; then
    SDK_PATH="$candidate"
    break
  fi
done

if [[ -z "$SDK_PATH" ]]; then
  echo "No supported macOS SDK found under /Library/Developer/CommandLineTools/SDKs" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swift -sdk "$SDK_PATH" "$ROOT_DIR/Scripts/generate_app_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

swiftc \
  -sdk "$SDK_PATH" \
  -parse-as-library \
  -emit-executable \
  "$ROOT_DIR"/Sources/CodexQuotaWidget/*.swift \
  -o "$EXECUTABLE_PATH" \
  -framework AppKit \
  -framework AuthenticationServices \
  -framework CryptoKit \
  -framework Network \
  -framework Security \
  -framework SwiftUI \
  -framework Combine

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

chmod +x "$EXECUTABLE_PATH"

echo "Built app bundle at: $APP_DIR"
