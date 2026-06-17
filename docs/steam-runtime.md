# Steam Runtime and Per-Game Profiles

The Steam tools are optional. They are for the Linux environment that already
runs Steam or a Steam ARM64 build.

## Install

```sh
cd /sdcard/Download/WayLandIE/linux-runtime
bash steam/install-steam-profiles.sh --prefix /usr/local
```

For a non-root Termux-style prefix:

```sh
bash steam/install-steam-profiles.sh --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
```

## What Gets Installed

```text
waylandie-steam-profile
waylandie-steam-game-launch
waylandie-steam-game-boost
waylandie-steam-launch-app
waylandie-steam-stop-app
waylandie-steam-arm64
waylandie-steam-session
waylandie-steam-session-child
waylandie-steam-install-dxvk-slot
waylandie-steam-install-turnip-slot
waylandie-steam-export-arm64-bundle
waylandie-steam-install-arm64-bundle
```

## Workflow

```sh
waylandie-steam-profile bootstrap
waylandie-steam-profile list-games
waylandie-steam-profile hook APPID
waylandie-steam-profile list-profiles APPID
waylandie-steam-profile set APPID turnip-current
waylandie-steam-profile launch APPID --process expected.exe
```

The hook writes Steam Launch Options to:

```text
waylandie-steam-game-launch APPID %command%
```

That keeps the game launch inside Steam's normal AppID and compatibility-tool
flow while still allowing WayLandIE to set the per-game environment.

## Useful Profiles

- `turnip-current`: known-good Mesa/Turnip style path.
- `turnip-mailbox`: Mesa Vulkan WSI mailbox present mode.
- `turnip-immediate`: Mesa Vulkan WSI immediate present mode.
- `turnip-submit-thread`: Mesa Vulkan submit thread test.
- `turnip-custom-icd-slot`: user-provided Turnip/Mesa ICD.
- `dxvk-stock-proton-current`: stock Proton DXVK comparison.
- `dxvk-custom-slot`: user-provided x86-64 DXVK DLLs.
- `qcom-custom-slot`: user-imported Qualcomm Adreno Linux Vulkan driver.

## NTSYNC and HUD Defaults

The default profile environment enables:

```text
PROTON_USE_NTSYNC=1
PROTON_NO_NTSYNC=0
MANGOHUD=1
```

MangoHud config is installed to:

```text
$HOME/.config/MangoHud/WayLandIESteamGame.conf
```

## DXVK and Turnip Slots

```sh
waylandie-steam-install-dxvk-slot --appid APPID --slot my-dxvk --activate ~/Downloads/dxvk.zip
waylandie-steam-install-turnip-slot --appid APPID --slot my-turnip --activate ~/Downloads/turnip.tar.gz
```

DXVK slots expect x86-64 Windows DLLs for Proton/FEX, such as `d3d11.dll` and
`dxgi.dll`. Turnip slots expect native Linux aarch64 Vulkan driver files.

## Steam ARM64 + Gamescope Session

After installing the helper scripts and a private Steam ARM64 bundle, start the
full Steam session with:

```sh
waylandie-steam-session start
waylandie-steam-session status
waylandie-steam-session restart
waylandie-steam-session stop
```

Important defaults:

- `WAYLANDIE_WIDTH=2688`, `WAYLANDIE_HEIGHT=1216`, and `WAYLANDIE_REFRESH=144`.
- Gamescope runs as the external Wayland client through `waylandie-run`.
- Steam launches through `waylandie-steam-arm64` inside Gamescope.
- The Steam UI path keeps CEF GPU enabled and rejects software GL/Vulkan fallbacks.
- Game launches still go through Steam-supported AppID paths and per-game profiles.

## Private Steam ARM64 Starter Bundle

Steam, Proton, and games are not redistributed by this repository. For your own
devices, you can export a private starter bundle from a working Linux container
and install it into another container:

```sh
waylandie-steam-export-arm64-bundle --output ~/waylandie-steam-arm64-bundle.tar.gz
waylandie-steam-install-arm64-bundle --bundle ~/waylandie-steam-arm64-bundle.tar.gz
```

The bundle contains the Steam ARM64 client/runtime pieces, Proton11ARM,
SteamLinuxRuntime_4-arm64, Gamescope/helper files, WayLandIE session/env
snippets, and any local Qualcomm Adreno Linux driver slots found under the
Steam profile config. It intentionally excludes games, `steamapps/common`,
compatdata, shader caches, logs, account userdata, and login config.

On install, Qualcomm slots are re-homed under:

```text
$XDG_CONFIG_HOME/waylandie/steam/qcom-adreno
```

The installer regenerates `qcom-driver.env` and ICD metadata for the target
machine, so profiles created with `waylandie-steam-profile create-qcom-profile`
can use the copied driver slot.

On the Windows host, if the `devtop` SSH backend is already working:

```powershell
.\scripts\export-devtop-steam-bundle.ps1
```

That script uploads the exporter through `tools\devtop-ssh.ps1`, creates the
private tarball inside `devtop`, downloads it to `local-bundles\`, and keeps the
tarball ignored by git.
