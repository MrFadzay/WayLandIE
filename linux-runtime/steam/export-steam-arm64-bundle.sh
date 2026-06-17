#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  export-steam-arm64-bundle.sh [options]

Creates a private local tarball from an already-working Steam ARM64 install.
The tarball is intentionally not meant to be committed to git.

Options:
  --output PATH              Output tar.gz path.
  --steam-root PATH          Steam root. Default: ~/.local/share/Steam.
  --proton NAME              Include compatibilitytools.d/NAME. Can repeat.
                             Default: Proton11ARM.
  --include-proton-beta      Also include Proton11Beta5ARM when present.
  --include-profile-state    Include local profile/DXVK slot state under ~/.config.
  --extra-path PATH          Include another path. Can repeat.
  --dry-run                  Print the paths that would be archived.
  -h, --help                 Show this help.

Default contents:
  - Steam ARM64 client/runtime pieces, excluding games/userdata/logs/cache.
  - SteamLinuxRuntime_4-arm64, required by the ARM Proton toolmanifest.
  - Proton11ARM.
  - Gamescope and Steam/Gamescope helper binaries/scripts from /usr/local/bin.
  - Root-owned Steam/Gamescope control scripts from /root.
  - MangoHud and DXVK config snippets.
EOF
}

home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/root}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
steam_root="${WAYLANDIE_STEAM_ROOT:-$home_dir/.local/share/Steam}"
output=""
dry_run=0
include_profile_state=0
include_proton_beta=0
protons=()
extra_paths=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --steam-root) steam_root="$2"; shift 2 ;;
    --proton) protons+=("$2"); shift 2 ;;
    --include-proton-beta) include_proton_beta=1; shift ;;
    --include-profile-state) include_profile_state=1; shift ;;
    --extra-path) extra_paths+=("$2"); shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "${#protons[@]}" -eq 0 ]; then
  protons=(Proton11ARM)
fi
if [ "$include_proton_beta" = "1" ]; then
  protons+=(Proton11Beta5ARM)
fi

stamp="$(date -u +%Y%m%d-%H%M%S)"
if [ -z "$output" ]; then
  output="$PWD/waylandie-steam-arm64-bundle-$stamp.tar.gz"
fi

stage="$(mktemp -d)"
paths_file="$stage/paths.txt"
manifest="$stage/manifest.txt"
session_env="$stage/session.env"
touch "$paths_file"

cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT

add_path() {
  local path="$1"
  if [ -e "$path" ]; then
    case "$(basename "$path")" in
      *bak*|*backup*|*before*|*pre-*|*handoff*|*session-bak*|*live-before*)
        printf 'skipped_backup=%s\n' "$path" >> "$manifest"
        return 0
        ;;
    esac
    printf '%s\n' "${path#/}" >> "$paths_file"
  else
    printf 'missing=%s\n' "$path" >> "$manifest"
  fi
}

add_glob() {
  local pattern="$1"
  local found=0
  while IFS= read -r -d '' path; do
    found=1
    add_path "$path"
  done < <(compgen -G "$pattern" | while IFS= read -r path; do printf '%s\0' "$path"; done)
  if [ "$found" = "0" ]; then
    printf 'missing_glob=%s\n' "$pattern" >> "$manifest"
  fi
}

write_manifest_header() {
  {
    printf 'bundle_format=waylandie-steam-arm64-v1\n'
    printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'host=%s\n' "$(hostname 2>/dev/null || true)"
    printf 'uname=%s\n' "$(uname -a 2>/dev/null || true)"
    printf 'steam_root=%s\n' "$steam_root"
    printf 'home=%s\n' "$home_dir"
    printf 'uid=%s\n' "$(id -u)"
    printf 'note=%s\n' 'private runtime bundle; do not commit or redistribute without rights'
  } > "$manifest"
}

write_session_env() {
  local display pulse
  display="${DISPLAY:-:5}"
  pulse="${PULSE_SERVER:-unix:/tmp/.pulse-socket}"
  if [ -r /run/droidspaces.env ]; then
    # shellcheck disable=SC1091
    . /run/droidspaces.env || true
    display="${DISPLAY:-$display}"
    pulse="${PULSE_SERVER:-$pulse}"
  fi

  cat > "$session_env" <<EOF
# Source this before launching Steam/Gamescope in a Droidspaces-style container.
export DISPLAY="\${DISPLAY:-$display}"
export PULSE_SERVER="\${PULSE_SERVER:-$pulse}"
export PULSE_LATENCY_MSEC="\${PULSE_LATENCY_MSEC:-20}"
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/tmp/runtime-\$(id -u)}"
export STEAM_BIN="\${STEAM_BIN:-\$HOME/.local/share/Steam/steamrtarm64/steam}"
export STEAM_RUNTIME_SERVICE="\${STEAM_RUNTIME_SERVICE:-\$HOME/.local/share/Steam/compatibilitytools.d/SteamLinuxRuntime_4-arm64/pressure-vessel/bin}"
export PATH="\$HOME/.local/share/Steam/steamrtarm64:\$STEAM_RUNTIME_SERVICE:/usr/local/bin:/usr/bin:/bin:\$PATH"
export VK_ICD_FILENAMES="\${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json}"
export VK_DRIVER_FILES="\${VK_DRIVER_FILES:-\$VK_ICD_FILENAMES}"
export MESA_VK_DEVICE_SELECT="\${MESA_VK_DEVICE_SELECT:-5143:44050a31}"
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE="\${MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE:-1}"
export __EGL_VENDOR_LIBRARY_FILENAMES="\${__EGL_VENDOR_LIBRARY_FILENAMES:-/usr/share/glvnd/egl_vendor.d/50_mesa.json}"
export NO_AT_BRIDGE=1
export GTK_USE_PORTAL=0
export GIO_USE_VFS=local
EOF
}

write_manifest_header
write_session_env

# Steam client/runtime without games, userdata, shader cache, or logs.
for path in \
  "$steam_root/steamrtarm64" \
  "$steam_root/steamrtarm64\\libs" \
  "$steam_root/steamrtarm64\\swiftshader" \
  "$steam_root/steamrtarm32" \
  "$steam_root/SteamLinuxRuntime_sniper" \
  "$steam_root/package" \
  "$steam_root/clientui" \
  "$steam_root/public" \
  "$steam_root/resource" \
  "$steam_root/graphics" \
  "$steam_root/friends" \
  "$steam_root/controller_base" \
  "$steam_root/steamui" \
  "$steam_root/bin" \
  "$steam_root/linuxarm64" \
  "$steam_root/androidarm64" \
  "$steam_root/steam.sh" \
  "$steam_root/steam_msg.sh" \
  "$steam_root/steamclient.dll" \
  "$steam_root/steamclient64.dll" \
  "$steam_root/GameOverlayRenderer64.dll" \
  "$steam_root/ThirdPartyLegalNotices.html" \
  "$steam_root/ThirdPartyLegalNotices-Chromium.html" \
  "$steam_root/ThirdPartyLegalNotices.css" \
  "$steam_root/steam_subscriber_agreement.txt" \
  "$steam_root/fossilize_engine_filters.json"; do
  add_path "$path"
done

add_path "$steam_root/compatibilitytools.d/SteamLinuxRuntime_4-arm64"
for proton in "${protons[@]}"; do
  add_path "$steam_root/compatibilitytools.d/$proton"
done

# Current Gamescope binary family and Steam/Gamescope helpers. This captures
# legacy helper names without spelling project-specific old names in the repo.
add_glob "/usr/local/bin/gamescope*"
add_glob "/usr/local/bin/steam-gamescope*"
add_path "/usr/local/bin/steam-arm64"
add_glob "/usr/local/bin/*steam*"
add_glob "/usr/local/bin/waylandie-*"
add_path "/usr/local/share/waylandie"

for path in \
  /root/start_steam_gamescope.sh \
  /root/restart_steam_gamescope.sh \
  /root/stop_steam_gamescope.sh; do
  add_path "$path"
done
add_glob "/root/*steam*watchdog*.sh"

for path in \
  "$home_dir/.config/MangoHud" \
  "$home_dir/.config/dxvk" \
  "$home_dir/.config/waylandie"; do
  add_path "$path"
done

# Proprietary Qualcomm Linux driver slots are user-owned private artifacts.
# Bundle them only into the local tarball, never into git.
add_glob "$config_home/*/qcom-adreno"
add_glob "/usr/share/vulkan/icd.d/*adreno*"
add_glob "/usr/share/vulkan/icd.d/*qcom*"
add_path "/usr/local/lib/aarch64-linux-gnu/adreno"
add_path "/usr/lib/aarch64-linux-gnu/gbm/default_fmt_alignment.xml"
add_glob "/usr/share/glvnd/egl_vendor.d/*adreno*"

if [ "$include_profile_state" = "1" ]; then
  add_glob "$home_dir/.config/*steam-profiles"
  add_glob "$home_dir/.config/*metro"
fi

for path in "${extra_paths[@]}"; do
  add_path "$path"
done

sort -u "$paths_file" -o "$paths_file"

{
  printf '\n[included_paths]\n'
  sed 's/^/path=/' "$paths_file"
} >> "$manifest"

mkdir -p "$stage/waylandie-bundle"
cp "$paths_file" "$stage/waylandie-bundle/paths.txt"
cp "$manifest" "$stage/waylandie-bundle/manifest.txt"
cp "$session_env" "$stage/waylandie-bundle/session.env"
cat > "$stage/waylandie-bundle/README.txt" <<'EOF'
This is a private WayLandIE Steam ARM64 starter bundle exported from a local
working container. It can contain proprietary Steam, Proton, and helper files.
Do not commit this archive to a public repository unless you have checked every
license and have redistribution rights.
EOF

if [ "$dry_run" = "1" ]; then
  cat "$stage/waylandie-bundle/manifest.txt"
  exit 0
fi

mkdir -p "$(dirname "$output")"
tar -czf "$output" \
  --exclude='root/.local/share/Steam/steamapps/common/*' \
  --exclude='root/.local/share/Steam/steamapps/compatdata/*' \
  --exclude='root/.local/share/Steam/steamapps/shadercache/*' \
  --exclude='root/.local/share/Steam/userdata/*' \
  --exclude='root/.local/share/Steam/logs/*' \
  --exclude='root/.local/share/Steam/config/loginusers.vdf' \
  --exclude='root/.local/share/Steam/config/config.vdf' \
  --exclude='*.bak-*' \
  --exclude='*.backup-*' \
  -C "$stage" waylandie-bundle \
  -C / -T "$paths_file"

printf 'bundle=%s\n' "$output"
du -h "$output" 2>/dev/null || true
