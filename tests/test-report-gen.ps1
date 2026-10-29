$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\assert.ps1"
$root = Join-Path $PSScriptRoot '..\skills\win-clean'
$fx = Join-Path $env:TEMP ("wc-rg-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$hist = "$fx\logs\history"
New-Item -ItemType Directory -Path $hist -Force | Out-Null

# Chinese finding names are built from char codes so this test file stays
# ASCII-only (PS 5.1 rule); the JSON fixture itself still carries the Chinese
# names as data, matching what scan.ps1 really emits.
$nameA = -join [char[]](0x70,0x69,0x20,0x4E0B,0x8F7D,0x7F13,0x5B58)   # pip download cache (CN)
$nameB = -join [char[]](0x5E94,0x7528,0x7F13,0x5B58,0x58)             # app cache X (CN)

$scan = [pscustomobject]@{
    timestamp='2026-10-18T19:30:00'; host='t'; totalBytes=5996; isAdmin=$false
    drives=@([pscustomobject]@{letter='C:'; total=[uint64]117GB; free=[uint64]14GB})
    findings=@(
        [pscustomobject]@{ id='pip-cache'; level=1; name=$nameA; type='cache'; strategy='delete-permanent'; desc='d'; auto_select=$true; source='builtin'; bytes=4096; needs_admin=$false; paths=@() },
        [pscustomobject]@{ id='quar-x';    level=3; name=$nameB;  type='cache'; strategy='recycle-bin';      desc='d'; auto_select=$false; source='learned'; bytes=1900; needs_admin=$false; paths=@() }
    )
}
$scanFile = "$fx\scan-result.json"
$scan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $scanFile -Encoding UTF8
$summary = [pscustomobject]@{
    stamp='20261018-193000'; dryRun=$false; freedBytes=5996
    drivesBefore=@([pscustomobject]@{letter='C:'; free=[uint64]1200000000; total=[uint64]117GB})
    drivesAfter=@([pscustomobject]@{letter='C:'; free=[uint64]7400000000; total=[uint64]117GB})
    logFile='l.jsonl'; restoreFile='restore-x.ps1'
}
$sumFile = "$fx\exec-summary.json"
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sumFile -Encoding UTF8

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\report-gen.ps1') `
    -ScanFile $scanFile -ExecSummaryFile $sumFile -SessionDir "$hist\2026-10-18_1930" -HistoryRoot $hist | Out-Null
Assert-Equal 0 $LASTEXITCODE 'report-gen exits 0'

$final = "$hist\2026-10-18_1930\final-report.html"
Assert-True (Test-Path $final) 'final-report.html written'
Assert-FileContains $final '5.9 KB' 'freed amount rendered'      # 5996 bytes
Assert-FileContains $final 'pip-cache' 'finding id rendered'     # ASCII id, not the CN name literal
Assert-True ((Get-Content $final -Raw -Encoding UTF8) -notmatch 'window\.FINAL_DATA = null') 'final data injected'

Assert-True (Test-Path "$hist\index.json") 'history index written'
$idx = Get-Content "$hist\index.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 1 @($idx.sessions).Count 'index has 1 session'
Assert-Equal 5996 $idx.sessions[0].freedBytes 'session freed recorded'

# -- second run appends
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\report-gen.ps1') `
    -ScanFile $scanFile -ExecSummaryFile $sumFile -SessionDir "$hist\2026-10-18_2100" -HistoryRoot $hist | Out-Null
$idx2 = Get-Content "$hist\index.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 2 @($idx2.sessions).Count 'second session appended'
Assert-Equal 11992 $idx2.totalFreed 'cumulative total updated'

# -- corrupt index.json: must fall back to a fresh index, not die
Set-Content -LiteralPath "$hist\index.json" -Value '{oops' -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\report-gen.ps1') `
    -ScanFile $scanFile -ExecSummaryFile $sumFile -SessionDir "$hist\2026-10-19_0900" -HistoryRoot $hist | Out-Null
Assert-Equal 0 $LASTEXITCODE 'report-gen survives corrupt index'
$idx3 = Get-Content "$hist\index.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 1 @($idx3.sessions).Count 'corrupt index reset to 1 session'
Assert-Equal 5996 $idx3.totalFreed 'fresh total after corruption'

Remove-Item -Recurse -Force $fx
Get-TestSummary 'test-report-gen'
