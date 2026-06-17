param(
  [string]$Adb = "adb",
  [string]$Destination = "/sdcard/Download/WayLandIE",
  [string]$NdkRoot = "",
  [switch]$RequireNative,
  [switch]$InstallApk,
  [switch]$SkipAndroidBuild,
  [switch]$CleanPush
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not $SkipAndroidBuild) {
  $buildArgs = @()
  if ($NdkRoot) {
    $buildArgs += @("-NdkRoot", $NdkRoot)
  }
  if ($RequireNative) {
    $buildArgs += "-RequireNative"
  }
  & (Join-Path $Root "android-app\tools\build-apk.ps1") @buildArgs
}

if ($InstallApk) {
  & (Join-Path $Root "android-app\tools\deploy-apk.ps1")
}

$pushParams = @{
  Adb = $Adb
  Destination = $Destination
}
if ($CleanPush) {
  $pushParams.Clean = $true
}
& (Join-Path $Root "scripts\push-to-phone.ps1") @pushParams

Write-Host ""
Write-Host "Phone bundle ready at $Destination"
Write-Host ""
Write-Host "Termux native install:"
Write-Host "  cd $Destination/linux-runtime"
Write-Host "  sh install.sh --backend termux-native --prefix `"`$HOME/.local`" --install-packages"
Write-Host "  export PATH=`"`$HOME/.local/bin:`$PATH`""
Write-Host "  waylandie-start-display"
Write-Host "  waylandie-run vkcube --wsi wayland"
Write-Host ""
Write-Host "Steam helper install inside the Steam Linux environment:"
Write-Host "  cd $Destination/linux-runtime"
Write-Host "  bash steam/install-steam-profiles.sh --prefix /usr/local"
