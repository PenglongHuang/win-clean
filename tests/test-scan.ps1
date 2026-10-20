$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\assert.ps1"
$root = Join-Path $PSScriptRoot '..'
$fx = Join-Path $env:TEMP ("wc-fx-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'fixtures\make-fixture.ps1') -Root $fx

# temp rules dir: copy builtin, add learned override for uv-cache pointing elsewhere
$rules = Join-Path $fx 'rules'
New-Item -ItemType Directory -Path $rules -Force | Out-Null
Copy-Item (Join-Path $root 'rules\builtin.json') $rules
# learned override: uv-cache id replaced path -> Local\uv2\cache (2048 bytes)
New-Item -ItemType Directory -Path "$fx\Local\uv2\cache" -Force | Out-Null
[IO.File]::WriteAllBytes("$fx\Local\uv2\cache\u2.bin", (New-Object byte[] 2048))
@'
[{"id":"uv-cache","level":1,"name":"uv override","paths":["%LOCALAPPDATA%\\uv2\\cache"],"type":"cache","strategy":"delete-permanent","desc":"learned test","guard":[],"auto_select":true,"source":"learned","discovered":"2026-10-18T00:00:00"}]
'@ | Set-Content -Path (Join-Path $rules 'learned.json') -Encoding UTF8

$out = Join-Path $fx 'scan-result.json'

# Env-override so %LOCALAPPDATA%/%APPDATA% resolve into fixture; child inherits.
$oldLA, $oldAR = $env:LOCALAPPDATA, $env:APPDATA
$env:LOCALAPPDATA = "$fx\Local"
$env:APPDATA      = "$fx\Roaming"
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\scan.ps1') `
        -RulesDir $rules -OutFile $out -OnlyIds pip-cache,user-temp,uv-cache,vscode-vsix-cache,hiberfil | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'scan exits 0'

    $scan = Get-Content -LiteralPath $out -Raw -Encoding UTF8 | ConvertFrom-Json

    # -- findings sizes (learned uv-cache wins: 2048 not 4096)
    $byId = @{}; foreach ($f in @($scan.findings)) { $byId[$f.id] = $f }
    Assert-Equal 3072  $byId['pip-cache'].bytes          'pip-cache size 3072'
    Assert-Equal 512   $byId['user-temp'].bytes          'user-temp size 512'
    Assert-Equal 2048  $byId['uv-cache'].bytes           'learned override wins'
    Assert-Equal 'learned' $byId['uv-cache'].source      'source is learned'
    Assert-Equal 256   $byId['vscode-vsix-cache'].bytes  'vsix cache size 256'
    # -- junction traversal: reparse point inside pip\cache must not be followed
    $jn = Join-Path $fx 'Local\pip\cache\loop-junction'
    Assert-True (Test-Path $jn) 'junction created in fixture'
    Assert-Equal 3072 $byId['pip-cache'].bytes 'junction not double-counted via pip-cache'
    # -- hiberfil tolerated whether or not it exists on this machine
    if ($byId.ContainsKey('hiberfil')) {
        Assert-Equal 'C:\hiberfil.sys' @($byId['hiberfil'].paths)[0].expanded 'hiberfil expanded path'
        Assert-Equal 'True' $byId['hiberfil'].needs_admin 'hiberfil needs admin when not elevated'
    }
    Assert-True $true 'hiberfil tolerated (present-or-absent)'
    # -- output schema
    Assert-True ($scan.timestamp -is [string])      'timestamp present'
    Assert-True (@($scan.drives).Count -ge 1)       'drives listed'
    Assert-True ($scan.drives[0].PSObject.Properties['free'] -ne $null) 'drive free present'
    Assert-True ($scan.PSObject.Properties['totalBytes'] -ne $null)     'totalBytes present'

    # -- empty findings: totalBytes must be 0, not null
    $out3 = Join-Path $fx 'scan-result3.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\scan.ps1') -RulesDir $rules -OutFile $out3 -OnlyIds nonexistent-id | Out-Null
    $empty = Get-Content -LiteralPath $out3 -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 0 $empty.totalBytes 'empty findings totalBytes is 0'
} finally {
    $env:LOCALAPPDATA, $env:APPDATA = $oldLA, $oldAR
    Remove-Item -Recurse -Force $fx -ErrorAction SilentlyContinue
}
Get-TestSummary 'test-scan'
