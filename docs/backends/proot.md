# Proot Backend

Use this for a Debian or Ubuntu userspace installed through Termux
`proot-distro`.

## Create a Debian Proot

From Termux:

```sh
pkg update
pkg install -y proot-distro
proot-distro install debian
termux-setup-storage
```

Copy the repo into a location visible from the proot, then enter:

```sh
proot-distro login debian --shared-tmp
```

Inside Debian:

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
sh install.sh --backend proot --prefix /usr/local --install-packages
waylandie-start-display
waylandie-run weston-simple-egl
```

If `/sdcard` is not visible in your proot, copy the folder into the proot home
directory from Termux first.

## Notes

Proot is easier to reproduce than chroot, but it can add syscall and filesystem
overhead. Use it as the portable baseline, then move to chroot or LXC for lower
overhead testing.
