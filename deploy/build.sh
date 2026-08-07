#!/usr/bin/env bash
set -euo pipefail

# Build sonos-tt Flutter app for flutter-pi on Raspberry Pi (aarch64).
#
# Uses flutterpi_tool (the official flutter-pi build tool) which:
#   - Downloads the correct Flutter Engine (libflutter_engine.so) automatically
#   - Produces a flat bundle ready for flutter-pi (no manual flattening needed)
#   - Works on macOS and Linux (no remote build required)
#
# Usage:
#   ./deploy/build.sh              # build only
#   ./deploy/build.sh --deploy     # build + deploy to /opt/sonos-tt on the Pi
#   PI_HOST=custom-pi ./deploy/build.sh --deploy
#   PI_CPU=pi4 ./deploy/build.sh --deploy   # use Pi 4-tuned engine (default)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PI_HOST="${PI_HOST:-raspberrypi}"
DEPLOY_AFTER="${1:-}"

# Target architecture and CPU for flutterpi_tool.
# --arch=arm64 builds for aarch64 (Pi 3/4/5/Zero 2 in 64-bit mode).
# --cpu=pi4 downloads a Pi 4-tuned engine for better performance.
# Set PI_CPU=generic to use the generic aarch64 engine instead.
PI_ARCH="${PI_ARCH:-arm64}"
PI_CPU="${PI_CPU:-pi4}"

# Deploy target on the Pi. /opt requires root, so the script bootstraps it once
# (sudo mkdir + chown to the remote user) and then writes to it without sudo.
DEPLOY_DIR="${DEPLOY_DIR:-/opt/sonos-tt}"

# The flutterpi_tool output directory name depends on --cpu.
# pi4 → pi4-64, arm → arm, generic arm64 → arm64, etc.
# We resolve the actual path after building.
BUNDLE_BASE="$PROJECT_DIR/build/flutter-pi"

echo "=== Building sonos-tt for flutter-pi ($PI_ARCH, cpu: $PI_CPU) ==="
cd "$PROJECT_DIR"

# ─── Ensure Flutter is available ─────────────────────────────────────────────
if ! command -v flutter &>/dev/null; then
  echo "ERROR: flutter not found in PATH"
  echo "Install Flutter SDK: https://docs.flutter.dev/get-started/install"
  exit 1
fi

# ─── Ensure flutterpi_tool is available ──────────────────────────────────────
# flutterpi_tool is the official build tool for flutter-pi. It downloads the
# correct Flutter Engine binaries (libflutter_engine.so) and produces a bundle
# in the flat layout flutter-pi expects.
#
# Without it, `flutter build linux` produces a GTK desktop bundle that does NOT
# include libflutter_engine.so, and flutter-pi fails with:
#   "Could not load flutter engine from any location"
FLUTTERPI_TOOL=""
if command -v flutterpi_tool &>/dev/null; then
  FLUTTERPI_TOOL="flutterpi_tool"
elif [ -x "$HOME/.pub-cache/bin/flutterpi_tool" ]; then
  FLUTTERPI_TOOL="$HOME/.pub-cache/bin/flutterpi_tool"
fi

if [ -z "$FLUTTERPI_TOOL" ]; then
  echo "→ flutterpi_tool not found — installing via flutter pub global activate..."
  flutter pub global activate flutterpi_tool
  # Re-check after installation
  if command -v flutterpi_tool &>/dev/null; then
    FLUTTERPI_TOOL="flutterpi_tool"
  elif [ -x "$HOME/.pub-cache/bin/flutterpi_tool" ]; then
    FLUTTERPI_TOOL="$HOME/.pub-cache/bin/flutterpi_tool"
  else
    echo "ERROR: flutterpi_tool installation failed."
    echo "Add \$HOME/.pub-cache/bin to your PATH, or run:"
    echo "  flutter pub global activate flutterpi_tool"
    exit 1
  fi
fi
echo "  Using: $FLUTTERPI_TOOL"

# ─── Build with flutterpi_tool ───────────────────────────────────────────────
echo "→ Building flutter-pi bundle..."

# Build the CPU flag — only pass --cpu if not "generic"
CPU_ARGS=()
if [ "$PI_CPU" != "generic" ]; then
  CPU_ARGS=(--cpu="$PI_CPU")
fi

# Build the flutter-pi bundle
"$FLUTTERPI_TOOL" build --release --arch="$PI_ARCH" "${CPU_ARGS[@]}" 2>&1 | tail -20

# ─── Locate the output bundle ────────────────────────────────────────────────
# flutterpi_tool outputs to build/flutter-pi/<cpu-arch>/
# e.g. build/flutter-pi/pi4-64/ or build/flutter-pi/arm64/
BUNDLE_DIR=""
for dir in "$BUNDLE_BASE"/*; do
  if [ -f "$dir/app.so" ] && [ -f "$dir/libflutter_engine.so" ]; then
    BUNDLE_DIR="$dir"
    break
  fi
done

if [ -z "$BUNDLE_DIR" ] || [ ! -d "$BUNDLE_DIR" ]; then
  echo "ERROR: Could not find flutter-pi bundle output."
  echo "Expected: app.so and libflutter_engine.so in $BUNDLE_BASE/*/"
  echo ""
  echo "Contents of $BUNDLE_BASE:"
  ls -la "$BUNDLE_BASE"/* 2>/dev/null || echo "  (empty or doesn't exist)"
  exit 1
fi

echo ""
echo "=== Build complete ==="
echo "Bundle: $BUNDLE_DIR"
echo "Contents:"
ls -la "$BUNDLE_DIR" | head -15

# Deploy if requested
if [ "$DEPLOY_AFTER" = "--deploy" ]; then
  echo ""
  echo "→ Deploying to $DEPLOY_DIR on $PI_HOST ..."
  exec "$SCRIPT_DIR/deploy.sh"
fi