$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\assert.ps1"
$root = Join-Path $PSScriptRoot '..'
$fx = Join-Path $env:TEMP ("wc-serve-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $fx -Force | Out-Null

$scan = [pscustomobject]@{
    timestamp='now'; host='t'; totalBytes=1234; isAdmin=$false
    drives=@([pscustomobject]@{letter='C:'; total=100GB; free=10GB})
    findings=@([pscustomobject]@{ id='pip-cache'; level=1; name='pip</script><script>alert(1)</script>'; type='cache'; strategy='delete-permanent'; desc='d'; auto_select=$true; source='builtin'; bytes=1234; needs_admin=$false
        paths=@(@{path='%LOCALAPPDATA%\pip\cache'; expanded='C:\Users\x\pip\cache'; exists=$true; bytes=1234}) })
}
$scanFile = "$fx\scan-result.json"
$scan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $scanFile -Encoding UTF8
$selOut = "$fx\selections.json"

# -- static mode: writes a standalone html
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\serve.ps1') `
    -ScanFile $scanFile -SelectionsOut $selOut -Static -OutHtml "$fx\report.html" | Out-Null
Assert-Equal 0 $LASTEXITCODE 'static mode exits 0'
Assert-FileContains "$fx\report.html" 'SCAN_DATA' 'static html embeds data marker'
Assert-FileContains "$fx\report.html" 'squarify' 'static html inlines app.js'
Assert-FileContains "$fx\report.html" '\u003c/script\u003e' 'scan JSON escapes script terminators'

# -- server mode: full loopback E2E
$proc = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',
    (Join-Path $root 'engine\serve.ps1'),'-ScanFile',$scanFile,'-SelectionsOut',$selOut -PassThru -WindowStyle Hidden
try {
    $infoFile = "$fx\serve-info.json"
    $deadline = (Get-Date).AddSeconds(20)
    while (-not (Test-Path $infoFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
    Assert-True (Test-Path $infoFile) 'serve-info.json written'
    $info = Get-Content $infoFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($info.url -match '^http://127\.0\.0\.1:\d+/') 'info has url'

    $html = Invoke-WebRequest -UseBasicParsing -Uri $info.url -TimeoutSec 5
    Assert-Equal 200 $html.StatusCode 'GET / returns 200'
    Assert-True ($html.Content -match 'treemap') 'page contains treemap container'

    $js = Invoke-WebRequest -UseBasicParsing -Uri ($info.url + 'app.js') -TimeoutSec 5
    Assert-Equal 200 $js.StatusCode 'GET /app.js returns 200'

    $hash = (Get-FileHash -LiteralPath $scanFile -Algorithm SHA256).Hash
    $token = [regex]::Match($html.Content, 'window.SESSION_TOKEN = "([a-f0-9]+)"').Groups[1].Value
    Assert-True ($token.Length -eq 64) 'session token injected'
    $body = @{ids=@('pip-cache'); ts='now'; scanHash=$hash} | ConvertTo-Json -Compress
    try { Invoke-WebRequest -UseBasicParsing -Method Post -Uri ($info.url + 'api/select') -ContentType 'application/json' -Body $body -TimeoutSec 5 | Out-Null; $rejected = $false } catch { $rejected = $true }
    Assert-True $rejected 'request without token rejected'
    $resp = Invoke-WebRequest -UseBasicParsing -Method Post -Uri ($info.url + 'api/select') `
        -Headers @{Origin=$info.url.TrimEnd('/'); 'X-Session-Token'=$token} -ContentType 'application/json' -Body $body -TimeoutSec 5
    Assert-True ($resp.Content -match '"ok":true') 'POST select ok'
    Assert-FileContains $selOut 'pip-cache' 'selections.json written'
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
Remove-Item -Recurse -Force $fx -ErrorAction SilentlyContinue
Get-TestSummary 'test-serve'
