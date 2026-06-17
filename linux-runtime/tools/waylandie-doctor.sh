#!/usr/bin/env sh
set -eu

ok=1
check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "cmd:$1=ok"
  else
    echo "cmd:$1=missing"
    ok=0
  fi
}

check_file() {
  if [ -e "$1" ]; then
    echo "path:$1=present"
  else
    echo "path:$1=missing"
  fi
}

check_cmd cc
check_cmd pkg-config
check_cmd wayland-scanner
check_cmd nc || true

for pkg in wayland-server wayland-client; do
  if pkg-config --exists "$pkg" 2>/dev/null; then
    echo "pkg:$pkg=ok"
  else
    echo "pkg:$pkg=missing"
    ok=0
  fi
done

for p in \
  /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
  /usr/share/wayland-protocols/unstable/linux-dmabuf/linux-dmabuf-unstable-v1.xml \
  /usr/share/wayland-protocols/stable/presentation-time/presentation-time.xml; do
  check_file "$p"
done

check_file /dev/dri/renderD128
check_file /dev/kgsl-3d0

if [ "$ok" = "1" ]; then
  echo "doctor=pass"
else
  echo "doctor=fail"
  exit 1
fi
