#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  install-steam-profiles.sh [--prefix PREFIX] [--profile-root PATH] [--force-config]

Installs the WayLandIE Steam helpers:
  waylandie-steam-profile
  waylandie-steam-game-launch
  waylandie-steam-game-boost
  waylandie-steam-launch-app
  waylandie-steam-stop-app
  waylandie-steam-arm64
  waylandie-steam-session
  waylandie-steam-session-child
  waylandie-steam-install-dxvk-slot
  waylandie-steam-install-turnip-slot
  waylandie-steam-export-arm64-bundle
  waylandie-steam-install-arm64-bundle

Examples:
  ./linux-runtime/steam/install-steam-profiles.sh --prefix /usr/local
  ./linux-runtime/steam/install-steam-profiles.sh --prefix "$HOME/.local"
EOF
}

prefix="/usr/local"
force_config=0
home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
profile_root="${WAYLANDIE_STEAM_PROFILE_ROOT:-$config_home/waylandie/steam}"
dxvk_config_dir="${WAYLANDIE_DXVK_CONFIG_DIR:-$config_home/dxvk}"
mangohud_dir="${WAYLANDIE_MANGOHUD_DIR:-$config_home/MangoHud}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix) prefix="$2"; shift 2 ;;
    --profile-root) profile_root="$2"; shift 2 ;;
    --force-config) force_config=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

src="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
stamp="$(date +%Y%m%d-%H%M%S)"

backup_file() {
  local file="$1"
  if [ -e "$file" ] && [ ! -e "$file.bak-$stamp" ]; then
    cp -a "$file" "$file.bak-$stamp"
  fi
}

install_file() {
  local mode="$1" from="$2" to="$3"
  backup_file "$to"
  install -D -m "$mode" "$from" "$to"
}

install_config_if_missing() {
  local mode="$1" from="$2" to="$3"
  if [ "$force_config" = "1" ] || [ ! -e "$to" ]; then
    install_file "$mode" "$from" "$to"
  fi
}

mkdir -p "$prefix/bin" "$prefix/share/waylandie/steam" "$profile_root" "$profile_root/fex" "$profile_root/dxvk" "$profile_root/turnip" "$dxvk_config_dir" "$mangohud_dir"

install_file 0755 "$src/steam-profile.py" "$prefix/bin/waylandie-steam-profile"
install_file 0755 "$src/steam-game-launch.sh" "$prefix/bin/waylandie-steam-game-launch"
install_file 0755 "$src/steam-game-boost.sh" "$prefix/bin/waylandie-steam-game-boost"
install_file 0755 "$src/steam-launch-app.sh" "$prefix/bin/waylandie-steam-launch-app"
install_file 0755 "$src/steam-stop-app.sh" "$prefix/bin/waylandie-steam-stop-app"
install_file 0755 "$src/steam-arm64-client.sh" "$prefix/bin/waylandie-steam-arm64"
install_file 0755 "$src/steam-session.sh" "$prefix/bin/waylandie-steam-session"
install_file 0755 "$src/steam-session-child.sh" "$prefix/bin/waylandie-steam-session-child"
install_file 0755 "$src/install-dxvk-slot.sh" "$prefix/bin/waylandie-steam-install-dxvk-slot"
install_file 0755 "$src/install-turnip-slot.sh" "$prefix/bin/waylandie-steam-install-turnip-slot"
install_file 0755 "$src/export-steam-arm64-bundle.sh" "$prefix/bin/waylandie-steam-export-arm64-bundle"
install_file 0755 "$src/install-steam-arm64-bundle.sh" "$prefix/bin/waylandie-steam-install-arm64-bundle"

install_file 0644 "$src/mangohud-full.conf" "$prefix/share/waylandie/steam/mangohud-full.conf"
install_file 0644 "$src/dxvk-default.conf" "$prefix/share/waylandie/steam/dxvk-default.conf"
install_file 0644 "$src/fex-safeperf.json" "$prefix/share/waylandie/steam/fex-safeperf.json"

install_config_if_missing 0644 "$src/mangohud-full.conf" "$mangohud_dir/WayLandIESteamGame.conf"
install_config_if_missing 0644 "$src/dxvk-default.conf" "$dxvk_config_dir/metro-lastlight.conf"
install_config_if_missing 0644 "$src/dxvk-default.conf" "$dxvk_config_dir/metro-lastlight-gplall.conf"
install_config_if_missing 0644 "$src/fex-safeperf.json" "$profile_root/fex/safeperf.json"

python3 -m py_compile "$prefix/bin/waylandie-steam-profile"
bash -n "$prefix/bin/waylandie-steam-game-launch"
bash -n "$prefix/bin/waylandie-steam-game-boost"
bash -n "$prefix/bin/waylandie-steam-arm64"
bash -n "$prefix/bin/waylandie-steam-session"
bash -n "$prefix/bin/waylandie-steam-session-child"
bash -n "$prefix/bin/waylandie-steam-install-dxvk-slot"
bash -n "$prefix/bin/waylandie-steam-install-turnip-slot"
bash -n "$prefix/bin/waylandie-steam-export-arm64-bundle"
bash -n "$prefix/bin/waylandie-steam-install-arm64-bundle"

WAYLANDIE_PREFIX="$prefix" \
WAYLANDIE_BIN_DIR="$prefix/bin" \
WAYLANDIE_STEAM_PROFILE_ROOT="$profile_root" \
WAYLANDIE_DXVK_CONFIG_DIR="$dxvk_config_dir" \
WAYLANDIE_MANGOHUD_CONFIG="$mangohud_dir/WayLandIESteamGame.conf" \
  "$prefix/bin/waylandie-steam-profile" bootstrap

cat <<EOF
installed=pass
prefix=$prefix
profile_root=$profile_root
profile_selector=$prefix/bin/waylandie-steam-profile gui
list_games=$prefix/bin/waylandie-steam-profile list-games
hook_example=$prefix/bin/waylandie-steam-profile hook 287390
launch_example=$prefix/bin/waylandie-steam-profile launch 287390 --process metro.exe
steam_session=$prefix/bin/waylandie-steam-session start
export_bundle=$prefix/bin/waylandie-steam-export-arm64-bundle --output ./waylandie-steam-arm64-bundle.tar.gz
install_bundle=$prefix/bin/waylandie-steam-install-arm64-bundle --bundle ./waylandie-steam-arm64-bundle.tar.gz
EOF
