#!/usr/bin/env sh
set -eu

HOST="${WAYLANDIE_STATUS_HOST:-127.0.0.1}"
PORT="${WAYLANDIE_STATUS_PORT:-57391}"
COMMAND="${1:-display}"

if command -v nc >/dev/null 2>&1; then
  printf '%s\n' "$COMMAND" | nc "$HOST" "$PORT"
elif command -v busybox >/dev/null 2>&1; then
  printf '%s\n' "$COMMAND" | busybox nc "$HOST" "$PORT"
else
  echo "missing nc/busybox nc; cannot query WayLandIE status" >&2
  exit 1
fi
