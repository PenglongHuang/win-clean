#Requires -Version 5.1
# Minimal HTTP server for the selection report. Binds 127.0.0.1:0 (OS-assigned port).
param(
    [Parameter(Mandatory=$true)][string]$ScanFile,
    [Parameter(Mandatory=$true)][string]$SelectionsOut,
    [string]$HistoryIndex,                # optional logs/history/index.json
    [string]$OutHtml,                     # static mode output file
    [switch]$Static
)
$ErrorActionPreference = 'Stop'

function Read-Utf8([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 }

# -- build the page: inject data, inline app.js for static mode
$scanJson = Read-Utf8 $ScanFile
$templatePath = Join-Path $PSScriptRoot '..\report\template.html'
$appJsPath    = Join-Path $PSScriptRoot '..\report\app.js'
$html = Read-Utf8 $templatePath
$mode = 'auto'
if ($Static) { $mode = 'static' }
$historyJson = 'null'
if ($HistoryIndex -and (Test-Path $HistoryIndex)) { $historyJson = Read-Utf8 $HistoryIndex }
$html = $html.Replace('/*__SCAN_DATA__*/null', $scanJson)
$html = $html.Replace('/*__MODE__*/''auto''', ("'{0}'" -f $mode))
$html = $html.Replace('/*__HISTORY__*/null', $historyJson)
if ($Static) {
    $inline = Read-Utf8 $appJsPath
    $html = $html.Replace('<script src="app.js"></script>', ("<script>`n" + $inline + "`n</script>"))
    $dir = Split-Path -Parent $OutHtml
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $html | Set-Content -LiteralPath $OutHtml -Encoding UTF8
    Write-Output ("STATIC REPORT: $OutHtml")
    exit 0
}

# -- embedded assets for server mode
$appJs = Read-Utf8 $appJsPath
$donePage = '<!DOCTYPE html><html><head><meta charset="utf-8"><body style="background:#14161f;color:#5dd18b;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh"><h2>[OK] Selection received - you can close this page and return to the terminal.</h2></body></html>'

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
        for ($i = 0; $i -lt $n; $i++) { $all.Add($buf[$i]) }
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
    return @{ Method = $parts[0]; Path = $parts[1]; Body = [Text.Encoding]::UTF8.GetString($bodyBytes) }
}

function Send-HttpResponse([System.IO.Stream]$s, [string]$Type, [string]$Body, [int]$Code = 200) {
    $b = [Text.Encoding]::UTF8.GetBytes($Body)
    $statusText = if ($Code -eq 200) { 'OK' } else { 'ERROR' }
    $head = "HTTP/1.1 $Code $statusText`r`nContent-Type: $Type; charset=utf-8`r`nContent-Length: $($b.Length)`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($head)
    $s.Write($hb, 0, $hb.Length); $s.Write($b, 0, $b.Length); $s.Flush()
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$url = "http://127.0.0.1:$($port)/"
$infoPath = Join-Path (Split-Path -Parent $SelectionsOut) 'serve-info.json'
@{ url = $url; port = $port; pid = $PID; selections = $SelectionsOut } |
    ConvertTo-Json | Set-Content -LiteralPath $infoPath -Encoding UTF8
Write-Output "SERVING: $url"
Write-Output "INFO: $infoPath"
Write-Output "Waiting for selection POST ... (Ctrl+C to stop)"

$received = $false
while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
        $stream = $client.GetStream()
        $req = Read-HttpRequest $stream
        if (-not $req) { $client.Close(); continue }
        switch ($req.Path) {
            '/' {
                if ($received) { Send-HttpResponse $stream 'text/html' $donePage }
                else { Send-HttpResponse $stream 'text/html' $html }
            }
            '/app.js'  { Send-HttpResponse $stream 'application/javascript' $appJs }
            '/api/select' {
                try {
                    $req.Body | Set-Content -LiteralPath $SelectionsOut -Encoding UTF8
                    $received = $true
                    Send-HttpResponse $stream 'application/json' '{"ok":true}'
                    Write-Output "SELECTION RECEIVED -> $SelectionsOut"
                } catch {
                    Send-HttpResponse $stream 'application/json' ('{"ok":false,"error":"' + $_.Exception.Message + '"}')
                }
            }
            '/shutdown' { Send-HttpResponse $stream 'application/json' '{"ok":true}' }
            default     { Send-HttpResponse $stream 'text/plain' 'not found' 404 }
        }
    } finally { $client.Close() }
    if ($received -or $req.Path -eq '/shutdown') { break }
}
$listener.Stop()
Write-Output 'SERVER DONE'
exit 0
