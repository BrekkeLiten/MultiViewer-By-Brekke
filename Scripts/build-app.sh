#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
RESOURCE_BUNDLE="$ROOT/.build/$SWIFT_TRIPLE/$BUILD_CONFIG/MetalMultiviewer_MetalMultiviewer.bundle"
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
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "build-app: missing resource bundle: $RESOURCE_BUNDLE" >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/"

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
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

chmod +x "$SCRIPT_DIR/bundle-ndi.sh"
if [[ -n "${NDI_SDK_DIR:-}" ]]; then
    "$SCRIPT_DIR/bundle-ndi.sh" "$APP_DIR" "$NDI_SDK_DIR"
else
    echo "Warning: NDI_SDK_DIR not set — app built without bundled NDI runtime." >&2
    echo "         Users must install NDI Tools, or set NDI_SDK_DIR before building for release." >&2
    echo "         See docs/NDI-BUNDLING.md" >&2
fi

codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "Built $APP_DIR"
echo "Open with: open \"$APP_DIR\""

# Code signing / notarization (manual — required before wide distribution with bundled dylibs):
#   codesign --force --options runtime --sign "Developer ID Application: …" "$APP_DIR"
#   xcrun notarytool submit … && xcrun stapler staple "$APP_DIR"
