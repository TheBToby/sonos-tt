# sonos-tt Flutter Port

Flutter frontend for the sonos-tt Sonos controller, designed to run on a
Raspberry Pi 4 with a 1080×1080px circular touchscreen via **flutter-pi**
(DRM/KMS, no desktop, no browser).

## Coder Workspace (virtual IDE) — Setup, Build, Publish & Smoke Test

Development continues on a Coder-based virtual IDE. Everything that must
**survive a workspace update** lives in the persistent volume
`/opt/coder/sonos-tt/`:

| Persistent path | Contents |
|-----------------|----------|
| `/opt/coder/sonos-tt/flutter` | Flutter SDK 3.47.0 (stable) |
| `/opt/coder/sonos-tt/pub-cache` | Dart/Flutter package cache (`PUB_CACHE`) |
| `/opt/coder/sonos-tt/publish/web` | Published web build (served via local IP) |
| `/opt/coder/sonos-tt/tools/brave` | Extracted Brave browser payload |
| `/opt/coder/sonos-tt/downloads` | Cached installers (Flutter tarball, Brave .deb) |
| `/opt/coder/sonos-tt/logs` | Build/server logs, smoke-test artifacts |

After a workspace rebuild only the ephemeral parts (`/usr/local/bin` links,
apt-installed runtime libraries) are gone — re-run setup to restore:

```bash
# 1. One-time (or after workspace update): SDK + tools + Brave
bash deploy/coder-setup.sh              # Flutter SDK → persistent area
sudo bash deploy/coder-install-brave.sh # Brave browser → persistent area
source deploy/coder-env.sh              # set PATH/PUB_CACHE in your shell

# 2. Build & publish (analyze + test + release build → persistent publish dir)
bash deploy/coder-build-web.sh

# 3. Serve on the workspace's local IP (port 8099, bound to 0.0.0.0)
bash deploy/coder-serve-web.sh --daemon
# → http://<workspace-ip>:8099/   (e.g. http://172.20.0.2:8099/)

# 4. Smoke test in Brave (headless, CDP-driven; artifacts in logs/)
bash deploy/coder-smoke-test.sh
```

Notes:

- **Why web?** The Coder workspace has no display/GPU passthrough for
  flutter-pi; the web build runs in the app's built-in **mock mode**
  (`kIsWeb` guard) — perfect for UI smoke tests, no Sonos hardware needed.
  The Raspberry Pi flutter-pi build pipeline is unchanged (`deploy/build.sh`).
- **Why CDP for the smoke test?** Brave's `--screenshot`/`--dump-dom` wait for
  a "load complete" event that continuously-animating Flutter apps never
  emit. `deploy/cdp_capture.py` (stdlib-only Python) drives Brave via the
  DevTools protocol instead, then asserts the `flutter-view` /
  `flt-glass-pane` engine markers and captures a screenshot.
- **Brave on Ubuntu 26.04:** the official Brave `.deb` depends on pre-t64
  package names (e.g. `libatk1.0-0`) that no longer exist. The install script
  resolves each dependency to its `t64` successor via apt, extracts the
  browser payload into the persistent area, and links a wrapper into
  `/usr/local/bin/brave-browser`.

## Exposing the Smoke-Test App (Port 8099) to the Host

The workspace is a **Docker container** on a Coder host (bridge network
`172.20.0.0/16`). The app server already binds to `0.0.0.0:8099` *inside* the
container, but that address is **not routable from your LAN** — the container
IP `172.20.0.2` only works on the Docker host itself. Pick one of the options
below (ordered: quickest first).

### Option 1 — `coder port-forward` from your host machine (recommended)

No infra changes needed; works from any machine that can reach the Coder
server. Run **on the machine where Brave runs** (your laptop/PC):

```bash
# One-time: install the Coder CLI (https://coder.com/docs/install) and log in
coder login https://coder.baechtold.rocks

# Forward local 8099 → workspace 8099 (agent "main" of workspace "Sonos-TT")
coder port-forward Sonos-TT --tcp 8099

# Alternative: SSH local-forward through the same relay
coder ssh Sonos-TT -L 8099:localhost:8099
```

Then open **http://localhost:8099** in Brave.

### Option 2 — Coder web preview / code-server port proxy (HTTPS, no CLI)

code-server in this workspace exposes proxied URLs of the form
`https://<port>--<agent>--<workspace>--<owner>.coder.baechtold.rocks`
(env var `VSCODE_PROXY_URI`). In VS Code's **Ports/Forwarded Ports** panel
forward port `8099`, then open
`https://8099--main--sonos-tt--tobias-baechtold.coder.baechtold.rocks`.

> ⚠️ Currently this returns the NPMplus "Default Page": the reverse proxy in
> front (NPMplus) serves `*.coder.baechtold.rocks` but has **no proxy-host
> route to the Coder server for the wildcard subdomains** (and the TLS cert
> presented doesn't match). To fix (one-time, on the proxy):
> 1. Add a proxy host for `*.coder.baechtold.rocks` → Coder server
>    (`coder.baechtold.rocks` upstream), and
> 2. issue a **wildcard certificate** covering `*.coder.baechtold.rocks`
>    (DNS-01 challenge) and attach it to both `coder.baechtold.rocks` and the
>    wildcard proxy host.

### Option 3 — Publish the port in the Coder workspace template (permanent IP)

To make the app reachable at `http://<docker-host-IP>:8099` for everyone on
the LAN, add the port to the workspace template's Docker resource (requires
template-admin rights):

```hcl
resource "docker_container" "workspace" {
  # …existing config…
  ports {
    internal = 8099
    external = 8099   # published on the Docker host
    protocol = "tcp"
  }
}
```

Then version + apply the template (`coder templates push <name>`) and rebuild
the workspace (`coder stop` / `coder start`). Verify on the host:
`docker ps` must show `0.0.0.0:8099->8099/tcp` for the workspace container.

### Option 4 — Quick iptables DNAT on the Docker host (no template change)

For a temporary, host-level route (note: the container IP may change when the
workspace restarts — re-check with `docker inspect | grep IPAddress`):

```bash
sudo iptables -t nat -A PREROUTING -p tcp --dport 8099 \
  -j DNAT --to-destination 172.20.0.2:8099
sudo iptables -A FORWARD -p tcp -d 172.20.0.2 --dport 8099 -j ACCEPT
```

Then open `http://<docker-host-IP>:8099` in Brave. Remove with `-D` instead of
`-A` when done.

### Which one to choose?

| Scenario | Choice |
|----------|--------|
| You just want to smoke test from your own Brave | **Option 1** |
| Browser-only access, no CLI, HTTPS desired | **Option 2** (needs the NPMplus wildcard fix) |
| Team/LAN access to the published app | **Option 3** |
| Quick demo today, template change not possible | **Option 4** |

Note: the automated smoke test (`deploy/coder-smoke-test.sh`) is unaffected —
it runs headless Brave **inside** the workspace, where `172.20.0.2:8099` is
directly reachable.

## SoCo-CLI API in the Test Environment (web, REAL speakers)

**The problem:** in a browser, `http://localhost:5001` refers to the
*visitor's* machine — not the Pi and not the workspace. Additionally the web
build previously forced built-in mock mode, and `dart:io` usage (`HttpClient`,
`Platform`, `File`) crashes in the browser.

**The fix — real SoCo-CLI server in the workspace (Pi deployment unchanged):**

1. **SoCo-CLI itself** runs in the workspace from a persistent venv
   (`/opt/coder/sonos-tt/soco-venv`), with its speaker cache in
   `/opt/coder/sonos-tt/soco-home` (survives workspace updates). It discovers
   and controls the **real Sonos speakers** in `192.168.0.0/24`
   (`SOCO_SUBNETS`, configurable).
2. **`deploy/coder-web-server.py`** (port 8099) — serves the app **and**
   proxies `/soco/*` → the local SoCo-CLI server (:5001). Same-origin → no
   CORS, no HTTPS mixed-content issues. Binds dual-stack `::` so the Coder
   workspace proxy (which dials the agent's tailnet IPv6 address) can connect.
3. **App web fixes** — `apiGet` uses the platform-agnostic `http` package;
   `localhost`/`127.0.0.1` URLs auto-remap to `/soco` **on web only**; web
   guards for `dart:io`-based services (event WebSockets, backlight, HA
   secrets file).

**Usage:** open the app in the browser via the Coder workspace proxy
(e.g. `https://8099--main--sonos-tt--tobias-baechtold.coder.baechtold.rocks`)
and keep the app's Server URL at its **default** (`http://localhost:5001`) —
on web it transparently becomes `/soco` and talks to the real SoCo-CLI server
in the workspace, which controls the real speakers. Leave the URL empty only
if you want the built-in demo mock mode.

```bash
# Start everything: real SoCo-CLI (:5001) + app with /soco proxy (:8099)
bash deploy/coder-serve-web.sh --daemon

# (Re)discover speakers after network changes:
HOME=/opt/coder/sonos-tt/soco-home /opt/coder/sonos-tt/soco-venv/bin/soco-discover --subnets 192.168.0.0/24
```

## Architecture

```
lib/
  main.dart            — App entry, CircularShell, all UI widgets
  app_state.dart       — ChangeNotifier state (replaces Svelte stores)
  app_theme.dart       — Dark/light themes with custom color extension
  models/
    sonos_models.dart  — Speaker, Playback, SonosGroup, PlaylistItem, etc.
    app_config.dart    — Configuration models with JSON serialization
  services/
    sonos_api.dart     — SoCo-CLI HTTP client + mock provider + parsers
    config_service.dart — SharedPreferences persistence
    artwork_cache.dart  — In-memory artwork image cache
    home_assistant_service.dart — HA WebSocket API client (light entity)
    backlight_service.dart — Waveshare USB backlight control
  l10n/
    strings.dart       — German/English string tables
```

## Key differences from the Svelte version

| Aspect | Svelte | Flutter |
|--------|--------|---------|
| Rendering | DOM + CSS | Skia/Impeller (GPU) |
| State | Svelte stores | `ChangeNotifier` + `Provider` |
| Gestures | Custom `gestures.js` | Flutter's `GestureDetector` |
| Styling | CSS with variables | `ThemeExtension` + inline |
| Circular clip | CSS `clip-path` | `ClipOval` widget |
| Radial nav | SVG paths | `CustomPainter` + `Path` |
| Artwork | `<img>` tag | Custom `ImageProvider` |

## Prerequisites

- **Flutter SDK** 3.22+ (stable channel)
- **flutter-pi** — [github.com/ardera/flutter-pi](https://github.com/ardera/flutter-pi)
- **Raspberry Pi 5** with Raspberry Pi OS (no desktop needed)
- **SoCo-CLI** HTTP API server running on the Pi (see [SoCo-CLI Backend Setup](#soco-cli-backend-setup) below)

## Testing Locally in VS Code (before Pi deployment)

### Step 1: Install Flutter SDK on macOS

```bash
# Install Flutter SDK (stable channel)
brew install --cask flutter

# Verify installation
flutter doctor
```

If `flutter doctor` shows issues, install the missing tools it suggests
(e.g., Xcode command-line tools: `xcode-select --install`).

### Step 2: Install VS Code extensions

Install these two extensions:
- **Dart** (Dart Code)
- **Flutter** (Dart Code)

### Step 3: Open the flutter/ folder as a workspace

In VS Code: **File → Open Folder…** → select the `flutter/` directory.
VS Code will detect the `pubspec.yaml` and prompt you to get dependencies.
Click **Get dependencies** in the prompt, or run:

```bash
cd flutter && flutter pub get
```

### Step 4: Run the app

**Option A — VS Code debugger (recommended):**
1. Press **F5** (or **Run → Start Debugging**)
2. Select **"Flutter (macOS Desktop)"** from the dropdown
3. The app opens in a macOS window with mock data (no Sonos needed)

**Option B — Terminal:**
```bash
cd flutter
flutter run -d macos          # macOS desktop window
flutter run -d chrome          # Browser (for quick layout checks)
```

### Step 5: What you'll see

The app launches in **mock mode** by default (simulated speakers, playlists,
playback) — no SoCo-CLI server or Sonos hardware needed. You'll see:
- Spinning turntable with vinyl grooves
- Radial navigation ring (6 segments + center play/pause)
- Tap segments to open Speakers, Playlists, Users, Settings panels
- Swipe gestures for prev/next track
- Screensaver after 30s of inactivity (tap to wake)

### Step 6: Connect to real Sonos (optional)

To test against real speakers from your Mac:
1. Make sure SoCo-CLI server is running (see root README)
2. In the app, open **Settings** (gear icon in nav ring)
3. Change **Server URL** from empty to `http://<pi-ip>:5001`
4. Tap **Save** — the app will connect to real speakers

### Step 7: Debugging tips

- **Hot reload:** Press `r` in the terminal (or save a file with hot-reload enabled)
- **Hot restart:** Press `R` in the terminal
- **DevTools:** Press `D` to open Flutter DevTools (widget inspector, performance)
- **Logging:** Console output appears in VS Code's Debug Console panel

### Other useful commands

```bash
cd flutter

# Static analysis (find errors without running)
flutter analyze

# Run tests
flutter test

# Install flutterpi_tool (required for Pi builds)
# flutterpi_tool downloads the Flutter Engine (libflutter_engine.so) and
# produces a flat bundle ready for flutter-pi. Without it, `flutter build linux`
# produces a GTK desktop bundle that's missing the engine library.
flutter pub global activate flutterpi_tool

# Build for flutter-pi (aarch64, Pi 4-tuned engine)
flutterpi_tool build --release --arch=arm64 --cpu=pi4
```

## SoCo-CLI Backend Setup

The Flutter app needs the [SoCo-CLI](https://github.com/avantrec/soco-cli) HTTP
API server to talk to Sonos speakers. It runs on port 5001 (the app's default
`baseUrl: http://localhost:5001`).

### Automated setup (recommended)

From your dev machine:

```bash
PI_HOST=pi@192.168.4.25 ./deploy/setup-soco-cli.sh
```

This will:
1. Install `pip3` if missing
2. Install `soco-cli` via `pip3 install --break-system-packages soco-cli`
3. Discover Sonos speakers on your network
4. Install systemd services (`soco-cli.service` + `soco-discover.timer`)
5. Start the server and verify it responds

**Important — Subnet configuration:**

If your Sonos speakers are on a different subnet than the Pi (common when the Pi
is on WiFi), SSDP multicast discovery won't find them. The scripts default to
scanning `192.168.0.0/24`. Change this if your speakers are elsewhere:

```bash
SOCO_SUBNETS=192.168.1.0/24 PI_HOST=pi@192.168.4.25 ./deploy/setup-soco-cli.sh
```

You also need to update the subnet in `deploy/soco-cli.service` and
`deploy/soco-discover.service` (the `SOCO_SUBNETS` environment variable).

### Manual setup

```bash
# On the Pi:
sudo apt install -y python3-pip
pip3 install --break-system-packages soco-cli

# Discover speakers (specify subnet if cross-VLAN):
~/.local/bin/soco-discover --subnets 192.168.0.0/24

# Start the HTTP API server:
~/.local/bin/soco-http-api-server --port 5001 --use-local-speaker-list --subnets 192.168.0.0/24
```

### systemd services

| Service | Purpose |
|---------|---------|
| `soco-cli.service` | HTTP API server on port 5001. Runs `soco-discover` at boot (ExecStartPre) to build speaker cache, then starts the server with `--use-local-speaker-list --subnets`. |
| `soco-discover.service` | Refreshes speaker discovery cache. Triggered by `soco-discover.timer` every 30 min to catch new/removed speakers. |
| `soco-discover.timer` | Timer for the above. |
| `sonos-tt-flutter.service` | The Flutter app via flutter-pi. Has `After=soco-cli.service` so it waits for the backend. |

```bash
# Install all services:
sudo cp /opt/sonos-tt/{soco-cli,soco-discover}.service /opt/sonos-tt/soco-discover.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now soco-cli.service soco-discover.timer
```

---

## Deploying to Raspberry Pi

### 1. Install flutter-pi on the Pi

flutter-pi is a standalone engine that runs Flutter apps directly on top of
the Linux DRM/KMS framebuffer (no X11/Wayland/desktop). It must be built from
source on the Pi.

```bash
# ─── On the Pi ────────────────────────────────────────────────────────────
# 1a. Install build tools, graphics/system libraries, and fonts.
#     These are the EXACT dependencies from the flutter-pi docs.
#     Do NOT skip ttf-mscorefonts-installer — the Flutter engine requires Arial.
sudo apt update
sudo apt install -y \
  build-essential cmake pkg-config git \
  libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev \
  libdrm-dev libgbm-dev \
  libsystemd-dev libinput-dev libudev-dev libxkbcommon-dev \
  ttf-mscorefonts-installer fontconfig

# Update the font cache so the newly installed fonts are found.
sudo fc-cache

# 1b. Clone flutter-pi (with submodules).
#     --recursive is required — it pulls in the Flutter engine binaries.
git clone --recursive https://github.com/ardera/flutter-pi.git
cd flutter-pi

# 1c. Configure and build.
#     ⚠️  Do NOT use sudo here! Run cmake and make as your normal user.
#     Using sudo for cmake can break the build (wrong sysroot, permission issues).
mkdir build && cd build
cmake ..
make -j"$(nproc)"

# 1d. Install system-wide. This places the binary at /usr/local/bin/flutter-pi.
#     ONLY this step uses sudo.
sudo make install
sudo ldconfig    # refresh the shared-library cache

# 1e. VERIFY the install — this must print a path, not "command not found".
which flutter-pi
flutter-pi --help    # should print usage info

# 1f. Give your user permission to access DRM/GPU/input devices.
#     flutter-pi opens these directly (no X11/Wayland/desktop). On Raspberry
#     Pi OS they are group-owned by:
#       video  → /dev/dri/card*   (DRM/KMS display)
#       render → /dev/dri/renderD* (GPU compute)
#       input  → /dev/input/event* (touchscreen/input devices)
#     Without all three, flutter-pi fails with:
#       "Couldn't open DRM device. open: Permission denied"
sudo usermod -aG video,render,input "$USER"
#     (Log out and back in, or reboot, for this to take effect.)
#     The deploy scripts also check and fix this automatically, and the
#     systemd service uses SupplementaryGroups=video render input as a
#     belt-and-braces fallback.
```

> **Common `cmake ..` errors and fixes:**
>
> - **`Package 'gbm', required by 'virtual:world', not found`**
>   → `pkg-config` is missing. Install it: `sudo apt install -y pkg-config`
>   Then delete the build dir and retry: `rm -rf build && mkdir build && cd build && cmake ..`
>
> - **`Package 'libsystemd' not found`** (or similar for other packages)
>   → A `-dev` package is missing. Re-run the full `apt install` command from step 1a.
>
> - **`Could NOT find OpenGL/EGL`**
>   → Mesa development libraries missing: `sudo apt install -y libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev`
>
> **If `flutter-pi` is still "command not found" after `sudo make install`:**
>
> - Check where it actually landed: `ls -la /usr/local/bin/flutter-pi`
> - If it's there but not in `PATH`, either call it by full path
>   (`/usr/local/bin/flutter-pi ...`) or add `/usr/local/bin` to your `PATH`.
> - If the `make install` step was skipped (e.g. the build failed earlier),
>   re-run it: `cd flutter-pi/build && sudo make install`.
> - The systemd service file uses the absolute path
>   `/usr/local/bin/flutter-pi` (see `deploy/sonos-tt-flutter.service`), so the
>   service does not depend on `PATH` — only interactive shell use does.

### 2. Install flutterpi_tool (one-time, on your dev machine)

`flutterpi_tool` is the official build tool for flutter-pi. It:
- Downloads the correct Flutter Engine (`libflutter_engine.so`) automatically
- Produces a flat bundle ready for flutter-pi (no manual flattening)
- Works natively on macOS and Linux — **no remote build needed**

```bash
# Install flutterpi_tool globally (one-time)
flutter pub global activate flutterpi_tool

# If flutterpi_tool isn't in your PATH after install, add the pub cache bin:
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

### 3. Build & deploy

The build script uses `flutterpi_tool` to produce a complete flutter-pi bundle
locally on your dev machine (macOS or Linux), then deploys it to the Pi via
rsync. No Flutter SDK or build tools needed on the Pi.

```bash
# From your dev machine (macOS or Linux)
./deploy/build.sh                    # build only
./deploy/build.sh --deploy           # build + deploy in one step
./deploy/deploy.sh                   # deploy an existing build to the Pi

# Specify a custom Pi hostname/IP
PI_HOST=pi@192.168.4.25 ./deploy/build.sh --deploy

# Use a generic aarch64 engine instead of Pi 4-tuned
PI_CPU=generic ./deploy/build.sh --deploy
```

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `PI_HOST` | `raspberrypi` | SSH destination (`user@host` or `host`) |
| `PI_ARCH` | `arm64` | Target architecture (`arm64`, `arm`, `x64`) |
| `PI_CPU` | `pi4` | CPU-tuned engine (`pi4`, `generic`) |
| `DEPLOY_DIR` | `/opt/sonos-tt` | Deploy path on the Pi |

**Where things live on the Pi:**

| Path | What | Notes |
|------|------|-------|
| `/opt/sonos-tt` | Final deployed bundle (read by flutter-pi) | `/opt` is root-owned. The scripts create it **once** via `sudo mkdir` + `chown` to your user, then subsequent deploys run without sudo. |

The first `--deploy` will prompt for the sudo password (to create `/opt/sonos-tt`).
If you prefer to set it up manually once:

```bash
ssh pi@raspberrypi 'sudo mkdir -p /opt/sonos-tt && sudo chown $USER:$USER /opt/sonos-tt'
```

### 4. Run as systemd service

```bash
# On the Pi
sudo cp /opt/sonos-tt/sonos-tt-flutter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sonos-tt-flutter
```

### Manual test run

```bash
# On the Pi, with SoCo-CLI running.
# Use the absolute path to match the systemd service and avoid PATH issues.
# NOTE: Pass the bundle DIRECTORY, not libapp.so — flutter-pi expects a dir.
# NOTE: --release must come BEFORE the bundle path (flutter-pi argument order).
/usr/local/bin/flutter-pi --release /opt/sonos-tt

# (equivalent, once flutter-pi is in your PATH:)
# flutter-pi --release /opt/sonos-tt
```

## Mock Mode

When `socoApi.baseUrl` is empty or starts with `mock://`, the app runs with
simulated speakers and playback — no hardware needed. This is the default
until you configure a real SoCo-CLI server URL in Settings.

## Configuration

Config is persisted via `SharedPreferences` (key `sonos-tt:config`).
Same structure as the Svelte version — you can copy JSON config between both.

## Display Setup (Pi 5)

For the 1080×1080 circular touchscreen, ensure `/boot/firmware/config.txt`
has appropriate display settings:

```
# Example for DSI圆形 display
dtoverlay=vc4-kms-dpi-generic
dtparam=i2c_arm=on
```

flutter-pi will use the DRM framebuffer directly — no X11 or Wayland needed.

## Hardware Backlight Dimming (Waveshare Displays)

The app can optionally dim the **physical backlight** of Waveshare HDMI displays
(e.g., 7" Round LCD) during the screensaver, reducing power consumption and
light emission. This uses the display's USB control interface (not DDC/CI).

### Prerequisites

On the Pi:

```bash
# Install pyusb (required by the brightness helper script)
sudo apt install -y python3-usb

# Install the udev rule for non-root USB access
sudo cp /opt/sonos-tt/51-waveshare-backlight.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Then **unplug and replug the display's USB cable** (or reboot) for the udev
rule to take effect.

> **Note:** The deploy script (`deploy/deploy.sh`) handles this automatically
> on each deploy — installing pyusb and the udev rule if they're missing.

### Enabling in the App

1. Open **Settings** (gear icon in the nav ring)
2. Under **Screensaver**, toggle **Hardware Dimming** ON
3. Tap **Save**

When the screensaver activates, the backlight dims to ~10%. Tapping to wake
restores it to 100%.

### Manual Testing

```bash
# Test the brightness script directly on the Pi:
python3 /opt/sonos-tt/brightness.py 50    # 50% brightness
python3 /opt/sonos-tt/brightness.py 100   # Full brightness
python3 /opt/sonos-tt/brightness.py 0     # Lowest brightness
```

If the script runs without errors but the brightness doesn't change, verify
that:
- The display's USB cable is connected (not just HDMI)
- The udev rule is installed (`ls /etc/udev/rules.d/51-waveshare-backlight.rules`)
- `python3-usb` is installed (`dpkg -s python3-usb`)
- The USB device is detected (`lsusb | grep 0712:000a`)

## Home Assistant Backlight Link

Instead of a fixed dim level during the screensaver, the display backlight can
follow a **Home Assistant light entity**. When the linked light is off, the
display is turned off entirely; when it's on, the display brightness is aligned
to the light's brightness (0–255 → 0–100%). This requires the hardware
backlight support above.

### Setup

**Option A — Secrets file (recommended for the Pi):**

Create `deploy/ha-secrets.json` (gitignored — never committed to GitHub) from
the template:

```bash
cp deploy/ha-secrets.example.json deploy/ha-secrets.json
```

Edit `deploy/ha-secrets.json` with your HA URL, entity ID, and long-lived
access token, then deploy:

```bash
./deploy/deploy.sh
```

The app reads `/opt/sonos-tt/ha-secrets.json` at startup and auto-enables the
HA backlight link. Values entered in the app UI (Option B) override the
secrets file.

**Option B — In-app configuration:**

1. In Home Assistant, create a **Long-Lived Access Token** (Profile →
   Long-Lived Access Tokens → Create Token).
2. In the app: **Settings → Screensaver → Home Assistant Backlight** → ON.
3. Enter your HA URL (e.g. `http://homeassistant.local:8123`), the entity ID
   (e.g. `light.living_room`), and the access token.
4. Tap **Test Connection** to verify credentials and that the entity exists.
   The result (success/failure + entity state including brightness) is shown
   inline.
5. **Save**. The app opens a persistent WebSocket subscription to HA
   (`/api/websocket`) and starts driving the backlight whenever the screensaver
   is active. The live connection state is shown beneath the test button.

### Behavior

| Light state | Display backlight |
|-------------|-------------------|
| Off | Fully off (0%) |
| On, brightness set | Aligned to light brightness (0–255 → 0–100%) |
| On, no brightness attr. | Standard hardware dim level |
| Connection lost | Falls back to standard hardware dimming |

When HA is active and connected, the screensaver's software color-matrix is
neutralized (set to 1.0) so the physical backlight is the sole brightness
control — preventing double dimming.
