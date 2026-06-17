#!/usr/bin/env bash
set -euo pipefail

appid="${1:-287390}"
process_name="${2:-metro.exe}"
grace_seconds="${3:-12}"

collect_pids() {
  ps -eo pid=,stat=,comm=,args= |
    awk -v appid="$appid" -v name="$process_name" -v self="$$" -v parent="$PPID" '
      $1 == self || $1 == parent { next }
      $2 ~ /^Z/ { next }
      $3 == "ssh" || $3 == "sshd" || $3 == "awk" || $3 == "grep" { next }
      index($0, "waylandie-steam-stop-app") { next }
      $3 == name || index($0, "AppId=" appid) || index($0, "compatdata/" appid) || index($0, "Metro Last Light Redux") { print $1 }
    ' | sort -n | uniq
}

print_matches() {
  ps -eo pid,ppid,ni,pri,psr,stat,comm,args |
    awk -v appid="$appid" -v name="$process_name" '
      index($0, "AppId=" appid) || index($0, "compatdata/" appid) || index($0, name) || index($0, "Metro Last Light Redux") { print }
    '
}

pids="$(collect_pids)"
if [ -z "$pids" ]; then
  echo "already-stopped appid=$appid process=$process_name"
  exit 0
fi

echo "stopping appid=$appid process=$process_name"
print_matches || true

for pid in $pids; do
  kill -TERM "$pid" 2>/dev/null || true
done

elapsed=0
while [ "$elapsed" -lt "$grace_seconds" ]; do
  sleep 1
  elapsed=$((elapsed + 1))
  pids="$(collect_pids)"
  [ -z "$pids" ] && echo "stopped after=${elapsed}s" && exit 0
done

echo "forcing remaining appid=$appid"
for pid in $pids; do
  kill -KILL "$pid" 2>/dev/null || true
done

sleep 1
pids="$(collect_pids)"
if [ -n "$pids" ]; then
  echo "ERROR app still has matching pids:"
  print_matches || true
  exit 1
fi

echo "stopped forced=1"
