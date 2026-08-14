#!/usr/bin/env bash
# =============================================================================
# coder-serve-web.sh — Publish & serve the built web app on the local IP.
#
#   bash deploy/coder-serve-web.sh            # foreground
#   bash deploy/coder-serve-web.sh --daemon   # background (nohup + pidfile)
#
# Serves /opt/coder/sonos-tt/publish/web on 0.0.0.0:8099 — reachable from
# any machine on the LAN via the workspace's local IP (e.g. http://172.20.0.2:8099).
# Uses Python's http.server (zero extra dependencies, threads per connection).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=coder-env.sh
source "$SCRIPT_DIR/coder-env.sh"

PUBLISH_DIR="$SONOS_TT_PERSIST/publish/web"
LOG_DIR="$SONOS_TT_PERSIST/logs"
PORT="${PORT:-8099}"
PIDFILE="$LOG_DIR/web-server.pid"
MODE="${1:-}"

mkdir -p "$LOG_DIR"

if [ ! -f "$PUBLISH_DIR/index.html" ]; then
    echo "ERROR: no published app at $PUBLISH_DIR — run deploy/coder-build-web.sh first" >&2
    exit 1
fi

# Stop a previous instance (if any).
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "[serve] stopping previous server (pid $(cat "$PIDFILE"))"
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    sleep 0.5
fi
rm -f "$PIDFILE"

IP="$(hostname -I | awk '{print $1}')"
echo "[serve] app:     $PUBLISH_DIR"
echo "[serve] URL:     http://$IP:$PORT/"
echo "[serve] bind:    0.0.0.0:$PORT"

cd "$PUBLISH_DIR"

if [ "$MODE" = "--daemon" ]; then
    nohup python3 -m http.server "$PORT" --bind 0.0.0.0 \
        >>"$LOG_DIR/web-server.log" 2>&1 &
    echo $! >"$PIDFILE"
    echo "[serve] daemon pid $(cat "$PIDFILE"), logs: $LOG_DIR/web-server.log"
else
    exec python3 -m http.server "$PORT" --bind 0.0.0.0
fi