# Bundling the NDI runtime

MultiViewer release builds can ship the NDI® runtime inside the app bundle. This document covers build steps, compliance, and signing notes.

**Not legal advice.** Download the [NDI SDK](https://ndi.video/for-developers/ndi-sdk/), read the License Agreement in the SDK folder, and accept it before distributing embedded libraries.

## Prerequisites

1. Download and extract the **NDI SDK for Apple** from [ndi.video/for-developers/ndi-sdk](https://ndi.video/for-developers/ndi-sdk).
2. Note the SDK root path (often `/Library/NDI SDK for Apple` after install).
3. Notify Vizrt about your commercial app: [support@ndi.video](mailto:support@ndi.video) (requested in [SDK licensing docs](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing)).

## Build with bundled NDI

```bash
export NDI_SDK_DIR="/Library/NDI SDK for Apple"
./Scripts/build-app.sh release
# or
./Scripts/build-dmg.sh
```

`Scripts/bundle-ndi.sh` copies `libndi*.dylib` from `$NDI_SDK_DIR/lib/macOS/` into:

```text
MultiViewer by Brekke.app/Contents/Frameworks/
```

It also copies non-system dylib dependencies reported by `otool -L` and sets `@rpath` load paths.

If **`NDI_SDK_DIR` is unset**, the app builds without Frameworks NDI libs and prints a warning — users must rely on a system NDI install (same as `swift run` development).

## Do not commit NDI binaries

- **`libndi*.dylib` must not be checked into git.**
- `/dist` is already gitignored.
- Only copy from your local SDK at build time.

## Do not bundle NDI Tools

Ship **SDK runtime dylibs only**. Do not redistribute NDI Tools apps (Scan Converter, Router, etc.). Link users to [ndi.video/tools](https://ndi.video/tools) instead.

## License compliance checklist

| Requirement | Where |
|-------------|--------|
| NDI® trademark on first use + attribution | App **Acknowledgments…**, Preferences NDI footer, [README](../README.md), [website](../website/) |
| Link to [ndi.video](https://ndi.video/) near NDI usage | Preferences, Acknowledgments, website |
| Runtime inside app `Contents/Frameworks/` | `Scripts/bundle-ndi.sh` |
| Notify Vizrt about commercial app | Email [support@ndi.video](mailto:support@ndi.video) |

## Code signing and notarization

Bundled dylibs require signing before wide distribution:

```bash
codesign --force --options runtime --sign "Developer ID Application: Your Name (TEAMID)" \
  "dist/MultiViewer by Brekke.app"

xcrun notarytool submit "dist/MultiViewer-by-Brekke.dmg" --keychain-profile "AC_PROFILE" --wait
xcrun stapler staple "dist/MultiViewer by Brekke.app"
```

Adjust profile and certificate names for your Apple Developer account.

## Runtime load order

[`NDILibraryLoader.swift`](../Sources/MetalMultiviewer/Video/NDI/NDILibraryLoader.swift) searches:

1. `NDI_RUNTIME_DIR_V3` / `NDI_SDK_DIR` env overrides (development)
2. **`Contents/Frameworks/libndi*.dylib`** when running as a packaged `.app`
3. System paths (`/Library/NDI`, NDI Tools apps, Homebrew, etc.)

Bundled runtime is preferred over system installs to avoid version conflicts, per NDI SDK guidance.
