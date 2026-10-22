# Build (and optionally install) the minimal TTS probe app against the locally built HAR.
#
#   pwsh -File example/tts-probe/build-probe.ps1                     # HAR + ohpm + assembleHap
#   pwsh -File example/tts-probe/build-probe.ps1 -Target 192.168.30.118:5555 -Install
#
# Signing material is maintained by the developer (DevEco Studio -> Project Structure ->
# Signing Configs -> Automatically generate signature) and never committed, so -Install
# refuses to run while build-profile.json5 has no signingConfigs.
param(
  [string]$Hvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat',
  [string]$Ohpm = 'C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin\ohpm.bat',
  [string]$Hdc = 'F:\OpenHarmony\Sdk\23\toolchains\hdc.exe',
  [string]$Target = '',
  [string]$BundleName = 'com.chindeo.ttprobe',
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
}

$Hap = Get-ChildItem (Join-Path $Probe 'entry\build\default\outputs\default\*.hap') -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Hap) { throw 'no HAP produced; check the hvigor log above.' }
Write-Host "==> HAP: $($Hap.FullName) ($($Hap.Length) bytes)"

if (-not $Install) {
  Write-Host 'Build only. Pass -Install -Target <ip:port> to install on a device.'
  return
}

$Profile = Get-Content -Raw -LiteralPath (Join-Path $Probe 'build-profile.json5')
if ($Profile -match '"signingConfigs"\s*:\s*\[\s*\]') {
  throw 'build-profile.json5 has no signingConfigs yet - generate signing material in DevEco first, then rebuild.'
}
if (-not $Target) { throw '-Target is required with -Install.' }

Write-Host "==> installing on $Target"
& $Hdc -t $Target install -r $Hap.FullName
if ($LASTEXITCODE -ne 0) { throw "hdc install failed with exit code $LASTEXITCODE." }
# install -r + start does not reload code on a live process; force a cold start.
& $Hdc -t $Target shell "aa force-stop $BundleName" | Out-Null
& $Hdc -t $Target shell "aa start -b $BundleName -a EntryAbility"
Write-Host "==> logs: & $Hdc -t $Target shell 'hilog -x -T RtcTts' (expect stage=init ok=true noiseScale=1 fsts=3)"
