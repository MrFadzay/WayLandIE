# Android Display App

The Android app owns the visible display surface. It listens on the abstract
socket `waylandie.display.bridge.v1`, receives bridge metadata, imports the
GPU path, and presents through the Android-side Vulkan presenter.

## Build

From Windows:

```powershell
cd path\to\WayLandIE\android-app
.\tools\build-apk.ps1
```

For a full GPU-path build, install Android NDK and require the native library:

```powershell
.\tools\build-apk.ps1 -RequireNative -NdkRoot C:\path\to\android-ndk
```

Without a verified NDK or prebuilt native library, the script can still build a
Java fallback APK for UI smoke testing, but that is not the full dmabuf/Vulkan
presenter build.

The APK is written to:

```text
android-app/out/waylandie-display-mvp.apk
```

Install it with:

```powershell
.\tools\deploy-apk.ps1
```

## Runtime Contract

Default app package:

```text
io.waylandie.display/.MainActivity
```

Default bridge socket:

```text
waylandie.display.bridge.v1
```

Default Android Vulkan driver name:

```text
vulkan.waylandie.a8xx.so
```

Driver blobs are local-only and are intentionally not committed to this repo.
