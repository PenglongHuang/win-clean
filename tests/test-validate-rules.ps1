$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\assert.ps1"
$root = Join-Path $PSScriptRoot '..'
$tmp = Join-Path $env:TEMP ("wc-test-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# -- valid file passes
$good = @'
[
  {"id":"a-cache","level":1,"name":"A cache","paths":["%LOCALAPPDATA%\\a\\cache"],"type":"cache","strategy":"delete-permanent","desc":"regenerable","guard":[],"auto_select":true,"source":"builtin","discovered":null},
  {"id":"b-old","level":5,"name":"B old","paths":["C:\\Windows.old"],"type":"leftover","strategy":"report-only","desc":"system","guard":["admin-required"],"auto_select":false,"source":"builtin","discovered":null}
]
'@
Set-Content -Path (Join-Path $tmp 'good.json') -Value $good -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\validate-rules.ps1') -RulesFile (Join-Path $tmp 'good.json') | Out-Null
Assert-Equal 0 $LASTEXITCODE 'valid file exits 0'

# -- invalid file fails: bad level, duplicate id, missing field, strategy/level mismatch
$bad = @'
[
  {"id":"a","level":9,"name":"x","paths":["C:\\a"],"type":"cache","strategy":"delete-permanent","desc":"d","guard":[],"auto_select":true,"source":"builtin","discovered":null},
  {"id":"a","level":1,"name":"x","paths":["C:\\a"],"type":"cache","strategy":"recycle-bin","desc":"d","guard":[],"auto_select":true,"source":"builtin","discovered":null},
  {"id":"b","level":1,"name":"x","type":"cache","strategy":"delete-permanent","desc":"d","guard":[],"auto_select":true,"source":"builtin","discovered":null}
]
'@
Set-Content -Path (Join-Path $tmp 'bad.json') -Value $bad -Encoding UTF8
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\validate-rules.ps1') -RulesFile (Join-Path $tmp 'bad.json') 2>&1
Assert-Equal 1 $LASTEXITCODE 'invalid file exits 1'
Assert-True ("$out" -match 'level must be 1-5') 'bad level reported'
Assert-True ("$out" -match 'duplicate id') 'duplicate id reported'
Assert-True ("$out" -match 'must use strategy') 'strategy mismatch reported'
Assert-True ("$out" -match 'missing field') 'missing field reported'

# -- null paths must be rejected explicitly
$nullPaths = @'
[{"id":"n","level":1,"name":"n","paths":null,"type":"cache","strategy":"delete-permanent","desc":"d","guard":[],"auto_select":true,"source":"builtin","discovered":null}]
'@
Set-Content -Path (Join-Path $tmp 'nullpaths.json') -Value $nullPaths -Encoding UTF8
$out2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\validate-rules.ps1') -RulesFile (Join-Path $tmp 'nullpaths.json') 2>&1
Assert-Equal 1 $LASTEXITCODE 'null paths rejected'
Assert-True ("$out2" -match 'paths empty') 'null paths message'

# -- real builtin.json must validate
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\validate-rules.ps1') -RulesFile (Join-Path $root 'rules\builtin.json') | Out-Null
Assert-Equal 0 $LASTEXITCODE 'builtin.json is valid'

Remove-Item -Recurse -Force $tmp
Get-TestSummary 'test-validate-rules'
