$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\assert.ps1"
$root = Join-Path $PSScriptRoot '..'
$fx = Join-Path $env:TEMP ("wc-exec-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$hist = Join-Path $fx 'history'
New-Item -ItemType Directory -Path "$fx\targets\perm\sub", "$fx\targets\quar", "$fx\targets\admin" -Force | Out-Null
[IO.Directory]::CreateDirectory("$fx\targets\quar[1]") | Out-Null   # bracket leaf: pins wildcard-safety
[IO.File]::WriteAllBytes("$fx\targets\perm\sub\f.bin", (New-Object byte[] 100))
[IO.File]::WriteAllBytes("$fx\targets\quar\g.bin",  (New-Object byte[] 200))
[IO.File]::WriteAllBytes("$fx\targets\quar[1]\h.bin", (New-Object byte[] 50))
[IO.File]::WriteAllBytes("$fx\targets\admin\a.bin", (New-Object byte[] 7))

$scan = [pscustomobject]@{
    timestamp = 'now'; host = 't'; drives = @(); totalBytes = 357
    findings = @(
        [pscustomobject]@{ id='perm-rule'; level=1; name='p'; type='cache'; strategy='delete-permanent'; desc=''; auto_select=$true; source='builtin'; bytes=100; needs_admin=$false
            paths=@(@{path='X';expanded="$fx\targets\perm";exists=$true;bytes=100}) },
        [pscustomobject]@{ id='quar-rule'; level=3; name='q'; type='cache'; strategy='recycle-bin'; desc=''; auto_select=$false; source='builtin'; bytes=200; needs_admin=$false
            paths=@(@{path='Y';expanded="$fx\targets\quar";exists=$true;bytes=200}) },
        [pscustomobject]@{ id='quar2-rule'; level=4; name='q2'; type='cache'; strategy='recycle-bin'; desc=''; auto_select=$false; source='builtin'; bytes=50; needs_admin=$false
            paths=@(@{path='Y2';expanded="$fx\targets\quar[1]";exists=$true;bytes=50}) },
        [pscustomobject]@{ id='admin-rule'; level=1; name='adm'; type='system'; strategy='delete-permanent'; desc=''; auto_select=$true; source='builtin'; bytes=7; needs_admin=$true
            paths=@(@{path='W';expanded="$fx\targets\admin\a.bin";exists=$true;bytes=7}) },
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
@{ ids = @('perm-rule','quar-rule','quar2-rule','admin-rule','protect-rule','root-rule','ro-rule') } | ConvertTo-Json | Set-Content -LiteralPath $selFile -Encoding UTF8

try {
    # -- DryRun first: no fs change
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\execute.ps1') `
        -ScanFile $scanFile -SelectionsFile $selFile -HistoryDir $hist -DryRun | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'dry-run exits 0'
    Assert-True (Test-Path "$fx\targets\perm\sub\f.bin") 'dry-run deleted nothing'
    Assert-True (Test-Path "$fx\targets\quar\g.bin")     'dry-run moved nothing'
    Assert-True (Test-Path -LiteralPath "$fx\targets\quar[1]\h.bin") 'dry-run moved nothing (quar2)'
    $dryText = (Get-ChildItem "$hist\*.jsonl" | ForEach-Object { Get-Content $_ -Raw -Encoding UTF8 }) -join "`n"
    Assert-True ($dryText -match 'dryrun') 'dry-run logs planned actions'

    # -- purge fixtures: fake quarantines old (40 days) and fresh; the real run must purge only the old one
    $oldQ = Join-Path $hist 'quarantine\zz-purge-old_x'
    $newQ = Join-Path $hist 'quarantine\zz-purge-new_x'
    New-Item -ItemType Directory -Path $oldQ, $newQ -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $oldQ 'stale.bin'), (New-Object byte[] 1))
    (Get-Item -LiteralPath $oldQ).LastWriteTime = (Get-Date).AddDays(-40)

    # -- real run
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'engine\execute.ps1') `
        -ScanFile $scanFile -SelectionsFile $selFile -HistoryDir $hist | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'execute exits 0'

    Assert-True (-not (Test-Path "$fx\targets\perm"))           'permanent path deleted'
    Assert-True (-not (Test-Path "$fx\targets\quar\g.bin"))     'quarantine source gone'
    Assert-True (-not (Test-Path -LiteralPath "$fx\targets\quar[1]\h.bin")) 'quar2 source gone'
    Assert-True (Test-Path "$fx\targets\admin\a.bin")   'needs-admin target survives'
    Assert-True (-not (Test-Path -LiteralPath $oldQ))   'stale quarantine purged (30d)'
    Assert-True (Test-Path -LiteralPath $newQ)          'fresh quarantine kept'
    Assert-True (Test-Path (Get-ChildItem "$hist\quarantine\quar-rule_*" -Recurse -Filter g.bin | Select-Object -First 1 -ExpandProperty FullName -ErrorAction SilentlyContinue)) 'quarantined file stored'
    Assert-True (@(Get-ChildItem "$hist\*.jsonl").Count -ge 1)  'audit log written'
    $restore = Get-ChildItem "$hist\restore-*.ps1" | Select-Object -First 1
    Assert-True ($null -ne $restore) 'restore script written'

    # -- audit log content: protected refusal + report-only refusal recorded
    $logText = (Get-ChildItem "$hist\*.jsonl" | ForEach-Object { Get-Content $_ -Raw -Encoding UTF8 }) -join "`n"
    Assert-True ($logText -match 'refused-protected')   'protected path refused'
    Assert-True ($logText -match 'skipped-report-only') 'report-only skipped'
    Assert-True ($logText -match 'deleted')             'real run logs deletions'
    Assert-True ($logText -match 'needs-admin')         'needs-admin skip logged'

    # -- exec summary written
    $summary = Get-Content "$hist\exec-summary.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($summary.PSObject.Properties['freedBytes'] -ne $null) 'summary has freedBytes'
    Assert-Equal 350 $summary.freedBytes 'freedBytes = 100 perm + 250 quar (2 items)'
    Assert-True ($summary.PSObject.Properties['errorCount'] -ne $null)   'summary has errorCount'
    Assert-Equal 0 $summary.errorCount   'errorCount = 0'
    Assert-Equal 2 $summary.refusedCount 'refusedCount = 2 (protect + drive root)'

    # -- restore returns EVERY quarantined file (multi-item restore round-trip)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $restore.FullName | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'restore script exits 0'
    Assert-True (Test-Path "$fx\targets\quar\g.bin")  'restore brought file back'
    Assert-True (Test-Path -LiteralPath "$fx\targets\quar[1]\h.bin") 'restore brought quar2 file back'
} finally {
    Remove-Item -Recurse -Force $fx -ErrorAction SilentlyContinue
}
Get-TestSummary 'test-execute'
