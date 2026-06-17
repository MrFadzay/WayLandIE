# WayLandIE

WayLandIE is an Android Wayland display bridge for Linux and Steam gaming. It
keeps the display side as an Android app, then lets a Linux backend in Termux,
proot, chroot, LXC, or Droidspaces run Wayland clients into that app.

The target path is:

```text
Linux Wayland client -> dmabuf metadata -> WayLandIE bridge socket -> Android SurfaceControl/Vulkan presenter
```

The project is built around the GPU-first path from the original experiments:
dmabuf presentation, Android `SurfaceControl`, AdrenoTools-loaded Vulkan
drivers, and `final-copy=forbidden` checks. CPU-copy paths are not the goal.

## Repository Layout

```text
android-app/       Android display app source and APK build scripts
linux-runtime/     Linux-side bridge, backend installers, Steam profile tools
linux-runtime/backends/
                   Termux native, proot, chroot, LXC, and optional Droidspaces adapters
linux-runtime/drivers/
                   User-supplied Qualcomm Adreno driver importer
linux-runtime/steam/
                   Steam launch wrapper, per-game profile manager, DXVK/Turnip slots
examples/          Game and tool examples
docs/              Architecture, backend setup, Steam, drivers, troubleshooting
scripts/           Host-side helpers for packaging and pushing to a phone
```

## Quick Start

Build and install the Android display app from Windows:

```powershell
cd path\to\WayLandIE
.\android-app\tools\build-apk.ps1
.\android-app\tools\deploy-apk.ps1
```

Push the source/runtime bundle to the phone:

```powershell
.\scripts\push-to-phone.ps1
```

Or run the combined host setup wrapper:

```powershell
.\scripts\setup-phone.ps1 -CleanPush
```

For a full native APK build and install:

```powershell
.\scripts\setup-phone.ps1 -RequireNative -NdkRoot C:\path\to\android-ndk -InstallApk -CleanPush
```

In Termux or inside your chosen Linux environment:

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
sh install.sh --backend termux-native --prefix "$HOME/.local" --install-packages
export PATH="$HOME/.local/bin:$PATH"
waylandie-start-display
waylandie-run vkcube --wsi wayland
```

For Debian, Ubuntu, or other chroot/proot/LXC environments, use:

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
sh install.sh --backend proot --prefix /usr/local --install-packages
waylandie-start-display
waylandie-run weston-simple-egl
```

Swap `--backend proot` for `chroot`, `lxc`, or `droidspaces` as needed.
Droidspaces is supported as an adapter, not required as the project foundation.

## Steam Helpers

Install the Steam profile tools inside the Linux environment that runs Steam:

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
bash steam/install-steam-profiles.sh --prefix /usr/local
waylandie-steam-profile bootstrap
waylandie-steam-profile list-games
```

Hook a game so Steam launches it through the WayLandIE profile wrapper:

```sh
waylandie-steam-profile hook 287390
waylandie-steam-profile list-profiles 287390
waylandie-steam-profile set 287390 turnip-current
waylandie-steam-profile launch 287390 --process metro.exe
```

Start or manage the full Steam ARM64 + Gamescope session:

```sh
waylandie-steam-session start
waylandie-steam-session status
waylandie-steam-session restart
waylandie-steam-session stop
```

The profile tool can install custom DXVK and Turnip slots:

```sh
waylandie-steam-install-dxvk-slot --appid 287390 --slot test-dxvk --activate ~/Downloads/dxvk.zip
waylandie-steam-install-turnip-slot --appid 287390 --slot test-turnip --activate ~/Downloads/turnip.tar.gz
```

To clone your own already-working Steam ARM64/Proton starting point into a
private local tarball:

```powershell
.\scripts\export-devtop-steam-bundle.ps1
```

The exported bundle is stored under `local-bundles\` and is ignored by git. It
is for personal devices only unless you have redistribution rights for every
runtime component inside it.

## Qualcomm Driver Slots

Qualcomm Linux driver packages are proprietary and are not shipped here. If you
have a legally obtained package, import it into a named slot:

```sh
waylandie-import-qcom-adreno-driver --name qcom-251009 --appid 287390 --activate ~/Downloads/qcom-adreno-0.1_arm64.deb
```

See [docs/drivers/qualcomm-adreno.md](docs/drivers/qualcomm-adreno.md).

## Status

This repo is an engineering handoff of a working experimental path, not a
polished app-store product yet. The app source and runtime scripts are arranged
so the project can be reviewed, built, and reproduced without depending on the
original Droidspaces container.

Vendor drivers, Steam, Proton, games, and extracted rootfs trees are not
redistributed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Start with:

- [docs/architecture.md](docs/architecture.md)
- [docs/backends/termux.md](docs/backends/termux.md)
- [docs/steam-runtime.md](docs/steam-runtime.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
- [docs/github-publishing.md](docs/github-publishing.md)
