#!/usr/bin/env bash
# =============================================================================
# coder-smoke-test.sh — Smoke-test the published web app in Brave (via CDP).
#
#   bash deploy/coder-smoke-test.sh
#
# Why CDP? Brave's --screenshot/--dump-dom wait for the page's "load complete",
# which a Flutter web app (continuous animation) never emits — the command
# hangs forever. Instead we:
#
#   1. HTTP checks via curl (index, JS, fonts, canvaskit)
#   2. Launch Brave headless with --remote-debugging-port
#   3. Let it load http://<local-ip>:8099/ for N seconds
#   4. Capture DOM + screenshot via deploy/cdp_capture.py (stdlib-only CDP)
#   5. Verify Flutter engine markers (flutter-view, flt-glass-pane)
#   6. Kill Brave, report PASS/FAIL
#
# All artifacts land in /opt/coder/sonos-tt/logs (persistent).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=coder-env.sh
source "$SCRIPT_DIR/coder-env.sh"

LOG_DIR="$SONOS_TT_PERSIST/logs"
IP="$(hostname -I | awk '{print $1}')"
PORT="${PORT:-8099}"          # app server port
CDP_PORT="${CDP_PORT:-9333}"  # DevTools port
BASE_URL="http://$IP:$PORT"
WAIT_BOOT="${WAIT_BOOT:-15}"
mkdir -p "$LOG_DIR"

BRAVE="${BRAVE:-brave-browser}"
command -v "$BRAVE" >/dev/null || { echo "ERROR: $BRAVE not found (run deploy/coder-install-brave.sh)"; exit 1; }

echo "=== [smoke] HTTP checks on $BASE_URL ==="
for p in / /main.dart.js /flutter.js /flutter_bootstrap.js /manifest.json /canvaskit/canvaskit.js; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE_URL$p" || echo 000)"
    printf '  %-28s %s\n' "$p" "$code"
    [ "$code" = "200" ] || { echo "FAILED: $p → $code"; exit 1; }
done
echo "HTTP checks passed."
echo

echo "=== [smoke] Launching Brave (headless, CDP on :$CDP_PORT) → $BASE_URL ==="
BRAVE_LOG="$LOG_DIR/brave-cdp.log"
PROFILE="$LOG_DIR/brave-profile"
rm -rf "$PROFILE"

# SIGTERM-safe launch in background
"$BRAVE" --headless=new --no-sandbox --disable-dev-shm-usage \
    --enable-unsafe-swiftshader --use-gl=swiftshader \
    --remote-debugging-port="$CDP_PORT" --remote-debugging-address=127.0.0.1 \
    --user-data-dir="$PROFILE" --window-size=1080,1080 \
    "$BASE_URL" >"$BRAVE_LOG" 2>&1 &
BRAVE_PID=$!
trap 'kill $BRAVE_PID 2>/dev/null || true' EXIT

echo "  brave pid $BRAVE_PID; waiting ${WAIT_BOOT}s for boot …"

# ─── CDP capture ─────────────────────────────────────────────────────────────
# (|| captures the exit code; set -e would otherwise abort the script)
CAPTURE_OK=0
python3 "$SCRIPT_DIR/cdp_capture.py" \
    --port "$CDP_PORT" \
    --wait "$WAIT_BOOT" \
    --dom-out "$LOG_DIR/smoke-dom.html" \
    --png-out "$LOG_DIR/smoke-screenshot.png" \
    --marker flutter-view || CAPTURE_OK=$?

echo
kill "$BRAVE_PID" 2>/dev/null || true
wait "$BRAVE_PID" 2>/dev/null || true
trap - EXIT

# ─── Verdict ─────────────────────────────────────────────────────────────────
echo "=== [smoke] Verifying Flutter markers in DOM ==="
PASS=1
for marker in flutter-view flt-glass-pane; do
    if grep -q "$marker" "$LOG_DIR/smoke-dom.html" 2>/dev/null; then
        echo "  ✓ $marker"
    else
        echo "  ✗ $marker MISSING"
        PASS=0
    fi
done

# Screenshot sanity: >10 KB means actual pixels were painted (a blank page PNG
# at 1080x1080 compresses to a few KB).
if [ -f "$LOG_DIR/smoke-screenshot.png" ]; then
    size=$(wc -c <"$LOG_DIR/smoke-screenshot.png")
    echo "  screenshot: $LOG_DIR/smoke-screenshot.png ($size bytes)"
    [ "$size" -gt 10000 ] && echo "  ✓ screenshot has content (>10 KB)" || { echo "  ✗ screenshot suspiciously small"; PASS=0; }
else
    echo "  ✗ no screenshot"
    PASS=0
fi

echo
if [ "$PASS" = "1" ] && [ "$CAPTURE_OK" = "0" ]; then
    echo "═══ SMOKE TEST PASSED — $BASE_URL renders the Flutter app in Brave ═══"
    echo "    Artifacts: $LOG_DIR/smoke-dom.html, $LOG_DIR/smoke-screenshot.png"
    exit 0
else
    echo "═══ SMOKE TEST FAILED — inspect $LOG_DIR/smoke-dom.html & $BRAVE_LOG ═══"
    exit 1
fi