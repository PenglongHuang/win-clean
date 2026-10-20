#Requires -Version 5.1
# The ONLY component allowed to delete. Honors per-rule strategy, refuses
# protected paths, writes an audit log and a one-click restore script.
param(
    [Parameter(Mandatory=$true)][string]$ScanFile,
    [Parameter(Mandatory=$true)][string]$SelectionsFile,
    [Parameter(Mandatory=$true)][string]$HistoryDir,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $HistoryDir)) { New-Item -ItemType Directory -Path $HistoryDir -Force | Out-Null }
$stamp       = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile     = Join-Path $HistoryDir "execute-$stamp.jsonl"
$quarRoot    = Join-Path $HistoryDir 'quarantine'
$restoreFile = Join-Path $HistoryDir "restore-$stamp.ps1"

function Write-Log([string]$Action, [string]$Id, [string]$Path, [int64]$Bytes, [string]$Result) {
    $line = [pscustomobject]@{
        ts = (Get-Date).ToString('o'); action = $Action; id = $Id
        path = $Path; bytes = $Bytes; result = $Result
    }
    Add-Content -LiteralPath $logFile -Value ($line | ConvertTo-Json -Compress) -Encoding UTF8
}

# Roots that must never be deleted themselves. Rules may clean INSIDE them
# (e.g. %LOCALAPPDATA%\Temp lives under Users), but the roots are off-limits.
$script:ProtectedRoots = @(
    $env:SystemRoot,
    "$env:SystemDrive\Program Files",
    "$env:SystemDrive\Program Files (x86)",
    "$env:SystemDrive\ProgramData",
    "$env:SystemDrive\Users",
    $env:USERPROFILE
) | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique

function Test-ProtectedPath([string]$Target) {
    try { $full = [IO.Path]::GetFullPath($Target).TrimEnd('\') } catch { return $true }
    if ($full -match '^[A-Za-z]:$') { return $true }                          # drive root
    foreach ($root in $script:ProtectedRoots) {
        if ($full -eq $root) { return $true }                                 # protected root itself (-eq is case-insensitive)
    }
    if ($full.StartsWith($env:SystemRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }  # anything inside Windows
    return $false
}

# PS 5.1: two-step JSON unwrap
$scanJson = Get-Content -LiteralPath $ScanFile -Raw -Encoding UTF8 | ConvertFrom-Json
$selJson  = Get-Content -LiteralPath $SelectionsFile -Raw -Encoding UTF8 | ConvertFrom-Json
$wanted = @($selJson.ids | Where-Object { $_ })
$byId = @{}; foreach ($f in @($scanJson.findings)) { $byId[$f.id] = $f }

$drivesBefore = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
    ForEach-Object { [pscustomobject]@{ letter = $_.DeviceID; free = [uint64]$_.FreeSpace; total = [uint64]$_.Size } }

$manifest = @()   # quarantine mapping for restore script
$freed = [int64]0
foreach ($id in $wanted) {
    $f = $byId[$id]
    if (-not $f) { Write-Log 'skipped' $id '' 0 'id-not-in-scan'; continue }
    if ($f.strategy -eq 'report-only') {
        foreach ($p in @($f.paths)) { Write-Log 'skipped-report-only' $id ([string]$p.expanded) $p.bytes 'see report for command' }
        continue
    }
    if ($f.needs_admin -and -not $scanJson.isAdmin) {
        Write-Log 'skipped' $id '' $f.bytes 'needs-admin'
        continue
    }
    foreach ($p in @($f.paths)) {
        if (-not $p.exists) { Write-Log 'skipped' $id ([string]$p.expanded) 0 'path-missing'; continue }
        $target = [string]$p.expanded
        if (Test-ProtectedPath $target) {
            Write-Log 'refused-protected' $id $target $p.bytes 'blocked-by-protection'
            continue
        }
        try {
            $item = Get-Item -LiteralPath $target -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                Write-Log 'skipped' $id $target 0 'reparse-point'; continue
            }
            if ($DryRun) {
                Write-Log ("dryrun-" + $f.strategy) $id $target $p.bytes 'planned'
                $freed += [int64]$p.bytes
                continue
            }
            if ($f.strategy -eq 'delete-permanent') {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
                Write-Log 'deleted' $id $target $p.bytes 'ok'
                $freed += [int64]$p.bytes
            }
            elseif ($f.strategy -eq 'recycle-bin') {
                $destDir = Join-Path $quarRoot ($id + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                $dest = Join-Path $destDir (Split-Path -Leaf $target)
                Move-Item -LiteralPath $target -Destination $dest -Force -ErrorAction Stop
                $manifest += @{ quar = $dest; original = $target }
                Write-Log 'quarantined' $id $target $p.bytes 'restorable'
                $freed += [int64]$p.bytes
            }
            else {
                Write-Log 'skipped' $id $target $p.bytes 'unknown-strategy'
            }
        } catch {
            Write-Log 'error' $id $target $p.bytes ([string]$_.Exception.Message)
        }
    }
}

# -- restore script: written on real runs (nothing was moved during a dry run,
#    so a dry-run restore script would be meaningless and misleading).
#    Manifest is embedded as one-line JSON in a single-quoted here-string and
#    parsed with ConvertFrom-Json: inlining raw JSON as PS source does not parse.
if (-not $DryRun) {
    $manifestJson = if ($manifest.Count) { ConvertTo-Json @($manifest) -Depth 4 -Compress } else { '[]' }
    $restoreBody = @"
# Auto-generated by win-clean execute engine. Moves quarantined items back to original paths.
`$movesJson = @'
$manifestJson
'@
foreach (`$m in @(ConvertFrom-Json `$movesJson)) {
    `$parent = Split-Path -Parent `$m.original
    if (-not (Test-Path `$parent)) { New-Item -ItemType Directory -Path `$parent -Force | Out-Null }
    Move-Item -LiteralPath `$m.quar -Destination `$m.original -Force
    Write-Output ("restored: " + `$m.original)
}
"@
    Set-Content -LiteralPath $restoreFile -Value $restoreBody -Encoding UTF8

    # -- purge quarantines older than 30 days (never during a dry run)
    if (Test-Path -LiteralPath $quarRoot) {
        Get-ChildItem -LiteralPath $quarRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

$drivesAfter = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
    ForEach-Object { [pscustomobject]@{ letter = $_.DeviceID; free = [uint64]$_.FreeSpace; total = [uint64]$_.Size } }

$summary = [pscustomobject]@{
    stamp = $stamp; dryRun = [bool]$DryRun
    freedBytes = $freed
    drivesBefore = @($drivesBefore); drivesAfter = @($drivesAfter)
    logFile = $logFile
    restoreFile = if ($DryRun) { $null } else { $restoreFile }
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $HistoryDir 'exec-summary.json') -Encoding UTF8
Write-Output ("EXECUTE OK: freed {0:N0} bytes (dryRun={1})" -f $freed, [bool]$DryRun)
exit 0
