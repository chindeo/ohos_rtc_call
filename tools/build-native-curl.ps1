param(
  [string]$NativeSdk = "F:\OpenHarmony\Sdk\13\native",
  [string]$CurlSourceRoot = "",
  [string]$CurlOutputRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "PowerShell 7 or newer is required. Run this script with pwsh.exe."
}

$Root = Split-Path -Parent $PSScriptRoot
$HarmonyRoot = Split-Path -Parent $Root
if (-not $CurlSourceRoot) {
  $CurlSourceRoot = Join-Path $HarmonyRoot "third_party_curl"
}
if (-not $CurlOutputRoot) {
  $CurlOutputRoot = Join-Path $CurlSourceRoot "out\curl-ohos\.build"
}

$Cmake = Join-Path $NativeSdk "build-tools\cmake\bin\cmake.exe"
$Ninja = Join-Path $NativeSdk "build-tools\cmake\bin\ninja.exe"
$Strip = Join-Path $NativeSdk "llvm\bin\llvm-strip.exe"
$Toolchain = Join-Path $NativeSdk "build\cmake\ohos.toolchain.cmake"
$SdkManifest = Join-Path $NativeSdk "oh-uni-package.json"
$NativeSource = Join-Path $Root "src\main\cpp"
$BuildRoot = Join-Path $Root ".native-curl-build"

foreach ($RequiredPath in @($Cmake, $Ninja, $Strip, $Toolchain, $SdkManifest,
  (Join-Path $NativeSdk "sysroot"), (Join-Path $CurlSourceRoot "include"))) {
  if (-not (Test-Path -LiteralPath $RequiredPath)) {
    throw "Required path not found: $RequiredPath"
  }
}

$SdkInfo = Get-Content -LiteralPath $SdkManifest -Raw
if ($SdkInfo -notmatch '"apiVersion"\s*:\s*"?13"?') {
  throw "NativeSdk must be an OpenHarmony API 13 SDK: $NativeSdk"
}

$Targets = @(
  [ordered]@{
    Abi = "armeabi-v7a"
    Curl = Join-Path $CurlOutputRoot "https-arm32-v7"
    OpenSsl = Join-Path $CurlOutputRoot "openssl-arm32-v7"
  },
  [ordered]@{
    Abi = "arm64-v8a"
    Curl = Join-Path $CurlOutputRoot "https-arm64"
    OpenSsl = Join-Path $CurlOutputRoot "openssl-arm64"
  }
)

foreach ($Target in $Targets) {
  $CurlLibrary = Join-Path $Target.Curl "lib\libcurl.a"
  $SslLibrary = Join-Path $Target.OpenSsl "libssl.a"
  $CryptoLibrary = Join-Path $Target.OpenSsl "libcrypto.a"
  foreach ($Library in @($CurlLibrary, $SslLibrary, $CryptoLibrary)) {
    if (-not (Test-Path -LiteralPath $Library)) {
      throw "Static dependency not found: $Library"
    }
  }

  $BuildDir = Join-Path $BuildRoot $Target.Abi
  $OutputDir = Join-Path $Root ("libs\" + $Target.Abi)
  $OutputLibrary = Join-Path $OutputDir "libcurl_http.so"
  New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

  Write-Host "Configuring native curl adapter for $($Target.Abi)..."
  & $Cmake --fresh `
    -S $NativeSource `
    -B $BuildDir `
    -G Ninja `
    "-DCMAKE_TOOLCHAIN_FILE=$Toolchain" `
    "-DCMAKE_MAKE_PROGRAM=$Ninja" `
    "-DOHOS_ARCH=$($Target.Abi)" `
    -DCMAKE_BUILD_TYPE=Release `
    "-DCURL_SOURCE_ROOT=$CurlSourceRoot" `
    "-DCURL_BUILD_ROOT=$($Target.Curl)" `
    "-DOPENSSL_BUILD_ROOT=$($Target.OpenSsl)"
  if ($LASTEXITCODE -ne 0) {
    throw "CMake configure failed for $($Target.Abi)."
  }

  Write-Host "Building native curl adapter for $($Target.Abi)..."
  & $Cmake --build $BuildDir --parallel
  if ($LASTEXITCODE -ne 0) {
    throw "CMake build failed for $($Target.Abi)."
  }

  $BuiltLibrary = Join-Path $BuildDir "libcurl_http.so"
  if (-not (Test-Path -LiteralPath $BuiltLibrary)) {
    throw "Native library was not produced: $BuiltLibrary"
  }
  & $Strip $BuiltLibrary -o $OutputLibrary
  if ($LASTEXITCODE -ne 0) {
    throw "llvm-strip failed for $($Target.Abi)."
  }
  $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputLibrary).Hash.ToLowerInvariant()
  Write-Host "NATIVE_ABI=$($Target.Abi)"
  Write-Host "NATIVE_LIBRARY=$OutputLibrary"
  Write-Host "NATIVE_SHA256=$Hash"
}

Write-Host "Native curl adapter build finished."
