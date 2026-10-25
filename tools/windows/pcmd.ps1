# Run a command on the phone via CMD Injector's TCP shell (port 9999)
# Phone IP: -HostIp or $env:LUMIA_WP_IP (the phone's Wi-Fi address while Windows runs)
param([string]$Cmd,[int]$Wait=4000,[string]$HostIp=$env:LUMIA_WP_IP)
if (-not $HostIp) { throw 'set LUMIA_WP_IP or pass -HostIp' }
$c=New-Object Net.Sockets.TcpClient; $c.Connect($HostIp,9999); $s=$c.GetStream(); $s.ReadTimeout=500
$buf=New-Object byte[] 65536; $out=New-Object Text.StringBuilder
function Drain($ms){ $end=(Get-Date).AddMilliseconds($ms); while((Get-Date) -lt $end){ try { $n=$s.Read($buf,0,$buf.Length); if($n -gt 0){ [void]$out.Append([Text.Encoding]::UTF8.GetString($buf,0,$n)); $end=(Get-Date).AddMilliseconds(800) } } catch {} } }
Drain 1500
$b=[Text.Encoding]::ASCII.GetBytes($Cmd + "`r`n"); $s.Write($b,0,$b.Length)
Drain $Wait
$c.Close(); $out.ToString()
