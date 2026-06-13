param(
  [string]$DistDir = "dist",
  [string]$Version = "",
  [string]$Ohpm = "ohpm",
  [switch]$SkipPrepublish,
  [switch]$Publish,
  [switch]$AllowLocalOverwrite,
  [switch]$DevTimestampName,
  [switch]$KeepStaging
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$PackageJsonPath = Join-Path $Root "oh-package.json5"
$FingerprintFileName = "rtc-package-fingerprint.json"

function Get-PackageSourceHash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [Parameter(Mandatory = $true)]
    [string]$FingerprintName
  )

  $Entries = Get-ChildItem -LiteralPath $PackagePath -Recurse -File |
    Where-Object { $_.Name -ne $FingerprintName } |
    ForEach-Object {
      $RelativePath = [System.IO.Path]::GetRelativePath($PackagePath, $_.FullName)
      $RelativePath = $RelativePath.Replace("\", "/")
      $FileHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
      "$RelativePath`t$FileHash"
    } |
    Sort-Object
  $Manifest = [string]::Join("`n", $Entries)
  $Hasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Manifest)
    $Digest = [System.BitConverter]::ToString($Hasher.ComputeHash($Bytes))
    return $Digest.Replace("-", "").ToLowerInvariant()
  } finally {
    $Hasher.Dispose()
  }
}

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
if ($Publish -and $DevTimestampName) {
  throw "-DevTimestampName is only for local development artifacts and cannot be used with -Publish."
}

$DistRoot = Join-Path $Root $DistDir
$StageRoot = Join-Path $DistRoot "ohos-rtc-call-package"
$PackageRoot = Join-Path $StageRoot "package"
$HarName = "ohos-rtc-call-$Version.har"
if ($DevTimestampName) {
  $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
  $HarName = "ohos-rtc-call-$Version-$Timestamp.har"
}
$HarPath = Join-Path $DistRoot $HarName

New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null
if (Test-Path $HarPath) {
  if ($Publish) {
    throw "Refusing to overwrite an existing publish artifact for version $Version. Bump the package version."
  }
  if (-not $AllowLocalOverwrite) {
    throw "HAR already exists: $HarPath. Use -AllowLocalOverwrite only for personal local iteration."
  }
}
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

$PublicDocs = @(
  "call-ui-reference.md",
  "host-call-ui-integration.md"
)
$PackageDocsRoot = Join-Path $PackageRoot "docs"
New-Item -ItemType Directory -Force -Path $PackageDocsRoot | Out-Null
foreach ($Doc in $PublicDocs) {
  $Source = Join-Path (Join-Path $Root "docs") $Doc
  if (-not (Test-Path $Source)) {
    throw "Required public document missing: $Source"
  }
  Copy-Item -LiteralPath $Source -Destination $PackageDocsRoot -Force
}

$StagedPackageJsonPath = Join-Path $PackageRoot "oh-package.json5"
$StagedPackageJson = Get-Content -Path $StagedPackageJsonPath -Raw
$StagedPackageJson = $StagedPackageJson -replace '"version"\s*:\s*"[^"]+"', "`"version`": `"$Version`""
$StagedPackageJson = $StagedPackageJson -replace '(?ms)"devDependencies"\s*:\s*\{.*?\}', '"devDependencies": {}'
Set-Content -Path $StagedPackageJsonPath -Value $StagedPackageJson -NoNewline

$SourceHash = Get-PackageSourceHash -PackagePath $PackageRoot -FingerprintName $FingerprintFileName
$FingerprintPath = Join-Path $PackageRoot $FingerprintFileName
$Fingerprint = [ordered]@{
  packageVersion = $Version
  sourceSha256 = $SourceHash
}
$Fingerprint | ConvertTo-Json | Set-Content -Path $FingerprintPath
Write-Host "Package fingerprint: version=$Version sourceSha256=$SourceHash"

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
