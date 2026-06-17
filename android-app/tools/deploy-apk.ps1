param(
    [string]$Apk = "",
    [switch]$Bridge,
    [switch]$AhbCpuProducer,
    [switch]$VulkanProducer,
    [switch]$ForceStopBeforeLaunch
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $Apk) {
    $Apk = Join-Path $ProjectRoot "out\waylandie-display-mvp.apk"
}

if (-not (Test-Path $Apk)) {
    throw "APK not found: $Apk"
}

adb install -r $Apk
if ($LASTEXITCODE -ne 0) { throw "adb install failed" }

$amArgs = @("shell", "am", "start", "-n", "io.waylandie.display/.MainActivity")
if ($Bridge) {
    $amArgs += @("--ez", "waylandie_bridge_server", "true")
}
if ($AhbCpuProducer) {
    $amArgs += @("--ez", "waylandie_ahb_cpu_producer", "true")
}
if ($VulkanProducer) {
    $amArgs += @("--ez", "waylandie_vulkan_producer", "true")
}
if ($ForceStopBeforeLaunch) {
    adb shell am force-stop io.waylandie.display
    if ($LASTEXITCODE -ne 0) { throw "am force-stop failed" }
}

adb @amArgs
if ($LASTEXITCODE -ne 0) { throw "am start failed" }
