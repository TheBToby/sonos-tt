#!/usr/bin/env bash
set -euo pipefail

# Build sonos-tt Flutter app for flutter-pi on Raspberry Pi 5 (aarch64).
# Run this on the Pi or cross-compile from a Linux host with the right sysroot.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/linux-arm64"

echo "=== Building sonos-tt for flutter-pi (aarch64) ==="

# Ensure Flutter is available
if ! command -v flutter &>/dev/null; then
  echo "ERROR: flutter not found in PATH"
  echo "Install Flutter SDK: https://docs.flutter.dev/get-started/install/linux"
  exit 1
fi

cd "$PROJECT_DIR"

# Get dependencies
echo "→ Getting dependencies..."
flutter pub get

# Build release (uses --release for AOT + tree-shaking)
echo "→ Building release bundle..."
flutter build linux --release 2>&1 | tail -5

echo ""
echo "=== Build complete ==="
echo "Output: $BUILD_DIR/bundle/"
echo ""
echo "To deploy to the Pi, copy the bundle directory:"
echo "  rsync -avz $BUILD_DIR/bundle/ pi@raspberrypi:/opt/sonos-tt/"
echo ""
echo "Then run with flutter-pi on the Pi:"
echo "  flutter-pi /opt/sonos-tt/libapp.so --release"
echo ""
echo "Or use the systemd service (see deploy/sonos-tt-flutter.service)"