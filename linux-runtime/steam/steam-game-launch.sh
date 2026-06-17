#!/usr/bin/env bash
set -euo pipefail

appid="${1:-${SteamAppId:-${SteamGameId:-}}}"
if [ -z "$appid" ]; then
  echo "Usage: waylandie-steam-game-launch APPID %command%" >&2
  exit 2
fi
shift || true
if [ "$#" -eq 0 ]; then
  echo "ERROR: Steam %command% is missing" >&2
  exit 2
fi

home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
cache_home="${XDG_CACHE_HOME:-$home_dir/.cache}"
steam_root="${WAYLANDIE_STEAM_ROOT:-$home_dir/.local/share/Steam}"
root="${WAYLANDIE_STEAM_PROFILE_ROOT:-$config_home/waylandie/steam}"
game_root="$root/games/$appid"
game_file="$game_root/game.env"
profile_file="${WAYLANDIE_STEAM_PROFILE_FILE:-$game_root/active.env}"

if [ -r "$game_file" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$game_file"
  set +a
fi

if [ -r "$profile_file" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$profile_file"
  set +a
fi

export SteamAppId="${SteamAppId:-$appid}"
export SteamGameId="${SteamGameId:-$appid}"
export STEAM_COMPAT_APP_ID="${STEAM_COMPAT_APP_ID:-$appid}"
export WAYLANDIE_STEAM_PROFILE_FILE="$profile_file"
export WAYLANDIE_STEAM_PROFILE_ID="${WAYLANDIE_STEAM_PROFILE_ID:-manual-default}"
export PROTON_NO_NTSYNC="${PROTON_NO_NTSYNC:-0}"
export PROTON_USE_NTSYNC="${PROTON_USE_NTSYNC:-1}"
export WINEDEBUG="${WINEDEBUG:--all}"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-none}"
export DXVK_STATE_CACHE="${DXVK_STATE_CACHE:-1}"
export FEX_APP_CONFIG_LOCATION="${FEX_APP_CONFIG_LOCATION:-$steam_root/compatibilitytools.d/Proton11ARM/files/share/fex-emu/}"

if [ -n "${WAYLANDIE_STEAM_DXVK_DLL_DIR:-}" ] && [ -z "${WAYLANDIE_METRO_DXVK_DLL_DIR:-}" ]; then
  export WAYLANDIE_METRO_DXVK_DLL_DIR="$WAYLANDIE_STEAM_DXVK_DLL_DIR"
fi
if [ -n "${WAYLANDIE_STEAM_GAME_DIR:-}" ] && [ -z "${WAYLANDIE_METRO_GAME_DIR:-}" ]; then
  export WAYLANDIE_METRO_GAME_DIR="$WAYLANDIE_STEAM_GAME_DIR"
fi
if [ -n "${WAYLANDIE_STEAM_CPUSET:-}" ]; then
  export WAYLANDIE_METRO_CPUSET="$WAYLANDIE_STEAM_CPUSET"
fi
if [ -n "${WAYLANDIE_STEAM_UCLAMP_MIN:-}" ]; then
  export WAYLANDIE_METRO_UCLAMP_MIN="$WAYLANDIE_STEAM_UCLAMP_MIN"
fi
if [ -n "${WAYLANDIE_STEAM_UCLAMP_MAX:-}" ]; then
  export WAYLANDIE_METRO_UCLAMP_MAX="$WAYLANDIE_STEAM_UCLAMP_MAX"
fi
if [ -n "${WAYLANDIE_STEAM_NICE:-}" ]; then
  export WAYLANDIE_METRO_NICE="$WAYLANDIE_STEAM_NICE"
fi
if [ -n "${WAYLANDIE_STEAM_MONITOR_SECONDS:-}" ]; then
  export WAYLANDIE_METRO_MONITOR_SECONDS="$WAYLANDIE_STEAM_MONITOR_SECONDS"
fi

scrub_steam_ui_env_for_game() {
  unset LD_PRELOAD
  unset MESA_LOADER_DRIVER_OVERRIDE
  unset GALLIUM_DRIVER
  unset LIBGL_KOPPER_DISABLE
  unset LIBGL_KOPPER_DRI2
  unset STEAM_UI_DRIVER_LABEL
  unset STEAM_UI_MESA_DRIVER
  unset STEAM_UI_GALLIUM_DRIVER
  unset STEAM_UI_ZINK_DESCRIPTORS
  unset STEAM_UI_ZINK_DEBUG
  unset WAYLANDIE_STEAM_UI_MESA_DRIVER
  unset WAYLANDIE_STEAM_UI_GALLIUM_DRIVER
  unset WAYLANDIE_STEAM_UI_WAYLAND_ONLY
  unset WAYLANDIE_STEAM_CEF_PATH
  unset WAYLANDIE_STEAM_EGL_PLATFORM
  unset WAYLANDIE_STEAM_X11_CEF_GL
  unset WAYLANDIE_STEAM_X11_CEF_ANGLE
  unset WAYLANDIE_STEAM_X11_CEF_FEATURES
}

apply_helper_gl_policy() {
  if [ "${WAYLANDIE_STEAM_HELPER_GL_SOFTWARE:-0}" = "1" ]; then
    export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
    export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"
    export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
    export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-mesa}"
  fi
}

export_qcom_pressure_vessel_libs() {
  local qcom_lib_dir=""
  if [ -n "${QCOM_VULKAN_ICD_LIB:-}" ]; then
    qcom_lib_dir="$(dirname "$QCOM_VULKAN_ICD_LIB")"
  fi
  [ -n "$qcom_lib_dir" ] && [ -d "$qcom_lib_dir" ] || return 0
  case ":${PRESSURE_VESSEL_APP_LD_LIBRARY_PATH:-}:" in
    *:"$qcom_lib_dir":*) ;;
    *) export PRESSURE_VESSEL_APP_LD_LIBRARY_PATH="$qcom_lib_dir${PRESSURE_VESSEL_APP_LD_LIBRARY_PATH:+:$PRESSURE_VESSEL_APP_LD_LIBRARY_PATH}" ;;
  esac
  case ":${SYSTEM_LD_LIBRARY_PATH:-}:" in
    *:"$qcom_lib_dir":*) ;;
    *) export SYSTEM_LD_LIBRARY_PATH="$qcom_lib_dir${SYSTEM_LD_LIBRARY_PATH:+:$SYSTEM_LD_LIBRARY_PATH}" ;;
  esac
  case ":${LD_LIBRARY_PATH:-}:" in
    *:"$qcom_lib_dir":*) ;;
    *) export LD_LIBRARY_PATH="$qcom_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
  esac
}

game_launch_log="${WAYLANDIE_STEAM_GAME_LAUNCH_LOG:-}"
if [ -z "$game_launch_log" ] && [ "${WAYLANDIE_STEAM_GAME_LAUNCH_CAPTURE:-0}" = "1" ]; then
  game_launch_log="$cache_home/waylandie/steam-game-launch-${appid}.log"
fi

enter_game_wayland_screen() {
  local screen_cmd="${WAYLANDIE_STEAM_GAME_WAYLAND_SCREEN_CMD:-}"
  local screen_env="${WAYLANDIE_STEAM_GAME_WAYLAND_SCREEN_ENV:-${XDG_RUNTIME_DIR:-/tmp}/waylandie-game-wayland-screen/env}"

  if [ "${WAYLANDIE_STEAM_GAME_WAYLAND_SCREEN:-0}" != "1" ] && [ -z "$screen_cmd" ]; then
    return 0
  fi

  screen_cmd="${screen_cmd:-$(command -v waylandie-game-wayland-screen 2>/dev/null || true)}"
  if [ ! -x "$screen_cmd" ]; then
    printf 'ERROR missing game Wayland screen helper: %s\n' "$screen_cmd" >&2
    return 65
  fi

  "$screen_cmd" start >&2
  if [ ! -r "$screen_env" ]; then
    printf 'ERROR game Wayland screen env missing: %s\n' "$screen_env" >&2
    return 66
  fi

  # shellcheck disable=SC1090
  . "$screen_env"
  export DISPLAY WAYLAND_DISPLAY GAMESCOPE_WAYLAND_DISPLAY XDG_RUNTIME_DIR
  export PULSE_SERVER PULSE_LATENCY_MSEC SDL_AUDIODRIVER ALSOFT_DRIVERS PIPEWIRE_LATENCY
}

log_game_launch() {
  [ -n "$game_launch_log" ] || return 0
  mkdir -p "$(dirname "$game_launch_log")"
  {
    echo
    echo "== waylandie-steam-game-launch $(date -u +%Y-%m-%dT%H:%M:%SZ) appid=$appid profile=${WAYLANDIE_STEAM_PROFILE_ID:-unset} =="
    echo "DISPLAY=${DISPLAY:-unset}"
    echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
    echo "GAMESCOPE_WAYLAND_DISPLAY=${GAMESCOPE_WAYLAND_DISPLAY:-unset}"
    echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
    echo "PROTON_USE_NTSYNC=${PROTON_USE_NTSYNC:-unset}"
    echo "PROTON_NO_NTSYNC=${PROTON_NO_NTSYNC:-unset}"
    echo "VK_DRIVER_FILES=${VK_DRIVER_FILES:-unset}"
    echo "QCOM_VULKAN_ICD_LIB=${QCOM_VULKAN_ICD_LIB:-unset}"
    echo "VK_LAYER_PATH=${VK_LAYER_PATH:-unset}"
    echo "VK_INSTANCE_LAYERS=${VK_INSTANCE_LAYERS:-unset}"
    echo "GBM_BACKENDS_PATH=${GBM_BACKENDS_PATH:-unset}"
    echo "GBM_BACKEND=${GBM_BACKEND:-unset}"
    echo "LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-unset}"
    echo "MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-unset}"
    echo "GALLIUM_DRIVER=${GALLIUM_DRIVER:-unset}"
    echo "__GLX_VENDOR_LIBRARY_NAME=${__GLX_VENDOR_LIBRARY_NAME:-unset}"
    echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-unset}"
    echo "PRESSURE_VESSEL_APP_LD_LIBRARY_PATH=${PRESSURE_VESSEL_APP_LD_LIBRARY_PATH:-unset}"
    echo "SYSTEM_LD_LIBRARY_PATH=${SYSTEM_LD_LIBRARY_PATH:-unset}"
    echo "DXVK_CONFIG_FILE=${DXVK_CONFIG_FILE:-unset}"
    echo "DXVK_LOG_LEVEL=${DXVK_LOG_LEVEL:-unset}"
    echo "PROTON_LOG=${PROTON_LOG:-unset}"
    echo "PROTON_LOG_DIR=${PROTON_LOG_DIR:-unset}"
    printf 'command='
    printf '%q ' "${base_cmd[@]}" "$@"
    printf '\n'
  } >>"$game_launch_log" 2>&1
}

stage_dxvk_dlls() {
  local src_dir="${WAYLANDIE_STEAM_DXVK_DLL_DIR:-${WAYLANDIE_METRO_DXVK_DLL_DIR:-}}"
  local dlls="${WAYLANDIE_STEAM_DXVK_DLLS:-d3d11.dll dxgi.dll}"
  local prefix_dir="$steam_root/steamapps/compatdata/$appid/pfx/drive_c/windows/system32"
  local prefix_backup="$root/backups/$appid/prefix-system32"
  local game_dir="${WAYLANDIE_STEAM_GAME_DIR:-${WAYLANDIE_METRO_GAME_DIR:-}}"
  local game_backup="$root/backups/$appid/game-dir"
  local dll arg

  [ -n "$src_dir" ] || return 0
  for dll in $dlls; do
    if [ ! -r "$src_dir/$dll" ]; then
      printf 'ERROR missing DXVK profile file: %s\n' "$src_dir/$dll" >&2
      return 64
    fi
  done

  mkdir -p "$prefix_backup"
  for dll in $dlls; do
    if [ -r "$prefix_dir/$dll" ] && [ ! -r "$prefix_backup/$dll" ]; then
      cp -a "$prefix_dir/$dll" "$prefix_backup/$dll"
    fi
    if [ -d "$prefix_dir" ] && ! cmp -s "$src_dir/$dll" "$prefix_dir/$dll" 2>/dev/null; then
      cp -a "$src_dir/$dll" "$prefix_dir/$dll"
    fi
  done

  if [ -z "$game_dir" ]; then
    for arg in "$@"; do
      case "$arg" in
        */*.exe|*/*.EXE)
          game_dir="$(dirname "$arg")"
          break
          ;;
      esac
    done
  fi

  if [ -n "$game_dir" ] && [ -d "$game_dir" ]; then
    mkdir -p "$game_backup"
    for dll in $dlls; do
      if [ -r "$game_dir/$dll" ] && [ ! -r "$game_backup/$dll" ]; then
        cp -a "$game_dir/$dll" "$game_backup/$dll"
      fi
      if ! cmp -s "$src_dir/$dll" "$game_dir/$dll" 2>/dev/null; then
        cp -a "$src_dir/$dll" "$game_dir/$dll"
      fi
    done
  fi
}

apply_boost_once() {
  local boost_tool="${WAYLANDIE_STEAM_BOOST_TOOL:-$(command -v waylandie-steam-game-boost 2>/dev/null || true)}"
  [ -x "$boost_tool" ] || return 0
  WAYLANDIE_STEAM_CPUSET="${WAYLANDIE_STEAM_CPUSET:-${WAYLANDIE_METRO_CPUSET:-4-7}}" \
  WAYLANDIE_STEAM_UCLAMP_MIN="${WAYLANDIE_STEAM_UCLAMP_MIN:-${WAYLANDIE_METRO_UCLAMP_MIN:-768}}" \
  WAYLANDIE_STEAM_UCLAMP_MAX="${WAYLANDIE_STEAM_UCLAMP_MAX:-${WAYLANDIE_METRO_UCLAMP_MAX:-1024}}" \
  WAYLANDIE_STEAM_NICE="${WAYLANDIE_STEAM_NICE:-${WAYLANDIE_METRO_NICE:--10}}" \
    "$boost_tool" "$appid" "${WAYLANDIE_STEAM_PROCESS_NAME:-}" >/dev/null 2>&1 || true
}

scrub_steam_ui_env_for_game
apply_helper_gl_policy
export_qcom_pressure_vessel_libs
enter_game_wayland_screen
stage_dxvk_dlls "$@"

base_cmd=()
if command -v uclampset >/dev/null 2>&1; then
  base_cmd+=(uclampset -m "${WAYLANDIE_STEAM_UCLAMP_MIN:-${WAYLANDIE_METRO_UCLAMP_MIN:-768}}" -M "${WAYLANDIE_STEAM_UCLAMP_MAX:-${WAYLANDIE_METRO_UCLAMP_MAX:-1024}}")
fi
if command -v ionice >/dev/null 2>&1; then
  base_cmd+=(ionice -c 2 -n 0)
fi
if command -v taskset >/dev/null 2>&1; then
  base_cmd+=(taskset -c "${WAYLANDIE_STEAM_CPUSET:-${WAYLANDIE_METRO_CPUSET:-4-7}}")
fi
if command -v nice >/dev/null 2>&1; then
  base_cmd+=(nice -n "${WAYLANDIE_STEAM_NICE:-${WAYLANDIE_METRO_NICE:--10}}")
fi
if command -v mangohud >/dev/null 2>&1 && [ "${MANGOHUD:-1}" != "0" ]; then
  export MANGOHUD=1
  base_cmd+=(mangohud)
fi

log_game_launch "$@"

monitor_perf() {
  local seconds="${WAYLANDIE_STEAM_MONITOR_SECONDS:-${WAYLANDIE_METRO_MONITOR_SECONDS:-21600}}"
  local end=$((SECONDS + seconds))
  while [ "$SECONDS" -lt "$end" ]; do
    apply_boost_once
    sleep 1
  done
}

monitor_perf &
monitor_pid=$!
if [ "${WAYLANDIE_STEAM_GAME_LAUNCH_CAPTURE:-0}" = "1" ] && [ -n "$game_launch_log" ]; then
  "${base_cmd[@]}" "$@" >>"$game_launch_log" 2>&1 &
else
  "${base_cmd[@]}" "$@" &
fi
launch_pid=$!
wait "$launch_pid"
status=$?
kill "$monitor_pid" >/dev/null 2>&1 || true
wait "$monitor_pid" 2>/dev/null || true
exit "$status"
