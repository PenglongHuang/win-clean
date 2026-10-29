#Requires -Version 5.1
# Renders the final analysis report (self-contained html) and maintains the history index.
param(
    [Parameter(Mandatory=$true)][string]$ScanFile,
    [string]$ExecSummaryFile,                       # optional: scan-only report if omitted
    [Parameter(Mandatory=$true)][string]$SessionDir,
    [Parameter(Mandatory=$true)][string]$HistoryRoot
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SessionDir)) { New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null }
if (-not (Test-Path $HistoryRoot)) { New-Item -ItemType Directory -Path $HistoryRoot -Force | Out-Null }

function Format-Bytes([int64]$n) {
    # PS-side twin of report/app.js fmtBytes (5996 -> '5.9 KB'), so the static
    # HTML carries a human-readable total even before JS runs. Invariant culture
    # pins '.' as the decimal separator regardless of system locale.
    if ($n -lt 0) { return [string]$n }
    $u = @('B','KB','MB','GB','TB'); $i = 0; $v = [double]$n
    while ($v -ge 1024 -and $i -lt ($u.Count - 1)) { $v = $v / 1024; $i++ }
    if ($i -eq 0) { return ('{0} B' -f [int64]$v) }
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:F1} {1}', $v, $u[$i])
}

$scan = Get-Content -LiteralPath $ScanFile -Raw -Encoding UTF8 | ConvertFrom-Json
$exec = $null
if ($ExecSummaryFile -and (Test-Path $ExecSummaryFile)) {
    $exec = Get-Content -LiteralPath $ExecSummaryFile -Raw -Encoding UTF8 | ConvertFrom-Json
}

# per-finding outcome from audit log (best-effort join)
$outcomes = @{}
if ($exec -and $exec.logFile -and (Test-Path $exec.logFile)) {
    foreach ($line in (Get-Content -LiteralPath $exec.logFile -Encoding UTF8)) {
        if (-not $line.Trim()) { continue }
        try {
            $e = $line | ConvertFrom-Json
            $outcomes[$e.id] = $e.action
        } catch { }
    }
}
$findings = @($scan.findings | ForEach-Object {
    [pscustomobject]@{
        id = $_.id; level = $_.level; name = $_.name; bytes = $_.bytes
        outcome = $outcomes[$_.id]
    }
})

$freedBytes = if ($exec) { [int64]$exec.freedBytes } else { [int64]0 }
$finalData = [pscustomobject]@{
    stamp = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    dryRun = [bool]($exec -and $exec.dryRun)
    freedBytes = $freedBytes
    freedBytesText = Format-Bytes $freedBytes
    drivesBefore = if ($exec) { $exec.drivesBefore } else { $scan.drives }
    drivesAfter  = if ($exec) { $exec.drivesAfter }  else { $scan.drives }
    findings = $findings
    logFile = if ($exec) { $exec.logFile } else { $null }
    restoreFile = if ($exec) { $exec.restoreFile } else { $null }
}

# history index (atomic-ish: read, merge, write)
$idxPath = Join-Path $HistoryRoot 'index.json'
$idx = [pscustomobject]@{ sessions = @(); totalFreed = [int64]0 }
if (Test-Path $idxPath) {
    # corrupt/invalid JSON falls back to the fresh default above so one bad
    # file cannot permanently brick history (worst case: totals restart)
    try {
        $old = Get-Content -LiteralPath $idxPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($old) { $idx = $old }
    } catch {
        Write-Warning "history index unreadable, starting fresh: $idxPath"
    }
}
$reportPath = Join-Path $SessionDir 'final-report.html'
$sessions = @($idx.sessions) + @(
    [pscustomobject]@{
        dir = Split-Path -Leaf $SessionDir
        ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        freedBytes = if ($finalData.dryRun) { [int64]0 } else { [int64]$finalData.freedBytes }
        reportPath = $reportPath
    }
)
$totalFreed = [int64]0
foreach ($s in $sessions) { $totalFreed += [int64]$s.freedBytes }
$newIdx = [pscustomobject]@{ sessions = $sessions; totalFreed = $totalFreed }

# render: inject data + inline app.js for self-contained file
# (report is rendered and written BEFORE the index, so a render failure cannot
# leave a phantom session whose reportPath is dead and whose bytes inflate totals)
$tplPath = Join-Path $PSScriptRoot '..\report\final-template.html'
$appJsPath = Join-Path $PSScriptRoot '..\report\app.js'
$html = Get-Content -LiteralPath $tplPath -Raw -Encoding UTF8
$html = $html.Replace('/*__FINAL_DATA__*/null', (($finalData | ConvertTo-Json -Depth 5).Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e')))
$html = $html.Replace('/*__HISTORY__*/null', (($newIdx | ConvertTo-Json -Depth 5).Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e')))
$inline = Get-Content -LiteralPath $appJsPath -Raw -Encoding UTF8
$html = $html.Replace('<script src="app.js"></script>', ("<script>`n" + $inline + "`n</script>"))
$html | Set-Content -LiteralPath $reportPath -Encoding UTF8
# index lands only after the report exists on disk (see ordering note above)
$newIdx | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $idxPath -Encoding UTF8
Write-Output "FINAL REPORT: $reportPath"
exit 0
