#!/usr/bin/env sh
set -eu

backend_name() { printf '%s\n' "lxc"; }

backend_detect() {
  grep -qaE 'lxc|container=lxc' /proc/1/environ /proc/self/cgroup 2>/dev/null
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
LXC is a strong backend if GPU device nodes and Android abstract socket access are passed through.
Configure the container with access to /dev/dri or /dev/kgsl-3d0 and enough permissions for dmabuf export.
EOF
}
