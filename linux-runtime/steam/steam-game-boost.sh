#!/usr/bin/env bash
set -euo pipefail

appid="${1:-}"
process_name="${2:-}"
[ -n "$appid" ] || { echo "Usage: waylandie-steam-game-boost APPID [PROCESS_NAME]" >&2; exit 2; }

cpu_set="${WAYLANDIE_STEAM_CPUSET:-4-7}"
uclamp_min="${WAYLANDIE_STEAM_UCLAMP_MIN:-768}"
uclamp_max="${WAYLANDIE_STEAM_UCLAMP_MAX:-1024}"
nice_val="${WAYLANDIE_STEAM_NICE:--10}"

matches_game() {
  local pid="$1" cmd env
  [ -r "/proc/$pid/status" ] || return 1
  grep -q '^State:[[:space:]]*Z' "/proc/$pid/status" 2>/dev/null && return 1
  cmd="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
  case "$cmd" in
    *"AppId=$appid"*|*"steam_app_$appid"*|*"compatdata/$appid"*|*"waylandie-steam-game-launch $appid"*) return 0 ;;
  esac
  if [ -n "$process_name" ]; then
    case "$cmd" in
      *"$process_name"*) return 0 ;;
    esac
  fi
  env="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -E "^(SteamAppId|SteamGameId|STEAM_COMPAT_APP_ID)=$appid$" || true)"
  [ -n "$env" ]
}

apply_perf_to_task() {
  local tid="$1"
  [ -d "/proc/$tid" ] || [ -d "/proc/self/task/$tid" ] || return 0
  command -v uclampset >/dev/null 2>&1 && uclampset -m "$uclamp_min" -M "$uclamp_max" -p "$tid" >/dev/null 2>&1 || true
  command -v taskset >/dev/null 2>&1 && taskset -pc "$cpu_set" "$tid" >/dev/null 2>&1 || true
  command -v renice >/dev/null 2>&1 && renice -n "$nice_val" -p "$tid" >/dev/null 2>&1 || true
}

apply_perf_to_pid() {
  local pid="$1" task tid
  command -v ionice >/dev/null 2>&1 && ionice -c 2 -n 0 -p "$pid" >/dev/null 2>&1 || true
  apply_perf_to_task "$pid"
  for task in "/proc/$pid/task/"[0-9]*; do
    [ -e "$task" ] || continue
    tid="${task##*/}"
    apply_perf_to_task "$tid"
  done
}

matched=0
for proc in /proc/[0-9]*; do
  pid="${proc##*/}"
  if matches_game "$pid"; then
    apply_perf_to_pid "$pid"
    matched=$((matched + 1))
  fi
done

printf 'boosted_processes=%s appid=%s process=%s cpuset=%s uclamp=%s-%s nice=%s\n' "$matched" "$appid" "$process_name" "$cpu_set" "$uclamp_min" "$uclamp_max" "$nice_val"
