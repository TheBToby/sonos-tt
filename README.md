# sonos-tt Flutter Port

Flutter frontend for the sonos-tt Sonos controller, designed to run on a
Raspberry Pi 5 with a 1080×1080px circular touchscreen via **flutter-pi**
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
- **SoCo-CLI** running on the Pi or network (see root `README.md`)

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

# Build for flutter-pi (on the Pi or cross-compile)
flutter build linux --release
```

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

# 1f. Give your user permission to use 3D acceleration.
#     flutter-pi needs direct GPU access via DRM/KMS.
sudo usermod -a -G render "$USER"
#     (Log out and back in, or reboot, for this to take effect.)
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

### 2. Build & deploy

The build script detects your OS and handles cross-compilation automatically:

- **macOS**: Syncs source to the Pi and builds **remotely** via SSH
- **Linux**: Builds locally (requires aarch64 cross-compile toolchain)

```bash
# From your dev machine (macOS or Linux)
./deploy/build.sh                    # build (remote on macOS, local on Linux)
./deploy/build.sh --deploy           # build + deploy in one step
./deploy/deploy.sh                   # deploy an existing build to the Pi

# Specify a custom Pi hostname
PI_HOST=my-pi ./deploy/build.sh --deploy
```

**Where things live on the Pi:**

| Path | What | Notes |
|------|------|-------|
| `~/sonos-tt-src` | Remote source checkout + build output | Inside the user's home — no sudo needed. Override with `REMOTE_DIR=...`. |
| `/opt/sonos-tt` | Final deployed bundle (read by flutter-pi) | `/opt` is root-owned. The scripts create it **once** via `sudo mkdir` + `chown` to your user, then subsequent deploys run without sudo. Override with `DEPLOY_DIR=...`. |

The first `--deploy` will prompt for the sudo password (to create `/opt/sonos-tt`).
If you prefer to set it up manually once:

```bash
ssh pi@raspberrypi 'sudo mkdir -p /opt/sonos-tt && sudo chown $USER:$USER /opt/sonos-tt'
```

**Requirements for macOS remote build:**
- SSH key access to the Pi: `ssh-copy-id pi@raspberrypi`
  (If your Pi username isn't the same as your Mac username, include it in
  `PI_HOST`, e.g. `PI_HOST=pi@192.168.0.25`)
- Flutter SDK installed on the Pi **and visible to non-interactive SSH** (the
  build runs via `ssh pi@host "flutter ..."`):

```bash
# Install Flutter on the Pi (one-time setup)
ssh pi@raspberrypi
# Flutter's `flutter build linux` requires the Linux desktop toolchain
# (clang/g++ compiler, ninja build system, GTK headers):
sudo apt install -y git curl clang g++ cmake pkg-config ninja-build libgtk-3-dev
git clone https://github.com/flutter/flutter.git ~/flutter

# IMPORTANT: Add Flutter to the SYSTEM PATH, not just ~/.bashrc.
# Non-interactive SSH (used by deploy/build.sh) does not source ~/.bashrc on
# Raspberry Pi OS, so a PATH export appended there is not applied. A symlink
# in /usr/local/bin is the most reliable fix:
sudo ln -s "$HOME/flutter/bin/flutter" /usr/local/bin/flutter

# Verify it is found both interactively AND non-interactively:
flutter doctor
ssh pi@raspberrypi 'command -v flutter'   # must print a path
```

> **Note:** If you previously followed instructions that appended
> `export PATH=...:$HOME/flutter/bin` to `~/.bashrc` and still see
> `ERROR: Flutter not found on <pi>` from `build.sh`, the cause is the
> non-interactive SSH PATH. Run the `sudo ln -s ...` command above.

### 3. Run as systemd service

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