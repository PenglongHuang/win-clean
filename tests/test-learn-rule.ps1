$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\assert.ps1"
$root = Join-Path $PSScriptRoot '..\skills\win-clean'
$fx = Join-Path $env:TEMP ("wc-lr-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $fx -Force | Out-Null
Copy-Item (Join-Path $root 'rules\builtin.json') $fx

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\learn-rule.ps1') `
    -RulesDir $fx -Id youku-leftover -Level 4 -Name 'Youku leftover' -Paths 'D:\Program Files (x86)\YouKu' `
    -Type leftover -Desc 'uninstalled client data' -AutoSelect:$false | Out-Null
Assert-Equal 0 $LASTEXITCODE 'learn-rule exits 0'

# PS 5.1: ConvertFrom-Json emits a JSON array as ONE pipeline object; two-step unwrap
# (assign, then @()) or @() inline collapses multi-element arrays.
$learnedJson = Get-Content (Join-Path $fx 'learned.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$learned = @($learnedJson)
Assert-Equal 1 $learned.Count 'one learned rule appended'
$externalLearned = Join-Path $fx 'user-data\rules\learned.json'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\learn-rule.ps1') `
    -RulesDir $fx -LearnedFile $externalLearned -Id external-rule -Level 3 -Name 'external' -Paths 'D:\external' `
    -Type cache -Desc 'external data path' | Out-Null
Assert-Equal 0 $LASTEXITCODE 'external learned rule saved'
Assert-True (Test-Path -LiteralPath $externalLearned) 'external learned file created'
Assert-Equal 'learned' $learned[0].source 'source is learned'
Assert-Equal 'recycle-bin' $learned[0].strategy 'level4 -> recycle-bin auto'
Assert-True ($learned[0].discovered -is [string] -and $learned[0].discovered.Length -gt 0) 'discovered timestamp set'

# -- comma-separated paths split into a real array (mandated fix 2)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\learn-rule.ps1') `
    -RulesDir $fx -Id multi-path -Level 3 -Name 'multi' -Paths 'D:\a,D:\b' `
    -Type cache -Desc 'd' | Out-Null
Assert-Equal 0 $LASTEXITCODE 'multi-path learn-rule exits 0'
$learned2Json = Get-Content (Join-Path $fx 'learned.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$learned2 = @($learned2Json)
Assert-Equal 2 $learned2.Count 'second rule appended'
Assert-Equal 2 @($learned2[1].paths).Count 'comma paths split into 2'

# -- duplicate id rejected
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\learn-rule.ps1') `
    -RulesDir $fx -Id youku-leftover -Level 4 -Name 'dup' -Paths 'D:\x' -Type leftover -Desc 'd' 2>&1 | Out-Null
Assert-Equal 1 $LASTEXITCODE 'duplicate id rejected'

# -- builtin id collision rejected
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\learn-rule.ps1') `
    -RulesDir $fx -Id pip-cache -Level 1 -Name 'collide' -Paths 'D:\x' -Type cache -Desc 'd' 2>&1 | Out-Null
Assert-Equal 1 $LASTEXITCODE 'builtin id collision rejected'

# -- invalid level rejected (child param-binding failure writes to stderr; relax EAP so
# the 2>&1 NativeCommandError doesn't abort this script under ErrorActionPreference=Stop)
$ErrorActionPreference = 'Continue'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\learn-rule.ps1') `
    -RulesDir $fx -Id ok-id -Level 9 -Name 'bad' -Paths 'D:\x' -Type leftover -Desc 'd' 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
Assert-Equal 1 $LASTEXITCODE 'invalid level rejected'

Remove-Item -Recurse -Force $fx
Get-TestSummary 'test-learn-rule'
