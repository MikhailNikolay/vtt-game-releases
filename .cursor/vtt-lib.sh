#!/usr/bin/env bash
# Shared helpers for running/QA-testing published VTT GAME builds on Linux.
#
# This repository ships only Windows release binaries (see README.md). The game
# is a Godot 4.x export (VTTGame.exe + VTTGame.pck). On the Linux Cloud Agent VM
# we run the exported .pck directly with a native Godot engine binary that
# matches the shipped engine version, so no Windows emulation is required.

set -euo pipefail

# Repository whose GitHub Releases host the builds.
VTT_REPO="${VTT_REPO:-MikhailNikolay/vtt-game-releases}"

# Where downloaded tooling and builds are cached (outside the git checkout).
VTT_TOOLS_DIR="${VTT_TOOLS_DIR:-$HOME/.local/share/vtt-tools}"
VTT_GODOT_DIR="${VTT_GODOT_DIR:-$VTT_TOOLS_DIR/godot}"
VTT_BUILD_DIR="${VTT_BUILD_DIR:-$HOME/.cache/vtt-game/build}"

# Engine version to preinstall during `install`. The run script re-detects the
# real version from each downloaded build and fetches a matching engine if this
# default ever drifts from what a release was exported with.
VTT_DEFAULT_GODOT_VERSION="${VTT_DEFAULT_GODOT_VERSION:-4.6.3}"

log() { printf '\033[1;36m[vtt]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[vtt:error]\033[0m %s\n' "$*" >&2; }

# ensure_godot <version> -> prints absolute path to a native Linux Godot binary,
# downloading it from the official godotengine/godot releases if missing.
ensure_godot() {
  local ver="$1"
  local bin="$VTT_GODOT_DIR/$ver/godot"
  if [ -x "$bin" ] && "$bin" --version 2>/dev/null | grep -q "^${ver}\."; then
    printf '%s\n' "$bin"
    return 0
  fi
  log "Downloading Godot engine v${ver} (native Linux x86_64)..."
  local dir="$VTT_GODOT_DIR/$ver"
  local zip="Godot_v${ver}-stable_linux.x86_64.zip"
  mkdir -p "$dir"
  ( cd "$dir" && gh release download "${ver}-stable" -R godotengine/godot -p "$zip" --clobber \
      && unzip -o "$zip" >/dev/null && rm -f "$zip" )
  mv -f "$dir/Godot_v${ver}-stable_linux.x86_64" "$bin"
  chmod +x "$bin"
  "$bin" --version >&2
  printf '%s\n' "$bin"
}

# fetch_release [tag] -> downloads a release's game files into VTT_BUILD_DIR.
# With no tag it fetches the latest release (what Launcher.exe updates to).
fetch_release() {
  local tag="${1:-}"
  mkdir -p "$VTT_BUILD_DIR"
  log "Fetching ${tag:-latest} release of ${VTT_REPO} into ${VTT_BUILD_DIR}"
  local args=(-R "$VTT_REPO" --clobber -D "$VTT_BUILD_DIR"
              -p 'VTTGame.exe' -p 'VTTGame.pck'
              -p 'libwebrtc_native.*.dll' -p 'version.json'
              -p 'launcher_config.json')
  if [ -n "$tag" ]; then
    gh release download "$tag" "${args[@]}"
  else
    gh release download "${args[@]}"
  fi
}

# verify_release -> reproduces the launcher's integrity check: every file listed
# in version.json must match its recorded sha256 and size. Returns non-zero on
# any mismatch.
verify_release() {
  python3 - "$VTT_BUILD_DIR" <<'PY'
import json, hashlib, os, sys
d = sys.argv[1]
v = json.load(open(os.path.join(d, "version.json")))
print(f"app_version={v.get('app_version')} channel={v.get('channel')}")
ok = True
for f in v.get("files", []):
    p = os.path.join(d, f["path"])
    if not os.path.exists(p):
        print(f"MISSING {f['path']}"); ok = False; continue
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    good = (h == f["sha256"] and os.path.getsize(p) == f["size"])
    ok = ok and good
    print(f"{'OK ' if good else 'BAD'} {f['path']} size={os.path.getsize(p)} expected={f['size']}")
print("ALL_SHA256_MATCH:", ok)
sys.exit(0 if ok else 1)
PY
}

# detect_engine_version -> prints the Godot version the downloaded build was
# exported with (e.g. 4.6.3), read straight from the shipped executable.
detect_engine_version() {
  strings -n 8 "$VTT_BUILD_DIR/VTTGame.exe" \
    | grep -oE 'Godot Engine v[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}
