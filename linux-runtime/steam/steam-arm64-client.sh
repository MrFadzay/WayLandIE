#!/usr/bin/env bash
set -euo pipefail

home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
steam_root="${WAYLANDIE_STEAM_ROOT:-$home_dir/.local/share/Steam}"
steam_bin="${STEAM_BIN:-$steam_root/steamrtarm64/steam}"
runtime_service="${WAYLANDIE_STEAM_RUNTIME_SERVICE:-$steam_root/compatibilitytools.d/SteamLinuxRuntime_4-arm64/pressure-vessel/bin}"
session_env="${WAYLANDIE_STEAM_SESSION_ENV:-$config_home/waylandie/steam/session.env}"

if [ -r "$session_env" ]; then
  # shellcheck disable=SC1090
  . "$session_env"
fi
if [ -r /run/droidspaces.env ]; then
  # shellcheck disable=SC1091
  . /run/droidspaces.env || true
fi

export DISPLAY="${DISPLAY:-:5.0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
export PATH="$steam_root/steamrtarm64:$runtime_service:/usr/local/bin:/usr/bin:/bin:$PATH"

export NO_AT_BRIDGE=1
export GTK_USE_PORTAL=0
export GIO_USE_VFS=local
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}"
export EGL_PLATFORM="${EGL_PLATFORM:-wayland}"
export STEAM_GAMESCOPE_FAST_CEF="${STEAM_GAMESCOPE_FAST_CEF:-1}"
export MESA_LOADER_DRIVER_OVERRIDE="${WAYLANDIE_STEAM_UI_MESA_DRIVER:-${MESA_LOADER_DRIVER_OVERRIDE:-zink}}"
export GALLIUM_DRIVER="${WAYLANDIE_STEAM_UI_GALLIUM_DRIVER:-${GALLIUM_DRIVER:-$MESA_LOADER_DRIVER_OVERRIDE}}"
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json}"
export VK_DRIVER_FILES="${VK_DRIVER_FILES:-$VK_ICD_FILENAMES}"
export MESA_VK_DEVICE_SELECT="${MESA_VK_DEVICE_SELECT:-5143:44050a31}"
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE="${MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE:-1}"
export LIBGL_KOPPER_DISABLE="${LIBGL_KOPPER_DISABLE:-false}"
export LIBGL_KOPPER_DRI2="${LIBGL_KOPPER_DRI2:-true}"
export __EGL_VENDOR_LIBRARY_FILENAMES="${__EGL_VENDOR_LIBRARY_FILENAMES:-/usr/share/glvnd/egl_vendor.d/50_mesa.json}"

export SDL_VIDEO_X11_XRANDR=0
export SDL_VIDEO_X11_XINERAMA=0
export SDL_VIDEO_X11_XVIDMODE=0
export GDK_SCALE=1
export GDK_DPI_SCALE=1
export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/.pulse-socket}"
export PULSE_LATENCY_MSEC="${PULSE_LATENCY_MSEC:-20}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-pulse}"
export ALSOFT_DRIVERS="${ALSOFT_DRIVERS:-pulse}"
export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-256/48000}"

mkdir -p "$XDG_RUNTIME_DIR" /dev/shm
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 1777 /dev/shm 2>/dev/null || true

if [ "${WAYLANDIE_STEAM_DISABLE_GTK_PORTAL:-1}" != "0" ]; then
  portal_config_root="${WAYLANDIE_STEAM_PORTAL_CONFIG_ROOT:-/tmp/waylandie-steam-xdg-config}"
  portal_desktop="${WAYLANDIE_STEAM_XDG_DESKTOP:-waylandiegamescope}"
  mkdir -p "$portal_config_root/xdg-desktop-portal"
  cat >"$portal_config_root/xdg-desktop-portal/${portal_desktop}-portals.conf" <<EOFPORTALS
[preferred]
default=none
EOFPORTALS
  export XDG_CURRENT_DESKTOP="$portal_desktop"
  case ":${XDG_CONFIG_DIRS:-/etc/xdg}:" in
    *":$portal_config_root:"*) ;;
    *) export XDG_CONFIG_DIRS="$portal_config_root:${XDG_CONFIG_DIRS:-/etc/xdg}" ;;
  esac
fi

pkill -f xdg-desktop-portal 2>/dev/null || true

if [ "${1:-}" != "--inside-dbus" ]; then
  unset DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER
  if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- "$0" --inside-dbus "$@"
  fi
fi
[ "${1:-}" = "--inside-dbus" ] && shift

rm -rf "$steam_root/steamrtarm32"
ln -s "$steam_root/steamrtarm64" "$steam_root/steamrtarm32" 2>/dev/null || true

steam_args=(
  -no-cef-sandbox
  -cef-disable-dev-shm-usage
  -cef-no-zygote
  --no-zygote
  --disable-gpu-sandbox
  --disable-software-rasterizer
  -cef-ignore-gpu-blocklist
  -cef-disable-software-rasterizer
  -cef-enable-gpu-rasterization
)

if [ "${WAYLANDIE_STEAM_CEF_FORCE_GPU:-1}" != "0" ]; then
  steam_args+=(-cef-force-gpu)
fi

if [ "${WAYLANDIE_STEAM_CEF_DISABLE_GBM_EXPORT:-0}" = "1" ]; then
  steam_args+=(
    -cef-disable-native-gpu-memory-buffers
    -cef-disable-gpu-memory-buffer-compositor-resources
    -cef-disable-gpu-memory-buffer-video-frames
    -cef-disable-zero-copy
  )
fi

case "${WAYLANDIE_STEAM_CEF_PATH:-x11}" in
  auto-wayland)
    steam_args+=(
      -cef-ozone-platform-hint=auto
      -cef-enable-native-gpu-memory-buffers
      -cef-enable-zero-copy
      -cef-use-gl=angle
      -cef-use-angle=gl-egl
      -cef-use-cmd-decoder=validating
      -cef-enable-features=UseOzonePlatform,WaylandWindowDecorations
    )
    ;;
  wayland)
    steam_args+=(
      -cef-ozone-platform=wayland
      -cef-enable-native-gpu-memory-buffers
      -cef-enable-zero-copy
      -cef-use-gl=angle
      -cef-use-angle=gl-egl
      -cef-use-cmd-decoder=validating
      -cef-enable-features=UseOzonePlatform,WaylandWindowDecorations
    )
    ;;
  x11)
    steam_args+=(-cef-ozone-platform=x11)
    case "${WAYLANDIE_STEAM_CEF_X11_GL_MODE:-angle-vulkan}" in
      angle-vulkan)
        steam_args+=(
          -cef-use-gl=angle
          -cef-use-angle=vulkan
          -cef-use-cmd-decoder=validating
          -cef-enable-features=Vulkan,DefaultANGLEVulkan,VulkanFromANGLE
        )
        ;;
      desktop)
        steam_args+=(-cef-use-gl=desktop -cef-use-cmd-decoder=validating)
        ;;
      egl)
        steam_args+=(-cef-use-gl=egl -cef-use-cmd-decoder=validating)
        ;;
      angle-gl)
        steam_args+=(-cef-use-gl=angle -cef-use-angle=gl -cef-use-cmd-decoder=validating)
        ;;
      *)
        echo "Unsupported WAYLANDIE_STEAM_CEF_X11_GL_MODE=${WAYLANDIE_STEAM_CEF_X11_GL_MODE:-}" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "Unsupported WAYLANDIE_STEAM_CEF_PATH=${WAYLANDIE_STEAM_CEF_PATH:-}" >&2
    exit 2
    ;;
esac

if [ "${WAYLANDIE_STEAM_REJECT_SOFTWARE_FALLBACK:-1}" != "0" ]; then
  if [ "${LIBGL_ALWAYS_SOFTWARE:-0}" = "1" ] \
      || [ "${MESA_LOADER_DRIVER_OVERRIDE:-}" = "llvmpipe" ] \
      || [ "${MESA_LOADER_DRIVER_OVERRIDE:-}" = "lavapipe" ] \
      || [ "${MESA_LOADER_DRIVER_OVERRIDE:-}" = "softpipe" ] \
      || [ "${MESA_LOADER_DRIVER_OVERRIDE:-}" = "swrast" ] \
      || [ "${GALLIUM_DRIVER:-}" = "llvmpipe" ] \
      || [ "${GALLIUM_DRIVER:-}" = "lavapipe" ] \
      || [ "${GALLIUM_DRIVER:-}" = "softpipe" ] \
      || [ "${GALLIUM_DRIVER:-}" = "swrast" ]; then
    echo "Refusing Steam hardware launch with software GL fallback enabled" >&2
    exit 2
  fi
  case "${VK_ICD_FILENAMES:-}:${VK_DRIVER_FILES:-}" in
    *lvp*|*lavapipe*|*swiftshader*)
      echo "Refusing Steam hardware launch with software Vulkan ICD selected" >&2
      exit 2
      ;;
  esac
fi

steam_args+=(-forcedesktopscaling "${WAYLANDIE_STEAM_DESKTOP_SCALING:-1.0}")

if [ -n "${WAYLANDIE_STEAM_OPEN_URI:-steam://open/bigpicture}" ]; then
  steam_args+=("${WAYLANDIE_STEAM_OPEN_URI:-steam://open/bigpicture}")
fi

if [ ! -x "$steam_bin" ]; then
  echo "Steam ARM64 binary not executable: $steam_bin" >&2
  exit 127
fi

exec "$steam_bin" "${steam_args[@]}" "$@"
