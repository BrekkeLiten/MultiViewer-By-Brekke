#!/usr/bin/env bash
# Sign and notarize MultiViewer for distribution (Messages, web download, etc.).
#
# One-time setup (Apple Developer Program required, ~$99/year):
#   1. Xcode → Settings → Accounts → your team → Manage Certificates →
#      create "Developer ID Application".
#   2. Store notary credentials:
#        xcrun notarytool store-credentials "multiviewer-notary" \
#          --apple-id "you@example.com" \
#          --team-id "YOURTEAMID" \
#          --password "@keychain:AC_PASSWORD"
#      (App-specific password from appleid.apple.com)
#
# Usage:
#   export APPLE_NOTARY_KEYCHAIN_PROFILE="multiviewer-notary"
#   ./Scripts/sign-and-notarize.sh sign [path/to/App.app]
#   ./Scripts/sign-and-notarize.sh notarize [path/to/App.app] [path/to.dmg]
#   ./Scripts/sign-and-notarize.sh all [path/to/App.app] [path/to.dmg]
#
# Or:
#   NOTARIZE=1 ./Scripts/build-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MultiViewer by Brekke"

resolve_identity() {
    if [[ -n "${APPLE_DEVELOPER_ID:-}" ]]; then
        echo "$APPLE_DEVELOPER_ID"
        return
    fi
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' \
        | head -1
}

sign_app() {
    local app_dir="$1"
    local identity
    identity="$(resolve_identity)"

    if [[ -z "$identity" ]]; then
        echo "sign-and-notarize: no Developer ID Application certificate found." >&2
        echo "  Create one in Xcode (Accounts → Manage Certificates) or set APPLE_DEVELOPER_ID." >&2
        exit 1
    fi

    if [[ ! -d "$app_dir" ]]; then
        echo "sign-and-notarize: app not found: $app_dir" >&2
        exit 1
    fi

    echo "Signing with: $identity"

    sign_file() {
        codesign --force --options runtime --timestamp \
            --sign "$identity" \
            "$1"
    }

    while IFS= read -r -d '' dylib; do
        echo "  signing $(basename "$dylib")"
        sign_file "$dylib"
    done < <(find "$app_dir/Contents/Frameworks" -type f \( -name '*.dylib' -o -name '*.framework' \) -print0 2>/dev/null || true)

    local exec="$app_dir/Contents/MacOS/MetalMultiviewer"
    if [[ -f "$exec" ]]; then
        echo "  signing MetalMultiviewer"
        sign_file "$exec"
    fi

    echo "  signing app bundle"
    sign_file "$app_dir"

    echo "Verifying signature…"
    codesign --verify --deep --strict --verbose=2 "$app_dir"
    spctl -a -vv -t exec "$app_dir"
}

notarize_dmg() {
    local app_dir="$1"
    local dmg_path="$2"
    local profile="${APPLE_NOTARY_KEYCHAIN_PROFILE:-}"

    if [[ -z "$profile" ]]; then
        echo "sign-and-notarize: set APPLE_NOTARY_KEYCHAIN_PROFILE (see script header)." >&2
        exit 1
    fi

    if [[ ! -f "$dmg_path" ]]; then
        echo "sign-and-notarize: DMG not found: $dmg_path" >&2
        exit 1
    fi

    echo "Submitting $dmg_path to Apple notarization (this may take a few minutes)…"
    xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$profile" \
        --wait

    echo "Stapling notarization ticket…"
    xcrun stapler staple "$dmg_path"
    xcrun stapler staple "$app_dir"

    echo "Done. Distribute: $dmg_path"
    spctl -a -vv -t open "$dmg_path" || true
}

ACTION="${1:-all}"
case "$ACTION" in
    sign)
        sign_app "${2:-$ROOT/dist/$APP_NAME.app}"
        ;;
    notarize)
        notarize_dmg "${2:-$ROOT/dist/$APP_NAME.app}" "${3:-$ROOT/dist/MultiViewer-by-Brekke.dmg}"
        ;;
    all)
        APP_DIR="${2:-$ROOT/dist/$APP_NAME.app}"
        DMG_PATH="${3:-$ROOT/dist/MultiViewer-by-Brekke.dmg}"
        sign_app "$APP_DIR"
        notarize_dmg "$APP_DIR" "$DMG_PATH"
        ;;
    *)
        echo "Usage: $0 {sign|notarize|all} [App.app] [file.dmg]" >&2
        exit 1
        ;;
esac
