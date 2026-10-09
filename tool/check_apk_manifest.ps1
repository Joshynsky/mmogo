<#
.SYNOPSIS
  Release assertion for an mmogo APK (architecture.md E7). Read-only: it never builds, signs or installs.

.PARAMETER Apk      Path to the APK to check.
.PARAMETER Flavor   standard | autoread. Only 'standard' is implemented; 'autoread' exits 1 until AR1.
.PARAMETER OutFile  Optional: also write the output to this file.
.PARAMETER BuildTools  Optional: an Android build-tools folder (default: newest under ANDROID_HOME / %LOCALAPPDATA%\Android\Sdk).
.PARAMETER ManifestText / PermissionsText
  Test hooks: use a pre-decoded text file instead of running aapt for the manifest tree / permissions.
  Used only to prove that the checker FAILS on a doctored manifest (patching a binary manifest is impractical).

Exit code: 0 = all checks passed, 1 = a check failed, 2 = bad usage / tool missing.

Permission filter (decision): the expected set is {android.permission.INTERNET}. The one extra entry allowed is
  <applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION, which androidx.core injects into every app (the shipped 0.1.1 has it
  too). The filter matches that exact name only, built from the APK's own applicationId. Any other entry fails.

Component filter (decision): the 0.1.1 baseline has two plugin receivers (share_plus SharePlusPendingIntent, androidx
  ProfileInstallReceiver) and no <service>. Those two names are the only receivers allowed; any <service>, any other
  <receiver>, or any SMS/notification string fails. E7 says "diff against the 0.1.1 baseline"; this is that diff.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Apk,
  [Parameter(Mandatory = $true, Position = 1)][string]$Flavor,
  [string]$OutFile,
  [string]$BuildTools,
  [string]$ManifestText,
  [string]$PermissionsText
)
$ErrorActionPreference = 'Stop'
$script:lines = New-Object System.Collections.ArrayList
function Say([string]$s) { Write-Output $s; [void]$script:lines.Add($s) }
function Finish([int]$code) {
  if ($OutFile) { $script:lines | Set-Content -Path $OutFile -Encoding UTF8 }
  exit $code
}

if ($Flavor -ne 'standard' -and $Flavor -ne 'autoread') { Say "usage: check_apk_manifest.ps1 <apk> <standard|autoread>  (got flavor '$Flavor')"; Finish 2 }
if (-not (Test-Path -LiteralPath $Apk)) { Say "APK not found: $Apk"; Finish 2 }
if ($Flavor -eq 'autoread') { Say 'autoread branch: not implemented until AR1'; Finish 1 }

if (-not $BuildTools) {
  $sdk = $env:ANDROID_HOME; if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }; if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
  $bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'aapt.exe') } | Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending | Select-Object -First 1
  if (-not $bt) { Say "no Android build-tools with aapt.exe found under $sdk"; Finish 2 }
  $BuildTools = $bt.FullName
}
$aapt = Join-Path $BuildTools 'aapt.exe'
$apksigner = Join-Path $BuildTools 'apksigner.bat'
$Apk = (Resolve-Path -LiteralPath $Apk).Path

function Aapt([string[]]$a) {
  $out = & $aapt @a 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) { throw "aapt $($a -join ' ') failed: $out" }
  return $out
}

$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
  if ($ok) { Say "PASS  $name" } else { Say "FAIL  $name"; $script:fail++ }
  if ($detail) { Say "      $detail" }
}

Say "mmogo manifest check, flavor=$Flavor"
Say "apk: $Apk"
Say "build-tools: $BuildTools"
if ($ManifestText -or $PermissionsText) { Say "NOTE: test hook in use (decoded text supplied: manifest='$ManifestText' permissions='$PermissionsText')" }

# --- identity
$badging = Aapt @('dump', 'badging', $Apk)
$pkgLine = $badging | Where-Object { $_ -like 'package:*' } | Select-Object -First 1
$appId = [regex]::Match($pkgLine, "name='([^']*)'").Groups[1].Value
$vCode = [regex]::Match($pkgLine, "versionCode='([^']*)'").Groups[1].Value
$vName = [regex]::Match($pkgLine, "versionName='([^']*)'").Groups[1].Value
Say "applicationId: $appId"
Say "versionName:   $vName"
Say "versionCode:   $vCode"
$cert = 'unavailable'
try {
  $ErrorActionPreference = 'Continue'
  $sig = & $apksigner verify --print-certs $Apk 2>&1 | ForEach-Object { "$_" }
  $ErrorActionPreference = 'Stop'
  $m = $sig | Where-Object { $_ -match 'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)' } | Select-Object -First 1
  if ($m) { $cert = [regex]::Match($m, 'digest: ([0-9a-f]+)').Groups[1].Value }
  $dn = $sig | Where-Object { $_ -match 'Signer #1 certificate DN:' } | Select-Object -First 1
  if ($dn) { Say "cert DN:       $(($dn -replace '^.*DN:\s*', ''))" }
} catch { $ErrorActionPreference = 'Stop' }
Say "cert SHA-256:  $cert"
Say ''

# --- permissions
if ($PermissionsText) { $permLines = Get-Content -LiteralPath $PermissionsText } else { $permLines = Aapt @('dump', 'permissions', $Apk) }
$usesPerms = @($permLines | ForEach-Object { if ($_ -match "^uses-permission(-sdk-23)?: name='([^']+)'") { $Matches[2] } })
$androidxPerm = "$appId.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
$effective = @($usesPerms | Where-Object { $_ -ne $androidxPerm } | Sort-Object -Unique)
Say ("permissions as reported: " + (($usesPerms | Sort-Object) -join ', '))
Check 'uses-permission set equals {android.permission.INTERNET} (after dropping the androidx DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION)' `
  (($effective.Count -eq 1) -and ($effective[0] -eq 'android.permission.INTERNET')) ("effective: " + ($effective -join ', '))

# --- decoded manifest
if ($ManifestText) { $tree = Get-Content -LiteralPath $ManifestText } else { $tree = Aapt @('dump', 'xmltree', $Apk, 'AndroidManifest.xml') }
$allowedReceivers = @('dev.fluttercommunity.plus.share.SharePlusPendingIntent', 'androidx.profileinstaller.ProfileInstallReceiver')
$recv = New-Object System.Collections.ArrayList; $svc = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $tree.Count; $i++) {
  $kind = $null
  if ($tree[$i] -match '^\s*E: receiver ') { $kind = 'r' } elseif ($tree[$i] -match '^\s*E: service ') { $kind = 's' }
  if ($kind) {
    $name = '(unnamed)'
    for ($j = $i + 1; $j -lt [Math]::Min($i + 12, $tree.Count); $j++) {
      if ($tree[$j] -match 'A: android:name\([^)]*\)="([^"]*)"') { $name = $Matches[1]; break }
      if ($tree[$j] -match '^\s*E: ') { break }
    }
    if ($kind -eq 'r') { [void]$recv.Add($name) } else { [void]$svc.Add($name) }
  }
}
$svcText = 'none'; if ($svc.Count) { $svcText = $svc -join ', ' }
Check 'no <service> element' ($svc.Count -eq 0) ("services: $svcText")
$extraRecv = @($recv | Where-Object { $allowedReceivers -notcontains $_ })
$recvText = 'none'; if ($recv.Count) { $recvText = $recv -join ', ' }
if ($extraRecv.Count) { $recvText += "  UNEXPECTED: " + ($extraRecv -join ', ') }
Check 'no <receiver> beyond the two 0.1.1 baseline plugin receivers' ($extraRecv.Count -eq 0) ("receivers: $recvText")
$banned = @('RECEIVE_SMS', 'READ_SMS', 'POST_NOTIFICATIONS', 'BIND_NOTIFICATION_LISTENER_SERVICE', 'BROADCAST_SMS', 'SmsReceiver')
$hits = @($banned | Where-Object { $b = $_; @($tree | Where-Object { $_ -like "*$b*" }).Count -gt 0 })
$hitText = ''; if ($hits.Count) { $hitText = 'found: ' + ($hits -join ', ') }
Check 'manifest contains none of RECEIVE_SMS, READ_SMS, POST_NOTIFICATIONS, BIND_NOTIFICATION_LISTENER_SERVICE, BROADCAST_SMS, SmsReceiver' ($hits.Count -eq 0) $hitText
# queries block: baseline is exactly one intent (PROCESS_TEXT, text/plain)
$qi = -1; for ($i = 0; $i -lt $tree.Count; $i++) { if ($tree[$i] -match '^\s*E: queries ') { $qi = $i; break } }
$qOk = $false; $qDetail = 'no <queries> block'
if ($qi -ge 0) {
  $indent = ([regex]::Match($tree[$qi], '^\s*')).Length; $blk = @()
  for ($i = $qi + 1; $i -lt $tree.Count; $i++) { if (([regex]::Match($tree[$i], '^\s*')).Length -le $indent) { break }; $blk += $tree[$i] }
  $names = @($blk | ForEach-Object { if ($_ -match 'android:(name|mimeType)\([^)]*\)="([^"]*)"') { $Matches[2] } })
  $qDetail = 'queries content: ' + ($names -join ' | ')
  $qOk = (($names -join '|') -eq 'android.intent.action.PROCESS_TEXT|text/plain')
}
Check '<queries> block equals the 0.1.1 baseline (one intent: PROCESS_TEXT, text/plain)' $qOk $qDetail

# --- dex / resources / libapp
Add-Type -AssemblyName System.IO.Compression.FileSystem
function EntryBytes($e) { $s = $e.Open(); $ms = New-Object System.IO.MemoryStream; $s.CopyTo($ms); $s.Dispose(); return ,$ms.ToArray() }
function HasText([byte[]]$b, [string]$t) {
  $l1 = [System.Text.Encoding]::GetEncoding(28591).GetString($b)
  if ($l1.IndexOf($t, [StringComparison]::Ordinal) -ge 0) { return $true }
  $u = [System.Text.Encoding]::Unicode.GetString($b)
  if ($u.IndexOf($t, [StringComparison]::Ordinal) -ge 0) { return $true }
  $u2 = [System.Text.Encoding]::Unicode.GetString($b, 1, $b.Length - 1)
  return ($u2.IndexOf($t, [StringComparison]::Ordinal) -ge 0)
}
$zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
try {
  $dexes = @($zip.Entries | Where-Object { $_.FullName -match '^classes\d*\.dex$' })
  $dexHit = @(); foreach ($d in $dexes) { if (HasText (EntryBytes $d) 'app/mmogo/autoread') { $dexHit += $d.FullName } }
  $dexNames = ($dexes | ForEach-Object { $_.FullName }) -join ' '
  Check "classes*.dex has no 'app/mmogo/autoread'" (($dexes.Count -gt 0) -and ($dexHit.Count -eq 0)) "dex files scanned: $dexNames"
  $arsc = $zip.GetEntry('resources.arsc')
  $arscHit = @()
  if ($arsc) { $ab = EntryBytes $arsc; foreach ($t in @('mmogo_mpesa_messages', 'autoread', 'AutoRead', 'auto_read')) { if (HasText $ab $t) { $arscHit += $t } } }
  $arscText = 'resources.arsc scanned'; if ($arscHit.Count) { $arscText = 'found: ' + ($arscHit -join ', ') }
  Check "resource table has no 'mmogo_mpesa_messages' or autoread string" (($null -ne $arsc) -and ($arscHit.Count -eq 0)) $arscText
  # sentinel: only meaningful on AOT builds. Debug builds ship the Dart kernel (no tree-shaking), so it is skipped there.
  $libs = @($zip.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/libapp\.so$' })
  if ($libs.Count -eq 0) { Say 'SKIP  libapp.so sentinel check: no libapp.so in this APK (debug/JIT build); it runs on the signed release APK' }
  else {
    $sent = @(); foreach ($l in $libs) { $lb = EntryBytes $l; foreach ($t in @('pending_entries_v1', 'kAutoReadSentinel', 'app/mmogo/autoread')) { if (HasText $lb $t) { $sent += "$($l.FullName):$t" } } }
    $libNames = ($libs | ForEach-Object { $_.FullName }) -join ' '
    $sentText = "libapp.so scanned: $libNames"; if ($sent.Count) { $sentText = 'found: ' + ($sent -join ', ') }
    Check 'libapp.so has no autoread-only sentinel string (pending_entries_v1, kAutoReadSentinel)' ($sent.Count -eq 0) $sentText
  }
} finally { $zip.Dispose() }

Say ''
if ($script:fail -eq 0) { Say 'RESULT: PASS'; Finish 0 } else { Say "RESULT: FAIL ($($script:fail) check(s) failed)"; Finish 1 }
