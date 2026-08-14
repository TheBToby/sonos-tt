#!/usr/bin/env bash
# =============================================================================
# coder-serve-web.sh — Publish & serve the app on the workspace local IP.
#
#   bash deploy/coder-serve-web.sh            # foreground
#   bash deploy/coder-serve-web.sh --daemon   # background (nohup + pidfiles)
#
# Starts:
#   1. soco-mock-server.py on :5001 — SoCo-CLI-compatible simulated backend
#      for the TEST environment (the real soco-http-api-server runs on the Pi).
#   2. coder-web-server.py on :8099 — static Flutter app + same-origin
#      /soco proxy → :5001. Dual-stack (IPv4+IPv6) so Coder's workspace
#      proxy (which dials the agent's tailnet IPv6 address) can connect.
#
# In the app's Settings, set the Server URL to `/soco` (relative) — the
# browser resolves it against the page origin. No CORS, no mixed content.
# Leave it empty for the app's built-in mock mode.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=coder-env.sh
source "$SCRIPT_DIR/coder-env.sh"

PUBLISH_DIR="$SONOS_TT_PERSIST/publish/web"
LOG_DIR="$SONOS_TT_PERSIST/logs"
PORT="${PORT:-8099}"
SOCO_PORT="${SOCO_PORT:-5001}"
MODE="${1:-}"

mkdir -p "$LOG_DIR"

if [ ! -f "$PUBLISH_DIR/index.html" ]; then
    echo "ERROR: no published app at $PUBLISH_DIR — run deploy/coder-build-web.sh first" >&2
    exit 1
fi

stop_pidfile() {
    local pf="$1" name="$2"
    if [ -f "$pf" ] && kill -0 "$(cat "$pf")" 2>/dev/null; then
        echo "[serve] stopping previous $name (pid $(cat "$pf"))"
        kill "$(cat "$pf")" 2>/dev/null || true
        sleep 0.5
    fi
    rm -f "$pf"
}

stop_pidfile "$LOG_DIR/soco-server.pid" "soco mock server"
stop_pidfile "$LOG_DIR/web-server.pid" "web server"

IP="$(hostname -I | awk '{print $1}')"
echo "[serve] app:      $PUBLISH_DIR"
echo "[serve] URLs:     http://$IP:$PORT/   http://localhost:$PORT/"
echo "[serve] soco API: same-origin proxy /soco → 127.0.0.1:$SOCO_PORT (mock)"

if [ "$MODE" = "--daemon" ]; then
    nohup python3 "$SCRIPT_DIR/soco-mock-server.py" --port "$SOCO_PORT" \
        >>"$LOG_DIR/soco-server.log" 2>&1 &
    echo $! >"$LOG_DIR/soco-server.pid"

    nohup python3 "$SCRIPT_DIR/coder-web-server.py" --port "$PORT" \
        --publish-dir "$PUBLISH_DIR" --soco-url "http://127.0.0.1:$SOCO_PORT" \
        >>"$LOG_DIR/web-server.log" 2>&1 &
    echo $! >"$LOG_DIR/web-server.pid"

    sleep 1
    echo "[serve] soco mock pid $(cat "$LOG_DIR/soco-server.pid") → $LOG_DIR/soco-server.log"
    echo "[serve] web server pid $(cat "$LOG_DIR/web-server.pid") → $LOG_DIR/web-server.log"
else
    echo "[serve] starting soco mock server on :$SOCO_PORT (background alongside)"
    python3 "$SCRIPT_DIR/soco-mock-server.py" --port "$SOCO_PORT" \
        >>"$LOG_DIR/soco-server.log" 2>&1 &
    SOCO_PID=$!
    trap 'kill $SOCO_PID 2>/dev/null || true' EXIT
    exec python3 "$SCRIPT_DIR/coder-web-server.py" --port "$PORT" \
        --publish-dir "$PUBLISH_DIR" --soco-url "http://127.0.0.1:$SOCO_PORT"
fi