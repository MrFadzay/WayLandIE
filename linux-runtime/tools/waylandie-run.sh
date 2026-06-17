#!/usr/bin/env sh
set -eu

if [ "$#" -eq 0 ]; then
  cat >&2 <<'EOF'
usage:
  waylandie-run <wayland-command> [args...]

examples:
  waylandie-run vkcube --wsi wayland
  waylandie-run weston-simple-egl
  waylandie-run your-game --fullscreen
EOF
  exit 2
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ -n "${WAYLANDIE_WAYLAND_HELPER:-}" ]; then
  HELPER="$WAYLANDIE_WAYLAND_HELPER"
else
  HELPER=""
  for candidate in \
    "$SCRIPT_DIR/../bridge/waylandie-wayland-bridge.sh" \
    "$SCRIPT_DIR/../share/waylandie/bridge/waylandie-wayland-bridge.sh" \
    "/usr/local/share/waylandie/bridge/waylandie-wayland-bridge.sh" \
    "$HOME/.local/share/waylandie/bridge/waylandie-wayland-bridge.sh"; do
    if [ -f "$candidate" ]; then
      HELPER="$candidate"
      break
    fi
  done
fi

if [ -z "$HELPER" ] || [ ! -f "$HELPER" ]; then
  echo "missing helper; set WAYLANDIE_WAYLAND_HELPER or run linux-runtime/install.sh first" >&2
  exit 1
fi

command_text=""
for arg in "$@"; do
  quoted="$(printf "%s" "$arg" | sed "s/'/'\\\\''/g")"
  if [ -z "$command_text" ]; then
    command_text="'$quoted'"
  else
    command_text="$command_text '$quoted'"
  fi
done

export CLIENT_MODE=external
export FRAME_COUNT="${FRAME_COUNT:-2147483647}"
export SERVER_TIMEOUT_MS="${SERVER_TIMEOUT_MS:-2147483647}"
export ACCEPT_CLIENT_COMPLETE="${ACCEPT_CLIENT_COMPLETE:-1}"
export CLIENT_WIDTH="${CLIENT_WIDTH:-2688}"
export CLIENT_HEIGHT="${CLIENT_HEIGHT:-1216}"
export BRIDGE_LOCAL_SOCKET="${BRIDGE_LOCAL_SOCKET:-waylandie.display.bridge.v1}"
export EXTERNAL_CLIENT_COMMAND="$command_text"

exec sh "$HELPER"
