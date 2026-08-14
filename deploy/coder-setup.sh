#!/usr/bin/env bash
# =============================================================================
# coder-setup.sh — One-time environment setup for the Coder workspace.
#
# Sets up everything needed to develop, build, and publish sonos-tt on the
# Coder-based virtual IDE:
#
#   1. Flutter SDK        → /opt/coder/sonos-tt/flutter     (persistent)
#   2. Pub cache          → /opt/coder/sonos-tt/pub-cache   (persistent)
#   3. Published web app  → /opt/coder/sonos-tt/publish     (persistent)
#   4. Build logs         → /opt/coder/sonos-tt/logs        (persistent)
#
# IMPORTANT: /opt/coder/sonos-tt is the persistent area that survives Coder
# workspace updates. NEVER move it. The Flutter SDK and pub cache live there
# so that a workspace rebuild only needs `./deploy/coder-env.sh` re-sourced
# and (at most) a re-run of this script's PATH links step.
#
# Idempotent: safe to re-run any time.
# =============================================================================
set -euo pipefail

PERSIST_ROOT="/opt/coder/sonos-tt"
FLUTTER_DIR="$PERSIST_ROOT/flutter"
PUB_CACHE_DIR="$PERSIST_ROOT/pub-cache"
DOWNLOADS_DIR="$PERSIST_ROOT/downloads"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.0}"
FLUTTER_ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_ARCHIVE}"

log() { printf '\n[setup] %s\n' "$*"; }

# ─── 1. Persistent directory layout ─────────────────────────────────────────
log "Ensuring persistent layout at $PERSIST_ROOT"
if [ "$(id -u)" -eq 0 ]; then
    mkdir -p "$PERSIST_ROOT"/{downloads,logs,publish,pub-cache}
    chown -R coder:coder "$PERSIST_ROOT" 2>/dev/null || true
else
    mkdir -p "$PERSIST_ROOT"/{downloads,logs,publish,pub-cache}
fi

# ─── 2. Flutter SDK (persistent) ────────────────────────────────────────────
if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
    log "Flutter SDK already present at $FLUTTER_DIR (skipping download)"
else
    log "Downloading Flutter $FLUTTER_VERSION …"
    if [ ! -f "$DOWNLOADS_DIR/$FLUTTER_ARCHIVE" ]; then
        curl -fSL --retry 3 --connect-timeout 15 "$FLUTTER_URL" \
             -o "$DOWNLOADS_DIR/$FLUTTER_ARCHIVE"
    fi
    log "Extracting Flutter SDK to $FLUTTER_DIR …"
    tar -xJf "$DOWNLOADS_DIR/$FLUTTER_ARCHIVE" -C "$PERSIST_ROOT"
    # tar extracts a top-level "flutter/" folder — already at the right place.
fi

# Flutter SDK is pre-warmed (bin cache committed inside tarball) — disable
# analytics telemetry for CI-like environments.
export PUB_CACHE="$PUB_CACHE_DIR"
"$FLUTTER_DIR/bin/flutter" --version 2>&1 | head -4 || true
"$FLUTTER_DIR/bin/flutter" config --no-analytics >/dev/null 2>&1 || true

# ─── 3. git safe.directory (SDK owned by different mount layer) ─────────────
git config --global --add safe.directory "$FLUTTER_DIR" 2>/dev/null || true
git config --global --add safe.directory "$FLUTTER_DIR/bin/cache/pkg/sky_engine" 2>/dev/null || true

# ─── 4. PATH convenience links (ephemeral layer) ────────────────────────────
# /usr/local/bin is inside the workspace image and may be reset on updates;
# the real binaries stay in the persistent area, these are just symlinks.
log "Linking flutter/dart into /usr/local/bin"
if [ "$(id -u)" -eq 0 ]; then
    ln -sf "$FLUTTER_DIR/bin/flutter" /usr/local/bin/flutter
    ln -sf "$FLUTTER_DIR/bin/dart" /usr/local/bin/dart
else
    sudo ln -sf "$FLUTTER_DIR/bin/flutter" /usr/local/bin/flutter
    sudo ln -sf "$FLUTTER_DIR/bin/dart" /usr/local/bin/dart
fi

log "Setup complete. Next: source ./deploy/coder-env.sh, then ./deploy/coder-build-web.sh"