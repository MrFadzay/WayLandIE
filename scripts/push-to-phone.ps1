param(
  [string]$Adb = "adb",
  [string]$Destination = "/sdcard/Download/WayLandIE",
  [switch]$Clean
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Stage = Join-Path $env:TEMP "WayLandIE-push"

if (Test-Path $Stage) {
  Remove-Item -Recurse -Force $Stage
}
New-Item -ItemType Directory -Force $Stage | Out-Null

$excludeDirs = @(
  ".git",
  ".idea",
  ".vscode",
  "obj",
  "out",
  "keystore",
  "steamapps",
  "compatdata",
  "shadercache",
  "local-bundles",
  "qcom-adreno-*",
  "dxvk-slot-*",
  "turnip-slot-*"
)
$excludeFiles = @(
  "*.apk",
  "*.aab",
  "*.idsig",
  "*.keystore",
  "*.jks",
  "*.deb",
  "*.rpm",
  "*.zip",
  "*.tar",
  "*.tar.gz",
  "*.tgz",
  "*.tar.xz",
  "*.7z",
  "*.so",
  "*.dll",
  "*.exe",
  "*.log"
)

$robocopyArgs = @($Root, $Stage, "/MIR", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/XD") + $excludeDirs + @("/XF") + $excludeFiles
& robocopy @robocopyArgs | Out-Host
if ($LASTEXITCODE -gt 7) {
  throw "robocopy failed with exit code $LASTEXITCODE"
}

& $Adb version | Out-Host
& $Adb devices | Out-Host

if ($Clean) {
  $keep = "$Destination.local-bundles.keep"
  & $Adb shell "rm -rf '$keep'; if [ -d '$Destination/local-bundles' ]; then mv '$Destination/local-bundles' '$keep'; fi; rm -rf '$Destination'; mkdir -p '$Destination'; if [ -d '$keep' ]; then mv '$keep' '$Destination/local-bundles'; fi"
}

& $Adb shell "mkdir -p '$Destination'"
& $Adb push "$Stage\." "$Destination"

Write-Host "pushed=$Destination"
Write-Host "termux_next=cd $Destination/linux-runtime && sh install.sh --backend termux-native --prefix `"`$HOME/.local`" --install-packages"
