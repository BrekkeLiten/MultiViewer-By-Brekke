#!/usr/bin/env bash
# Copy NDI runtime dylibs from the official SDK into an .app bundle and fix load paths.
# Requires NDI_SDK_DIR (or pass as second argument). Does not commit binaries to git.
set -euo pipefail

APP_DIR="${1:?Usage: bundle-ndi.sh <path/to/App.app> [NDI_SDK_DIR]}"
NDI_SDK_DIR="${2:-${NDI_SDK_DIR:-}}"

if [[ -z "$NDI_SDK_DIR" ]]; then
    echo "bundle-ndi: NDI_SDK_DIR not set — skipping NDI bundling" >&2
    exit 0
fi

LIB_DIR="$NDI_SDK_DIR/lib/macOS"
FRAMEWORKS="$APP_DIR/Contents/Frameworks"
EXEC="$APP_DIR/Contents/MacOS/MetalMultiviewer"

if [[ ! -d "$LIB_DIR" ]]; then
    echo "bundle-ndi: missing SDK lib folder: $LIB_DIR" >&2
    exit 1
fi

if [[ ! -f "$EXEC" ]]; then
    echo "bundle-ndi: missing executable: $EXEC" >&2
    exit 1
fi

MAIN_LIB=""
MAIN_NAME=""
for name in libndi.3.dylib libndi.dylib libndi.4.dylib; do
    if [[ -f "$LIB_DIR/$name" ]]; then
        MAIN_LIB="$LIB_DIR/$name"
        MAIN_NAME="$name"
        break
    fi
done

if [[ -z "$MAIN_LIB" ]]; then
    echo "bundle-ndi: no libndi*.dylib in $LIB_DIR" >&2
    exit 1
fi

mkdir -p "$FRAMEWORKS"
COPIED_LIST="$(mktemp)"
trap 'rm -f "$COPIED_LIST"' EXIT

already_copied() {
    local base="$1"
    grep -Fxq "$base" "$COPIED_LIST" 2>/dev/null
}

mark_copied() {
    echo "$1" >> "$COPIED_LIST"
}

copy_dylib() {
    local src="$1"
    local base dest dep old new resolved
    base="$(basename "$src")"
    dest="$FRAMEWORKS/$base"

    if already_copied "$base"; then
        return 0
    fi

    if [[ ! -f "$src" ]]; then
        return 0
    fi

    cp -f "$src" "$dest"
    install_name_tool -id "@rpath/$base" "$dest"
    install_name_tool -add_rpath "@loader_path" "$dest" 2>/dev/null || true
    mark_copied "$base"

    while IFS= read -r dep; do
        dep="${dep%% *}"
        dep="${dep#"${dep%%[![:space:]]*}"}"
        [[ "$dep" == "@rpath/"* ]] && continue
        [[ "$dep" == /usr/* ]] && continue
        [[ "$dep" == /System/* ]] && continue
        [[ "$dep" != *.dylib ]] && continue

        if [[ -f "$dep" ]]; then
            resolved="$dep"
        elif [[ -f "$LIB_DIR/$(basename "$dep")" ]]; then
            resolved="$LIB_DIR/$(basename "$dep")"
        else
            continue
        fi

        copy_dylib "$resolved"
        old="$dep"
        new="@rpath/$(basename "$resolved")"
        if [[ "$old" != "$new" ]]; then
            install_name_tool -change "$old" "$new" "$dest" 2>/dev/null || true
        fi
    done < <(otool -L "$dest" | tail -n +2 | sed 's/^[[:space:]]*//')
}

copy_dylib "$MAIN_LIB"

install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXEC" 2>/dev/null || true

COPIED_COUNT="$(wc -l < "$COPIED_LIST" | tr -d ' ')"
echo "bundle-ndi: bundled $MAIN_NAME (+ $COPIED_COUNT dylib(s)) into $FRAMEWORKS"
