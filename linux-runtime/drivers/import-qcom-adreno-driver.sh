#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  import-qcom-adreno-driver.sh --name SLOT [--appid APPID] [--profile PROFILE_ID] [--activate] [--wsi-layer PATH] PATH

Imports a user-supplied Qualcomm Adreno Linux driver package into a WayLandIE
Steam profile slot. PATH may be a Debian package, an extracted rootfs, or a
directory containing libvulkan_adreno.so.

This script does not download or redistribute Qualcomm binaries. Bring your own
legally obtained driver package.

Examples:
  waylandie-import-qcom-adreno-driver --name qcom-251009 ~/Downloads/qcom-adreno-0.1_arm64.deb
  waylandie-import-qcom-adreno-driver --name qcom-251009 --appid 287390 --activate ~/Downloads/qcom-adreno-0.1_arm64.deb
EOF
}

slot=""
appid=""
profile=""
activate=0
wsi_layer=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) slot="${2:-}"; shift 2 ;;
    --appid) appid="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --activate) activate=1; shift ;;
    --wsi-layer) wsi_layer="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

src="${1:-}"
[ -n "$slot" ] || { echo "ERROR missing --name SLOT" >&2; usage >&2; exit 2; }
case "$slot" in *[!A-Za-z0-9_.-]*|'') echo "ERROR invalid slot: $slot" >&2; exit 2 ;; esac
[ -n "$src" ] || { echo "ERROR missing driver PATH" >&2; usage >&2; exit 2; }
[ -e "$src" ] || { echo "ERROR path not found: $src" >&2; exit 3; }

home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
profile_root="${WAYLANDIE_STEAM_PROFILE_ROOT:-$config_home/waylandie/steam}"
slot_dir="$profile_root/qcom-adreno/$slot"
rootfs="$slot_dir/rootfs"
profile_cmd="${WAYLANDIE_STEAM_PROFILE_CMD:-$(command -v waylandie-steam-profile 2>/dev/null || true)}"

rm -rf "$slot_dir.new"
mkdir -p "$slot_dir.new/rootfs"

extract_deb() {
  local deb="$1" out="$2" tmp data
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -x "$deb" "$out"
    return
  fi
  command -v ar >/dev/null 2>&1 || { echo "ERROR dpkg-deb or ar is required to extract .deb packages" >&2; exit 4; }
  tmp="$(mktemp -d)"
  (cd "$tmp" && ar x "$deb")
  data="$(find "$tmp" -maxdepth 1 -type f -name 'data.tar*' | head -n 1)"
  [ -n "$data" ] || { echo "ERROR .deb data archive not found: $deb" >&2; exit 4; }
  tar -xf "$data" -C "$out"
  rm -rf "$tmp"
}

case "$src" in
  *.deb)
    extract_deb "$src" "$slot_dir.new/rootfs"
    ;;
  *)
    if [ -d "$src" ]; then
      cp -a "$src"/. "$slot_dir.new/rootfs/"
    else
      echo "ERROR unsupported driver path: $src" >&2
      exit 4
    fi
    ;;
esac

lib="$(find "$slot_dir.new/rootfs" -type f \( -name 'libvulkan_adreno.so' -o -name 'libvulkan_adreno.so.*' \) | head -n 1)"
[ -n "$lib" ] || { echo "ERROR libvulkan_adreno.so not found after import" >&2; exit 5; }
lib_dir="$(dirname "$lib")"
gbm_dir="$(find "$slot_dir.new/rootfs" -type d -path '*/gbm' | head -n 1)"
egl_lib="$(find "$slot_dir.new/rootfs" -type f \( -name 'libEGL_adreno.so' -o -name 'libEGL_adreno.so.*' \) | head -n 1)"
final_lib="$slot_dir${lib#"$slot_dir.new"}"
final_lib_dir="$slot_dir${lib_dir#"$slot_dir.new"}"
final_gbm_dir=""
final_egl_lib=""
[ -n "$gbm_dir" ] && final_gbm_dir="$slot_dir${gbm_dir#"$slot_dir.new"}"
[ -n "$egl_lib" ] && final_egl_lib="$slot_dir${egl_lib#"$slot_dir.new"}"

mkdir -p "$slot_dir.new/icd-shim"
python3 - "$slot_dir.new/icd-shim/qcom_icd_shim.json" "$final_lib" <<'PY'
import json
import sys
dst, lib = sys.argv[1:3]
data = {
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": lib,
        "api_version": "1.3.0",
    },
}
with open(dst, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

egl_json=""
if [ -n "$egl_lib" ]; then
  egl_json="$slot_dir.new/egl_adreno_abs.json"
  python3 - "$egl_json" "$final_egl_lib" <<'PY'
import json
import sys
dst, lib = sys.argv[1:3]
data = {
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": lib,
    },
}
with open(dst, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
fi

{
  printf 'WAYLANDIE_QCOM_SLOT=%s\n' "\"$slot\""
  printf 'VK_DRIVER_FILES=%s\n' "\"$slot_dir/icd-shim/qcom_icd_shim.json\""
  printf 'QCOM_VULKAN_ICD_LIB=%s\n' "\"$final_lib\""
  printf 'LD_LIBRARY_PATH=%s\n' "\"$final_lib_dir:\${LD_LIBRARY_PATH:-}\""
  [ -n "$final_gbm_dir" ] && printf 'GBM_BACKENDS_PATH=%s\n' "\"$final_gbm_dir\""
  [ -n "$final_gbm_dir" ] && printf 'GBM_BACKEND=%s\n' "\"msm\""
  [ -n "$egl_json" ] && printf '__EGL_VENDOR_LIBRARY_FILENAMES=%s\n' "\"$slot_dir/egl_adreno_abs.json\""
  if [ -n "$wsi_layer" ]; then
    printf 'VK_LAYER_PATH=%s\n' "\"$wsi_layer\""
    printf 'VK_INSTANCE_LAYERS=%s\n' "\"VK_LAYER_window_system_integration\""
  fi
  printf 'VK_LOADER_LAYERS_DISABLE=%s\n' "\"*MESA*,*MANGOHUD*,*VALVE*,*FROG*\""
  printf 'MESA_LOADER_DRIVER_OVERRIDE=\n'
  printf 'MESA_VK_DEVICE_SELECT=\n'
  printf 'MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=\n'
} > "$slot_dir.new/qcom-driver.env"

rm -rf "$slot_dir"
mv "$slot_dir.new" "$slot_dir"

echo "installed_qcom_slot=$slot_dir"
echo "vulkan_icd=$slot_dir/icd-shim/qcom_icd_shim.json"
echo "vulkan_library=$final_lib"
[ -n "$final_gbm_dir" ] && echo "gbm_backends=$final_gbm_dir"
[ -n "$egl_json" ] && echo "egl_vendor=$slot_dir/egl_adreno_abs.json"

if [ -n "$appid" ]; then
  [ -n "$profile_cmd" ] || { echo "ERROR waylandie-steam-profile not found on PATH; install Steam helpers first" >&2; exit 6; }
  cmd=("$profile_cmd" create-qcom-profile "$appid" "$slot")
  [ -n "$profile" ] && cmd+=(--profile "$profile")
  [ "$activate" = "1" ] && cmd+=(--activate)
  WAYLANDIE_STEAM_PROFILE_ROOT="$profile_root" "${cmd[@]}"
fi
