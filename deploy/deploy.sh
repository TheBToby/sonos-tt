#!/usr/bin/env bash
set -euo pipefail

# Deploy sonos-tt Flutter bundle to a Raspberry Pi.
#
# Copies the flutterpi_tool output bundle to /opt/sonos-tt on the Pi.
# The flutterpi_tool bundle already has the correct flat layout for flutter-pi:
#   app.so, libflutter_engine.so, icudtl.dat, fonts/, shaders/, etc.
#
# No manual flattening or renaming is needed — just rsync the entire directory.
#
# Usage:
#   ./deploy/deploy.sh [pi-host]
#   PI_HOST=custom-pi ./deploy/deploy.sh

PI_HOST="${PI_HOST:-${1:-raspberrypi}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Deploy target on the Pi. /opt requires root, so the script bootstraps it once
# (sudo mkdir + chown to the remote user) and then writes to it without sudo.
DEPLOY_DIR="${DEPLOY_DIR:-/opt/sonos-tt}"

# The flutterpi_tool output directory.
BUNDLE_BASE="$PROJECT_DIR/build/flutter-pi"

echo "=== Deploying sonos-tt to $PI_HOST ==="

# ─── Locate the local bundle ─────────────────────────────────────────────────
BUNDLE_DIR=""
for dir in "$BUNDLE_BASE"/*; do
  if [ -f "$dir/app.so" ] && [ -f "$dir/libflutter_engine.so" ]; then
    BUNDLE_DIR="$dir"
    break
  fi
done

if [ -z "$BUNDLE_DIR" ] || [ ! -d "$BUNDLE_DIR" ]; then
  echo "ERROR: flutter-pi bundle not found in $BUNDLE_BASE"
  echo "Expected: app.so and libflutter_engine.so in $BUNDLE_BASE/*/"
  echo "Run ./deploy/build.sh first"
  exit 1
fi
echo "Bundle: $BUNDLE_DIR"
echo ""

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
  # Ensure $DEPLOY_DIR exists and is FULLY owned by the remote user.
  # A simple `test -w` check is insufficient: a prior deploy done as root
  # (or a manual `sudo cp`) can leave the top-level dir user-owned while
  # subdirectories remain root-owned. `test -w` then passes, but `rm -rf`
  # later fails with "Permission denied" on the root-owned subtrees.
  # We scan for any file/dir NOT owned by $USER inside $DEPLOY_DIR; if any
  # are found (or the dir doesn't exist), fix ownership with sudo chown -R.
  if ssh "${SSH_CTL[@]}" "$PI_HOST" "
    test -d '$DEPLOY_DIR' && \
    ! find '$DEPLOY_DIR' ! -user \"\$USER\" -print -quit 2>/dev/null | grep -q .
  " 2>/dev/null; then
    return 0
  fi
  # Dir doesn't exist, or contains files not owned by $USER — fix with sudo.
  # Use -t to allocate a TTY so sudo can interactively prompt for a password.
  echo "→ Ensuring $DEPLOY_DIR ownership (requires sudo on Pi)..."
  ssh -t "${SSH_CTL[@]}" "$PI_HOST" "
    sudo mkdir -p '$DEPLOY_DIR' && sudo chown -R \"\$USER:\$USER\" '$DEPLOY_DIR'
  "
}

# ─── Helper: ensure the remote user is in video/render/input groups ──────────
# flutter-pi opens DRM/GPU/input devices directly. On Raspberry Pi OS these are
# group-owned by:
#   video  (/dev/dri/card*)
#   render (/dev/dri/renderD*)
#   input  (/dev/input/event*)
# Without membership in these groups, flutter-pi fails with:
#   "Couldn't open DRM device. open: Permission denied"
# Manual `flutter-pi ...` runs use the user's own groups, so the user MUST be
# in them. (The systemd service uses SupplementaryGroups as a belt-and-braces
# fallback.) Only prompts for sudo if a group is actually missing.
ensure_groups() {
  local missing
  missing="$(ssh "${SSH_CTL[@]}" "$PI_HOST" '
    for g in video render input; do
      groups "$USER" | grep -qw "$g" || echo "$g"
    done
  ' 2>/dev/null | tr -d '\r')"
  if [ -z "$missing" ]; then
    return 0
  fi
  echo "→ Adding remote user to group(s): $(echo "$missing" | tr '\n' ' ')"
  echo "  (requires sudo on Pi; log out/in or reboot afterward for it to take effect)"
  # NOTE: paste -sd, - joins lines with commas WITHOUT a trailing comma (unlike
  # tr '\n' ',' which leaves a trailing comma → usermod: group '' does not exist).
  # The "-" tells paste to read stdin (required by BSD paste on macOS; GNU paste
  # reads stdin by default, so "-" is the portable form across both).
  # The $(...) runs LOCALLY (macOS) before the SSH command string is assembled,
  # so we must use a form that works on the local host OS, not the Pi.
  ssh -t "${SSH_CTL[@]}" "$PI_HOST" "sudo usermod -aG \"$(echo "$missing" | paste -sd, -)\" \"\$USER\""
}

# ─── Deploy ──────────────────────────────────────────────────────────────────
ensure_deploy_dir

# ─── Copy the bundle to the Pi ───────────────────────────────────────────────
# flutterpi_tool produces a flat bundle directory containing:
#   app.so                   — compiled Dart AOT snapshot
#   libflutter_engine.so     — Flutter Engine library (downloaded by flutterpi_tool)
#   icudtl.dat               — ICU internationalization data
#   flutter_assets/          — Flutter asset bundle
#   (and other supporting files)
#
# We rsync the entire directory to /opt/sonos-tt. --delete removes old files
# from previous deploys.
echo "→ Copying bundle to $PI_HOST:$DEPLOY_DIR ..."
rsync -avz --delete \
  -e "$SSH_RSYNC_E" \
  --exclude='flutter-pi' \
  --exclude='linux/' \
  --exclude='native_assets/' \
  "$BUNDLE_DIR/" "$PI_HOST:$DEPLOY_DIR/"

# Also copy the systemd service files and backlight helper
for f in sonos-tt-flutter.service soco-cli.service soco-discover.service soco-discover.timer brightness.py 51-waveshare-backlight.rules; do
  if [ -f "$SCRIPT_DIR/$f" ]; then
    rsync -avz \
      -e "$SSH_RSYNC_E" \
      "$SCRIPT_DIR/$f" "$PI_HOST:$DEPLOY_DIR/"
  fi
done

# Copy Home Assistant secrets file if it exists (gitignored, contains tokens).
# This allows deploying HA credentials without entering them in the app UI.
if [ -f "$SCRIPT_DIR/ha-secrets.json" ]; then
  echo "→ Deploying Home Assistant secrets..."
  rsync -avz \
    -e "$SSH_RSYNC_E" \
    "$SCRIPT_DIR/ha-secrets.json" "$PI_HOST:$DEPLOY_DIR/"
else
  echo "ℹ️  No ha-secrets.json found (see ha-secrets.example.json). Skipping."
fi

# Install backlight udev rule + pyusb if the brightness script is present.
# This enables hardware backlight dimming for Waveshare displays.
# All paths are defined as LOCAL variables and expanded BEFORE being passed
# to ssh — the remote shell only sees literal paths, no variables.
if ssh "${SSH_CTL[@]}" "$PI_HOST" "test -f '$DEPLOY_DIR/brightness.py'" 2>/dev/null; then
  echo "→ Setting up hardware backlight dimming (Waveshare USB control)..."
  local_udev_dst="/etc/udev/rules.d/51-waveshare-backlight.rules"
  local_src_rule="$DEPLOY_DIR/51-waveshare-backlight.rules"

  # Install pyusb if missing (needed by brightness.py)
  ssh "${SSH_CTL[@]}" "$PI_HOST" \
    "dpkg -s python3-usb >/dev/null 2>&1 || sudo apt install -y python3-usb" \
    2>/dev/null || true

  # Install or update udev rule for non-root USB + hidraw access.
  # All $-variables expanded locally; remote shell sees only literal paths.
  # We use --action=add to force udev to re-evaluate rules against existing
  # devices (plain "udevadm trigger" sometimes doesn't update permissions
  # for devices that are already bound to a kernel driver).
  ssh "${SSH_CTL[@]}" "$PI_HOST" \
    "if [ ! -f '$local_udev_dst' ] || ! diff -q '$local_src_rule' '$local_udev_dst' >/dev/null 2>&1; then sudo cp '$local_src_rule' '$local_udev_dst' && sudo udevadm control --reload-rules && sudo udevadm trigger --action=add --subsystem-match=hidraw --subsystem-match=usb && echo '  Backlight udev rule installed/updated.'; fi" \
    2>/dev/null || true
fi

# Ensure the remote user can access DRM/GPU/input devices for manual runs.
ensure_groups

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Bundle contents on Pi:"
ssh "${SSH_CTL[@]}" "$PI_HOST" "ls -la '$DEPLOY_DIR/' | head -15"
echo ""
echo "On the Pi, you can now:"
echo "  1. Restart the systemd service:"
echo "     ssh $PI_HOST 'sudo systemctl restart sonos-tt-flutter'"
echo ""
echo "  2. Or run manually (requires the video/render/input groups above):"
echo "     ssh $PI_HOST 'flutter-pi --release $DEPLOY_DIR'"