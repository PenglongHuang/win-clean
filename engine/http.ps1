function Read-HttpRequest([System.IO.Stream]$s) {
    $all = New-Object System.Collections.Generic.List[byte]
    $buf = New-Object byte[] 8192
    while ($true) {
        $text = [Text.Encoding]::ASCII.GetString($all.ToArray())
        $idx = $text.IndexOf("`r`n`r`n")
        if ($idx -ge 0) {
            $m = [regex]::Match($text.Substring(0, $idx), 'Content-Length:\s*(\d+)', 'IgnoreCase')
            $need = $idx + 4 + ($(if ($m.Success) { [int]$m.Groups[1].Value } else { 0 }))
            if ($all.Count -ge $need) { break }
        }
        $n = $s.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        for ($i = 0; $i -lt $n; $i++) { $all.Add($buf[$i]); if ($all.Count -gt 1048576) { throw "request too large" } }
    }
    $text = [Text.Encoding]::ASCII.GetString($all.ToArray())
    $idx = $text.IndexOf("`r`n`r`n")
    if ($idx -lt 0) { return $null }
    $head = $text.Substring(0, $idx)
    $parts = ($head -split "`r`n")[0] -split ' '
    $m = [regex]::Match($head, 'Content-Length:\s*(\d+)', 'IgnoreCase')
    $cl = if ($m.Success) { [int]$m.Groups[1].Value } else { 0 }
    $bodyStart = $idx + 4
    # NB: cannot use `$bodyBytes = if (...) {...} else {[byte[]]@()}` here - PS 5.1
    # if-expressions enumerate via pipeline, an empty array becomes $null and
    # GetString throws ArgumentNullException. Build the array directly instead.
    $bodyLen = [Math]::Max(0, [Math]::Min($cl, $all.Count - $bodyStart))
    $bodyBytes = [byte[]]::new($bodyLen)
    if ($bodyLen -gt 0) { $all.CopyTo($bodyStart, $bodyBytes, 0, $bodyLen) }
    $headers = @{}
    foreach ($line in ($head -split "`r`n" | Select-Object -Skip 1)) { if ($line -match '^([^:]+):\s*(.*)$') { $headers[$Matches[1].ToLowerInvariant()] = $Matches[2].Trim() } }
    return @{ Method = $parts[0]; Path = $parts[1]; Body = [Text.Encoding]::UTF8.GetString($bodyBytes); Headers = $headers }
}

function Send-HttpResponse([System.IO.Stream]$s, [string]$Type, [string]$Body, [int]$Code = 200) {
    $b = [Text.Encoding]::UTF8.GetBytes($Body)
    $statusText = if ($Code -eq 200) { 'OK' } else { 'ERROR' }
    $head = "HTTP/1.1 $Code $statusText`r`nContent-Type: $Type; charset=utf-8`r`nContent-Length: $($b.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nContent-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($head)
    $s.Write($hb, 0, $hb.Length); $s.Write($b, 0, $b.Length); $s.Flush()
}
