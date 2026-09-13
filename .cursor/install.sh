#!/usr/bin/env bash
# Idempotent environment bootstrap for the VTT GAME releases repo.
#
# This repo has no source code to build; it distributes Windows release
# packages. To let a Cloud Agent actually run and QA those builds on Linux, we
# preinstall a native Godot engine matching the shipped export. The game's
# exported .pck then runs directly, no Windows emulation needed.

set -euo pipefail
cd "$(dirname "$0")/.."
source .cursor/vtt-lib.sh

# Best-effort software-GL / audio runtime deps. The default image already ships
# Mesa (llvmpipe), so these are non-fatal if apt is unavailable or offline.
if command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y --no-install-recommends \
    libgl1-mesa-dri mesa-utils libspeechd2 alsa-utils >/dev/null 2>&1 \
    || log "apt runtime deps skipped (offline or unavailable) -- non-fatal"
fi

# Preinstall the engine that matches the current shipped build.
GODOT_BIN="$(ensure_godot "$VTT_DEFAULT_GODOT_VERSION")"

log "Environment ready."
log "Godot engine: $GODOT_BIN ($("$GODOT_BIN" --version))"
log "Run the latest published build with: bash .cursor/run-latest.sh"
