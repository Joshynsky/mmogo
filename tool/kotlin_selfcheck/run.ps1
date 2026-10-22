<#
.SYNOPSIS
  Runs the plain-JVM self-checks for the auto-read Kotlin (no JUnit in this build).
  Compiles the real sources with the Kotlin compiler jar that Gradle already cached, so nothing is installed.

.PARAMETER Out   Scratch folder for the compiled classes (default: a new folder under the temp dir).
Exit code 0 = every check passed, 1 = a check failed, 2 = a jar or file is missing.

The checks live OUTSIDE every Android source set on purpose: nothing test-only ships in the APK.
#>
param([string]$Out = (Join-Path ([IO.Path]::GetTempPath()) ('mmogo_selfcheck_' + [guid]::NewGuid().ToString('N'))))

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cache = Join-Path $env:USERPROFILE '.gradle\caches\modules-2\files-2.1'
function Jar([string]$pattern) {
  $j = Get-ChildItem -Path $cache -Recurse -Filter $pattern -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Select-Object -First 1
  if (-not $j) { Write-Host "MISSING jar: $pattern (build the app once so Gradle caches it)"; exit 2 }
  $j.FullName
}
$compiler = @(
  (Jar 'kotlin-compiler-embeddable-2.2.20.jar'), (Jar 'kotlin-stdlib-2.2.20.jar'), (Jar 'kotlin-reflect-*.jar'),
  (Jar 'kotlin-script-runtime-2.2.20.jar'), (Jar 'kotlin-daemon-embeddable-2.2.20.jar'), (Jar 'trove4j-*.jar'),
  (Jar 'annotations-13.0.jar'), (Jar 'kotlinx-coroutines-core-jvm-*.jar')) -join ';'
$stdlib = Jar 'kotlin-stdlib-2.2.20.jar'
$json = Jar 'json-20180813.jar'

$k = Join-Path $root 'android\app\src\autoread\kotlin\app\mmogo\autoread'
$sc = $PSScriptRoot
$src = @(
  (Join-Path $k 'HeldId.kt'), (Join-Path $k 'HeldStore.kt'), (Join-Path $k 'NotifierPure.kt'),
  (Join-Path $k 'SmsReceiverLogic.kt'), (Join-Path $k 'BridgeLogic.kt'), (Join-Path $k 'ConsentGate.kt'), (Join-Path $k 'ParsePolicy.kt'),
  (Join-Path $sc 'HeldStoreSelfCheck.kt'), (Join-Path $sc 'NotifierSelfCheck.kt'), (Join-Path $sc 'SmsReceiverSelfCheck.kt'), (Join-Path $sc 'BridgeSelfCheck.kt'), (Join-Path $sc 'ParseSelfCheck.kt'), (Join-Path $sc 'SelfCheckMain.kt'))
foreach ($s in $src) { if (-not (Test-Path $s)) { Write-Host "MISSING file: $s"; exit 2 } }

New-Item -ItemType Directory -Force $Out | Out-Null
& java -cp $compiler org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -cp "$stdlib;$json" -d $Out @src 2>&1 | Where-Object { $_ -notmatch '^warning:' }
if ($LASTEXITCODE -ne 0) { Write-Host 'COMPILE FAILED'; exit 1 }
& java -cp "$Out;$stdlib;$json" app.mmogo.autoread.SelfCheckMainKt
exit $LASTEXITCODE
