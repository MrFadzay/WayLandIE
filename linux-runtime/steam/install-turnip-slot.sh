#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: waylandie-steam-install-turnip-slot [--appid APPID] [--slot NAME] [--profile PROFILE_ID] [--label TEXT] [--summary TEXT] [--activate] PATH

PATH may be a file, directory, or .zip/.tar/.tar.gz archive containing native
aarch64 libvulkan_freedreno.so. If a freedreno ICD JSON is missing, one is
generated from the currently installed system ICD template.
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

if [ -f "$src" ]; then
  file_src="$src"
  tmp="$(mktemp -d)"
  cp -a "$file_src" "$tmp/libvulkan_freedreno.so"
  src="$tmp"
fi

lib="$(find "$src" -type f -name 'libvulkan_freedreno.so*' | head -n 1)"
json="$(find "$src" -type f \( -name '*freedreno*icd*.json' -o -name 'freedreno_icd*.json' \) | head -n 1)"
[ -n "$lib" ] || { echo "ERROR libvulkan_freedreno.so not found in $src" >&2; exit 4; }
if [ -z "$json" ]; then
  json="/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
  [ -r "$json" ] || json="/run/host/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
  [ -r "$json" ] || { echo "ERROR freedreno ICD JSON not found and no system template is readable" >&2; exit 4; }
  echo "using_icd_template=$json"
fi

desc="$(file "$lib")"
echo "$desc"
case "$desc" in
  *"ELF 64-bit"*"ARM aarch64"*) ;;
  *) echo "ERROR expected native Linux aarch64 libvulkan_freedreno.so: $lib" >&2; exit 5 ;;
esac

home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
profile_root="${WAYLANDIE_STEAM_PROFILE_ROOT:-${XDG_CONFIG_HOME:-$home_dir/.config}/waylandie/steam}"
profile_cmd="${WAYLANDIE_STEAM_PROFILE_CMD:-$(command -v waylandie-steam-profile 2>/dev/null || true)}"
profile_cmd="${profile_cmd:-/usr/local/bin/waylandie-steam-profile}"
dst="$profile_root/turnip/$slot"
mkdir -p "$dst"
find "$src" -type f \( -name '*.so' -o -name '*.so.*' \) -exec cp -a {} "$dst/" \;
install -m 0644 "$json" "$dst/freedreno_icd.aarch64.json.src"

python3 - "$dst/freedreno_icd.aarch64.json.src" "$dst/freedreno_icd.aarch64.json" "$dst/libvulkan_freedreno.so" <<'PY'
import json
import sys
src, dst, lib = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as f:
    data = json.load(f)
data.setdefault("ICD", {})["library_path"] = lib
with open(dst, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
rm -f "$dst/freedreno_icd.aarch64.json.src"

echo "installed_turnip_slot=$dst"
cat "$dst/freedreno_icd.aarch64.json"

cmd=("$profile_cmd" create-turnip-profile "$appid" "$slot")
[ -n "$profile" ] && cmd+=(--profile "$profile")
[ -n "$label" ] && cmd+=(--label "$label")
[ -n "$summary" ] && cmd+=(--summary "$summary")
[ "$activate" -eq 1 ] && cmd+=(--activate)
"${cmd[@]}"
