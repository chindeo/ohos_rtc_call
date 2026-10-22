# Build (and optionally install) the minimal TTS probe app against the locally built HAR.
#
#   pwsh -File example/tts-probe/build-probe.ps1                     # HAR + ohpm + assembleHap
#   pwsh -File example/tts-probe/build-probe.ps1 -Target 192.168.30.118:5555 -Install
#
# Signing material is maintained by the developer (DevEco Studio -> Project Structure ->
# Signing Configs -> Automatically generate signature) and never committed.
#
# For a one-off device test you can borrow a host project's profile instead:
#   pwsh -File example/tts-probe/build-probe.ps1 -Install -Target 192.168.20.58:5555 `
#        -BorrowSigningFrom D:\...\5.0.1-SHIMeta\build-profile.json5 -BorrowBundle com.chindeo.bed
# Each auto-sign profile pins ONE bundle name, so -BorrowBundle must be the name that profile
# was issued for. The block is written in only for the duration of the build and always restored,
# so the passwords never stay on disk (and never reach Git).
param(
  [string]$Hvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat',
  [string]$Ohpm = 'C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin\ohpm.bat',
  [string]$Hdc = 'F:\OpenHarmony\Sdk\23\toolchains\hdc.exe',
  [string]$Target = '',
  [string]$BundleName = 'com.chindeo.ttprobe',
  [string]$BorrowSigningFrom = '',
  [string]$BorrowBundle = '',
  [switch]$SkipHar,
  [switch]$Install
)
$ErrorActionPreference = 'Stop'

$Probe = Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo = (Resolve-Path (Join-Path $Probe '..\..')).Path

if (-not $SkipHar) {
  Write-Host "==> publishing local HAR from $Repo"
  & (Join-Path $Repo 'tools\publish-ohos-rtc-call.ps1') -DevTimestampName -SkipPrepublish
  if ($LASTEXITCODE -ne 0) { throw "publish-ohos-rtc-call.ps1 failed with exit code $LASTEXITCODE." }
}

$Har = Get-ChildItem (Join-Path $Repo 'dist\*.har') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Har) { throw "no HAR under $Repo\dist; drop -SkipHar or publish first." }
$HarTarget = Join-Path $Probe 'libs\ohos-rtc-call.har'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $HarTarget) | Out-Null
Copy-Item -LiteralPath $Har.FullName -Destination $HarTarget -Force
Write-Host "==> probe HAR <- $($Har.Name)"

$ProfilePath = Join-Path $Probe 'build-profile.json5'
$ProfileOriginal = Get-Content -Raw -LiteralPath $ProfilePath

if ($BorrowSigningFrom) {
  $Source = Get-Content -Raw -LiteralPath $BorrowSigningFrom
  if ($Source -notmatch '(?ms)"signingConfigs"\s*:\s*\[.*?\]\s*,') {
    throw "no signingConfigs block found in $BorrowSigningFrom"
  }
  $Block = $Matches[0]
  if ($Block -notmatch '"name"\s*:\s*"([^"]+)"') { throw "borrowed signingConfigs has no name" }
  $SignName = $Matches[1]
  $Patched = $ProfileOriginal -replace '(?ms)"signingConfigs"\s*:\s*\[\s*\],', { param($m) $Block }
  # The block alone is not enough: hvigor only signs a product that names a signingConfig.
  $Patched = $Patched -replace '("products"\s*:\s*\[\s*\{\s*"name"\s*:\s*"default"\s*,)', "`$1`r`n        `"signingConfig`": `"$SignName`","
  if ($Patched -notmatch '"signingConfig"') { throw "failed to wire signingConfig=$SignName into the product" }
  $Patched | Set-Content -LiteralPath $ProfilePath -NoNewline
  if ($BorrowBundle) {
    (Get-Content -Raw -LiteralPath $ProfilePath) -replace '"bundleName"\s*:\s*"com\.chindeo\.ttprobe"',
      "`"bundleName`": `"$BorrowBundle`"" | Set-Content -LiteralPath $ProfilePath -NoNewline
  }
  Write-Host "==> borrowed signing block from $BorrowSigningFrom (signingConfig=$SignName, bundle=$BorrowBundle); will restore"
}

Push-Location $Probe
try {
  Write-Host '==> ohpm install'
  & $Ohpm install --all
  if ($LASTEXITCODE -ne 0) { throw "ohpm install failed with exit code $LASTEXITCODE." }

  Write-Host '==> hvigor assembleHap'
  & $Hvigor assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
  if ($LASTEXITCODE -ne 0) { throw "Hvigor build failed with exit code $LASTEXITCODE." }
} finally {
  Pop-Location
  Set-Content -LiteralPath $ProfilePath -Value $ProfileOriginal -NoNewline
  if ($BorrowSigningFrom) { Write-Host '==> build-profile.json5 restored (no passwords left on disk)' }
}

$OutDir = Join-Path $Probe 'entry\build\default\outputs\default'
# assembleHap drops both entry-default-unsigned.hap and entry-default-signed.hap; the newest by
# mtime is not necessarily the signed one, and installing the unsigned file only yields "no signature file".
$Hap = Get-ChildItem (Join-Path $OutDir '*-signed.hap') -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Hap) {
  if ($Install) { throw "no signed HAP under $OutDir - signing was not applied, refusing to install an unsigned build." }
  $Hap = Get-ChildItem (Join-Path $OutDir '*.hap') -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if (-not $Hap) { throw 'no HAP produced; check the hvigor log above.' }
Write-Host "==> HAP: $($Hap.FullName) ($($Hap.Length) bytes)"

if (-not $Install) {
  Write-Host 'Build only. Pass -Install -Target <ip:port> to install on a device.'
  return
}

$Profile = Get-Content -Raw -LiteralPath $ProfilePath
if (-not $BorrowSigningFrom -and $Profile -match '"signingConfigs"\s*:\s*\[\s*\]') {
  throw 'build-profile.json5 has no signingConfigs - generate signing material in DevEco, or pass -BorrowSigningFrom/-BorrowBundle.'
}
if (-not $Target) { throw '-Target is required with -Install.' }

Write-Host "==> installing on $Target"
& $Hdc -t $Target install -r $Hap.FullName
if ($LASTEXITCODE -ne 0) { throw "hdc install failed with exit code $LASTEXITCODE." }
# install -r + start does not reload code on a live process; force a cold start.
& $Hdc -t $Target shell "aa force-stop $BundleName" | Out-Null
& $Hdc -t $Target shell "aa start -b $BundleName -a EntryAbility"
Write-Host "==> logs: & $Hdc -t $Target shell 'hilog -x -T RtcTts' (expect stage=init ok=true noiseScale=1 fsts=3)"
