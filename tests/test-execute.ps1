$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\assert.ps1"
$root = Join-Path $PSScriptRoot '..'
$fx = Join-Path $env:TEMP ("wc-exec-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$hist = Join-Path $fx 'history'
New-Item -ItemType Directory -Path "$fx\targets\perm\sub", "$fx\targets\quar" -Force | Out-Null
[IO.File]::WriteAllBytes("$fx\targets\perm\sub\f.bin", (New-Object byte[] 100))
[IO.File]::WriteAllBytes("$fx\targets\quar\g.bin",  (New-Object byte[] 200))

$scan = [pscustomobject]@{
    timestamp = 'now'; host = 't'; drives = @(); totalBytes = 300
    findings = @(
        [pscustomobject]@{ id='perm-rule'; level=1; name='p'; type='cache'; strategy='delete-permanent'; desc=''; auto_select=$true; source='builtin'; bytes=100; needs_admin=$false
            paths=@(@{path='X';expanded="$fx\targets\perm";exists=$true;bytes=100}) },
        [pscustomobject]@{ id='quar-rule'; level=3; name='q'; type='cache'; strategy='recycle-bin'; desc=''; auto_select=$false; source='builtin'; bytes=200; needs_admin=$false
            paths=@(@{path='Y';expanded="$fx\targets\quar";exists=$true;bytes=200}) },
        [pscustomobject]@{ id='protect-rule'; level=1; name='w'; type='cache'; strategy='delete-permanent'; desc=''; auto_select=$true; source='builtin'; bytes=1; needs_admin=$false
            paths=@(@{path='Z';expanded="$env:SystemRoot\FontsFake";exists=$true;bytes=1}) },
        [pscustomobject]@{ id='root-rule'; level=2; name='r'; type='temp'; strategy='delete-permanent'; desc=''; auto_select=$true; source='builtin'; bytes=1; needs_admin=$false
            paths=@(@{path='R';expanded="$env:SystemDrive\";exists=$true;bytes=1}) },
        [pscustomobject]@{ id='ro-rule'; level=5; name='v'; type='system'; strategy='report-only'; desc=''; auto_select=$false; source='builtin'; bytes=5; needs_admin=$false
            paths=@(@{path='V';expanded="$fx\targets\perm";exists=$true;bytes=5}) }
    )
}
$scanFile  = "$fx\scan-result.json"
$selFile   = "$fx\selections.json"
$scan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $scanFile -Encoding UTF8
@{ ids = @('perm-rule','quar-rule','protect-rule','root-rule','ro-rule') } | ConvertTo-Json | Set-Content -LiteralPath $selFile -Encoding UTF8

try {
    # -- DryRun first: no fs change
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\execute.ps1') `
        -ScanFile $scanFile -SelectionsFile $selFile -HistoryDir $hist -DryRun | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'dry-run exits 0'
    Assert-True (Test-Path "$fx\targets\perm\sub\f.bin") 'dry-run deleted nothing'
    Assert-True (Test-Path "$fx\targets\quar\g.bin")     'dry-run moved nothing'

    # -- real run
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\execute.ps1') `
        -ScanFile $scanFile -SelectionsFile $selFile -HistoryDir $hist | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'execute exits 0'

    Assert-True (-not (Test-Path "$fx\targets\perm"))           'permanent path deleted'
    Assert-True (-not (Test-Path "$fx\targets\quar\g.bin"))     'quarantine source gone'
    Assert-True (Test-Path (Get-ChildItem "$hist\quarantine\quar-rule_*" -Recurse -Filter g.bin | Select-Object -First 1 -ExpandProperty FullName -ErrorAction SilentlyContinue)) 'quarantined file stored'
    Assert-True (@(Get-ChildItem "$hist\*.jsonl").Count -ge 1)  'audit log written'
    $restore = Get-ChildItem "$hist\restore-*.ps1" | Select-Object -First 1
    Assert-True ($null -ne $restore) 'restore script written'

    # -- audit log content: protected refusal + report-only refusal recorded
    $logText = (Get-ChildItem "$hist\*.jsonl" | ForEach-Object { Get-Content $_ -Raw -Encoding UTF8 }) -join "`n"
    Assert-True ($logText -match 'refused-protected')   'protected path refused'
    Assert-True ($logText -match 'skipped-report-only') 'report-only skipped'

    # -- exec summary written
    $summary = Get-Content "$hist\exec-summary.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($summary.PSObject.Properties['freedBytes'] -ne $null) 'summary has freedBytes'
    Assert-Equal 300 $summary.freedBytes 'freedBytes = 100 perm + 200 quar'

    # -- restore returns quarantined file
    & powershell -NoProfile -ExecutionPolicy Bypass -File $restore.FullName | Out-Null
    Assert-True (Test-Path "$fx\targets\quar\g.bin") 'restore brought file back'
} finally {
    Remove-Item -Recurse -Force $fx -ErrorAction SilentlyContinue
}
Get-TestSummary 'test-execute'
