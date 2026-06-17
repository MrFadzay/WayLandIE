# Linux Runtime

`linux-runtime` is the portable Linux side of WayLandIE.

It provides:

- `waylandie-run`: runs one Wayland client through the bridge helper.
- `waylandie-start-display`: starts the Android display activity from Termux or a shell.
- `waylandie-status`: checks whether the Android bridge socket exists.
- `waylandie-doctor`: prints backend, package, and GPU access diagnostics.
- `waylandie-import-qcom-adreno-driver`: imports a user-supplied Qualcomm driver package.
- `steam/`: optional Steam launch and per-game profile tooling.

## Install

```sh
sh install.sh --backend termux-native --prefix "$HOME/.local" --install-packages
export PATH="$HOME/.local/bin:$PATH"
```

For Debian-style proot, chroot, and LXC containers:

```sh
sh install.sh --backend proot --prefix /usr/local --install-packages
```

Use `--backend chroot`, `--backend lxc`, or `--backend droidspaces` when that
matches the environment.

## Test

```sh
waylandie-start-display
waylandie-run vkcube --wsi wayland
waylandie-run weston-simple-egl
```

## Steam Session Tools

Install the optional Steam helpers after the base runtime:

```sh
bash steam/install-steam-profiles.sh --prefix /usr/local
```

Then start the Steam ARM64 + Gamescope session through the WayLandIE bridge:

```sh
waylandie-steam-session start
waylandie-steam-session status
waylandie-steam-session restart
waylandie-steam-session stop
```

The session controller uses the same shape as the working development setup:
WayLandIE starts the Android display, runs Gamescope as the external Wayland
client, and launches the Steam ARM64 client inside Gamescope.
