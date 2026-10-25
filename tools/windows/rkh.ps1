param([string]$Dir)
$sha=[System.Security.Cryptography.SHA256]::Create()
Get-ChildItem $Dir -Recurse -File | Where-Object { $_.Extension -ne '.zip' } | ForEach-Object {
  $f=$_.FullName
  $b=[IO.File]::ReadAllBytes($f)
  if($b.Length -gt 0 -and $b[0] -eq 0x3A){ # intel hex
    $ms=New-Object IO.MemoryStream
    foreach($l in [IO.File]::ReadAllLines($f)){ if($l.Length -lt 11){continue}
      $n=[Convert]::ToInt32($l.Substring(1,2),16); $t=[Convert]::ToInt32($l.Substring(7,2),16)
      if($t -eq 0){ for($i=0;$i -lt $n;$i++){ $ms.WriteByte([Convert]::ToByte($l.Substring(9+2*$i,2),16)) } } }
    $b=$ms.ToArray() }
  $hs=@()
  for($i=0;$i -lt $b.Length-4;$i++){
    if($b[$i] -eq 0x30 -and $b[$i+1] -eq 0x82){
      $len=($b[$i+2] -shl 8) + $b[$i+3] + 4
      if($len -gt 300 -and $len -lt 3000 -and $i+$len -le $b.Length -and $b[$i+4] -eq 0x30 -and $b[$i+5] -eq 0x82){
        $h=($sha.ComputeHash($b,$i,$len) | ForEach-Object { $_.ToString('X2') }) -join ''
        $hs+=$h; $i+=$len-1 } } }
  "{0} | certs={1} | last={2}" -f $_.FullName.Replace($Dir,''),$hs.Count,($(if($hs){$hs[-1]}else{'-'}))
}
