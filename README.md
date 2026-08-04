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

```bash
# On the Pi
git clone https://github.com/ardera/flutter-pi.git
cd flutter-pi
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
```

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

**Requirements for macOS remote build:**
- SSH key access to the Pi: `ssh-copy-id pi@raspberrypi`
- Flutter SDK installed on the Pi (the build runs there):

```bash
# Install Flutter on the Pi (one-time setup)
ssh pi@raspberrypi
sudo apt install -y git curl
git clone https://github.com/flutter/flutter.git ~/flutter
echo 'export PATH=$PATH:$HOME/flutter/bin' >> ~/.bashrc
source ~/.bashrc
flutter doctor
```

### 3. Run as systemd service

```bash
# On the Pi
sudo cp /opt/sonos-tt/sonos-tt-flutter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sonos-tt-flutter
```

### Manual test run

```bash
# On the Pi, with SoCo-CLI running
flutter-pi /opt/sonos-tt/libapp.so --release
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