# sonos-tt Flutter Port

Flutter frontend for the sonos-tt Sonos controller, designed to run on a
Raspberry Pi 4 with a 1080×1080px circular touchscreen via **flutter-pi**
(DRM/KMS, no desktop, no browser).

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