param(
  [string]$DistDir = "dist",
  [string]$Version = "",
  [string]$Ohpm = "ohpm",
  [switch]$SkipPrepublish,
  [switch]$Publish,
  [switch]$KeepStaging
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$PackageJsonPath = Join-Path $Root "oh-package.json5"

if (-not (Test-Path $PackageJsonPath)) {
  throw "Package config not found: $PackageJsonPath"
}

$PackageJson = Get-Content -Path $PackageJsonPath -Raw
if (-not $Version) {
  if ($PackageJson -notmatch '"version"\s*:\s*"([^"]+)"') {
    throw "Package version not found in $PackageJsonPath"
  }
  $Version = $Matches[1]
}

$DistRoot = Join-Path $Root $DistDir
$StageRoot = Join-Path $DistRoot "ohos-rtc-call-package"
$PackageRoot = Join-Path $StageRoot "package"
$HarPath = Join-Path $DistRoot "ohos-rtc-call-$Version.har"

New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null
if (Test-Path $StageRoot) {
  Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
if (Test-Path $HarPath) {
  Remove-Item -LiteralPath $HarPath -Force
}
New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null

$IncludeItems = @(
  "build-profile.json5",
  "hvigorfile.ts",
  "Index.ets",
  "README.md",
  "CHANGELOG.md",
  "LICENSE",
  "oh-package.json5",
  "example",
  "src"
)

foreach ($Item in $IncludeItems) {
  $Source = Join-Path $Root $Item
  if (-not (Test-Path $Source)) {
    throw "Required package item missing: $Source"
  }
  Copy-Item -LiteralPath $Source -Destination $PackageRoot -Recurse -Force
}

$StagedPackageJsonPath = Join-Path $PackageRoot "oh-package.json5"
$StagedPackageJson = Get-Content -Path $StagedPackageJsonPath -Raw
$StagedPackageJson = $StagedPackageJson -replace '(?ms)"devDependencies"\s*:\s*\{.*?\}', '"devDependencies": {}'
Set-Content -Path $StagedPackageJsonPath -Value $StagedPackageJson -NoNewline

$SensitivePatterns = @(
  "BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY",
  "publish_id",
  "key_path",
  "storePassword",
  "keyPassword",
  "access[_-]?token",
  "secret[_-]?key",
  "dgzyh\.server\.chindeo\.test",
  "@company/device_sdk",
  '"file:'
)

$ScanFiles = Get-ChildItem -Path $PackageRoot -Recurse -File -Include *.ets,*.ts,*.json,*.json5,*.md,*.txt
foreach ($Pattern in $SensitivePatterns) {
  $Match = $ScanFiles | Select-String -Pattern $Pattern -CaseSensitive:$false
  if ($Match) {
    $First = $Match | Select-Object -First 1
    throw "Sensitive content matched '$Pattern' at $($First.Path):$($First.LineNumber)"
  }
}

Push-Location $StageRoot
try {
  & tar -czf $HarPath package
} finally {
  Pop-Location
}

Write-Host "Created HAR: $HarPath"

if (-not $SkipPrepublish) {
  Write-Host "Running OHPM prepublish..."
  & $Ohpm prepublish $HarPath
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if ($Publish) {
  Write-Host "Publishing to OHPM..."
  & $Ohpm publish $HarPath
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $KeepStaging -and (Test-Path $StageRoot)) {
  Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
