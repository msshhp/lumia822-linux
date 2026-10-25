# Runs ON THE PC. Uploads a set of boot-area images plus a .cmd script to the phone over USB (MTP),
# checks every file size on the phone, then runs the script on the phone through CMD Injector's
# SYSTEM shell and prints the log lines.
#
#   upload_and_run.ps1 -ImageDir <folder with *.bin> -Script run_unlock.cmd   (stage 1)
#   upload_and_run.ps1 -ImageDir <folder with *.bin> -Script run_nv.cmd       (stage 2)
#
# Needs: Interop Tools' MTP full-C:\ access, disktool.exe already in C:\Data\Users\Public\Downloads,
# CMD Injector open on the phone, $env:LUMIA_WP_IP set. READ docs/unlock.md FIRST.
param([Parameter(Mandatory)][string]$ImageDir, [Parameter(Mandatory)][string]$Script)
$ErrorActionPreference = 'Stop'
$T   = Split-Path $PSScriptRoot -Parent
$mtp = Join-Path $T 'mtp.ps1'
$pc  = Join-Path $T 'pcmd.ps1'
$files = @(Get-ChildItem (Join-Path $ImageDir '*') -Include *.bin) + @(Get-Item (Join-Path $PSScriptRoot $Script))

foreach ($f in $files) {
    try { & $mtp rm "Data\Users\Public\Downloads\$($f.Name)" | Out-Null } catch {}
    & $mtp put $f.FullName 'Data\Users\Public\Downloads'
}

# Size check on the phone side
$listing = & $pc -Cmd 'dir C:\Data\Users\Public\Downloads' -Wait 5000
$bad = 0
foreach ($f in $files) {
    $pattern = '(?m)\s([\d,]+)\s+' + [regex]::Escape($f.Name) + '\s*$'
    $m = [regex]::Match(($listing -replace ([char]27 + '\[[0-9;]*[A-Za-z]'), ''), $pattern)
    $phoneSize = if ($m.Success) { [int64]($m.Groups[1].Value -replace ',', '') } else { -1 }
    $ok = $phoneSize -eq $f.Length
    if (-not $ok) { $bad++ }
    '{0,-18} pc={1,-9} phone={2,-9} {3}' -f $f.Name, $f.Length, $phoneSize, $(if ($ok) { 'OK' } else { 'MISMATCH' })
}
if ($bad) { 'Upload check FAILED - nothing was written to the phone.'; exit 1 }

"Uploads verified. Running $Script on the phone..."
$out = & $pc -Cmd "C:\Data\Users\Public\Downloads\$Script" -Wait 60000
($out -replace ([char]27 + '\[[0-9;]*[A-Za-z]'), '') -split "`n" | Where-Object { $_ -match 'write ok|VERIFY|failed|ALL_OK|FAILED_RESTORING|RESTORED|start' }
