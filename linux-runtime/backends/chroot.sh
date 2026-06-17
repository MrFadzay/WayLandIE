#!/usr/bin/env sh
set -eu

backend_name() { printf '%s\n' "chroot"; }

backend_detect() {
  [ "$(id -u)" = "0" ] && [ -d /proc ] && [ -d /sys ]
}

backend_install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      build-essential pkg-config wayland-protocols libwayland-dev \
      libx11-dev libxtst-dev x11-utils netcat-openbsd vulkan-tools weston \
      python3 curl ca-certificates unzip tar
  else
    printf 'Install compiler, pkg-config, wayland dev headers, wayland-protocols, X11/XTest dev headers, nc, vulkan-tools.\n' >&2
  fi
}

backend_check_gpu_access() {
  for node in /dev/dri/renderD128 /dev/kgsl-3d0; do
    [ -e "$node" ] && printf 'gpu-node=%s\n' "$node"
  done
}

backend_notes() {
  cat <<'EOF'
Chroot is the recommended backend for rooted Android gaming when device nodes are bind-mounted.
Bind /dev, /proc, /sys, /tmp, and GPU nodes from Android before launching the rootfs.
EOF
}
