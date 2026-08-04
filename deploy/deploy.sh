#!/usr/bin/env bash
set -euo pipefail

# Deploy sonos-tt Flutter bundle to a Raspberry Pi.
#
# This script detects the host OS:
#   - Linux:  deploys local build/linux-arm64/bundle/ to the Pi via rsync
#   - macOS/other: deploys the remote bundle from the Pi's build dir to /opt/sonos-tt
#
# Usage:
#   ./deploy/deploy.sh [pi-host]
#   PI_HOST=custom-pi ./deploy/deploy.sh

PI_HOST="${PI_HOST:-${1:-raspberrypi}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_OS="$(uname -s)"
REMOTE_DIR="${REMOTE_DIR:-/opt/sonos-tt-src}"

echo "=== Deploying sonos-tt to $PI_HOST ==="

# ─── Local deploy (Linux host — bundle is local) ─────────────────────────────
if [ "$HOST_OS" = "Linux" ]; then
  BUNDLE_DIR="$PROJECT_DIR/build/linux-arm64/bundle"
  if [ ! -d "$BUNDLE_DIR" ]; then
    echo "ERROR: Bundle not found at $BUNDLE_DIR"
    echo "Run ./deploy/build.sh first"
    exit 1
  fi
  echo "Bundle: $BUNDLE_DIR"
  echo ""
  ssh "$PI_HOST" "mkdir -p /opt/sonos-tt"
  rsync -avz --delete \
    --exclude='lib/' \
    "$BUNDLE_DIR/" \
    "$PI_HOST:/opt/sonos-tt/"
  rsync -avz "$BUNDLE_DIR/lib/" "$PI_HOST:/opt/sonos-tt/lib/"

# ─── Remote deploy (macOS host — bundle is on the Pi from remote build) ──────
else
  REMOTE_BUNDLE="$REMOTE_DIR/build/linux/arm64/release/bundle"
  echo "Bundle: $PI_HOST:$REMOTE_BUNDLE"
  echo ""
  # Check that a remote build exists
  if ! ssh "$PI_HOST" "test -d $REMOTE_BUNDLE"; then
    echo "ERROR: Remote bundle not found at $PI_HOST:$REMOTE_BUNDLE"
    echo "Run ./deploy/build.sh first (builds remotely on the Pi)"
    exit 1
  fi
  ssh "$PI_HOST" "mkdir -p /opt/sonos-tt"
  # Copy from build dir to deploy dir on the Pi (local-to-local on the Pi)
  rsync -avz --delete \
    "$PI_HOST:$REMOTE_BUNDLE/" \
    "$PI_HOST:/opt/sonos-tt/"
fi

echo ""
echo "=== Deploy complete ==="
echo ""
echo "On the Pi, you can now:"
echo "  1. Restart the systemd service:"
echo "     ssh $PI_HOST 'sudo systemctl restart sonos-tt-flutter'"
echo ""
echo "  2. Or run manually:"
echo "     ssh $PI_HOST 'flutter-pi /opt/sonos-tt/bundle/main.bin --release'"