# Publishing to GitHub

This folder is already arranged as a GitHub repository. To publish it:

## Option 1: GitHub Desktop

1. Open GitHub Desktop.
2. Choose `File -> Add local repository`.
3. Select the `WayLandIE` folder.
4. If asked to initialize a repository, allow it.
5. Review the changed files before committing.
6. Publish the repository as `WayLandIE`.

Recommended repository description:

```text
Android Wayland display bridge for Linux and Steam gaming with GPU-first dmabuf/Vulkan presentation and portable backend support.
```

## Option 2: Git CLI

Install Git for Windows, then run from the `WayLandIE` folder:

```sh
git init
git add .
git commit -m "Initial WayLandIE public project"
git branch -M main
git remote add origin https://github.com/YOUR_NAME/WayLandIE.git
git push -u origin main
```

## Before Publishing

Run:

```powershell
.\scripts\check-public-tree.ps1
.\scripts\setup-phone.ps1 -CleanPush
```

Do not publish:

- Android debug keystores.
- APK build output unless you intentionally attach it to a release.
- Qualcomm driver packages or extracted vendor rootfs trees.
- Steam, Proton, compatdata, shader cache, or game files.

The `.gitignore` file already excludes these by default.
