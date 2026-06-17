#!/usr/bin/env sh
set -eu

PACKAGE="${WAYLANDIE_ANDROID_PACKAGE:-io.waylandie.display}"
ACTIVITY="${WAYLANDIE_ANDROID_ACTIVITY:-.MainActivity}"

AM_BIN="${AM_BIN:-}"
if [ -z "$AM_BIN" ]; then
  for candidate in am /system/bin/am /system/bin/cmd; do
    if command -v "$candidate" >/dev/null 2>&1; then
      AM_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [ -z "$AM_BIN" ]; then
  cat >&2 <<EOF
No Android activity launcher found in this backend.
Start the app from Android manually, or run from Termux/adb:
  am start -W -f 0x10008000 -n $PACKAGE/$ACTIVITY --ez waylandie_bridge_server true --ez waylandie_external_present_only true
EOF
  exit 1
fi

case "$(basename "$AM_BIN")" in
  cmd)
    exec "$AM_BIN" activity start-activity -W -f 0x10008000 \
      -n "$PACKAGE/$ACTIVITY" \
      --ez waylandie_bridge_server true \
      --ez waylandie_external_present_only true
    ;;
  *)
    exec "$AM_BIN" start -W -f 0x10008000 \
      -n "$PACKAGE/$ACTIVITY" \
      --ez waylandie_bridge_server true \
      --ez waylandie_external_present_only true
    ;;
esac
