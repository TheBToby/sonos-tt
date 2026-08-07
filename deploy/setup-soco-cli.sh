#!/usr/bin/env bash
set -euo pipefail

# Install and configure SoCo-CLI HTTP API server on a Raspberry Pi.
#
# This script runs ON the Pi (either directly or via ssh).
# It installs soco-cli, discovers Sonos speakers, and sets up systemd services.
#
# Usage (from your dev machine):
#   PI_HOST=pi@192.168.4.25 ./deploy/setup-soco-cli.sh
#
# Or directly on the Pi:
#   ./setup-soco-cli.sh
#
# Environment variables:
#   PI_HOST       — SSH target (e.g. pi@192.168.4.25). If empty, runs locally.
#   SOCO_SUBNETS  — Subnet to scan for Sonos (default: 192.168.0.0/24)

PI_HOST="${PI_HOST:-}"
SOCO_SUBNETS="${SOCO_SUBNETS:-192.168.0.0/24}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Helper: run a command either locally or via SSH
run() {
  if [ -n "$PI_HOST" ]; then
    ssh -t "$PI_HOST" "$1"
  else
    bash -c "$1"
  fi
}

echo "=== SoCo-CLI Setup ==="
echo "Target: ${PI_HOST:-localhost}"
echo "Sonos subnet: $SOCO_SUBNETS"
echo ""

# ─── 1. Install pip if missing ────────────────────────────────────────────────
echo "→ Checking pip..."
if ! run 'python3 -m pip --version >/dev/null 2>&1'; then
  echo "  Installing python3-pip..."
  run 'sudo apt update -qq && sudo apt install -y python3-pip'
fi

# ─── 2. Install soco-cli ──────────────────────────────────────────────────────
echo "→ Checking soco-cli..."
if ! run '/home/pi/.local/bin/soco --version >/dev/null 2>&1'; then
  echo "  Installing soco-cli..."
  run 'pip3 install --break-system-packages soco-cli'
fi

# ─── 3. Discover Sonos speakers ───────────────────────────────────────────────
echo "→ Discovering Sonos speakers on $SOCO_SUBNETS..."
run "timeout 60 /home/pi/.local/bin/soco-discover --subnets $SOCO_SUBNETS || true"

# ─── 4. Install systemd services ──────────────────────────────────────────────
echo "→ Installing systemd services..."
for svc in soco-cli.service soco-discover.service soco-discover.timer; do
  if [ -f "$SCRIPT_DIR/$svc" ]; then
    if [ -n "$PI_HOST" ]; then
      scp "$SCRIPT_DIR/$svc" "$PI_HOST:/tmp/$svc"
      run "sudo cp /tmp/$svc /etc/systemd/system/$svc"
    else
      sudo cp "$SCRIPT_DIR/$svc" "/etc/systemd/system/$svc"
    fi
  fi
done

run 'sudo systemctl daemon-reload'
run 'sudo systemctl enable --now soco-cli.service soco-discover.timer'

# ─── 5. Verify ────────────────────────────────────────────────────────────────
echo ""
echo "→ Waiting for service to start..."
sleep 5
echo ""
echo "=== soco-cli service status ==="
run 'sudo systemctl status soco-cli.service --no-pager -l 2>&1 | head -12'
echo ""
echo "=== API test: /speakers ==="
run 'curl -s --max-time 10 http://localhost:5001/speakers'
echo ""
echo ""
echo "=== Setup complete ==="
echo "SoCo-CLI HTTP API is running on port 5001."
echo "The Flutter app (default baseUrl: http://localhost:5001) will connect automatically."