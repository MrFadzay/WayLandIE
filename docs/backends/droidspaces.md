# Droidspaces Backend

Droidspaces was the original working container environment. WayLandIE keeps a
backend adapter for it, but the public project is not built around requiring it.

Inside the running Droidspaces rootfs:

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
sh install.sh --backend droidspaces --prefix /usr/local --install-packages
waylandie-doctor
waylandie-run vkcube --wsi wayland
```

Use this backend only when you already have Droidspaces. New users should start
with Termux native or proot.
