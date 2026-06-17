# Troubleshooting

## The Android App Does Not Open

Run:

```sh
waylandie-start-display
```

If Android blocks the background start, open WayLandIE manually from the launcher
once, then run the command again.

## The Bridge Socket Is Missing

Run:

```sh
waylandie-status
```

Expected socket:

```text
waylandie.display.bridge.v1
```

If it is missing, the Android display app is not listening or the Linux
environment cannot see Android abstract sockets.

## vkcube Does Not Start

Try:

```sh
waylandie-doctor
command -v vkcube
vulkaninfo --summary
```

If `vkcube` is missing, reinstall with the backend package installer:

```sh
sh install.sh --backend termux-native --install-packages
```

Use the backend that matches your environment.

## Steam Game Does Not Use the Profile

Check:

```sh
waylandie-steam-profile status APPID
```

If `launch_hook=not-installed`, run:

```sh
waylandie-steam-profile hook APPID
```

Restart Steam if Steam was already running while the hook was written.

## Qualcomm Driver Slot Is Missing Files

Run:

```sh
waylandie-steam-profile status APPID
```

If `qcom_vulkan_icd` or `vk_driver_files` is missing, import the driver again:

```sh
waylandie-import-qcom-adreno-driver --name SLOT --appid APPID --activate path/to/qcom-adreno.deb
```

## Droidspaces Is Not Required

If you see Droidspaces in the docs or scripts, it is an optional backend
adapter. New reproducibility tests should start with Termux native or proot.
