#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MultiViewer by Brekke"
BUNDLE_ID="com.brekke.multiviewer"
BUILD_CONFIG="${1:-release}"
ARCH="$(uname -m)"
case "$ARCH" in
    arm64) SWIFT_TRIPLE="arm64-apple-macosx" ;;
    x86_64) SWIFT_TRIPLE="x86_64-apple-macosx" ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac
PRODUCT="$ROOT/.build/$SWIFT_TRIPLE/$BUILD_CONFIG/MetalMultiviewer"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

cd "$ROOT"
swift build -c "$BUILD_CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RES"

cp "$PRODUCT" "$MACOS/MetalMultiviewer"
cp "$ROOT/Sources/MetalMultiviewer/Resources/AppIcon.icns" "$RES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MetalMultiviewer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Built $APP_DIR"
echo "Open with: open \"$APP_DIR\""
