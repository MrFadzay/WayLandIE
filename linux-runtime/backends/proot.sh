#!/usr/bin/env sh
set -eu

backend_name() { printf '%s\n' "proot"; }

backend_detect() {
  [ -n "${PROOT_TMP_DIR:-}" ] || grep -qi proot /proc/self/status 2>/dev/null || command -v proot >/dev/null 2>&1
}

backend_install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      build-essential pkg-config wayland-protocols libwayland-dev \
      libx11-dev libxtst-dev x11-utils netcat-openbsd vulkan-tools weston
  else
    printf 'Install: compiler, pkg-config, wayland dev headers, wayland-protocols, libX11, libXtst, nc, vulkan-tools.\n' >&2
  fi
}

backend_check_gpu_access() {
  for node in /dev/dri/renderD128 /dev/kgsl-3d0; do
    [ -e "$node" ] && printf 'gpu-node=%s\n' "$node"
  done
  cat <<'EOF'
proot-note=dmabuf export/import is experimental under proot. For real gaming, prefer chroot or LXC with real device nodes.
EOF
}

backend_notes() {
  cat <<'EOF'
Proot is supported as an experimental backend. It is useful for install testing and light apps.
Steam/FEX/Proton performance may be poor because proot adds syscall/ptrace overhead and may not expose GPU nodes correctly.
EOF
}
