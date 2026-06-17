#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  install-steam-arm64-bundle.sh --bundle PATH [options]

Installs a private bundle made by export-steam-arm64-bundle.sh into the current
Linux environment. This does not install games or account data.

Options:
  --bundle PATH              Bundle tar.gz to install.
  --steam-root PATH          Target Steam root. Default: ~/.local/share/Steam.
  --prefix PATH              Prefix for helper binaries. Default: /usr/local.
  --config-home PATH         Config root. Default: $XDG_CONFIG_HOME or ~/.config.
  --skip-helpers             Do not install bundled helper binaries/scripts.
  --skip-config              Do not install MangoHud/DXVK/session config.
  --dry-run                  Print planned actions without copying files.
  -h, --help                 Show this help.
EOF
}

bundle=""
home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/root}"
steam_root="${WAYLANDIE_STEAM_ROOT:-$home_dir/.local/share/Steam}"
prefix="/usr/local"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
install_helpers=1
install_config=1
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle) bundle="$2"; shift 2 ;;
    --steam-root) steam_root="$2"; shift 2 ;;
    --prefix) prefix="$2"; shift 2 ;;
    --config-home) config_home="$2"; shift 2 ;;
    --skip-helpers) install_helpers=0; shift ;;
    --skip-config) install_config=0; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$bundle" ]; then
  echo "missing --bundle" >&2
  usage >&2
  exit 2
fi
if [ ! -r "$bundle" ]; then
  echo "bundle is not readable: $bundle" >&2
  exit 2
fi

stage="$(mktemp -d)"
stamp="$(date +%Y%m%d-%H%M%S)"

cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT

log() {
  printf '%s\n' "$*"
}

run() {
  log "+ $*"
  if [ "$dry_run" != "1" ]; then
    "$@"
  fi
}

copy_tree() {
  local src="$1" dst="$2"
  [ -e "$src" ] || return 0
  run mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ "$dry_run" != "1" ]; then
    mv "$dst" "$dst.bak-$stamp"
  elif [ -e "$dst" ]; then
    log "+ mv $dst $dst.bak-$stamp"
  fi
  run cp -a "$src" "$dst"
}

rewrite_root_paths() {
  local file="$1"
  [ -f "$file" ] || return 0
  if [ "$dry_run" = "1" ]; then
    log "+ rewrite-root-paths $file"
    return 0
  fi
  python3 - "$file" "$steam_root" "$config_home" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
steam_root = sys.argv[2]
config_home = sys.argv[3]
try:
    text = path.read_text(encoding="utf-8")
except UnicodeDecodeError:
    returncode = 0
    sys.exit(returncode)
text = text.replace("/root/.local/share/Steam", steam_root)
text = text.replace("/root/.config", config_home)
path.write_text(text, encoding="utf-8")
PY
}

write_qcom_slot_metadata() {
  local slot_dir="$1" slot_name lib lib_dir gbm_dir egl_lib final_gbm final_egl
  slot_name="$(basename "$slot_dir")"
  lib="$(find "$slot_dir/rootfs" -type f \( -name 'libvulkan_adreno.so' -o -name 'libvulkan_adreno.so.*' \) | head -n 1)"
  [ -n "$lib" ] || return 0
  lib_dir="$(dirname "$lib")"
  gbm_dir="$(find "$slot_dir/rootfs" -type d -path '*/gbm' | head -n 1)"
  egl_lib="$(find "$slot_dir/rootfs" -type f \( -name 'libEGL_adreno.so' -o -name 'libEGL_adreno.so.*' \) | head -n 1)"

  run mkdir -p "$slot_dir/icd-shim"
  if [ "$dry_run" != "1" ]; then
    python3 - "$slot_dir/icd-shim/qcom_icd_shim.json" "$lib" <<'PY'
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
  fi

  final_gbm=""
  final_egl=""
  if [ -n "$egl_lib" ]; then
    final_egl="$slot_dir/egl_adreno_abs.json"
    if [ "$dry_run" != "1" ]; then
      python3 - "$final_egl" "$egl_lib" <<'PY'
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
  fi
  [ -n "$gbm_dir" ] && final_gbm="$gbm_dir"

  if [ "$dry_run" != "1" ]; then
    {
      printf 'WAYLANDIE_QCOM_SLOT=%s\n' "\"$slot_name\""
      printf 'VK_DRIVER_FILES=%s\n' "\"$slot_dir/icd-shim/qcom_icd_shim.json\""
      printf 'QCOM_VULKAN_ICD_LIB=%s\n' "\"$lib\""
      printf 'LD_LIBRARY_PATH=%s\n' "\"$lib_dir:\${LD_LIBRARY_PATH:-}\""
      [ -n "$final_gbm" ] && printf 'GBM_BACKENDS_PATH=%s\n' "\"$final_gbm\""
      [ -n "$final_gbm" ] && printf 'GBM_BACKEND=%s\n' "\"msm\""
      [ -n "$final_egl" ] && printf '__EGL_VENDOR_LIBRARY_FILENAMES=%s\n' "\"$final_egl\""
      printf 'VK_LOADER_LAYERS_DISABLE=%s\n' "\"*MESA*,*MANGOHUD*,*VALVE*,*FROG*\""
      printf 'MESA_LOADER_DRIVER_OVERRIDE=\n'
      printf 'MESA_VK_DEVICE_SELECT=\n'
      printf 'MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=\n'
    } > "$slot_dir/qcom-driver.env"
  fi
}

install_qcom_slots() {
  local source_config="$stage/root/.config" target_qcom="$config_home/waylandie/steam/qcom-adreno"
  local found=0 qroot slot src_slot dst_slot active_slot active_lib active_adreno_dir icd_out
  [ -d "$source_config" ] || return 0

  for qroot in "$source_config"/*/qcom-adreno; do
    [ -d "$qroot" ] || continue
    found=1
    run mkdir -p "$target_qcom"
    for src_slot in "$qroot"/*; do
      [ -d "$src_slot" ] || continue
      slot="$(basename "$src_slot")"
      dst_slot="$target_qcom/$slot"
      copy_tree "$src_slot" "$dst_slot"
      write_qcom_slot_metadata "$dst_slot"
    done
  done

  [ "$found" = "1" ] || return 0

  active_slot=""
  if [ -L "$stage/usr/local/lib/aarch64-linux-gnu/adreno" ]; then
    active_slot="$(readlink "$stage/usr/local/lib/aarch64-linux-gnu/adreno" | sed -n 's#.*qcom-adreno/\([^/]*\)/.*#\1#p')"
  fi
  if [ -z "$active_slot" ]; then
    for dst_slot in "$target_qcom"/*; do
      [ -d "$dst_slot" ] || continue
      active_lib="$(find "$dst_slot/rootfs" -type f \( -name 'libvulkan_adreno.so' -o -name 'libvulkan_adreno.so.*' \) | head -n 1)"
      if [ -n "$active_lib" ]; then
        active_slot="$(basename "$dst_slot")"
        break
      fi
    done
  fi
  [ -n "$active_slot" ] || return 0

  active_adreno_dir="$(find "$target_qcom/$active_slot/rootfs" -type d -path '*/aarch64-linux-gnu/adreno' | head -n 1)"
  if [ -n "$active_adreno_dir" ]; then
    run mkdir -p "$prefix/lib/aarch64-linux-gnu"
    if [ "$dry_run" != "1" ]; then
      ln -sfn "$active_adreno_dir" "$prefix/lib/aarch64-linux-gnu/adreno"
    else
      log "+ ln -sfn $active_adreno_dir $prefix/lib/aarch64-linux-gnu/adreno"
    fi
  fi

  icd_out="$prefix/share/vulkan/icd.d/adreno-vk-qcom-${active_slot}.json"
  active_lib="$(find "$target_qcom/$active_slot/rootfs" -type f \( -name 'libvulkan_adreno.so' -o -name 'libvulkan_adreno.so.*' \) | head -n 1)"
  if [ -n "$active_lib" ]; then
    run mkdir -p "$(dirname "$icd_out")"
    if [ "$dry_run" != "1" ]; then
      python3 - "$icd_out" "$active_lib" <<'PY'
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
    else
      log "+ write $icd_out"
    fi
  fi

  log "qcom_slots=$target_qcom"
  log "qcom_active_slot=$active_slot"
}

mkdir -p "$stage/waylandie-bundle"
tar --occurrence=1 -xOzf "$bundle" waylandie-bundle/manifest.txt > "$stage/waylandie-bundle/manifest.txt" 2>/dev/null || {
  echo "not a WayLandIE Steam ARM64 bundle: $bundle" >&2
  exit 2
}
tar --occurrence=1 -xOzf "$bundle" waylandie-bundle/session.env > "$stage/waylandie-bundle/session.env" 2>/dev/null || true

if [ "$dry_run" = "1" ]; then
  log "bundle_manifest=$stage/waylandie-bundle/manifest.txt"
  sed -n '1,120p' "$stage/waylandie-bundle/manifest.txt"
  log "dry_run=pass"
  log "planned_steam_root=$steam_root"
  log "planned_prefix=$prefix"
  log "planned_session_env=$config_home/waylandie/steam/session.env"
  exit 0
fi

rm -rf "$stage"
stage="$(mktemp -d)"
trap cleanup EXIT
tar -C "$stage" -xzf "$bundle"

if [ ! -d "$stage/waylandie-bundle" ]; then
  echo "not a WayLandIE Steam ARM64 bundle: $bundle" >&2
  exit 2
fi

log "bundle_manifest=$stage/waylandie-bundle/manifest.txt"
if [ -r "$stage/waylandie-bundle/manifest.txt" ]; then
  sed -n '1,80p' "$stage/waylandie-bundle/manifest.txt"
fi

source_steam="$stage/root/.local/share/Steam"

for item in \
  steamrtarm64 \
  steamrtarm32 \
  package \
  clientui \
  public \
  resource \
  graphics \
  friends \
  controller_base \
  steamui \
  bin \
  linuxarm64 \
  androidarm64; do
  copy_tree "$source_steam/$item" "$steam_root/$item"
done

run mkdir -p "$steam_root"
for file in \
  steam.sh \
  steam_msg.sh \
  steamclient.dll \
  steamclient64.dll \
  GameOverlayRenderer64.dll \
  ThirdPartyLegalNotices.html \
  ThirdPartyLegalNotices-Chromium.html \
  ThirdPartyLegalNotices.css \
  steam_subscriber_agreement.txt \
  fossilize_engine_filters.json; do
  if [ -e "$source_steam/$file" ]; then
    run cp -a "$source_steam/$file" "$steam_root/$file"
  fi
done

if [ -d "$source_steam/compatibilitytools.d" ]; then
  run mkdir -p "$steam_root/compatibilitytools.d"
  for item in "$source_steam/compatibilitytools.d"/*; do
    [ -e "$item" ] || continue
    name="$(basename "$item")"
    copy_tree "$item" "$steam_root/compatibilitytools.d/$name"
  done
fi

if [ "$install_helpers" = "1" ]; then
  if [ -d "$stage/usr/local/bin" ]; then
    run mkdir -p "$prefix/bin"
    for file in "$stage/usr/local/bin"/*; do
      [ -f "$file" ] || continue
      run install -m 0755 "$file" "$prefix/bin/$(basename "$file")"
    done
  fi
  copy_tree "$stage/usr/local/share/waylandie" "$prefix/share/waylandie"
  for script in start_steam_gamescope.sh restart_steam_gamescope.sh stop_steam_gamescope.sh; do
    if [ -f "$stage/root/$script" ]; then
      run install -m 0755 "$stage/root/$script" "$prefix/bin/waylandie-${script%.sh}"
    fi
  done
fi

if [ "$install_config" = "1" ]; then
  copy_tree "$stage/root/.config/MangoHud" "$config_home/MangoHud"
  copy_tree "$stage/root/.config/dxvk" "$config_home/dxvk"
  copy_tree "$stage/root/.config/waylandie" "$config_home/waylandie"
  install_qcom_slots
  run mkdir -p "$config_home/waylandie/steam"
  if [ -r "$stage/waylandie-bundle/session.env" ]; then
    run cp -a "$stage/waylandie-bundle/session.env" "$config_home/waylandie/steam/session.env"
  fi
fi

for file in \
  "$steam_root/compatibilitytools.d"/*/toolmanifest.vdf \
  "$steam_root/compatibilitytools.d"/*/compatibilitytool.vdf \
  "$steam_root/compatibilitytools.d"/*/proton \
  "$prefix/bin/steam-arm64" \
  "$prefix/bin/steam-gamescope-child" \
  "$prefix/bin/steam-gamescope-child."* \
  "$prefix/bin/waylandie-start_steam_gamescope" \
  "$prefix/bin/waylandie-restart_steam_gamescope" \
  "$prefix/bin/waylandie-stop_steam_gamescope"; do
  [ -e "$file" ] || continue
  rewrite_root_paths "$file"
done

if [ "$dry_run" != "1" ]; then
  mkdir -p "$steam_root"
  ln -sfn "$steam_root/steamrtarm64" "$steam_root/steamrtarm32" 2>/dev/null || true
fi

log "installed=pass"
log "steam_root=$steam_root"
log "prefix=$prefix"
log "session_env=$config_home/waylandie/steam/session.env"
log "steam_bin=$steam_root/steamrtarm64/steam"
log "proton_tools_dir=$steam_root/compatibilitytools.d"
