#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  waylandie-steam-session start|restart|stop|status|run [-- extra steam args...]

Environment:
  WAYLANDIE_WIDTH / WAYLANDIE_HEIGHT          Output size. Default 2688x1216.
  WAYLANDIE_REFRESH                           Gamescope refresh. Default 144.
  WAYLANDIE_STEAM_LOG                         Session log path.
  WAYLANDIE_STEAM_PIDFILE                     Session pidfile path.
  WAYLANDIE_STEAM_SESSION_CHILD               Child command. Default waylandie-steam-session-child.
  WAYLANDIE_START_DISPLAY                     Start Android activity before session. Default 1.
EOF
}

home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
cache_home="${XDG_CACHE_HOME:-$home_dir/.cache}"
state_dir="${WAYLANDIE_STEAM_STATE_DIR:-$cache_home/waylandie}"
log_file="${WAYLANDIE_STEAM_LOG:-$state_dir/steam-session.log}"
pid_file="${WAYLANDIE_STEAM_PIDFILE:-$state_dir/steam-session.pid}"
command_name="${1:-status}"
[ "$#" -gt 0 ] && shift || true

have() {
  command -v "$1" >/dev/null 2>&1
}

find_tool() {
  local env_name="$1" default_name="$2" value
  value="${!env_name:-}"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return
  fi
  command -v "$default_name" 2>/dev/null || printf '%s\n' "/usr/local/bin/$default_name"
}

select_pulse_server() {
  if [ -n "${PULSE_SERVER:-}" ]; then
    printf '%s\n' "$PULSE_SERVER"
    return
  fi
  if [ -r /run/droidspaces.env ]; then
    # shellcheck disable=SC1091
    . /run/droidspaces.env || true
    if [ -n "${PULSE_SERVER:-}" ]; then
      printf '%s\n' "$PULSE_SERVER"
      return
    fi
  fi
  printf 'unix:/tmp/.pulse-socket\n'
}

session_pids() {
  ps -eo pid=,stat=,comm=,args= 2>/dev/null |
    awk -v self="$$" '
      $1 == self { next }
      $2 ~ /^Z/ { next }
      index($0, "waylandie-steam-session run") ||
      index($0, "waylandie-steam-session-child") ||
      index($0, "waylandie-steam-arm64") ||
      index($0, "gamescope --backend wayland") ||
      index($0, "waylandie-wayland") ||
      index($0, "wayland-shm-ahb-server") ||
      index($0, "/steamrtarm64/steam") ||
      index($0, "/steamrtarm64/steamwebhelper") ||
      index($0, "steam-runtime-launcher-service") {
        print $1
      }
    ' | sort -n | uniq
}

session_status() {
  if [ -f "$pid_file" ]; then
    pid="$(sed -n '1p' "$pid_file" 2>/dev/null | tr -cd '0-9')"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "session=running pid=$pid log=$log_file"
    else
      echo "session=stale-pidfile pidfile=$pid_file log=$log_file"
    fi
  else
    echo "session=no-pidfile log=$log_file"
  fi
  ps -eo pid,ppid,ni,pri,psr,stat,comm,args 2>/dev/null |
    awk 'index($0, "waylandie-steam") || index($0, "gamescope --backend wayland") || index($0, "/steamrtarm64/steam") || index($0, "wayland-shm-ahb-server") { print }' || true
}

stop_session() {
  mkdir -p "$state_dir"
  pids="$(session_pids || true)"
  if [ -z "$pids" ]; then
    rm -f "$pid_file"
    echo "already-stopped"
    return 0
  fi

  echo "stopping pids=$(printf '%s' "$pids" | tr '\n' ' ')"
  for pid in $pids; do
    kill -TERM "$pid" 2>/dev/null || true
  done

  elapsed=0
  grace="${WAYLANDIE_STEAM_STOP_GRACE_SECONDS:-12}"
  while [ "$elapsed" -lt "$grace" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
    pids="$(session_pids || true)"
    if [ -z "$pids" ]; then
      rm -f "$pid_file"
      echo "stopped after=${elapsed}s"
      return 0
    fi
  done

  echo "forcing pids=$(printf '%s' "$pids" | tr '\n' ' ')"
  for pid in $pids; do
    kill -KILL "$pid" 2>/dev/null || true
  done
  sleep 1
  pids="$(session_pids || true)"
  if [ -n "$pids" ]; then
    echo "ERROR session still has matching pids"
    session_status
    return 1
  fi
  rm -f "$pid_file"
  echo "stopped forced=1"
}

run_session() {
  if [ "${WAYLANDIE_START_DISPLAY:-1}" != "0" ]; then
    start_display="$(find_tool WAYLANDIE_START_DISPLAY_TOOL waylandie-start-display)"
    if [ -x "$start_display" ]; then
      "$start_display" >/dev/null 2>&1 || true
    fi
  fi

  waylandie_run="$(find_tool WAYLANDIE_RUN_TOOL waylandie-run)"
  child="$(find_tool WAYLANDIE_STEAM_SESSION_CHILD waylandie-steam-session-child)"
  if [ ! -x "$waylandie_run" ]; then
    echo "missing waylandie-run: $waylandie_run" >&2
    exit 127
  fi
  if [ ! -x "$child" ]; then
    echo "missing waylandie-steam-session-child: $child" >&2
    exit 127
  fi
  if ! have gamescope; then
    echo "missing gamescope in PATH" >&2
    exit 127
  fi

  width="${WAYLANDIE_WIDTH:-2688}"
  height="${WAYLANDIE_HEIGHT:-1216}"
  refresh="${WAYLANDIE_REFRESH:-144}"
  unfocused_refresh="${WAYLANDIE_UNFOCUSED_REFRESH:-$refresh}"
  xwayland_count="${WAYLANDIE_GAMESCOPE_XWAYLAND_COUNT:-2}"
  stats_path="${WAYLANDIE_GAMESCOPE_STATS_PATH:-$state_dir/gamescope-stats.csv}"
  max_scale="${WAYLANDIE_GAMESCOPE_MAX_SCALE:-1}"

  mkdir -p "$state_dir" /dev/shm
  chmod 1777 /dev/shm 2>/dev/null || true
  export TMPDIR="${TMPDIR:-/tmp}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

  export PULSE_SERVER="$(select_pulse_server)"
  export PULSE_LATENCY_MSEC="${PULSE_LATENCY_MSEC:-20}"
  export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-pulse}"
  export ALSOFT_DRIVERS="${ALSOFT_DRIVERS:-pulse}"
  export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-256/48000}"
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json}"
  export VK_DRIVER_FILES="${VK_DRIVER_FILES:-$VK_ICD_FILENAMES}"
  export MESA_VK_DEVICE_SELECT="${MESA_VK_DEVICE_SELECT:-5143:44050a31}"
  export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE="${MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE:-1}"
  export GAMESCOPE_DRM_RENDER_NODE="${GAMESCOPE_DRM_RENDER_NODE:-/dev/dri/renderD128}"
  export WLR_DRM_DEVICES="${WLR_DRM_DEVICES:-/dev/dri/renderD128}"
  export GAMESCOPE_FORCE_GENERAL_QUEUE="${GAMESCOPE_FORCE_GENERAL_QUEUE:-1}"
  export MESA_LOADER_DRIVER_OVERRIDE="${WAYLANDIE_GAMESCOPE_MESA_DRIVER:-zink}"
  export GALLIUM_DRIVER="${WAYLANDIE_GAMESCOPE_GALLIUM_DRIVER:-$MESA_LOADER_DRIVER_OVERRIDE}"
  export LIBGL_KOPPER_DISABLE="${LIBGL_KOPPER_DISABLE:-false}"
  export LIBGL_KOPPER_DRI2="${LIBGL_KOPPER_DRI2:-true}"
  export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-mesa}"
  export __EGL_VENDOR_LIBRARY_FILENAMES="${__EGL_VENDOR_LIBRARY_FILENAMES:-/usr/share/glvnd/egl_vendor.d/50_mesa.json}"
  export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
  unset LIBGL_ALWAYS_SOFTWARE

  export CLIENT_MODE=external
  export CLIENT_WIDTH="$width"
  export CLIENT_HEIGHT="$height"
  export FRAME_COUNT="${FRAME_COUNT:-2147483647}"
  export FRAME_INTERVAL_MS="${FRAME_INTERVAL_MS:-6.944}"
  export SERVER_TIMEOUT_MS="${SERVER_TIMEOUT_MS:-2147483647}"
  export ACCEPT_CLIENT_COMPLETE=1
  export CLEAR_AHB_OUTSIDE=0
  export BRIDGE_LOCAL_SOCKET="${BRIDGE_LOCAL_SOCKET:-waylandie.display.bridge.v1}"
  export WAYLANDIE_ANDROID_VK_DRIVER="${WAYLANDIE_ANDROID_VK_DRIVER:-vulkan.waylandie.a8xx.so}"

  gamescope_args=(
    gamescope
    --backend wayland
    -f
    -e
    --expose-wayland
    --xwayland-count "$xwayland_count"
    --keep-alive
    --prefer-vk-device "${WAYLANDIE_GAMESCOPE_PREFER_VK_DEVICE:-5143:44050a31}"
    -W "$width"
    -H "$height"
    -w "$width"
    -h "$height"
    -r "$refresh"
    -o "$unfocused_refresh"
    --stats-path "$stats_path"
  )

  if [ -n "$max_scale" ] && gamescope --help 2>&1 | grep -q -- '--max-scale'; then
    gamescope_args+=(--max-scale "$max_scale")
  fi
  if [ "${WAYLANDIE_GAMESCOPE_FORCE_WINDOWS_FULLSCREEN:-1}" != "0" ]; then
    gamescope_args+=(--force-windows-fullscreen)
  fi
  if [ "${WAYLANDIE_GAMESCOPE_IMMEDIATE_FLIPS:-0}" != "0" ] && gamescope --help 2>&1 | grep -q -- '--immediate-flips'; then
    gamescope_args+=(--immediate-flips)
  fi
  if [ "${WAYLANDIE_GAMESCOPE_FORCE_COMPOSITION:-0}" != "0" ] && gamescope --help 2>&1 | grep -q -- '--force-composition'; then
    gamescope_args+=(--force-composition)
  fi
  if [ "${WAYLANDIE_GAMESCOPE_ADAPTIVE_SYNC:-0}" = "1" ] && gamescope --help 2>&1 | grep -q -- '--adaptive-sync'; then
    gamescope_args+=(--adaptive-sync)
  fi
  if [ "${WAYLANDIE_GAMESCOPE_MANGOAPP:-0}" = "1" ] && gamescope --help 2>&1 | grep -q -- '--mangoapp'; then
    gamescope_args+=(--mangoapp)
  fi

  echo "waylandie-steam-session refresh=$refresh size=${width}x${height} xwayland-count=$xwayland_count pulse=$PULSE_SERVER stats=$stats_path"
  exec "$waylandie_run" "${gamescope_args[@]}" -- "$child" "$@"
}

start_session() {
  mkdir -p "$state_dir"
  if [ -f "$pid_file" ]; then
    old_pid="$(sed -n '1p' "$pid_file" 2>/dev/null | tr -cd '0-9')"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      echo "already-running pid=$old_pid log=$log_file"
      return 0
    fi
  fi

  nohup "$0" run "$@" >"$log_file" 2>&1 &
  pid="$!"
  echo "$pid" > "$pid_file"
  sleep "${WAYLANDIE_STEAM_START_CHECK_SECONDS:-8}"
  if kill -0 "$pid" 2>/dev/null; then
    echo "started pid=$pid log=$log_file"
    return 0
  fi
  echo "ERROR session exited during startup; recent log:" >&2
  tail -n 160 "$log_file" >&2 || true
  return 1
}

case "$command_name" in
  start) start_session "$@" ;;
  restart) stop_session || true; start_session "$@" ;;
  stop) stop_session ;;
  status) session_status ;;
  run) run_session "$@" ;;
  -h|--help|help) usage ;;
  *)
    echo "unknown command: $command_name" >&2
    usage >&2
    exit 2
    ;;
esac
