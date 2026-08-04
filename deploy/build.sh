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
DEPLOY_AFTER="${1:-}"

# Deploy target on the Pi. /opt requires root, so the script bootstraps it once
# (sudo mkdir + chown to the remote user) and then writes to it without sudo.
DEPLOY_DIR="${DEPLOY_DIR:-/opt/sonos-tt}"

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
  # Ensure the Linux platform directory exists (required for flutter build linux)
  if [ ! -d "$PROJECT_DIR/linux" ]; then
    echo "→ Linux platform not found — generating with 'flutter create --platforms=linux'..."
    flutter create --platforms=linux --project-name=sonos_tt .
  fi
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

# ─── SSH connection multiplexing ─────────────────────────────────────────────
# Reuse a single SSH connection for ALL ssh/rsync calls in this script. This
# means only ONE password prompt (or key unlock) for the entire build instead
# of one per command. The control socket is cleaned up on exit.
SSH_SOCK="$(mktemp -u "${TMPDIR:-/tmp}/sonos-tt-ssh.XXXXXXXX")"
SSH_CTL=(-o ControlMaster=auto -o ControlPath="$SSH_SOCK" -o ControlPersist=300)
SSH_RSYNC_E="ssh -o ControlMaster=auto -o ControlPath=$SSH_SOCK -o ControlPersist=300"
cleanup() {
  [ -n "${SSH_SOCK:-}" ] && ssh -o ControlPath="$SSH_SOCK" -O exit "$PI_HOST" 2>/dev/null || true
}
trap cleanup EXIT

# Check SSH connectivity AND resolve remote $HOME in a single round-trip.
REMOTE_HOME="$(ssh "${SSH_CTL[@]}" -o ConnectTimeout=5 "$PI_HOST" 'printf %s "$HOME"' 2>/dev/null | tr -d '\r\n')"
if [ -z "$REMOTE_HOME" ]; then
  echo "ERROR: Cannot connect to $PI_HOST via SSH (or could not resolve remote \$HOME)"
  echo "Make sure:"
  echo "  1. The Pi is reachable (ping $PI_HOST)"
  echo "  2. SSH key/password is set up (ssh-copy-id pi@$PI_HOST)"
  echo "  3. Or set PI_HOST=custom-name: ./deploy/build.sh"
  exit 1
fi

# Build in the remote user's home (NOT under /opt, which needs root).
REMOTE_DIR="${REMOTE_DIR:-$REMOTE_HOME/sonos-tt-src}"
REMOTE_BUNDLE="$REMOTE_DIR/build/linux/arm64/release/bundle"

# ─── Locate Flutter on the Pi ────────────────────────────────────────────────
# Non-interactive SSH commands do not fully source ~/.bashrc on Debian/Raspberry
# Pi OS: the default ~/.bashrc returns early for non-interactive shells, so an
# `export PATH=...:$HOME/flutter/bin` line appended there is never applied.
# Therefore `command -v flutter` can fail even though Flutter is installed and
# works fine in an interactive `ssh pi@host` session.
#
# We handle this by, in order:
#   1. Trying `command -v flutter`           (works if PATH is set system-wide)
#   2. Falling back to ~/flutter/bin/flutter (the location from the README)
#   3. Falling back to /opt/flutter/bin/flutter
# Whatever we find is stored in REMOTE_FLUTTER and used by absolute path for the
# rest of the script, so we never depend on the remote PATH again.
echo "→ Checking Flutter on $PI_HOST..."
REMOTE_FLUTTER="$(ssh "${SSH_CTL[@]}" "$PI_HOST" '
  command -v flutter 2>/dev/null \
  || { [ -x "$HOME/flutter/bin/flutter" ] && echo "$HOME/flutter/bin/flutter"; } \
  || { [ -x /opt/flutter/bin/flutter ]   && echo /opt/flutter/bin/flutter; }
' 2>/dev/null | tr -d '\r\n' | tail -n1)"

if [ -z "$REMOTE_FLUTTER" ]; then
  echo "ERROR: Flutter not found on $PI_HOST"
  echo ""
  echo "Flutter is expected at one of:"
  echo "  - in PATH (system-wide install)"
  echo "  - \$HOME/flutter/bin/flutter   (per the README)"
  echo "  - /opt/flutter/bin/flutter"
  echo ""
  echo "If you already installed Flutter but it is only on your interactive PATH,"
  echo "the non-interactive SSH used by this script cannot see it. Fix it with a"
  echo "system-wide symlink:"
  echo "  ssh $PI_HOST 'sudo ln -s \$HOME/flutter/bin/flutter /usr/local/bin/flutter'"
  echo ""
  echo "Or install Flutter fresh on the Pi:"
  echo "  ssh $PI_HOST"
  echo "  sudo apt install -y git curl"
  echo "  git clone https://github.com/flutter/flutter.git ~/flutter"
  echo "  sudo ln -s \$HOME/flutter/bin/flutter /usr/local/bin/flutter"
  echo "  flutter doctor"
  exit 1
fi
echo "  Found Flutter: $REMOTE_FLUTTER"
echo "  Build dir:     $REMOTE_DIR"

# Sync source code to the Pi (exclude build artifacts and platform dirs)
echo "→ Syncing source to $PI_HOST:$REMOTE_DIR ..."
rsync -avz --delete \
  -e "$SSH_RSYNC_E" \
  --exclude='.git' \
  --exclude='build/' \
  --exclude='.dart_tool/' \
  --exclude='macos/' \
  --exclude='web/' \
  --exclude='.vscode/' \
  --exclude='*.iml' \
  --exclude='.idea/' \
  "$PROJECT_DIR/" "$PI_HOST:$REMOTE_DIR/"

# Build on the Pi (use the resolved absolute path — do not rely on remote PATH)
# Also ensure the Linux platform directory exists — without it, Flutter reports
# "No Linux desktop project configured" and the build fails.
echo "→ Building on $PI_HOST ..."
ssh "${SSH_CTL[@]}" "$PI_HOST" "cd '$REMOTE_DIR' && \
  { [ -d linux ] || '$REMOTE_FLUTTER' create --platforms=linux --project-name=sonos_tt .; } && \
  '$REMOTE_FLUTTER' pub get && \
  '$REMOTE_FLUTTER' build linux --release" 2>&1 | tail -15

echo ""
echo "=== Remote build complete ==="
echo "Bundle on Pi: $PI_HOST:$REMOTE_BUNDLE/"
echo ""

# Deploy if requested
if [ "$DEPLOY_AFTER" = "--deploy" ]; then
  echo "→ Deploying to $DEPLOY_DIR on $PI_HOST ..."
  # /opt is root-owned. Only the FIRST deploy needs sudo to create the dir;
  # after that, it's owned by the remote user and no sudo is needed.
  if ! ssh "${SSH_CTL[@]}" "$PI_HOST" "test -w '$DEPLOY_DIR'" 2>/dev/null; then
    echo "→ First deploy: creating $DEPLOY_DIR (requires sudo on Pi)..."
    # Use -t to allocate a TTY so sudo can interactively prompt for a password.
    ssh -t "${SSH_CTL[@]}" "$PI_HOST" "
      sudo mkdir -p '$DEPLOY_DIR' && sudo chown \"\$USER:\$USER\" '$DEPLOY_DIR'
    "
  fi
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
  echo ""
  echo "=== Deploy complete ==="
  echo "Run:  flutter-pi --release $DEPLOY_DIR"
  echo "Or:   sudo systemctl restart sonos-tt-flutter"
fi
