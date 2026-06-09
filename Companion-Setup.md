# MultiViewer by Brekke — Bitfocus Companion setup

This guide explains how to install MultiViewer and control it from **[Bitfocus Companion](https://bitfocus.io/companion/)** (Stream Deck, buttons, macros, etc.) using the built-in HTTP API.

---

## 1. Install MultiViewer

1. Open **`MultiViewer-by-Brekke.dmg`**.
2. Drag **MultiViewer by Brekke** into **Applications**.
3. Eject the disk image.

**First launch:** Official downloads from [multiviewer.brek.ke](https://multiviewer.brek.ke) are signed and notarized — open the DMG, drag to Applications, and launch normally.

**If macOS says the app is “damaged”** (common when the app was sent via Messages/AirDrop or is an unsigned build): the app is not broken. Remove the quarantine flag, then open once:

```bash
xattr -cr "/Applications/MultiViewer by Brekke.app"
```

Or right-click the app → **Open** → **Open** again.

**NDI sources:** The release app includes the NDI® runtime. No separate NDI Tools install is required for NDI inputs. Optional NDI utilities are at [ndi.video/tools](https://ndi.video/tools).

**SDI (DeckLink):** Install Blackmagic **Desktop Video** drivers if you use SDI hardware.

---

## 2. Turn on the control server

1. Launch **MultiViewer by Brekke**.
2. Open **Preferences** (**⌘ ,** or menu **MultiViewer by Brekke → Preferences…**).
3. Under **Control**:
   - Check **Enable control server**.
   - Choose **Listen on** (see below).
   - Set **Port** (default **8080**).
4. Note the **URL** shown in Preferences — that is the base address for Companion buttons.

Settings are saved automatically.

### Which “Listen on” address?

| Setting | Use when |
|--------|----------|
| **Localhost (127.0.0.1)** | Companion runs on the **same Mac** as MultiViewer. |
| **Wi‑Fi / Ethernet (your LAN IP)** | Companion runs on **another computer** on the same network (e.g. Stream Deck PC). |
| **All interfaces (0.0.0.0)** | Listen on every interface; the URL shown uses your first LAN IP. |

Example URL: `http://192.168.0.185:8080`

Use **Copy URL** in Preferences when building Companion actions.

---

## 3. Install Companion

1. Download and install Companion from [bitfocus.io/companion](https://bitfocus.io/companion/).
2. Open the Companion admin page in your browser (usually `http://127.0.0.1:8000` on the Companion machine).
3. Create or open a **button page** for your Stream Deck / surface.

Companion does **not** need a special MultiViewer module. Use generic HTTP actions.

---

## 4. Add HTTP button actions

For each button, add an action that sends an HTTP **POST** request to MultiViewer.

The exact action name depends on your Companion version, for example:

- **Generic HTTP Request**
- **HTTP Request**
- Module: **[companion-generic-http](https://github.com/bitfocus/companion-generic-http)**

Configure each action:

| Field | Value |
|-------|--------|
| **Method** | `POST` |
| **URL** | Full URL (see examples below) |
| **Body** | Leave empty |
| **Headers / auth** | None required |

Replace the host and port with the URL from MultiViewer **Preferences**.

### Layout buttons

| Button idea | URL |
|-------------|-----|
| **4-up multiview** | `http://192.168.0.185:8080/layout/4` |
| **1-up (single full screen)** | `http://192.168.0.185:8080/layout/1` |
| **1-up, show slot 2** | `http://192.168.0.185:8080/layout/primary/2` |

`primary` sets which input (1–4) fills the screen in **1-up** mode.

### Assign a source to a slot

Route pattern:

```http
POST /source/{slot}/{source}
```

`{slot}` is **1**, **2**, **3**, or **4**.

`{source}` is the same text you pick in **Configure inputs**, for example:

- `ndi:OBS (Program)` — NDI source name after `ndi:`
- `ndi:192.168.1.10:5961` — direct NDI IP connect
- `sdi:0` — first DeckLink device

**Important:** Special characters in the URL must be **percent-encoded**:

| Character | Encoded |
|-----------|---------|
| `:` | `%3A` |
| Space | `%20` |
| `(` | `%28` |
| `)` | `%29` |

**Examples**

| Goal | URL |
|------|-----|
| NDI “OBS (Program)” on slot 1 | `http://192.168.0.185:8080/source/1/ndi%3AOBS%20(Program)` |
| NDI IP on slot 2 | `http://192.168.0.185:8080/source/2/ndi%3A192.168.1.10%3A5961` |
| SDI device 0 on slot 3 | `http://192.168.0.185:8080/source/3/sdi%3A0` |

Tip: Open **Configure inputs…** (**⇧ ⌘ I**) in MultiViewer to see exact NDI/SDI names, then encode them for the URL.

---

## 5. Test with curl (optional)

On the machine that can reach MultiViewer’s control URL:

```bash
# 4-up layout
curl -X POST 'http://192.168.0.185:8080/layout/4'

# 1-up layout
curl -X POST 'http://192.168.0.185:8080/layout/1'

# Read current layout + monitoring (GET)
curl 'http://192.168.0.185:8080/state'

# Toggle focus peaking
curl -X POST 'http://192.168.0.185:8080/monitoring/peaking/toggle'
```

Successful commands return JSON like `{"ok":true}`.

---

## 6. API reference (quick)

Base URL: `http://HOST:PORT` (from Preferences)

| Method | Path | Effect |
|--------|------|--------|
| `GET` | `/state` | JSON: `layout`, `primarySlot`, and `monitoring` |
| `POST` | `/layout/1` | Switch to 1-up |
| `POST` | `/layout/4` | Switch to 4-up |
| `POST` | `/layout/primary/{1-4}` | Which slot is fullscreen in 1-up |
| `POST` | `/source/{slot}/{name}` | Assign NDI/SDI source to slot |
| `POST` | `/monitoring/peaking/toggle` | Toggle focus peaking |
| `POST` | `/monitoring/peaking/on` / `off` | Set focus peaking |
| `POST` | `/monitoring/falsecolor/toggle` | Toggle false color |
| `POST` | `/monitoring/falsecolor/on` / `off` | Set false color |
| `POST` | `/monitoring/zebra/toggle` | Toggle zebra |
| `POST` | `/monitoring/zebra/on` / `off` | Set zebra |
| `POST` | `/monitoring/zebra/{70,80,90,95,100}` | Set zebra level (%) |

Errors return HTTP **400** with `{"ok":false,"error":"…"}`.

Clearing a slot is done in the app (**Configure inputs** → **(None)**); there is no HTTP “clear slot” route yet.

**Scope monitor:** When enabled in **Preferences → Scope monitor in 1-up**, switching to **1-up** shows picture, vectorscope, RGB waveform, and RGB parade (no YUV parade). Scopes are display-only.

**Picture monitoring:** Use the title-bar **P** / **F** / **Z** controls (top-right) or HTTP routes above for focus peaking, false color, and zebra on all visible feeds. Peaking color, sensitivity, and zebra % are in **Preferences → Picture monitoring** (gear icon opens Preferences).

---

## 7. Troubleshooting

| Problem | Things to check |
|---------|------------------|
| Button does nothing | MultiViewer is running; **Enable control server** is on; URL host/port match Preferences. |
| Companion on another PC can’t connect | **Listen on** must be your Mac’s LAN IP or **All interfaces**, not localhost only. Firewall must allow inbound TCP on the port. |
| `127.0.0.1` from remote Companion | `127.0.0.1` always means “this computer” — use MultiViewer’s **Wi‑Fi/Ethernet IP** instead. |
| Source button fails | Encode `:` and spaces in the URL; match the exact NDI name from **Configure inputs**. |
| Port in use | Change **Port** in Preferences (e.g. `8081`) and update every Companion URL. |

---

## 8. Example Companion page

A simple show setup might use:

1. **4-up** — `POST …/layout/4`
2. **Cam 1 full** — `POST …/layout/1` then `POST …/layout/primary/1`
3. **Program on slot 1** — `POST …/source/1/ndi%3A…`
4. **Preview on slot 2** — `POST …/source/2/ndi%3A…`

Build URLs once, duplicate buttons, and change slot or encoded source names as needed.

---

**MultiViewer by Brekke** — multiview monitor with NDI/SDI inputs and HTTP control for automation.
