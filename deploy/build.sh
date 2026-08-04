#!/usr/bin/env bash
set -euo pipefail

# Build sonos-tt Flutter app for flutter-pi on Raspberry Pi 5 (aarch64).
#
# This script detects the host OS:
#   - Linux:  builds locally (requires aarch64 cross-compile toolchain)
#   - macOS/other: builds REMOTELY on the Pi via SSH (requires Flutter SDK on the Pi)
#
# Usage:
#   ./deploy/build.sh              # build only (local or remote depending on host)
#   ./deploy/build.sh --deploy     # build + deploy to /opt/sonos-tt on the Pi
#   PI_HOST=custom-pi ./deploy/build.sh --deploy   # specify Pi hostname

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PI_HOST="${PI_HOST:-raspberrypi}"
REMOTE_DIR="${REMOTE_DIR:-/opt/sonos-tt-src}"
DEPLOY_AFTER="${1:-}"

# ─── Detect host OS ──────────────────────────────────────────────────────────
HOST_OS="$(uname -s)"
BUILD_DIR="$PROJECT_DIR/build/linux-arm64"

echo "=== Building sonos-tt for flutter-pi (aarch64) ==="
echo "Host OS: $HOST_OS"

# ─── Ensure Flutter is available ─────────────────────────────────────────────
if ! command -v flutter &>/dev/null; then
  echo "ERROR: flutter not found in PATH"
  echo "Install Flutter SDK: https://docs.flutter.dev/get-started/install"
  exit 1
fi

cd "$PROJECT_DIR"

# ─── Local build (Linux host) ────────────────────────────────────────────────
if [ "$HOST_OS" = "Linux" ]; then
  echo "→ Building locally (Linux host)..."
  flutter pub get
  echo "→ Building release bundle..."
  flutter build linux --release 2>&1 | tail -5
  echo ""
  echo "=== Build complete ==="
  echo "Output: $BUILD_DIR/bundle/"
  if [ "$DEPLOY_AFTER" = "--deploy" ]; then
    echo ""
    "$SCRIPT_DIR/deploy.sh"
  fi
  exit 0
fi

# ─── Remote build (macOS or other non-Linux host) ────────────────────────────
# Syncs source code to the Pi, builds there via SSH, then optionally deploys.
echo "→ Cross-build not supported on $HOST_OS — building remotely on $PI_HOST"
echo ""

# Check SSH connectivity
if ! ssh -o ConnectTimeout=5 "$PI_HOST" "echo ok" &>/dev/null; then
  echo "ERROR: Cannot connect to $PI_HOST via SSH"
  echo "Make sure:"
  echo "  1. The Pi is reachable (ping $PI_HOST)"
  echo "  2. SSH key is set up (ssh-copy-id pi@$PI_HOST)"
  echo "  3. Or set PI_HOST=custom-name: ./deploy/build.sh"
  exit 1
fi

# Check Flutter is installed on the Pi
echo "→ Checking Flutter on $PI_HOST..."
if ! ssh "$PI_HOST" "command -v flutter" &>/dev/null; then
  echo "ERROR: Flutter not found on $PI_HOST"
  echo "Install Flutter SDK on the Pi:"
  echo "  ssh $PI_HOST"
  echo "  sudo apt install -y git curl"
  echo "  git clone https://github.com/flutter/flutter.git ~/flutter"
  echo "  echo 'export PATH=\$PATH:\$HOME/flutter/bin' >> ~/.bashrc"
  echo "  source ~/.bashrc"
  echo "  flutter doctor"
  exit 1
fi

# Sync source code to the Pi (exclude build artifacts and platform dirs)
echo "→ Syncing source to $PI_HOST:$REMOTE_DIR ..."
rsync -avz --delete \
  --exclude='.git' \
  --exclude='build/' \
  --exclude='.dart_tool/' \
  --exclude='macos/' \
  --exclude='web/' \
  --exclude='.vscode/' \
  --exclude='*.iml' \
  --exclude='.idea/' \
  "$PROJECT_DIR/" "$PI_HOST:$REMOTE_DIR/"

# Build on the Pi
echo "→ Building on $PI_HOST ..."
ssh "$PI_HOST" "cd $REMOTE_DIR && flutter pub get && flutter build linux --release" 2>&1 | tail -15

echo ""
echo "=== Remote build complete ==="
echo "Bundle on Pi: $PI_HOST:$REMOTE_DIR/build/linux/arm64/release/bundle/"
echo ""

# Deploy if requested
if [ "$DEPLOY_AFTER" = "--deploy" ]; then
  echo "→ Deploying to /opt/sonos-tt on $PI_HOST ..."
  ssh "$PI_HOST" "mkdir -p /opt/sonos-tt"
  rsync -avz --delete \
    "$PI_HOST:$REMOTE_DIR/build/linux/arm64/release/bundle/" \
    "$PI_HOST:/opt/sonos-tt/"
  echo ""
  echo "=== Deploy complete ==="
  echo "Run:  flutter-pi /opt/sonos-tt/bundle/main.bin --release"
  echo "Or:   sudo systemctl restart sonos-tt-flutter"
fi