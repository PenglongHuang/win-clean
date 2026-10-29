$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\assert.ps1"
$root = Join-Path $PSScriptRoot '..\skills\win-clean'
$fx = Join-Path $env:TEMP ("wc-fx-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'fixtures\make-fixture.ps1') -Root $fx

# temp rules dir: copy builtin, add learned override for uv-cache pointing elsewhere
$rules = Join-Path $fx 'rules'
New-Item -ItemType Directory -Path $rules -Force | Out-Null
Copy-Item (Join-Path $root 'rules\builtin.json') $rules
# learned override: uv-cache id replaced path -> Local\uv2\cache (2048 bytes)
New-Item -ItemType Directory -Path "$fx\Local\uv2\cache" -Force | Out-Null
[IO.File]::WriteAllBytes("$fx\Local\uv2\cache\u2.bin", (New-Object byte[] 2048))

# -- extra fixture for -Drives/-ProgressFile: a path on the fixture drive (1024 bytes),
#    a second REAL drive via subst (512 bytes), and a bogus never-existing drive letter.
$fxDrive = $fx.Substring(0,1).ToUpperInvariant()
New-Item -ItemType Directory -Path "$fx\Local\qdrive-local" -Force | Out-Null
[IO.File]::WriteAllBytes("$fx\Local\qdrive-local\q1.bin", (New-Object byte[] 1024))
$substLetter = $null
$bogusLetter = $null
foreach ($n in 68..90) {
    $l = [string][char]$n
    if ($l -eq $fxDrive) { continue }
    if (Test-Path -LiteralPath "$l`:\" -ErrorAction SilentlyContinue) { continue }
    if (-not $substLetter) {
        New-Item -ItemType Directory -Path "$fx\qroot\payload" -Force | Out-Null
        [IO.File]::WriteAllBytes("$fx\qroot\payload\q2.bin", (New-Object byte[] 512))
        cmd /c subst "${l}:" "$fx\qroot" | Out-Null
        if (Test-Path -LiteralPath "${l}:\payload" -ErrorAction SilentlyContinue) { $substLetter = $l }
    } elseif (-not $bogusLetter) { $bogusLetter = $l }
}
if (-not $bogusLetter) { $bogusLetter = 'Q' }
$haveSubst = [bool]$substLetter
$qAllBytes = 1024 + (512 * [int]$haveSubst)     # qdrive-local + subst payload; bogus drive contributes 0
$qAllPaths = 2 + [int]$haveSubst                # qdrive-local + subst payload + bogus nowhere
$qKeptPaths = 1 + [int]$haveSubst               # under a filter that selects both real drives
$qRulePaths = '"%LOCALAPPDATA%\\qdrive-local","' + $bogusLetter + ':\\nowhere"'
if ($haveSubst) { $qRulePaths = '"%LOCALAPPDATA%\\qdrive-local","' + $substLetter + ':\\payload","' + $bogusLetter + ':\\nowhere"' }
$learnedRules = '[{"id":"uv-cache","level":1,"name":"uv override","paths":["%LOCALAPPDATA%\\uv2\\cache"],"type":"cache","strategy":"delete-permanent","desc":"learned test","guard":[],"auto_select":true,"source":"learned","discovered":"2026-10-18T00:00:00"},' +
    '{"id":"qdrive-test","level":1,"name":"qdrive test","paths":[' + $qRulePaths + '],"type":"cache","strategy":"delete-permanent","desc":"drive filter fixture rule","guard":[],"auto_select":true,"source":"learned","discovered":"2026-10-18T00:00:00"}]'
$learnedRules | Set-Content -Path (Join-Path $rules 'learned.json') -Encoding UTF8

$out = Join-Path $fx 'scan-result.json'
$scanPs1 = Join-Path $root 'engine\scan.ps1'

# Env-override so %LOCALAPPDATA%/%APPDATA% resolve into fixture; child inherits.
$oldLA, $oldAR = $env:LOCALAPPDATA, $env:APPDATA
$env:LOCALAPPDATA = "$fx\Local"
$env:APPDATA      = "$fx\Roaming"
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs1 `
        -RulesDir $rules -OutFile $out -OnlyIds pip-cache,user-temp,uv-cache,vscode-vsix-cache,hiberfil | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'scan exits 0'

    $scan = Get-Content -LiteralPath $out -Raw -Encoding UTF8 | ConvertFrom-Json

    # -- findings sizes (learned uv-cache wins: 2048 not 4096)
    $byId = @{}; foreach ($f in @($scan.findings)) { $byId[$f.id] = $f }
    Assert-Equal 3072  $byId['pip-cache'].bytes          'pip-cache size 3072'
    Assert-Equal 512   $byId['user-temp'].bytes          'user-temp size 512'
    Assert-Equal 2048  $byId['uv-cache'].bytes           'learned override wins'
    Assert-Equal 'learned' $byId['uv-cache'].source      'source is learned'
    $externalLearned = Join-Path $fx 'user-data\rules\learned.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $externalLearned) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $rules 'learned.json') -Destination $externalLearned
    $externalOut = Join-Path $fx 'scan-external-rules.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs1 -RulesDir $rules -LearnedFile $externalLearned -OutFile $externalOut -OnlyIds uv-cache | Out-Null
    $externalScan = Get-Content -LiteralPath $externalOut -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 2048 @($externalScan.findings)[0].bytes 'external learned rules loaded'
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
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs1 -RulesDir $rules -OutFile $out3 -OnlyIds nonexistent-id | Out-Null
    $empty = Get-Content -LiteralPath $out3 -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 0 $empty.totalBytes 'empty findings totalBytes is 0'

    # ===== Feature 1 (-Drives) + Feature 2 (-ProgressFile) =====

    # (a) baseline, no -Drives: every path entry kept (incl. other-drive + bogus); no progress file written
    $outD = Join-Path $fx 'scan-result-drives.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs1 -RulesDir $rules -OutFile $outD -OnlyIds qdrive-test | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'drive baseline exits 0'
    if (Test-Path -LiteralPath $outD) {
        $sD = Get-Content -LiteralPath $outD -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Equal $qAllPaths @(@($sD.findings)[0].paths).Count 'no -Drives keeps every path entry'
        Assert-Equal $qAllBytes @($sD.findings)[0].bytes 'no -Drives bytes include other drives'
    } else { Assert-True $false 'drive baseline output written' }
    Assert-True (@(Get-ChildItem -LiteralPath $fx -Recurse -Filter '*progress*' -ErrorAction SilentlyContinue).Count -eq 0) 'no progress file created without -ProgressFile'

    # (b) -Drives lowercase fixture letter: other/bogus drive paths dropped, bytes recomputed, drives filtered;
    #     -ProgressFile written incl. auto-created parent dir
    $outD2 = Join-Path $fx 'scan-result-drives2.json'
    $prog = Join-Path $fx 'prog\nested\scan-progress.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs1 -RulesDir $rules -OutFile $outD2 -OnlyIds qdrive-test -Drives ($fxDrive.ToLowerInvariant()) -ProgressFile $prog | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'drive filter scan exits 0'
    if (Test-Path -LiteralPath $outD2) {
        $sF = Get-Content -LiteralPath $outD2 -Raw -Encoding UTF8 | ConvertFrom-Json
        $f0 = @($sF.findings)[0]
        Assert-Equal 1 @($f0.paths).Count '-Drives drops other-drive path entries'
        Assert-Equal "$fxDrive`:" @($f0.paths)[0].expanded.Substring(0,2) 'remaining path is on selected drive'
        Assert-Equal 1024 $f0.bytes 'finding bytes recomputed after -Drives'
        Assert-Equal 1024 $sF.totalBytes 'totalBytes recomputed after -Drives'
        Assert-True (@($sF.drives).Count -ge 1) 'drives array non-empty when filtered'
        foreach ($d in @($sF.drives)) { Assert-Equal "$fxDrive`:" $d.letter 'drives array filtered to selection' }
        Assert-True (Test-Path -LiteralPath $prog) 'progress file written, parent dir created'
        if (Test-Path -LiteralPath $prog) {
            $pf = Get-Content -LiteralPath $prog -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-Equal 1 $pf.done 'progress done equals rule count'
            Assert-Equal 1 $pf.total 'progress total equals rule count'
            Assert-True ($pf.PSObject.Properties['currentName'] -ne $null) 'progress has currentName field'
            Assert-Equal '' $pf.currentId 'progress currentId empty after loop'
            Assert-Equal '' $pf.currentName 'progress currentName empty after loop'
            Assert-Equal 1024 $pf.bytesSoFar 'progress bytesSoFar equals totalBytes'
        }
    } else { Assert-True $false 'drive filter output written' }

    # (c) multi-letter -Drives (fixture + subst) across 5 rules: both real paths kept, running progress sum
    $outD3 = Join-Path $fx 'scan-result-drives3.json'
    $prog2 = Join-Path $fx 'prog2\scan-progress.json'
    $multiDrives = $fxDrive
    if ($haveSubst) { $multiDrives = "$fxDrive,$substLetter" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs1 -RulesDir $rules -OutFile $outD3 -OnlyIds pip-cache,user-temp,uv-cache,vscode-vsix-cache,qdrive-test -Drives $multiDrives -ProgressFile $prog2 | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'multi-drive scan exits 0'
    $expectedAll = 3072 + 512 + 2048 + 256 + $qAllBytes
    if (Test-Path -LiteralPath $outD3) {
        $sM = Get-Content -LiteralPath $outD3 -Raw -Encoding UTF8 | ConvertFrom-Json
        $qM = @($sM.findings) | Where-Object { $_.id -eq 'qdrive-test' }
        Assert-Equal $qKeptPaths @($qM.paths).Count 'multi-letter -Drives keeps both real drives'
        Assert-Equal $expectedAll $sM.totalBytes 'multi-rule totalBytes after -Drives'
        if (Test-Path -LiteralPath $prog2) {
            $pf2 = Get-Content -LiteralPath $prog2 -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-Equal 5 $pf2.done 'progress done counts every evaluated rule'
            Assert-Equal 5 $pf2.total 'progress total counts rules after merge'
            Assert-Equal '' $pf2.currentName 'multi progress currentName empty after loop'
            Assert-Equal $expectedAll $pf2.bytesSoFar 'progress running sum equals totalBytes'
        } else { Assert-True $false 'multi progress file written' }
    } else { Assert-True $false 'multi-drive output written' }

    # (d) -Drives selects ONLY the subst drive: fixture-drive findings excluded entirely
    if ($haveSubst) {
        $outD4 = Join-Path $fx 'scan-result-drives4.json'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs1 -RulesDir $rules -OutFile $outD4 -OnlyIds pip-cache,qdrive-test -Drives $substLetter | Out-Null
        Assert-Equal 0 $LASTEXITCODE 'subst-only scan exits 0'
        if (Test-Path -LiteralPath $outD4) {
            $sQ = Get-Content -LiteralPath $outD4 -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-Equal 1 @($sQ.findings).Count 'findings with zero remaining paths excluded'
            Assert-Equal 'qdrive-test' @($sQ.findings)[0].id 'surviving finding is on selected drive'
            Assert-Equal 512 @($sQ.findings)[0].bytes 'subst-only finding bytes'
            Assert-Equal 512 $sQ.totalBytes 'subst-only totalBytes'
        } else { Assert-True $false 'subst-only output written' }
    } else { Assert-True $true 'subst unavailable: second-drive asserts skipped' }

    # (e) invalid tokens only ("CC","1"): no valid letters -> no filter + warning on stdout
    $outD5 = Join-Path $fx 'scan-result-drives5.json'
    $warnLines = & powershell -NoProfile -ExecutionPolicy Bypass -File $scanPs1 -RulesDir $rules -OutFile $outD5 -OnlyIds qdrive-test -Drives 'CC,1'
    Assert-Equal 0 $LASTEXITCODE 'invalid-tokens scan exits 0'
    Assert-True ((@($warnLines) -join ' ') -match 'WARN') 'warning printed for invalid -Drives tokens'
    if (Test-Path -LiteralPath $outD5) {
        $sI = Get-Content -LiteralPath $outD5 -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Equal $qAllPaths @(@($sI.findings)[0].paths).Count 'invalid tokens behave as no filter'
        Assert-Equal $qAllBytes @($sI.findings)[0].bytes 'invalid tokens keep all bytes'
    } else { Assert-True $false 'invalid-tokens output written' }
} finally {
    $env:LOCALAPPDATA, $env:APPDATA = $oldLA, $oldAR
    if ($substLetter) { cmd /c subst "${substLetter}:" /D | Out-Null }
    Remove-Item -Recurse -Force $fx -ErrorAction SilentlyContinue
}
Get-TestSummary 'test-scan'
