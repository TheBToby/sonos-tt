#!/usr/bin/env bash
# =============================================================================
# coder-build-web.sh — Install deps, verify, build & publish the web app.
#
#   bash deploy/coder-build-web.sh [--skip-tests]
#
# Pipeline:
#   1. flutter pub get            (packages → persistent pub cache)
#   2. flutter analyze            (static analysis)
#   3. flutter test               (widget/unit tests; --skip-tests to bypass)
#   4. flutter build web --release (uses canvaskit from the persistent SDK)
#   5. rsync → /opt/coder/sonos-tt/publish/web  (the published app)
#
# Everything heavy (SDK, cache, output) lives under /opt/coder/sonos-tt so it
# survives Coder workspace updates.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=coder-env.sh
source "$SCRIPT_DIR/coder-env.sh"

PUBLISH_DIR="$SONOS_TT_PERSIST/publish/web"
LOG_DIR="$SONOS_TT_PERSIST/logs"
SKIP_TESTS="${1:-}"

mkdir -p "$LOG_DIR" "$PUBLISH_DIR"

log() { printf '\n=== %s ===\n' "$*"; }

# ─── 1. Dependencies ───────────────────────── persistent pub cache ─────────
log "flutter pub get"
flutter pub get

# ─── 2. Static analysis ──────────────────────────────────────────────────────
log "flutter analyze"
flutter analyze

# ─── 3. Tests ────────────────────────────────────────────────────────────────
if [ "$SKIP_TESTS" = "--skip-tests" ]; then
    log "flutter test SKIPPED (--skip-tests)"
else
    log "flutter test"
    flutter test
fi

# ─── 4. Release build ────────────────────────────────────────────────────────
log "flutter build web --release"
flutter build web --release

# ─── 5. Publish to persistent area ───────────────────────────────────────────
log "Publishing build → $PUBLISH_DIR"
rsync -a --delete "$PROJECT_DIR/build/web/" "$PUBLISH_DIR/"
echo "Published files:"
ls -la "$PUBLISH_DIR" | head -15

log "DONE — serve with: bash deploy/coder-serve-web.sh"