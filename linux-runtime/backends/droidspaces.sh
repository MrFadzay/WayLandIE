#!/usr/bin/env sh
set -eu

backend_name() { printf '%s\n' "droidspaces"; }

backend_detect() {
  [ -n "${DROIDSPACES_NAME:-}" ] || [ -x /data/local/Droidspaces/bin/droidspaces ]
}

backend_install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      build-essential pkg-config wayland-protocols libwayland-dev \
      libx11-dev libxtst-dev x11-utils netcat-openbsd vulkan-tools weston \
      python3 curl ca-certificates unzip tar
  else
    printf 'Install packages inside the running Droidspaces rootfs with its distro package manager.\n' >&2
  fi
}

backend_check_gpu_access() {
  for node in /dev/dri/renderD128 /dev/kgsl-3d0; do
    [ -e "$node" ] && printf 'gpu-node=%s\n' "$node"
  done
}

backend_notes() {
  cat <<'EOF'
Droidspaces is a tested backend, not a required dependency.
The portable project should also work in normal Termux, chroot, LXC, or proot when the Linux side can produce dmabufs.
EOF
}
