#!/usr/bin/env sh
set -eu

backend_name() { printf '%s\n' "termux-native"; }

backend_detect() {
  [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux/files/usr" ]
}

backend_install_packages() {
  pkg update
  pkg install -y clang pkg-config make wayland wayland-protocols libx11 libxtst xorgproto vulkan-tools mesa-demos weston
}

backend_check_gpu_access() {
  for node in /dev/dri/renderD128 /dev/kgsl-3d0; do
    [ -e "$node" ] && printf 'gpu-node=%s\n' "$node"
  done
}

backend_notes() {
  cat <<'EOF'
Termux-native is best for bridge development, simple Wayland apps, and device-side control.
Steam/FEX/Proton usually need a glibc rootfs through chroot, LXC, or proot.
EOF
}
