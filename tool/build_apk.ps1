<#
.SYNOPSIS
  Signed release APK for one flavor (architecture.md E7). Sets flavor and dart-define together.

  tool\build_apk.ps1 standard                        -> flutter build apk --release --flavor standard
  tool\build_apk.ps1 autoread                        -> flutter build apk --release --flavor autoread --dart-define=MMOGO_AUTOREAD=true

.PARAMETER Flavor      standard | autoread
.PARAMETER StagingDir  Optional folder. If given, the built APK is COPIED there as mmogo.apk (standard) or
                       mmogo-autoread.apk (autoread). Without it, the copy command is only printed. Nothing is published.
.PARAMETER AppRoot     Optional: the Flutter project root (default: the folder above tool\). Test hook for the refusal path.

Refuses (exit 1) if android\key.properties is missing: a release build never falls back to the debug key.
Never reads or prints key.properties contents; only checks that the file exists.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Flavor,
  [string]$StagingDir,
  [string]$AppRoot
)
$ErrorActionPreference = 'Stop'
if ($Flavor -ne 'standard' -and $Flavor -ne 'autoread') {
  Write-Output "usage: build_apk.ps1 <standard|autoread> [-StagingDir <folder>]  (got '$Flavor')"
  exit 2
}
if (-not $AppRoot) { $AppRoot = Split-Path -Parent $PSScriptRoot }
$keyProps = Join-Path $AppRoot 'android\key.properties'
if (-not (Test-Path -LiteralPath $keyProps)) {
  Write-Output "REFUSED: $keyProps is missing. A release build must be signed with the release key; this script never falls back to the debug key."
  Write-Output 'Create android\key.properties as described in README, "Releasing" (it is gitignored). Nothing was built.'
  exit 1
}
$buildArgs = @('build', 'apk', '--release', '--flavor', $Flavor)
if ($Flavor -eq 'autoread') { $buildArgs += '--dart-define=MMOGO_AUTOREAD=true' }
Write-Output ("running: flutter " + ($buildArgs -join ' '))
Push-Location $AppRoot
try { & flutter @buildArgs; $code = $LASTEXITCODE } finally { Pop-Location }
if ($code -ne 0) { Write-Output "flutter build failed (exit $code)"; exit $code }

$built = Join-Path $AppRoot "build\app\outputs\flutter-apk\app-$Flavor-release.apk"
if (-not (Test-Path -LiteralPath $built)) { Write-Output "build finished but $built was not found"; exit 1 }
$stageName = 'mmogo.apk'; if ($Flavor -eq 'autoread') { $stageName = 'mmogo-autoread.apk' }
Write-Output "built: $built"
Write-Output ("SHA-256: " + (Get-FileHash -Algorithm SHA256 -LiteralPath $built).Hash.ToLower())
if ($StagingDir) {
  New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null
  Copy-Item -LiteralPath $built -Destination (Join-Path $StagingDir $stageName) -Force
  Write-Output "staged: $(Join-Path $StagingDir $stageName)"
} else {
  Write-Output "to stage it: Copy-Item '$built' '<staging folder>\$stageName'"
}
Write-Output "next: tool\check_apk_manifest.ps1 '$built' $Flavor"
Write-Output 'not published: publishing is a separate, manual release step.'
