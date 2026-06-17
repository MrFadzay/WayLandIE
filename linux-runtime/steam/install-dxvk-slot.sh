#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: waylandie-steam-install-dxvk-slot [--appid APPID] [--slot NAME] [--profile PROFILE_ID] [--label TEXT] [--summary TEXT] [--activate] PATH

PATH may be a directory or .zip/.tar/.tar.gz archive containing x86-64 Windows
DXVK DLLs. For FEX/Proton, these are PE32+ x86-64 DLLs, not Linux aarch64 .so files.
EOF
  exit 2
}

appid="287390"
slot="custom"
profile=""
label=""
summary=""
activate=0
while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --appid)
      appid="${2:-}"; [ -n "$appid" ] || usage; shift 2 ;;
    --slot)
      slot="${2:-}"; [ -n "$slot" ] || usage; shift 2 ;;
    --profile)
      profile="${2:-}"; [ -n "$profile" ] || usage; shift 2 ;;
    --label)
      label="${2:-}"; [ -n "$label" ] || usage; shift 2 ;;
    --summary)
      summary="${2:-}"; [ -n "$summary" ] || usage; shift 2 ;;
    --activate)
      activate=1; shift ;;
    --help|-h)
      usage ;;
    --*)
      usage ;;
    *)
      break ;;
  esac
done

case "$slot" in
  *[!A-Za-z0-9_.-]*|'') echo "ERROR invalid slot: $slot" >&2; exit 2 ;;
esac

src="${1:-}"
[ -n "$src" ] || usage
[ -e "$src" ] || { echo "ERROR path not found: $src" >&2; exit 3; }

tmp=""
cleanup() {
  [ -n "$tmp" ] && rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

case "$src" in
  *.zip)
    tmp="$(mktemp -d)"
    unzip -oq "$src" -d "$tmp"
    src="$tmp"
    ;;
  *.tar|*.tar.gz|*.tgz|*.tar.xz)
    tmp="$(mktemp -d)"
    tar -xf "$src" -C "$tmp"
    src="$tmp"
    ;;
esac

find_dll() {
  local name="$1"
  find "$src" -type f -iname "$name" | head -n 1
}

required="d3d11.dll dxgi.dll"
for dll in $required; do
  found="$(find_dll "$dll")"
  [ -n "$found" ] || { echo "ERROR $dll not found in $src" >&2; exit 4; }
  desc="$(file "$found")"
  echo "$desc"
  case "$desc" in
    *"PE32+ executable"*"x86-64"*) ;;
    *) echo "ERROR expected PE32+ x86-64 Windows DLL: $found" >&2; exit 5 ;;
  esac
done

home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
profile_root="${WAYLANDIE_STEAM_PROFILE_ROOT:-${XDG_CONFIG_HOME:-$home_dir/.config}/waylandie/steam}"
profile_cmd="${WAYLANDIE_STEAM_PROFILE_CMD:-$(command -v waylandie-steam-profile 2>/dev/null || true)}"
profile_cmd="${profile_cmd:-/usr/local/bin/waylandie-steam-profile}"
dst="$profile_root/dxvk/$slot"
mkdir -p "$dst"
for dll in d3d9.dll d3d10.dll d3d10_1.dll d3d10core.dll d3d11.dll dxgi.dll; do
  found="$(find_dll "$dll")"
  [ -n "$found" ] || continue
  install -m 0644 "$found" "$dst/$dll"
done

echo "installed_dxvk_slot=$dst"
ls -l "$dst"

cmd=("$profile_cmd" create-dxvk-profile "$appid" "$slot")
[ -n "$profile" ] && cmd+=(--profile "$profile")
[ -n "$label" ] && cmd+=(--label "$label")
[ -n "$summary" ] && cmd+=(--summary "$summary")
[ "$activate" -eq 1 ] && cmd+=(--activate)
"${cmd[@]}"
