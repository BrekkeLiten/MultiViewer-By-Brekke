# MultiViewer by Brekke

Native **macOS** app that shows up to **four live video feeds** in a Metal-powered multiview (**1-up** or **4-up**), with a small **HTTP control API** suited for **[Bitfocus Companion](https://bitfocus.io/companion/)** or any system that can send `POST` requests.

NDI ingestion uses the vendor **NDI runtime** (`libndi.dylib` / `libndi.3.dylib`) loaded at runtime. **Blackmagic DeckLink SDI** uses the DeckLink APIs from Blackmagic Desktop Video—the app lists devices and captures when drivers are installed.

## Requirements

| Item | Notes |
|------|------|
| **macOS** | 13+ (SwiftPM package platform) |
| **Swift** | Toolchain matching `Package.swift` (Swift 6.3 family) |
| **NDI** | A working **`libndi`** on the machine (see [NDI setup](#ndi-runtime-setup)) |
| **DeckLink (SDI)** | **Blackmagic Desktop Video** drivers for macOS plus a compatible DeckLink/UltraStudio device; configure SDI connection in Desktop Video Setup if needed. |

## Features

- **Layouts**: Full-screen **slot 1** (1-up) or **four quadrants** (4-up).
- **NDI receivers**: Sources from **NDI Finder** when possible; bonjour **`_ndi._tcp`** as fallback; **`ndi:IPv4:port`** for direct IP connect.
- **Aspect ratio**: Incoming **NDI/SDI** frames are letterboxed/pillarboxed to match **broadcast display aspect** (NDI `picture_aspect_ratio`, or pixel size when unset).
- **On-screen HUD**: Upper-right label shows **NDI · WxH / SDI · WxH** (and slot breakdown in 4-up).
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

The display redraws **on each new frame** (not a blind 60 Hz timer). Restart the app after changing **`previewMaxFPS`** or **`ndiFullQuality`**.

## Application shortcuts & UI

| Action | Shortcut / location |
|--------|---------------------|
| Preferences | **⌘ ,** |
| 1-Up layout | **⌘ 1** (View menu) |
| 4-Up layout | **⌘ 4** |
| Configure inputs… | **⇧ ⌘ I** ; title-bar **Inputs…** |

The main window subtitle shows **`Control: http://127.0.0.1:PORT`** when the server is running.

## NDI runtime setup

MultiViewer by Brekke does **not** ship NDI’s proprietary library; it discovers and `dlopen`s it at launch.

1. Prefer installing **NDI Tools / runtime for macOS** from [ndi.video/download](https://ndi.video/download/).
2. The loader searches typical locations (`/Library/NDI`, NDI-branded `.app` bundles under `/Applications`, Homebrew **`/opt/homebrew/lib`**, some third-party bundles such as **Resolume**, **`NDI_RUNTIME_DIR_V3`** / **`NDI_SDK_DIR`**).
3. **`HX_Driver`** under `Application Support` is **HX codec helpers**, **not** a replacement for the core **`libndi`** — you still need a full runtime.

Override directory (folder **containing** the dylib):

```bash
export NDI_RUNTIME_DIR_V3="/path/to/folder"
swift run MetalMultiviewer
```

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

Success: JSON `{"ok":true}`. Errors: `400` with `{"ok":false,"error":"…"}`.

## Bitfocus Companion setup

Companion does not need a bespoke module if you use the **generic HTTP / generic TCP** helpers.

### Generic HTTP Request (recommended)

1. Edit a button → **Actions** → add **HTTP** / **REST**–style action (exact name varies by Companion version — “HTTP Request”, “TCP/UDP Send”, or use **[companion-generic-http](https://github.com/bitfocus/companion-generic-http)** module if installed).
2. Method: **`POST`**.
3. URL examples (port **8080**):
   - **4-up**: `http://127.0.0.1:8080/layout/4`
   - **1-up**: `http://127.0.0.1:8080/layout/1`
   - **NDI slot 2**:  
     `http://127.0.0.1:8080/source/2/` + encoded name, e.g.  
     `http://127.0.0.1:8080/source/2/ndi%3AMYHOST%20(Screen%201)` (`ndi:` encoded as `%3A`).
4. No auth or custom headers required.
5. If Companion runs on another computer, **`127.0.0.1` points at that remote machine**, not the MultiViewer host — expose the HTTP server on a reachable interface first (currently not configured in-repo).

Tip: Encode tricky NDI titles in Companion using a **Javascript** trigger or Companion’s encoding fields; test with **curl**:

```bash
curl -X POST 'http://127.0.0.1:8080/layout/4'
curl -X POST --globoff 'http://127.0.0.1:8080/source/1/ndi:MACHINE%20(Main)'
```

## Project layout

- `Sources/MetalMultiviewer/` — App entry, MTKView pipeline, preferences, discovery, HTTP control, NDI modules, DeckLink SDI capture.
- `Sources/DeckLinkBridge/` — Objective-C++ bridge and vendored DeckLink SDK headers (Blackmagic-licensed; see `LICENSE.decklink-sdk`).
- `Sources/MetalMultiviewer/Resources/Shaders.metal` — textured quad shaders.
- `Tests/MetalMultiviewerTests/` — lightweight config tests.

## License / NDI trademark

Uses **NDI** via the vendor dynamic library installed on your system — comply with Vizrt/NewTek **[NDI license terms](https://ndi.video/)** for redistribution or bundling beyond personal use.

---

If you extend HTTP control or SDI DeckLink paths, prefer small PR-shaped changes and keep Companion URLs backwards compatible.
