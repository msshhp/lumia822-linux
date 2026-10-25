# Minimal offline regf hive dumper: prints key paths and values
param([string]$Hive)
$b=[IO.File]::ReadAllBytes($Hive)
function U16($o){ [BitConverter]::ToUInt16($b,$o) }
function U32($o){ [BitConverter]::ToUInt32($b,$o) }
function Cell($off){ 0x1000 + $off + 4 }   # skip cell size
function SubkeyOffsets($listOff){
  $c=Cell $listOff; $sig=[Text.Encoding]::ASCII.GetString($b,$c,2); $n=U16 ($c+2); $r=@()
  switch($sig){
    {$_ -in 'lf','lh'} { for($i=0;$i -lt $n;$i++){ $r+= (U32 ($c+4+8*$i)) } }
    'li' { for($i=0;$i -lt $n;$i++){ $r+= (U32 ($c+4+4*$i)) } }
    'ri' { for($i=0;$i -lt $n;$i++){ $r+= SubkeyOffsets (U32 ($c+4+4*$i)) } }
  }
  $r
}
function Dump($nkOff,$path){
  $c=Cell $nkOff
  $nameLen=U16 ($c+0x48); $flags=U16 ($c+2)
  $name= if($flags -band 0x20){ [Text.Encoding]::ASCII.GetString($b,$c+0x4C,$nameLen) } else { [Text.Encoding]::Unicode.GetString($b,$c+0x4C,$nameLen) }
  $p= if($path -eq $null){ $name } else { "$path\$name" }
  $p
  $nVals=U32 ($c+0x24); $valList=U32 ($c+0x28)
  for($i=0;$i -lt $nVals;$i++){
    $vk=Cell (U32 ((Cell $valList)+4*$i))
    $vnLen=U16 ($vk+2); $dLen=U32 ($vk+4); $dOff=U32 ($vk+8); $type=U32 ($vk+12); $vf=U16 ($vk+16)
    $vn= if($vnLen -eq 0){'(default)'} elseif($vf -band 1){ [Text.Encoding]::ASCII.GetString($b,$vk+20,$vnLen) } else { [Text.Encoding]::Unicode.GetString($b,$vk+20,$vnLen) }
    $inline=($dLen -band 0x80000000) -ne 0; $len=$dLen -band 0x7FFFFFFF
    $data= if($inline){ [BitConverter]::GetBytes($dOff)[0..([Math]::Max(0,$len-1))] } elseif($len -gt 0){ $b[(Cell $dOff)..((Cell $dOff)+$len-1)] } else { @() }
    $s= switch($type){ 1 { [Text.Encoding]::Unicode.GetString($data).TrimEnd([char]0) } 7 { ([Text.Encoding]::Unicode.GetString($data).Split([char]0) | ? {$_}) -join ' | ' } 4 { '0x{0:X}' -f [BitConverter]::ToUInt32($data,0) } default { ($data | % { $_.ToString('X2') }) -join ' ' } }
    "    [$vn] type=$type len=$len : $s"
  }
  $nSub=U32 ($c+0x14)
  if($nSub -gt 0){ foreach($s in SubkeyOffsets (U32 ($c+0x1C))){ Dump $s $p } }
}
Dump (U32 0x24) $null
