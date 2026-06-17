# Chroot and LXC Backends

Use chroot or LXC when you want lower overhead than proot and you can provide
rooted Android device access.

## Chroot Checklist

There is no single universal Android chroot command because ROMs expose device
nodes differently. A practical rootfs path is:

1. Create or download an arm64 Debian/Ubuntu rootfs tarball.
2. Extract it to a rooted location such as `/data/local/waylandie-rootfs`.
3. Bind Android system paths into it.
4. Enter the rootfs with `chroot`.

Example shape:

```sh
su
mkdir -p /data/local/waylandie-rootfs
tar -xf /sdcard/Download/debian-arm64-rootfs.tar.gz -C /data/local/waylandie-rootfs
mount -t proc proc /data/local/waylandie-rootfs/proc
mount --rbind /sys /data/local/waylandie-rootfs/sys
mount --rbind /dev /data/local/waylandie-rootfs/dev
mount --rbind /sdcard /data/local/waylandie-rootfs/sdcard
chroot /data/local/waylandie-rootfs /bin/bash
```

Bind or expose the pieces your distro needs:

```text
/dev
/dev/dri if available
/dev/kgsl-3d0 on Adreno devices when available
/proc
/sys
/tmp
/sdcard or another transfer path for WayLandIE
```

Inside the chroot:

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
apt-get update
sh install.sh --backend chroot --prefix /usr/local --install-packages
waylandie-doctor
waylandie-run vkcube --wsi wayland
```

## LXC Checklist

The LXC container needs equivalent device and filesystem access. The exact
configuration is device and ROM specific, but the WayLandIE install command is:

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
sh install.sh --backend lxc --prefix /usr/local --install-packages
waylandie-doctor
```

Use chroot or LXC when measuring real performance. Use proot first when you are
testing reproducibility.
