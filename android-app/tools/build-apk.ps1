param(
    [string]$SdkRoot = "$env:LOCALAPPDATA\Android\Sdk",
    [string]$JavaHome = "$env:JAVA_HOME",
    [string]$NdkRoot = "",
    [switch]$RequireNative
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
function Test-NdkLayout {
    param(
        [string]$CandidateRoot,
        [string]$RequiredClangRelativePath
    )

    if (-not $CandidateRoot) {
        return $false
    }

    $NdkSourceProperties = Join-Path $CandidateRoot "source.properties"
    $NdkClang = Join-Path $CandidateRoot $RequiredClangRelativePath
    return (Test-Path $NdkSourceProperties) -and (Test-Path $NdkClang)
}

function Get-NdkSortVersion {
    param([string]$Name)

    try {
        return [version]$Name
    } catch {
        return [version]"0.0"
    }
}

function Resolve-NdkRoot {
    param(
        [string]$ExplicitNdkRoot,
        [string]$ProjectRoot,
        [string]$SdkRoot,
        [string]$RequiredClangRelativePath
    )

    $LookedPaths = [System.Collections.Generic.List[string]]::new()
    $RepoLocalNdk = Join-Path $ProjectRoot "android-ndk\android-ndk-r29"

    if ($ExplicitNdkRoot) {
        $LookedPaths.Add($ExplicitNdkRoot)
        return [pscustomobject]@{
            Root = $ExplicitNdkRoot
            LookedPaths = $LookedPaths.ToArray()
            Explicit = $true
        }
    }

    $LookedPaths.Add($RepoLocalNdk)
    if (Test-NdkLayout -CandidateRoot $RepoLocalNdk -RequiredClangRelativePath $RequiredClangRelativePath) {
        return [pscustomobject]@{
            Root = $RepoLocalNdk
            LookedPaths = $LookedPaths.ToArray()
            Explicit = $false
        }
    }

    $SdkNdkRoot = Join-Path $SdkRoot "ndk"
    $LookedPaths.Add($SdkNdkRoot)

    if (Test-Path $SdkNdkRoot) {
        $SdkNdkCandidates = Get-ChildItem -Path $SdkNdkRoot -Directory |
            Sort-Object -Property `
                @{ Expression = { Get-NdkSortVersion $_.Name }; Descending = $true }, `
                @{ Expression = { $_.Name }; Descending = $true }

        foreach ($SdkNdkCandidate in $SdkNdkCandidates) {
            $LookedPaths.Add($SdkNdkCandidate.FullName)
            if (Test-NdkLayout -CandidateRoot $SdkNdkCandidate.FullName -RequiredClangRelativePath $RequiredClangRelativePath) {
                return [pscustomobject]@{
                    Root = $SdkNdkCandidate.FullName
                    LookedPaths = $LookedPaths.ToArray()
                    Explicit = $false
                }
            }
        }
    }

    return [pscustomobject]@{
        Root = $null
        LookedPaths = $LookedPaths.ToArray()
        Explicit = $false
    }
}

$RequiredNdkClangRelativePath = "toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android33-clang.cmd"
$ResolvedNdk = Resolve-NdkRoot `
    -ExplicitNdkRoot $NdkRoot `
    -ProjectRoot $ProjectRoot `
    -SdkRoot $SdkRoot `
    -RequiredClangRelativePath $RequiredNdkClangRelativePath
$NdkRoot = $ResolvedNdk.Root
$NdkLookupPaths = $ResolvedNdk.LookedPaths
$BuildTools = Join-Path $SdkRoot "build-tools\36.1.0"
$AndroidJar = Join-Path $SdkRoot "platforms\android-36\android.jar"
$Aapt2 = Join-Path $BuildTools "aapt2.exe"
$D8 = Join-Path $BuildTools "d8.bat"
$ApkSigner = Join-Path $BuildTools "apksigner.bat"
$ZipAlign = Join-Path $BuildTools "zipalign.exe"

if (-not $JavaHome) {
    $Java = (Get-Command java.exe).Source
    $Javac = (Get-Command javac.exe).Source
    $Jar = (Get-Command jar.exe).Source
    $Keytool = (Get-Command keytool.exe).Source
} else {
    $JavaBin = Join-Path $JavaHome "bin"
    $Java = Join-Path $JavaBin "java.exe"
    $Javac = Join-Path $JavaBin "javac.exe"
    $Jar = Join-Path $JavaBin "jar.exe"
    $Keytool = Join-Path $JavaBin "keytool.exe"
}

foreach ($Path in @($Aapt2, $D8, $ApkSigner, $ZipAlign, $AndroidJar, $Java, $Javac, $Jar, $Keytool)) {
    if (-not (Test-Path $Path)) {
        throw "Missing required build tool: $Path"
    }
}

$ObjDir = Join-Path $ProjectRoot "obj"
$GenDir = Join-Path $ObjDir "gen"
$ClassDir = Join-Path $ObjDir "classes"
$DexDir = Join-Path $ObjDir "dex"
$FlatDir = Join-Path $ObjDir "flat"
$NativeBuildDir = Join-Path $ObjDir "native"
$OutDir = Join-Path $ProjectRoot "out"
$KeystoreDir = Join-Path $ProjectRoot "keystore"
$UnsignedApk = Join-Path $ObjDir "waylandie-display-unsigned.apk"
$DexedApk = Join-Path $ObjDir "waylandie-display-dexed.apk"
$AlignedApk = Join-Path $ObjDir "waylandie-display-aligned.apk"
$SignedApk = Join-Path $OutDir "waylandie-display-mvp.apk"
$Keystore = Join-Path $KeystoreDir "debug.keystore"

Remove-Item -Recurse -Force $ObjDir, $OutDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $GenDir, $ClassDir, $DexDir, $FlatDir, $OutDir, $KeystoreDir | Out-Null

$NativeApkRoot = $null
$NativeSource = Join-Path $ProjectRoot "native\waylandie_display_native.c"
$NdkSourceProperties = if ($NdkRoot) { Join-Path $NdkRoot "source.properties" } else { $null }
$NdkToolchainBin = if ($NdkRoot) { Join-Path $NdkRoot "toolchains\llvm\prebuilt\windows-x86_64\bin" } else { $null }
$NdkClang = if ($NdkToolchainBin) { Join-Path $NdkToolchainBin "aarch64-linux-android33-clang.cmd" } else { $null }
$NdkStrip = if ($NdkToolchainBin) { Join-Path $NdkToolchainBin "llvm-strip.exe" } else { $null }

if ($NdkSourceProperties -and $NdkClang -and (Test-Path $NdkSourceProperties) -and (Test-Path $NdkClang)) {
    $NativeApkRoot = Join-Path $NativeBuildDir "apk"
    $NativeLibDir = Join-Path $NativeApkRoot "lib\arm64-v8a"
    $NativeOutput = Join-Path $NativeLibDir "libwaylandie_display_native.so"
    New-Item -ItemType Directory -Force $NativeLibDir | Out-Null

    & $NdkClang -shared -fPIC -O2 -Wall -Wextra -o $NativeOutput $NativeSource -landroid
    if ($LASTEXITCODE -ne 0) { throw "native clang failed" }

    $AdrenoToolsPrebuiltDir = Join-Path $ProjectRoot "deps\adrenotools\built-arm64"
    if (Test-Path $AdrenoToolsPrebuiltDir) {
        $AdrenoToolsLibraries = Get-ChildItem -Path $AdrenoToolsPrebuiltDir -Filter *.so -File
        foreach ($AdrenoToolsLibrary in $AdrenoToolsLibraries) {
            Copy-Item -Force $AdrenoToolsLibrary.FullName (Join-Path $NativeLibDir $AdrenoToolsLibrary.Name)
        }
        if ($AdrenoToolsLibraries.Count -gt 0) {
            Write-Host "Bundled AdrenoTools libraries from $AdrenoToolsPrebuiltDir"
        }
    }

    if (Test-Path $NdkStrip) {
        & $NdkStrip --strip-unneeded $NativeOutput
        if ($LASTEXITCODE -ne 0) { throw "native strip failed" }
    }

    Write-Host "Using NDK $NdkRoot"
    Write-Host "Built native smoke library $NativeOutput"
} else {
    $PrebuiltNativeApkRoot = Join-Path $ProjectRoot "deps\native-prebuilt-apk"
    if (Test-Path (Join-Path $PrebuiltNativeApkRoot "lib\arm64-v8a\libwaylandie_display_native.so")) {
        $NativeApkRoot = $PrebuiltNativeApkRoot
        Write-Host "Using prebuilt native libraries from $PrebuiltNativeApkRoot"
    }
    $LookedPathsMessage = if ($NdkLookupPaths.Count -gt 0) { $NdkLookupPaths -join "; " } else { "<none>" }
    $NdkOverrideHint = "Pass -NdkRoot C:\path\to\android-ndk to force a specific NDK."
    if ($ResolvedNdk.Explicit) {
        Write-Warning "Verified NDK not found at $NdkRoot; building Java-only APK with native fallback UI. $NdkOverrideHint"
    } else {
        Write-Warning "Verified NDK not found. Looked in: $LookedPathsMessage. Building Java-only APK with native fallback UI. $NdkOverrideHint"
    }
    if ($RequireNative -and -not $NativeApkRoot) {
        throw "Native build required but no verified NDK or prebuilt native library was found. $NdkOverrideHint"
    }
}

& $Aapt2 compile --dir (Join-Path $ProjectRoot "res") -o $FlatDir
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile failed" }

$FlatFiles = Get-ChildItem -Path $FlatDir -Filter *.flat -Recurse | ForEach-Object { $_.FullName }
& $Aapt2 link `
    -o $UnsignedApk `
    -I $AndroidJar `
    --manifest (Join-Path $ProjectRoot "AndroidManifest.xml") `
    --java $GenDir `
    --min-sdk-version 33 `
    --target-sdk-version 36 `
    --version-code 1 `
    --version-name "0.1.0" `
    $FlatFiles
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }

$SourceFiles = @()
$SourceFiles += Get-ChildItem -Path (Join-Path $ProjectRoot "src") -Filter *.java -Recurse | ForEach-Object { $_.FullName }
$SourceFiles += Get-ChildItem -Path $GenDir -Filter *.java -Recurse | ForEach-Object { $_.FullName }

& $Javac `
    -encoding UTF-8 `
    -source 17 `
    -target 17 `
    -classpath $AndroidJar `
    -d $ClassDir `
    $SourceFiles
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

$ClassFiles = Get-ChildItem -Path $ClassDir -Filter *.class -Recurse | ForEach-Object { $_.FullName }
& $D8 --min-api 33 --output $DexDir $ClassFiles
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }

Copy-Item $UnsignedApk $DexedApk
& $Jar uf $DexedApk -C $DexDir .
if ($LASTEXITCODE -ne 0) { throw "jar update failed" }

if ($NativeApkRoot) {
    & $Jar uf $DexedApk -C $NativeApkRoot .
    if ($LASTEXITCODE -ne 0) { throw "native jar update failed" }
}

& $ZipAlign -f -p 4 $DexedApk $AlignedApk
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

if (-not (Test-Path $Keystore)) {
    & $Keytool -genkeypair `
        -keystore $Keystore `
        -storepass android `
        -keypass android `
        -alias androiddebugkey `
        -keyalg RSA `
        -keysize 2048 `
        -validity 10000 `
        -dname "CN=Android Debug,O=Android,C=US"
    if ($LASTEXITCODE -ne 0) { throw "keytool failed" }
}

& $ApkSigner sign `
    --ks $Keystore `
    --ks-pass pass:android `
    --key-pass pass:android `
    --out $SignedApk `
    $AlignedApk
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }

& $ApkSigner verify --verbose $SignedApk
if ($LASTEXITCODE -ne 0) { throw "apksigner verify failed" }

Write-Host "Built $SignedApk"
