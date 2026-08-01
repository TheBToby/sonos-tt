#!/usr/bin/env bash
set -euo pipefail

# Deploy sonos-tt Flutter bundle to a Raspberry Pi.
# Usage: ./deploy/deploy.sh [pi-host] [bundle-dir]
# Defaults: pi-host=raspberrypi, bundle-dir=build/linux-arm64/bundle

PI_HOST="${1:-raspberrypi}"
BUNDLE_DIR="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "$BUNDLE_DIR" ]; then
  BUNDLE_DIR="$PROJECT_DIR/build/linux-arm64/bundle"
fi

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "ERROR: Bundle not found at $BUNDLE_DIR"
  echo "Run ./deploy/build.sh first"
  exit 1
fi

echo "=== Deploying sonos-tt to $PI_HOST ==="
echo "Bundle: $BUNDLE_DIR"
echo ""

# Create target directory
ssh "$PI_HOST" "mkdir -p /opt/sonos-tt"

# Sync bundle (exclude assets that don't change often to speed up)
rsync -avz --delete \
  --exclude='lib/' \
  "$BUNDLE_DIR/" \
  "$PI_HOST:/opt/sonos-tt/"

# Sync lib directory separately (larger, changes on each build)
rsync -avz "$BUNDLE_DIR/lib/" "$PI_HOST:/opt/sonos-tt/lib/"

echo ""
echo "=== Deploy complete ==="
echo ""
echo "On the Pi, you can now:"
echo "  1. Install the systemd service:"
echo "     scp deploy/sonos-tt-flutter.service $PI_HOST:/tmp/"
echo "     ssh $PI_HOST 'sudo cp /tmp/sonos-tt-flutter.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now sonos-tt-flutter'"
echo ""
echo "  2. Or run manually:"
echo "     ssh $PI_HOST 'flutter-pi /opt/sonos-tt/libapp.so --release'"