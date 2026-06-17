#!/bin/sh
set -eu

appid="${1:-287390}"
process_name="${2:-metro.exe}"
timeout_seconds="${3:-90}"
home_dir="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
home_dir="${home_dir:-/tmp}"
cache_dir="${XDG_CACHE_HOME:-$home_dir/.cache}"
steam_root="${WAYLANDIE_STEAM_ROOT:-$home_dir/.local/share/Steam}"
steam_bin="${STEAM_BIN:-$steam_root/steamrtarm64/steam}"
log_file="${WAYLANDIE_STEAM_LAUNCH_LOG:-$cache_dir/waylandie/steam-launch-app-${appid}.log}"
restart_script="${WAYLANDIE_STEAM_RESTART_SCRIPT:-}"
auto_recover="${WAYLANDIE_STEAM_LAUNCH_AUTO_RECOVER:-1}"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" | tee -a "$log_file"
}

find_target_process() {
  ps -eo pid=,stat=,comm=,args= 2>/dev/null |
    awk -v name="$process_name" '
      $2 !~ /^Z/ && $3 == name { pid=$1 }
      END { if (pid) print pid }
    '
}

find_steam_pid() {
  ps -eo pid=,stat=,comm=,args= 2>/dev/null |
    awk '
      $2 !~ /^Z/ && $3 == "steam" && index($0, "steamrtarm64/steam") { pid=$1 }
      END { if (pid) print pid }
    '
}

import_live_steam_env() {
  steam_pid="$1"
  env_file="/proc/${steam_pid}/environ"
  tmp_file="$(mktemp)"

  if [ ! -r "$env_file" ]; then
    log "WARN cannot read $env_file; using launcher defaults"
    rm -f "$tmp_file"
    return 0
  fi

  tr '\000' '\n' < "$env_file" > "$tmp_file"
  while IFS= read -r envline; do
    name="${envline%%=*}"
    value="${envline#*=}"
    [ "$name" = "$value" ] && continue
    case "$name" in
      HOME|USER|LOGNAME|PATH|DISPLAY|WAYLAND_DISPLAY|GAMESCOPE_WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|LD_LIBRARY_PATH|LD_PRELOAD|PULSE_SERVER|PULSE_LATENCY_MSEC|VK_ICD_FILENAMES|VK_DRIVER_FILES|MESA_LOADER_DRIVER_OVERRIDE|GALLIUM_DRIVER|__EGL_VENDOR_LIBRARY_FILENAMES)
        export "$name=$value" 2>/dev/null || true
        ;;
    esac
  done < "$tmp_file"
  rm -f "$tmp_file"
}

print_session() {
  log "appid=$appid process=$process_name timeout=${timeout_seconds}s"
  log "steam_bin=$steam_bin"
  log "DISPLAY=${DISPLAY:-unset} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} GAMESCOPE_WAYLAND_DISPLAY=${GAMESCOPE_WAYLAND_DISPLAY:-unset}"
  log "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset} DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unset}"
}

saw_launch_chain() {
  ps -eo pid=,stat=,comm=,args= 2>/dev/null |
    awk -v appid="$appid" '
      $2 !~ /^Z/ &&
      index($0, "waylandie-steam-launch-app") == 0 &&
      (index($0, "steam_app_" appid) || index($0, "AppId=" appid)) {
        found=1
      }
      END { exit(found ? 0 : 1) }
    '
}

wait_for_target() {
  method="$1"
  start_epoch="$(date +%s)"
  chain_reported=0

  while :; do
    now_epoch="$(date +%s)"
    elapsed=$((now_epoch - start_epoch))
    [ "$elapsed" -le "$timeout_seconds" ] || break

    target_pid="$(find_target_process | tail -n 1)"
    if [ -n "$target_pid" ]; then
      log "SUCCESS method=$method pid=$target_pid after=${elapsed}s"
      ps -p "$target_pid" -o pid,ni,pri,psr,stat,comm,args 2>/dev/null | tee -a "$log_file" || true
      return 0
    fi

    if [ "$chain_reported" -eq 0 ] && saw_launch_chain; then
      log "launch-chain-seen method=$method after=${elapsed}s"
      chain_reported=1
    fi

    sleep 1
  done

  log "TIMEOUT method=$method after=${timeout_seconds}s"
  return 1
}

attempt_launches() {
  log "launching method=steam-url-rungameid"
  nohup "$steam_bin" "steam://rungameid/$appid" >> "$log_file" 2>&1 &
  if wait_for_target "steam-url-rungameid"; then
    return 0
  fi

  log "launching method=steam-applaunch-fallback"
  nohup "$steam_bin" -applaunch "$appid" >> "$log_file" 2>&1 &
  if wait_for_target "steam-applaunch"; then
    return 0
  fi

  return 1
}

print_failure_context() {
  log "failure-context: matching process table"
  ps -eo pid,ni,pri,psr,stat,comm,args 2>/dev/null |
    awk -v appid="$appid" -v name="$process_name" '
      index($0, "steam") || index($0, appid) || index($0, name) { print }
    ' | tail -n 80 | tee -a "$log_file" || true

  content_log="${HOME:-$home_dir}/.local/share/Steam/logs/content_log.txt"
  if [ -r "$content_log" ]; then
    log "failure-context: recent Steam content_log entries for appid=$appid"
    tail -n 200 "$content_log" |
      awk -v appid="$appid" 'index($0, appid) || index($0, "AppID") || index($0, "state changed") { print }' |
      tail -n 80 | tee -a "$log_file" || true
  fi
}

mkdir -p "$(dirname "$log_file")"
: > "$log_file"

already_running_pid="$(find_target_process | tail -n 1)"
if [ -n "$already_running_pid" ]; then
  log "SUCCESS already-running pid=$already_running_pid"
  ps -p "$already_running_pid" -o pid,ni,pri,psr,stat,comm,args 2>/dev/null | tee -a "$log_file" || true
  exit 0
fi

steam_pid="$(find_steam_pid | tail -n 1)"
if [ -z "$steam_pid" ]; then
  log "ERROR no live steamrtarm64 Steam process found"
  print_failure_context
  exit 2
fi

import_live_steam_env "$steam_pid"
export HOME="${HOME:-$home_dir}"
export USER="${USER:-$(id -un 2>/dev/null || printf '%s' root)}"
export LOGNAME="${LOGNAME:-$USER}"
export PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
export DISPLAY="${DISPLAY:-:9}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-0}"

print_session
log "live_steam_pid=$steam_pid"

if [ ! -x "$steam_bin" ]; then
  steam_bin="$(command -v steam || true)"
fi

if [ -z "$steam_bin" ] || [ ! -x "$steam_bin" ]; then
  log "ERROR Steam binary not executable"
  print_failure_context
  exit 3
fi

if attempt_launches; then
  exit 0
fi

if [ "$auto_recover" != "0" ] && [ -n "$restart_script" ] && [ -x "$restart_script" ]; then
  log "recovering method=restart-steam-gamescope script=$restart_script"
  if "$restart_script" >> "$log_file" 2>&1; then
    sleep 8
    steam_pid="$(find_steam_pid | tail -n 1)"
    if [ -n "$steam_pid" ]; then
      import_live_steam_env "$steam_pid"
      print_session
      log "live_steam_pid=$steam_pid after-recover=1"
      if attempt_launches; then
        exit 0
      fi
    else
      log "ERROR no live Steam process after recovery restart"
    fi
  else
    log "ERROR recovery restart script failed"
  fi
fi

print_failure_context
exit 1
