# MultiViewer by Brekke

**Website:** [multiviewer.brek.ke](https://multiviewer.brek.ke) · landing page source in [`website/`](website/)

Native **macOS** app that shows up to **four live video feeds** in a Metal-powered multiview (**1-up** or **4-up**), with a small **HTTP control API** suited for **[Bitfocus Companion](https://bitfocus.io/companion/)** or any system that can send `POST` requests.

NDI ingestion uses the vendor **NDI® runtime** (`libndi.dylib` / `libndi.3.dylib`) loaded at runtime. Official **release builds** bundle the SDK runtime inside the app (see [NDI runtime](#ndi-runtime)). **Blackmagic DeckLink SDI** uses the DeckLink APIs from Blackmagic Desktop Video—the app lists devices and captures when drivers are installed.

## Requirements

| Item | Notes |
|------|------|
| **macOS** | 13+ (SwiftPM package platform) |
| **Swift** | Toolchain matching `Package.swift` (Swift 6.3 family) |
| **NDI** | **Included** in release `.app` builds (bundled at build time). Dev/`swift run` can use a system install — see [NDI runtime](#ndi-runtime) |
| **DeckLink (SDI)** | **Blackmagic Desktop Video** drivers for macOS plus a compatible DeckLink/UltraStudio device; configure SDI connection in Desktop Video Setup if needed. |

## Features

- **Layouts**: Full-screen **slot 1** (1-up) or **four quadrants** (4-up).
- **NDI receivers**: Sources from **NDI Finder** when possible; bonjour **`_ndi._tcp`** as fallback; **`ndi:IPv4:port`** for direct IP connect.
- **Aspect ratio**: Incoming **NDI/SDI** frames are letterboxed/pillarboxed to match **broadcast display aspect** (NDI `picture_aspect_ratio`, or pixel size when unset).
- **On-screen HUD**: Upper-right label shows **NDI · WxH / SDI · WxH** (and slot breakdown in 4-up).
- **1-up scope monitor** (optional): LiveScopes-style 2×2 grid — picture, vectorscope, RGB waveform, RGB parade. Drag the vertical/horizontal dividers to resize panels (saved in config). Enable in **Preferences** or `"oneUpScopeMonitor": true` in config.
- **Picture monitoring**: GPU **focus peaking**, **false color**, and **zebra** on all visible feeds. Title-bar controls (**P** / **F** / **Z** / gear) + **⌘⇧P/F/Z** shortcuts; peaking color, sensitivity, and zebra % in **Preferences**.
- **Inputs UI**: Sheet to assign **ndi:…** / **sdi:…** per slot; network scan button.
- **Persistence**: **`~/Library/Application Support/Multiviewer/config.json`** (layout + slots + control settings), or **`--config /path/to.json`**.
- **HTTP companion control**: **`POST`** endpoints bind to **127.0.0.1** on the configured port (default **8080** unless changed in Preferences).

## Build and run

From the package root:

```bash
swift build
swift run MetalMultiviewer
```

Run tests:

```bash
swift test
```

### Command-line overrides

| Argument | Effect |
|---------|--------|
| `--config path` | Use this JSON instead of the default Multiviewer `config.json` path. |
| `--port N` | **HTTP server listening port only** when starting (see note below vs Preferences). |

**Note:** Preference UI persists `port`; for day-to-day use, set port in **Preferences** so Companion URLs stay predictable.

### Config file shape (`AppConfig`)

Example `config.json`:

```json
{
  "layout": 4,
  "port": 8080,
  "controlEnabled": true,
  "previewMaxFPS": 30,
  "ndiFullQuality": true,
  "oneUpScopeMonitor": false,
  "scopeColumnSplit": 0.64,
  "scopeRowSplit": 0.72,
  "slots": {
    "1": "ndi:MACHINE-HOSTNAME (OBS)",
    "2": "ndi:192.168.1.10:5961",
    "3": "sdi:0"
  }
}
```

- **`layout`**: `1` = one-up, `4` = four-up.
- **`slots`**: keys `"1"`…`"4"`, values `ndi:…` or `sdi:n`.
- **`controlEnabled`**: omit or `true` to run HTTP control; `false` to disable.
- **`port`**: HTTP companion port.
- **`previewMaxFPS`** (optional): cap on **ingest/upload** rate per NDI/SDI slot (default **30**). Source FPS is used up to this cap. Also editable in **Preferences**. Clamped **5**–**120**.
- **`ndiFullQuality`** (optional): when **`false`**, NDI uses SDK low-bandwidth receive. Omit or **`true`** for full source resolution on the wire (default). Feeds are **downscaled to on-screen size** before GPU upload either way.
- **`oneUpScopeMonitor`** (optional): when **`true`**, **1-up** uses a LiveScopes-style layout: picture and vectorscope on top, RGB waveform and RGB parade below (display-only shading reference). Omit or **`false`** = fullscreen 1-up.
- **`scopeColumnSplit`** / **`scopeRowSplit`** (optional): left-column width and top-row height in **1-up scope monitor** (roughly **0.30–0.85** and **0.35–0.90**). Defaults **0.64** / **0.72**. Updated when you drag layout dividers.
- **`focusPeakingEnabled`**, **`falseColorEnabled`**, **`zebraEnabled`** (optional): picture monitoring toggles.
- **`focusPeakingColor`** (optional): `green`, `red`, `white`, or `yellow`.
- **`focusPeakingSensitivity`** (optional): edge threshold **0.05–0.35** (default **0.12**).
- **`zebraLevel`** (optional): over-exposure threshold **0.70–1.00** (default **0.90** = 90%).

The display redraws **on each new frame** (not a blind 60 Hz timer). Restart the app after changing **`previewMaxFPS`** or **`ndiFullQuality`**.

## Application shortcuts & UI

| Action | Shortcut / location |
|--------|---------------------|
| Preferences | **⌘ ,** |
| 1-Up layout | **⌘ 1** (View menu) |
| 4-Up layout | **⌘ 4** |
| Configure inputs… | **⇧ ⌘ I** ; title-bar **Inputs…** |
| Toggle focus peaking | **⇧ ⌘ P** (View menu) ; title bar **P** |
| Toggle false color | **⇧ ⌘ F** ; title bar **F** |
| Toggle zebra | **⇧ ⌘ Z** ; title bar **Z** |

The main window subtitle shows **`Control: http://127.0.0.1:PORT`** when the server is running.

## NDI runtime

Release builds made with **`NDI_SDK_DIR`** set (see [`docs/NDI-BUNDLING.md`](docs/NDI-BUNDLING.md)) ship the NDI® runtime inside **`MultiViewer by Brekke.app/Contents/Frameworks/`**. End users do **not** need a separate NDI Tools install for NDI inputs.

When developing with **`swift run`**, or if the app was built without bundling, the loader falls back to a system **`libndi`**:

1. Optional override: **`NDI_RUNTIME_DIR_V3`** or **`NDI_SDK_DIR`** (folder containing the dylib or SDK root).
2. Typical installs: **`/Library/NDI`**, NDI-branded `.app` bundles under **`/Applications`**, Homebrew **`/opt/homebrew/lib`**, or third-party apps such as **Resolume**.
3. **`HX_Driver`** under Application Support is **HX codec helpers**, **not** a replacement for the core **`libndi`**.

Build a release app **with** bundled NDI:

```bash
export NDI_SDK_DIR="/Library/NDI SDK for Apple"   # path to extracted SDK
./Scripts/build-dmg.sh
```

### Distribution (sign + notarize)

For downloads from the web or Messages to open without “damaged” errors, you need an [Apple Developer Program](https://developer.apple.com/programs/) membership and a **Developer ID Application** certificate.

One-time setup:

```bash
# Xcode → Settings → Accounts → Manage Certificates → Developer ID Application
xcrun notarytool store-credentials "multiviewer-notary" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "@keychain:AC_PASSWORD"
```

Release build with notarization:

```bash
export NDI_SDK_DIR="/Library/NDI SDK for Apple"
export APPLE_NOTARY_KEYCHAIN_PROFILE="multiviewer-notary"
NOTARIZE=1 ./Scripts/build-dmg.sh
```

Distribute `dist/MultiViewer-by-Brekke.dmg`. See [`docs/NDI-BUNDLING.md`](docs/NDI-BUNDLING.md) for signing details.

Learn more about NDI and optional tools at [ndi.video](https://ndi.video/). **NDI® is a registered trademark of Vizrt NDI AB.**

## Blackmagic DeckLink (SDI)

On a Mac with **Desktop Video** installed and hardware connected, open **Configure inputs** — DeckLink-backed inputs appear alongside NDI discovery. Slot refs use **`sdi:n`** where **`n`** is the device index (same order as Desktop Video lists devices). Capture enables **the highest reported input mode first** (UHD/8K/DCI fallbacks before 1080p), then format detection follows the incoming SDI/HDMI timing. On-wire format changes re-arm with **UYVY then BGRA**, consistent with startup.

## HTTP control API (Companion / automation)

Server listens on **IPv4 localhost** (**`127.0.0.1`**) unless you fork Swifter config. Companion on the **same Mac** uses `127.0.0.1`; from another machine you would need a proxy or extend the binding (not shipped by default).

Base URL (replace `8080` with your port):

```text
http://127.0.0.1:8080
```

All routes below use **`POST`** (body ignored).

### Layout

| Route | Meaning |
|-------|---------|
| `POST /layout/1` | Switch to **1-up** |
| `POST /layout/4` | Switch to **4-up** |

### Source per slot (`1…4`)

| Route pattern | Meaning |
|---------------|---------|
| `POST /source/{slot}/{name}` | Assign **ndi:** or **sdi:** ref to **`slot`** |

`{name}` is the literal string you'd type in Inputs, **URL-encoded**:

- Spaces → `%20`
- Parentheses and other specials → encode per RFC 3986

Examples (**encode the part after `{slot}/`**):

```http
POST /source/1/ndi:MACHINE-HOSTNAME%20(Program)
POST /source/2/ndi:192.168.1.20:5960
POST /source/3/sdi%3A0
```

To **clear** a slot programmatically — not exposed as HTTP in the current codebase; clear it in **Configure Inputs** (set to `(None)`).

### Picture monitoring

| Route | Meaning |
|-------|---------|
| `POST /monitoring/peaking/toggle` | Toggle focus peaking |
| `POST /monitoring/peaking/on` / `off` | Set focus peaking |
| `POST /monitoring/falsecolor/toggle` | Toggle false color |
| `POST /monitoring/falsecolor/on` / `off` | Set false color |
| `POST /monitoring/zebra/toggle` | Toggle zebra |
| `POST /monitoring/zebra/on` / `off` | Set zebra |
| `POST /monitoring/zebra/{70,80,90,95,100}` | Set zebra level (%) |

`GET /state` includes a `monitoring` object with current toggle states and `zebraLevel`.

Success: JSON `{"ok":true}`. Errors: `400` with `{"ok":false,"error":"…"}`.

## Bitfocus Companion setup

See **[Companion-Setup.md](Companion-Setup.md)** for the full walkthrough (button recipes, URL encoding, troubleshooting).

Quick version — Companion does not need a bespoke module; use the **generic HTTP** helper:

1. Edit a button → **Actions** → add an **HTTP Request**–style action.
2. Method: **`POST`**.
3. URL examples (port **8080**):
   - **4-up**: `http://<multiviewer-host>:8080/layout/4`
   - **1-up**: `http://<multiviewer-host>:8080/layout/1`
   - **NDI slot 2**:  
     `http://<multiviewer-host>:8080/source/2/` + encoded name, e.g.  
     `http://<multiviewer-host>:8080/source/2/ndi%3AMYHOST%20(Screen%201)` (`ndi:` encoded as `%3A`).
4. No auth or custom headers required.
5. If Companion runs on another computer, set the control server's **bind address** in **Preferences → Control** to your LAN IP (or `0.0.0.0` for all interfaces) and use the MultiViewer host's IP in URLs — `127.0.0.1` only works when Companion runs on the same machine.

Test with **curl**:

```bash
curl -X POST 'http://127.0.0.1:8080/layout/4'
curl -X POST --globoff 'http://127.0.0.1:8080/source/1/ndi:MACHINE%20(Main)'
```

## Project layout

- `Sources/MetalMultiviewer/` — App entry, MTKView pipeline, preferences, discovery, HTTP control, NDI modules, DeckLink SDI capture.
- `Sources/DeckLinkBridge/` — Objective-C++ bridge and vendored DeckLink SDK headers (Blackmagic-licensed; see `LICENSE.decklink-sdk`).
- `Sources/MetalMultiviewer/Resources/Shaders.metal` — textured quad shaders.
- `Tests/MetalMultiviewerTests/` — lightweight config tests.

## License / NDI® trademark

The NDI® runtime is redistributed in release builds under the [NDI SDK license](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing). **NDI® is a registered trademark of Vizrt NDI AB.** See **MultiViewer by Brekke → Acknowledgments…** in the app and [ndi.video](https://ndi.video/) for more information.

---

If you extend HTTP control or SDI DeckLink paths, prefer small PR-shaped changes and keep Companion URLs backwards compatible.
