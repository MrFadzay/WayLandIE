#!/usr/bin/env bash
set -euo pipefail

home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
steam_root="${WAYLANDIE_STEAM_ROOT:-$home_dir/.local/share/Steam}"
steam_client="${WAYLANDIE_STEAM_ARM64_CLIENT:-$(command -v waylandie-steam-arm64 2>/dev/null || true)}"
steam_client="${steam_client:-/usr/local/bin/waylandie-steam-arm64}"

export STEAM_GAMESCOPE_FAST_CEF="${STEAM_GAMESCOPE_FAST_CEF:-1}"
export WAYLANDIE_STEAM_CEF_PATH="${WAYLANDIE_STEAM_CEF_PATH:-x11}"
export WAYLANDIE_STEAM_CEF_X11_GL_MODE="${WAYLANDIE_STEAM_CEF_X11_GL_MODE:-angle-vulkan}"
export WAYLANDIE_STEAM_CEF_DISABLE_GBM_EXPORT="${WAYLANDIE_STEAM_CEF_DISABLE_GBM_EXPORT:-1}"
export WAYLANDIE_STEAM_CEF_FORCE_GPU="${WAYLANDIE_STEAM_CEF_FORCE_GPU:-1}"
export WAYLANDIE_STEAM_UI_WAYLAND_ONLY="${WAYLANDIE_STEAM_UI_WAYLAND_ONLY:-0}"
export GAMESCOPE_WAYLAND_DISPLAY="${GAMESCOPE_WAYLAND_DISPLAY:-${WAYLAND_DISPLAY:-gamescope-0}}"
export MESA_LOADER_DRIVER_OVERRIDE="${WAYLANDIE_STEAM_UI_MESA_DRIVER:-zink}"
export GALLIUM_DRIVER="${WAYLANDIE_STEAM_UI_GALLIUM_DRIVER:-$MESA_LOADER_DRIVER_OVERRIDE}"
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json}"
export VK_DRIVER_FILES="${VK_DRIVER_FILES:-$VK_ICD_FILENAMES}"
export MESA_VK_DEVICE_SELECT="${MESA_VK_DEVICE_SELECT:-5143:44050a31}"
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE="${MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE:-1}"
export LIBGL_KOPPER_DISABLE="${WAYLANDIE_STEAM_UI_KOPPER_DISABLE:-false}"
export LIBGL_KOPPER_DRI2="${LIBGL_KOPPER_DRI2:-true}"
export __EGL_VENDOR_LIBRARY_FILENAMES="${__EGL_VENDOR_LIBRARY_FILENAMES:-/usr/share/glvnd/egl_vendor.d/50_mesa.json}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"
export EGL_PLATFORM="${EGL_PLATFORM:-x11}"
export SDL_VIDEO_X11_XRANDR=0
export SDL_VIDEO_X11_XINERAMA=0
export SDL_VIDEO_X11_XVIDMODE=0
export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/.pulse-socket}"
export PULSE_LATENCY_MSEC="${PULSE_LATENCY_MSEC:-20}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-pulse}"
export ALSOFT_DRIVERS="${ALSOFT_DRIVERS:-pulse}"
export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-256/48000}"
unset LIBGL_ALWAYS_SOFTWARE

if [ "${WAYLANDIE_STEAM_REJECT_SOFTWARE_FALLBACK:-1}" != "0" ]; then
  if [ "${MESA_LOADER_DRIVER_OVERRIDE:-}" = "llvmpipe" ] \
      || [ "${MESA_LOADER_DRIVER_OVERRIDE:-}" = "lavapipe" ] \
      || [ "${MESA_LOADER_DRIVER_OVERRIDE:-}" = "softpipe" ] \
      || [ "${GALLIUM_DRIVER:-}" = "llvmpipe" ] \
      || [ "${GALLIUM_DRIVER:-}" = "lavapipe" ] \
      || [ "${GALLIUM_DRIVER:-}" = "softpipe" ]; then
    echo "Refusing Steam child launch with software GL fallback selected" >&2
    exit 2
  fi
  case "${VK_ICD_FILENAMES:-}:${VK_DRIVER_FILES:-}" in
    *lvp*|*lavapipe*|*swiftshader*)
      echo "Refusing Steam child launch with software Vulkan ICD selected" >&2
      exit 2
      ;;
  esac
fi

if [ -e /usr/local/lib/steam-exec-env-shim.so ]; then
  export LD_PRELOAD="/usr/local/lib/steam-exec-env-shim.so${LD_PRELOAD:+:$LD_PRELOAD}"
  export STEAM_EXEC_SHIM_DEBUG="${STEAM_EXEC_SHIM_DEBUG:-1}"
  export STEAM_EXEC_SHIM_LOG="${STEAM_EXEC_SHIM_LOG:-$home_dir/steam-exec-env-shim.log}"
fi

if command -v renice >/dev/null 2>&1; then
  renice -n "${WAYLANDIE_STEAM_NICE:--15}" -p $$ >/dev/null 2>&1 || true
fi

steam_process_alive() {
  ps -eo stat=,comm= |
    awk '$1 !~ /Z/ && ($2=="steam" || $2=="steamwebhelper" || $2=="steam-runtime-l" || $2=="reaper") {found=1} END {exit found ? 0 : 1}'
}

sync_steam_beta_file() {
  local channel="$1"
  [ "${WAYLANDIE_STEAM_SYNC_BETA_FILE:-1}" != "0" ] || return
  [ -n "$channel" ] || return
  mkdir -p "$steam_root/package" "$home_dir/.steam/root/package" "$home_dir/.steam/steam/package"
  printf '%s\n' "$channel" > "$steam_root/package/beta"
  printf '%s\n' "$channel" > "$home_dir/.steam/root/package/beta"
  printf '%s\n' "$channel" > "$home_dir/.steam/steam/package/beta"
}

reset_webhelper_gpu_state() {
  [ "${WAYLANDIE_STEAM_RESET_CEF_GPU_STATE:-1}" != "0" ] || return
  local cache_root="$steam_root/config/htmlcache"
  [ -d "$cache_root" ] || return 0

  rm -rf \
    "$cache_root/Default/GPUCache" \
    "$cache_root/Default/DawnWebGPUCache" \
    "$cache_root/Default/DawnGraphiteCache" \
    "$cache_root/GrShaderCache" \
    "$cache_root/GraphiteDawnCache" \
    "$cache_root/ShaderCache" 2>/dev/null || true
  find "$cache_root" "$cache_root/Default" -maxdepth 1 -name ".com.valvesoftware.Steam.*" -delete 2>/dev/null || true
}

selected_beta="${WAYLANDIE_STEAM_CLIENT_BETA:-publicbeta}"
steam_launch_args=()
if [ -n "$selected_beta" ]; then
  sync_steam_beta_file "$selected_beta"
  steam_launch_args+=(-clientbeta "$selected_beta")
fi
if [ "${WAYLANDIE_STEAM_SKIP_BOOTSTRAP_UPDATE:-1}" != "0" ]; then
  steam_launch_args+=(-skipinitialbootstrap -nobootstrapperupdate -noverifyfiles)
fi
if [ "${WAYLANDIE_STEAM_BIGPICTURE:-1}" != "0" ]; then
  steam_launch_args+=(-gamepadui)
fi
if [ "${WAYLANDIE_STEAM_DECK_FLAGS:-0}" != "0" ]; then
  steam_launch_args+=(-steamdeck -steamos3 -steampal)
fi

if [ ! -x "$steam_client" ]; then
  echo "missing Steam ARM64 client wrapper: $steam_client" >&2
  exit 127
fi

reset_webhelper_gpu_state

echo "waylandie-steam-session-child beta=${selected_beta:-none} bigpicture=${WAYLANDIE_STEAM_BIGPICTURE:-1} deck-flags=${WAYLANDIE_STEAM_DECK_FLAGS:-0} cef-path=${WAYLANDIE_STEAM_CEF_PATH} driver=${MESA_LOADER_DRIVER_OVERRIDE} pulse=${PULSE_SERVER} pulse-latency-ms=${PULSE_LATENCY_MSEC}"
"$steam_client" "${steam_launch_args[@]}" "$@" &
steam_bootstrap_pid=$!
bootstrap_status=0
start_time="$(date +%s)"
last_seen="$start_time"
min_hold_seconds="${WAYLANDIE_STEAM_CHILD_MIN_HOLD_SECONDS:-180}"
idle_grace_seconds="${WAYLANDIE_STEAM_CHILD_IDLE_GRACE_SECONDS:-45}"

while :; do
  now="$(date +%s)"
  if kill -0 "$steam_bootstrap_pid" 2>/dev/null; then
    last_seen="$now"
    sleep 1
    continue
  fi

  wait "$steam_bootstrap_pid" 2>/dev/null || bootstrap_status=$?

  if steam_process_alive; then
    last_seen="$now"
    sleep 2
    continue
  fi

  if [ $((now - start_time)) -lt "$min_hold_seconds" ]; then
    sleep 1
    continue
  fi
  if [ $((now - last_seen)) -lt "$idle_grace_seconds" ]; then
    sleep 1
    continue
  fi
  break
done

exit "$bootstrap_status"
