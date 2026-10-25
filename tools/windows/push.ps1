# Push a file to the phone over Wi-Fi while it runs Windows: starts recv.exe on the phone through
# CMD Injector's shell, then streams the file to it.
#   push.ps1 <localFile> <phonePath> [port] [-HostIp <phone IP>]   (or set $env:LUMIA_WP_IP)
# Needs recv.exe in C:\Data\Users\Public\Downloads on the phone and the CMD Injector app open.
param([string]$Local, [string]$Remote, [int]$Port = 9998, [string]$HostIp = $env:LUMIA_WP_IP)
if (-not $HostIp) { throw 'set LUMIA_WP_IP or pass -HostIp' }
$pc = Join-Path $PSScriptRoot 'pcmd.ps1'
& $pc -HostIp $HostIp -Cmd "start /b C:\Data\Users\Public\Downloads\recv.exe $Port $Remote" -Wait 2500 | Out-Null
$bytes = [IO.File]::ReadAllBytes($Local)
$c = New-Object Net.Sockets.TcpClient
for ($i = 0; $i -lt 10 -and -not $c.Connected; $i++) { try { $c.Connect($HostIp, $Port) } catch { Start-Sleep -Milliseconds 500 } }
$s = $c.GetStream()
$s.Write([BitConverter]::GetBytes([uint32]$bytes.Length), 0, 4)
$s.Write($bytes, 0, $bytes.Length)
$s.ReadTimeout = 30000
$buf = New-Object byte[] 64
$n = $s.Read($buf, 0, 64)
$c.Close()
"{0} -> {1}: {2}" -f (Split-Path $Local -Leaf), $Remote, [Text.Encoding]::ASCII.GetString($buf, 0, $n).Trim()
