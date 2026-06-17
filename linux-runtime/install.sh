#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
usage:
  ./linux-runtime/install.sh [--prefix PREFIX] [--backend auto|termux-native|proot|chroot|lxc|droidspaces] [--install-packages]

examples:
  ./linux-runtime/install.sh --backend termux-native --install-packages
  ./linux-runtime/install.sh --backend chroot --prefix /usr/local --install-packages
  ./linux-runtime/install.sh --backend proot --prefix "$HOME/.local"
EOF
}

PREFIX="/usr/local"
BACKEND="auto"
INSTALL_PACKAGES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --backend) BACKEND="$2"; shift 2 ;;
    --install-packages) INSTALL_PACKAGES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BACKEND_DIR="$ROOT/backends"

load_backend() {
  name="$1"
  file="$BACKEND_DIR/$name.sh"
  [ -r "$file" ] || return 1
  # shellcheck disable=SC1090
  . "$file"
  return 0
}

if [ "$BACKEND" = "auto" ]; then
  for candidate in termux-native lxc proot chroot droidspaces; do
    if load_backend "$candidate" && backend_detect; then
      BACKEND="$candidate"
      break
    fi
  done
fi

if [ "$BACKEND" = "auto" ]; then
  echo "could not auto-detect backend; pass --backend explicitly" >&2
  exit 1
fi

load_backend "$BACKEND" || { echo "unknown backend: $BACKEND" >&2; exit 1; }

echo "waylandie backend=$BACKEND prefix=$PREFIX"
backend_notes || true

if [ "$INSTALL_PACKAGES" = "1" ]; then
  backend_install_packages
fi

mkdir -p "$PREFIX/bin" "$PREFIX/share/waylandie/bridge" "$PREFIX/share/waylandie/backends" "$PREFIX/share/waylandie/drivers"
cp "$ROOT/bridge/waylandie-wayland-bridge.sh" "$PREFIX/share/waylandie/bridge/waylandie-wayland-bridge.sh"
cp "$ROOT/tools/waylandie-run.sh" "$PREFIX/bin/waylandie-run"
cp "$ROOT/tools/waylandie-status.sh" "$PREFIX/bin/waylandie-status"
cp "$ROOT/tools/waylandie-start-display.sh" "$PREFIX/bin/waylandie-start-display"
cp "$ROOT/tools/waylandie-doctor.sh" "$PREFIX/bin/waylandie-doctor"
cp "$BACKEND_DIR"/*.sh "$PREFIX/share/waylandie/backends/"
if [ -f "$ROOT/drivers/import-qcom-adreno-driver.sh" ]; then
  cp "$ROOT/drivers/import-qcom-adreno-driver.sh" "$PREFIX/bin/waylandie-import-qcom-adreno-driver"
  cp "$ROOT/drivers/import-qcom-adreno-driver.sh" "$PREFIX/share/waylandie/drivers/import-qcom-adreno-driver.sh"
fi
chmod 755 "$PREFIX/bin/waylandie-run" "$PREFIX/bin/waylandie-status" "$PREFIX/bin/waylandie-start-display" "$PREFIX/bin/waylandie-doctor" "$PREFIX/share/waylandie/bridge/waylandie-wayland-bridge.sh"
[ -f "$PREFIX/bin/waylandie-import-qcom-adreno-driver" ] && chmod 755 "$PREFIX/bin/waylandie-import-qcom-adreno-driver" "$PREFIX/share/waylandie/drivers/import-qcom-adreno-driver.sh"

backend_check_gpu_access || true

cat <<EOF
installed=pass
backend=$BACKEND
run_display=waylandie-start-display
test_vkcube=waylandie-run vkcube --wsi wayland
status=waylandie-status
import_qcom_driver=waylandie-import-qcom-adreno-driver --name qcom-slot path/to/qcom-adreno.deb
steam_helpers=bash steam/install-steam-profiles.sh --prefix $PREFIX
EOF
