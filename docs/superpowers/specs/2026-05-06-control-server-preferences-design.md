# Control Server Preferences (macOS)

## Goal

Make the local HTTP control server (used by Stream Deck / scripts) configurable **from inside the app**, rather than via a hard-coded default or CLI flags.

## Non-goals

- Redesigning the HTTP API routes (`/layout/*`, `/source/*`).
- Remote access configuration (this remains a local control surface; defaults stay loopback-only).
- Building a Stream Deck plugin (out of scope).

## Current behavior (baseline)

- The app starts a Swifter-based HTTP server during `MainViewController.viewDidLoad()`.
- Port selection order:
  1. `--port <n>` CLI argument
  2. `port` field in config JSON
  3. default `8080`
- Config file is loaded from either:
  - `--config <path>` CLI argument, or
  - `~/Library/Application Support/Multiviewer/config.json` if present

## Proposed UX

### Entry point

- App menu item: **Preferences…** (or **Settings…** if macOS chooses that naming), opening a small window.

### Preferences UI fields

- **Enable Control Server**: toggle
- **Port**: numeric input
- **Control URL**: read-only field: `http://127.0.0.1:<port>` (or actual bound port)
- **Copy URL** button
- **Status line** (inline text):
  - `Running on http://127.0.0.1:<port>`
  - `Stopped`
  - `Failed to start: <reason>` (e.g. address already in use)

### Apply semantics

- Changes apply **immediately** (no app restart required):
  - Toggle OFF → stop the server.
  - Toggle ON → start the server using the configured port.
  - Changing the port while enabled → stop → start on new port.

### Failure semantics

- If binding fails (e.g. port is in use), the app must **not crash**.
- The UI shows the failure and the server remains stopped (or continues running on the previous port if we choose to keep old behavior).
  - Recommended: keep running on previous port if already running; only switch if the new port starts successfully.

## Persistence & config format

### Storage location

- Continue using: `~/Library/Application Support/Multiviewer/config.json`

### Schema (additive)

Existing fields remain:

- `slots?: { [slot: string]: string }`
- `layout?: number`
- `port?: number`

Add:

- `controlEnabled?: boolean` (default: `true` for backward compatibility)

## Implementation design (high-level)

### New components

- `SettingsStore`
  - Loads/saves the JSON config file.
  - Exposes current settings (`controlEnabled`, `port`, plus any existing fields).
  - Creates parent directory if missing.

- `ControlServerManager`
  - Owns `ControlServer` lifecycle.
  - API:
    - `start(port:)`, `stop()`, `restartIfNeeded(settings:)`
  - Publishes status (`stopped`, `running(url)`, `failed(error)`), and the actual bound port.

- `PreferencesWindowController` + `PreferencesViewController`
  - AppKit UI for settings.
  - Binds UI controls to `SettingsStore` and triggers `ControlServerManager` updates.

### Wiring

- App entry (`MetalMultiviewerApp`):
  - Create one shared `SettingsStore` + `ControlServerManager`.
  - Start control server depending on stored settings.
  - Provide a menu item to open Preferences.

- Main view:
  - No longer needs to start the control server directly.
  - It can optionally display a small overlay label that shows the current control URL from the manager.

## Testing

- Unit tests (Swift Testing or XCTest depending on toolchain availability):
  - `SettingsStore` round-trip encode/decode.
  - `ControlServerManager` state transitions (can be limited to “doesn’t crash” + status updates, with network tests optional).

## Acceptance criteria

- User can open Preferences and:
  - Enable/disable control server.
  - Change port.
  - See current status and copy the URL.
- Changing settings does not require app restart and does not crash the app on bind failures.
- Settings persist across launches in the config JSON at the standard location.

