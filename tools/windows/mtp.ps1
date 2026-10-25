# MTP helper: mtp.ps1 ls <path> | get <path> <localdir> | put <localfile> <phonedir>
param([string]$Cmd,[string]$P1,[string]$P2)
$sh=New-Object -ComObject Shell.Application
$dev=($sh.NameSpace(17).Items() | Where-Object { $_.Name -eq 'Windows phone' })
if(-not $dev){ throw "phone not found" }
$root=($dev.GetFolder.Items() | Select -First 1).GetFolder
function Resolve([string]$path){ $f=$root; if($path){ foreach($part in $path.Split('\') | Where-Object {$_}){ $it=$f.Items() | Where-Object { $_.Name -eq $part }; if(-not $it){ throw "not found: $part" }; if($it.IsFolder){ $f=$it.GetFolder } else { return $it } } }; return $f }
switch($Cmd){
 'ls' { $f=Resolve $P1; $f.Items() | ForEach-Object { "{0}`t{1}`t{2}" -f ($(if($_.IsFolder){'D'}else{'F'})),$_.Size,$_.Name } }
 'get' { $it=Resolve $P1; $dst=$sh.NameSpace($P2); $dst.CopyHere($it,0x14); $n=Split-Path $P1 -Leaf; $t=0; while(-not (Test-Path (Join-Path $P2 $n)) -and $t -lt 60){ Start-Sleep 1; $t++ }; Start-Sleep 2; Get-Item (Join-Path $P2 $n) | Select Name,Length }
 'rm' { $it=Resolve $P1; $it.InvokeVerbEx('delete'); Start-Sleep 3; $par=Resolve (Split-Path $P1 -Parent); if($par.Items() | Where-Object { $_.Name -eq (Split-Path $P1 -Leaf) }){ 'rm: still present' } else { 'rm ok' } }
 'put' { $f=Resolve $P2; $f.CopyHere($P1,0x14); Start-Sleep 5; $f.Items() | Where-Object { $_.Name -eq (Split-Path $P1 -Leaf) } | ForEach-Object { "put ok: " + $_.Name + " " + $_.Size } }
}
