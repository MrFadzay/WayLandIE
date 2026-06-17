# Qualcomm Adreno Linux Driver Slots

WayLandIE can test a user-supplied Qualcomm Linux Vulkan driver package as a
Steam profile slot.

The repo does not ship Qualcomm binaries. Do not commit `.deb`, `.so`, extracted
rootfs, or vendor driver folders.

## Import

```sh
waylandie-import-qcom-adreno-driver --name qcom-251009 ~/Downloads/qcom-adreno-0.1_arm64.deb
```

Create and activate a Steam game profile in one step:

```sh
waylandie-import-qcom-adreno-driver --name qcom-251009 --appid 287390 --activate ~/Downloads/qcom-adreno-0.1_arm64.deb
```

## What the Importer Does

The importer:

- extracts the package to `$WAYLANDIE_STEAM_PROFILE_ROOT/qcom-adreno/SLOT/rootfs`,
- finds `libvulkan_adreno.so`,
- writes a Vulkan ICD JSON with an absolute library path,
- writes an EGL vendor JSON when an Adreno EGL library exists,
- records GBM backend paths when present,
- writes `qcom-driver.env`,
- optionally creates a Steam profile through `waylandie-steam-profile create-qcom-profile`.

## Optional WSI Layer

If you are testing a Termux/X11/Wayland WSI workaround layer, pass it explicitly:

```sh
waylandie-import-qcom-adreno-driver --name qcom-251009 --wsi-layer /path/to/implicit_layer.d ~/Downloads/qcom-adreno-0.1_arm64.deb
```

This adds:

```text
VK_LAYER_PATH=/path/to/implicit_layer.d
VK_INSTANCE_LAYERS=VK_LAYER_window_system_integration
```

## Reality Check

The Qualcomm path is experimental. Turnip remains the portable open driver path.
Use Qualcomm slots for measurable A/B testing, not as a guaranteed default.

## Private Bundle Export

If a working container already has Qualcomm slots, the private Steam ARM64
bundle exporter includes those slots in the local tarball:

```sh
waylandie-steam-export-arm64-bundle --output ~/waylandie-steam-arm64-bundle.tar.gz
```

The public repository still does not ship Qualcomm binaries. The bundle is a
local artifact for your own devices. During install, copied slots are normalized
under `$XDG_CONFIG_HOME/waylandie/steam/qcom-adreno` and fresh `qcom-driver.env`
metadata is generated for the target path.
