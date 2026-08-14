#!/usr/bin/env bash
# =============================================================================
# coder-env.sh — Environment for the Coder workspace (SOURCE this file!).
#
#   source deploy/coder-env.sh
#
# Points PATH and pub cache at the persistent area under /opt/coder/sonos-tt
# so that SDK, packages and builds survive Coder workspace updates.
# =============================================================================
# shellcheck shell=bash

export SONOS_TT_PERSIST="/opt/coder/sonos-tt"

# Flutter SDK lives in the persistent area.
export FLUTTER_ROOT="$SONOS_TT_PERSIST/flutter"
case ":$PATH:" in
    *":$FLUTTER_ROOT/bin:"*) : ;;          # already present
    *) export PATH="$FLUTTER_ROOT/bin:$PATH" ;;
esac

# Pub package cache — persistent, shared across workspace rebuilds.
export PUB_CACHE="$SONOS_TT_PERSIST/pub-cache"
case ":$PATH:" in
    *":$PUB_CACHE/bin:"*) : ;;
    *) export PATH="$PUB_CACHE/bin:$PATH" ;;
esac

# Never colorize build output that ends up in log files.
export TERM="${TERM:-xterm}"

echo "[env] Flutter:  $(command -v flutter || echo 'NOT FOUND')"
echo "[env] Dart:     $(command -v dart || echo 'NOT FOUND')"
echo "[env] PUB_CACHE=$PUB_CACHE"