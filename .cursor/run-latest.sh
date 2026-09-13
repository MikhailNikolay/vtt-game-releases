#!/usr/bin/env bash
# Fetch, verify, and run a published VTT GAME build on the Linux VM.
#
# Mirrors what Launcher.exe does on Windows (download the files listed in
# version.json from the "latest" release and verify their sha256), then boots
# the exported .pck with a native Godot engine that matches the shipped version.
#
# Usage:
#   bash .cursor/run-latest.sh                 # fetch latest, run windowed on $DISPLAY
#   bash .cursor/run-latest.sh --tag v1.3.6    # run a specific release
#   VTT_HEADLESS=1 bash .cursor/run-latest.sh  # verify boot without a window (CI-style)
#   VTT_VERIFY_ONLY=1 bash .cursor/run-latest.sh   # only run the integrity check

set -euo pipefail
cd "$(dirname "$0")/.."
source .cursor/vtt-lib.sh

TAG=""
GODOT_EXTRA_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --) shift; GODOT_EXTRA_ARGS=("$@"); break ;;
    *) GODOT_EXTRA_ARGS+=("$1"); shift ;;
  esac
done

fetch_release "$TAG"

log "Verifying release integrity (launcher sha256 pipeline)..."
verify_release

if [ "${VTT_VERIFY_ONLY:-0}" = "1" ]; then
  log "Verify-only mode: integrity check passed."
  exit 0
fi

ENGINE_VER="$(detect_engine_version || echo "$VTT_DEFAULT_GODOT_VERSION")"
log "Build was exported with Godot v${ENGINE_VER}"
GODOT_BIN="$(ensure_godot "$ENGINE_VER")"

# Software GL is the reliable path on a headless VM (Mesa llvmpipe).
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export DISPLAY="${DISPLAY:-:1}"

RUN_ARGS=(--main-pack "$VTT_BUILD_DIR/VTTGame.pck" --rendering-driver opengl3)

if [ "${VTT_HEADLESS:-0}" = "1" ]; then
  log "Booting headless (${VTT_QUIT_AFTER:-300} frames) to validate startup..."
  exec "$GODOT_BIN" "${RUN_ARGS[@]}" --headless --quit-after "${VTT_QUIT_AFTER:-300}" "${GODOT_EXTRA_ARGS[@]}"
else
  log "Launching VTT GAME on DISPLAY=$DISPLAY ..."
  log "Note: the Windows-only WebRTC extension (multiplayer) is not loaded on Linux."
  exec "$GODOT_BIN" "${RUN_ARGS[@]}" --resolution "${VTT_RESOLUTION:-1280x720}" "${GODOT_EXTRA_ARGS[@]}"
fi
