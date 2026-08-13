#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources/PunchReminder"
BUILD="$ROOT/.build"
APP_DIR="$BUILD/朝夕打卡.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
SDK="${SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
if [[ ! -d "$SDK" ]]; then
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi
TARGET="arm64-apple-macosx14.0"

mkdir -p "$BUILD" "$MACOS_DIR" "$RESOURCES_DIR"

echo "Compiling PunchReminder…"
swiftc -parse-as-library \
  -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -framework UserNotifications \
  -framework ServiceManagement \
  -o "$MACOS_DIR/PunchReminder" \
  "$SRC"/*.swift

cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
for sound in Glass Hero Ping Submarine Tink Pop Purr Sosumi Funk; do
  if [[ -f "/System/Library/Sounds/${sound}.aiff" ]]; then
    cp "/System/Library/Sounds/${sound}.aiff" "$RESOURCES_DIR/${sound}.aiff"
  fi
done
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
