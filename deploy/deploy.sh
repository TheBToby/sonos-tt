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

# Deploy target on the Pi. /opt requires root, so the script bootstraps it once
# (sudo mkdir + chown to the remote user) and then writes to it without sudo.
DEPLOY_DIR="${DEPLOY_DIR:-/opt/sonos-tt}"

echo "=== Deploying sonos-tt to $PI_HOST ==="

# ─── SSH connection multiplexing ─────────────────────────────────────────────
# Reuse a single SSH connection for ALL ssh/rsync calls in this script. This
# means only ONE password prompt (or key unlock) for the entire deploy instead
# of one per command. The control socket is cleaned up on exit.
SSH_SOCK="$(mktemp -u "${TMPDIR:-/tmp}/sonos-tt-ssh.XXXXXXXX")"
SSH_CTL=(-o ControlMaster=auto -o ControlPath="$SSH_SOCK" -o ControlPersist=300)
SSH_RSYNC_E="ssh -o ControlMaster=auto -o ControlPath=$SSH_SOCK -o ControlPersist=300"
cleanup() {
  [ -n "${SSH_SOCK:-}" ] && ssh -o ControlPath="$SSH_SOCK" -O exit "$PI_HOST" 2>/dev/null || true
}
trap cleanup EXIT

# ─── Helper: ensure remote /opt dir is writable by the remote user ───────────
# /opt is root-owned. Bootstrap the deploy dir ONCE: create it with sudo and
# chown it to the remote user, so subsequent deploys work without sudo.
# Only the FIRST deploy triggers the sudo prompt; after that, the dir is owned
# by the remote user and no sudo is needed.
ensure_deploy_dir() {
  # Fast path: if the dir already exists and is writable, skip sudo entirely.
  if ssh "${SSH_CTL[@]}" "$PI_HOST" "test -w '$DEPLOY_DIR'" 2>/dev/null; then
    return 0
  fi
  # Dir doesn't exist or isn't writable — need sudo to create it.
  # Use -t to allocate a TTY so sudo can interactively prompt for a password.
  echo "→ First deploy: creating $DEPLOY_DIR (requires sudo on Pi)..."
  ssh -t "${SSH_CTL[@]}" "$PI_HOST" "
    sudo mkdir -p '$DEPLOY_DIR' && sudo chown \"\$USER:\$USER\" '$DEPLOY_DIR'
  "
}

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
  ensure_deploy_dir
  # ─── Flatten the bundle for flutter-pi ─────────────────────────────────
  # (See comment in the remote deploy section below for full explanation.)
  # Rename libapp.so → app.so during deploy (flutter-pi expects app.so)
  rsync -avz --delete \
    -e "$SSH_RSYNC_E" \
    --copy-links \
    "$BUNDLE_DIR/lib/libapp.so" \
    "$BUNDLE_DIR/data/icudtl.dat" \
    "$PI_HOST:$DEPLOY_DIR/"
  ssh "${SSH_CTL[@]}" "$PI_HOST" "mv '$DEPLOY_DIR/libapp.so' '$DEPLOY_DIR/app.so'"
  rsync -avz --delete \
    -e "$SSH_RSYNC_E" \
    "$BUNDLE_DIR/data/flutter_assets/" \
    "$PI_HOST:$DEPLOY_DIR/flutter_assets/"

# ─── Remote deploy (macOS host — bundle is on the Pi from remote build) ──────
else
  # Resolve remote HOME so we can find the remote build output.
  REMOTE_HOME="$(ssh "${SSH_CTL[@]}" "$PI_HOST" 'printf %s "$HOME"' 2>/dev/null | tr -d '\r\n')"
  if [ -z "$REMOTE_HOME" ]; then
    echo "ERROR: Could not resolve remote \$HOME on $PI_HOST"
    exit 1
  fi
  REMOTE_DIR="${REMOTE_DIR:-$REMOTE_HOME/sonos-tt-src}"
  REMOTE_BUNDLE="$REMOTE_DIR/build/linux/arm64/release/bundle"
  echo "Bundle: $PI_HOST:$REMOTE_BUNDLE"
  echo ""
  # Check that a remote build exists
  if ! ssh "${SSH_CTL[@]}" "$PI_HOST" "test -d '$REMOTE_BUNDLE'"; then
    echo "ERROR: Remote bundle not found at $PI_HOST:$REMOTE_BUNDLE"
    echo "Run ./deploy/build.sh first (builds remotely on the Pi)"
    exit 1
  fi
  ensure_deploy_dir
  # ─── Flatten the bundle for flutter-pi ─────────────────────────────────
  # `flutter build linux` produces a GTK desktop layout:
  #   bundle/lib/libapp.so       (compiled Dart app)
  #   bundle/data/icudtl.dat     (ICU data)
  #   bundle/data/flutter_assets/(Flutter assets)
  #
  # But flutter-pi expects a FLAT layout with app.so (not libapp.so):
  #   app.so                      (renamed from lib/libapp.so)
  #   icudtl.dat
  #   flutter_assets/
  #
  # We flatten + rename during deploy.
  ssh "${SSH_CTL[@]}" "$PI_HOST" "
    rm -rf '$DEPLOY_DIR'/* &&
    cp '$REMOTE_BUNDLE/lib/libapp.so' '$DEPLOY_DIR/app.so' &&
    cp '$REMOTE_BUNDLE/data/icudtl.dat' '$DEPLOY_DIR/icudtl.dat' &&
    cp -r '$REMOTE_BUNDLE/data/flutter_assets' '$DEPLOY_DIR/flutter_assets'
  "
fi

echo ""
echo "=== Deploy complete ==="
echo ""
echo "On the Pi, you can now:"
echo "  1. Restart the systemd service:"
echo "     ssh $PI_HOST 'sudo systemctl restart sonos-tt-flutter'"
echo ""
echo "  2. Or run manually:"
echo "     ssh $PI_HOST 'flutter-pi --release $DEPLOY_DIR'"
