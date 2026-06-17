# Termux Native Backend

Use this when the Linux workload runs directly inside Termux.

## Install Termux Packages

```sh
pkg update
pkg install -y git clang pkg-config make wayland wayland-protocols libx11 libxtst xorgproto vulkan-tools mesa-demos weston
```

## Install WayLandIE

After pushing the repo to the phone:

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
sh install.sh --backend termux-native --prefix "$HOME/.local" --install-packages
export PATH="$HOME/.local/bin:$PATH"
```

## Start and Test

```sh
waylandie-start-display
waylandie-doctor
waylandie-run vkcube --wsi wayland
```

If Android blocks background activity starts, open the WayLandIE app manually
once, then run the test again.
