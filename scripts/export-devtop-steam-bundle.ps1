param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$SshWrapper = "C:\Users\Administrator\Documents\Wayland project\tools\devtop-ssh.ps1",
    [string]$RemoteOutput,
    [string]$LocalOutput,
    [switch]$IncludeProtonBeta,
    [switch]$IncludeProfileState,
    [switch]$RemoteOnly,
    [switch]$KeepRemote,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (Test-Path variable:global:PSNativeCommandUseErrorActionPreference) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

if (-not (Test-Path -LiteralPath $SshWrapper)) {
    throw "Missing SSH wrapper: $SshWrapper"
}

$exporter = Join-Path $RepoRoot "linux-runtime\steam\export-steam-arm64-bundle.sh"
if (-not (Test-Path -LiteralPath $exporter)) {
    throw "Missing exporter: $exporter"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not $RemoteOutput) {
    $RemoteOutput = "/root/waylandie-steam-arm64-bundle-$stamp.tar.gz"
}
if (-not $LocalOutput) {
    $LocalOutput = Join-Path $RepoRoot "local-bundles\waylandie-steam-arm64-bundle-$stamp.tar.gz"
}

$remoteScript = "/tmp/waylandie-export-steam-arm64-bundle.sh"

& $SshWrapper -Upload $exporter -RemotePath $remoteScript
if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload exporter."
}

$args = @("bash", $remoteScript, "--output", $RemoteOutput)
if ($IncludeProtonBeta) { $args += "--include-proton-beta" }
if ($IncludeProfileState) { $args += "--include-profile-state" }
if ($DryRun) { $args += "--dry-run" }

$quoted = $args | ForEach-Object {
    "'" + ($_ -replace "'", "'\''") + "'"
}
$commandLine = "chmod 755 '$remoteScript'; " + ($quoted -join " ")

& $SshWrapper -CommandLine $commandLine
if ($LASTEXITCODE -ne 0) {
    throw "Remote export failed."
}

if ($DryRun -or $RemoteOnly) {
    Write-Host "Remote bundle path: $RemoteOutput"
    exit 0
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LocalOutput) | Out-Null
& $SshWrapper -Download $RemoteOutput -LocalPath $LocalOutput
if ($LASTEXITCODE -ne 0) {
    throw "Bundle download failed."
}

if (-not $KeepRemote) {
    & $SshWrapper -CommandLine "rm -f '$RemoteOutput' '$remoteScript'"
}

Write-Host "Local bundle: $LocalOutput"
