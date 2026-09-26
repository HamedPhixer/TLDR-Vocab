<#
  StallServer.ps1 - a server whose first connection hangs, for Logic.test.ahk

  Takes the first connection and never answers it - the stuck connection a VPN
  sometimes leaves - then answers the second at once with "second". Writes
  -Ready when it is listening; gives up after 20 s whatever happens.
#>
param([int]$Port = 18765, [string]$Ready)

$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$l.Start()
if ($Ready) { Set-Content -Path $Ready -Value "ready" }
try {
    $t = $l.AcceptTcpClientAsync()
    if (-not $t.Wait(20000)) { exit 1 }
    $held = $t.Result                                   # never answered
    $t = $l.AcceptTcpClientAsync()
    if (-not $t.Wait(20000)) { exit 1 }
    $c = $t.Result
    $s = $c.GetStream()
    $buf = New-Object byte[] 65536
    $null = $s.Read($buf, 0, $buf.Length)
    $body = "second"
    $reply = "HTTP/1.1 200 OK`r`nContent-Type: text/plain`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n$body"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($reply)
    $s.Write($bytes, 0, $bytes.Length)
    $s.Flush()
    Start-Sleep -Milliseconds 500
    $c.Close()
    $held.Close()
} finally {
    $l.Stop()
}
