#Requires -Version 5.1
# Deterministic rule scan. READ-ONLY: never deletes anything.
param(
    [string]$RulesDir = (Join-Path $PSScriptRoot '..\rules'),
    [string]$OutFile  = (Join-Path (Get-Location) 'scan-result.json'),
    [string[]]$OnlyIds,
    [string]$Drives,
    [string]$ProgressFile
)
$ErrorActionPreference = 'Stop'

# PS 5.1 quirk: via `powershell -File`, a comma-separated -OnlyIds a,b,c binds as ONE
# string (no expression parsing). Normalize: split every element on ',' and trim.
if ($OnlyIds) {
    $OnlyIds = @($OnlyIds | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# -Drives: comma-separated letters (e.g. "C,D"). Normalize to an uppercase letter set.
# Empty/absent, or no valid tokens at all -> no filter (scan every drive).
$driveSet = $null
if ($Drives) {
    $letters = @($Drives -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() } |
        Where-Object { $_ -match '^[A-Z]$' } | Select-Object -Unique)
    if ($letters.Count -gt 0) {
        $driveSet = @{}
        foreach ($l in $letters) { $driveSet[$l] = $true }
    } else {
        Write-Output ("WARN: -Drives '{0}' has no valid drive letters, scanning all drives" -f $Drives)
    }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Expand-RulePath([string]$Path) {
    if ($Path -match '^%(\w+)%(.*)$') {
        $val = [Environment]::GetEnvironmentVariable($Matches[1])
        if (-not $val) { return $null }
        return $val + $Matches[2]
    }
    return $Path
}

function Get-PathBytes([string]$Path) {
    # Returns byte count, 0 for reparse points, -1 when path does not exist / inaccessible.
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return -1 }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return 0 }
    if (-not $item.PSIsContainer) { return [int64]$item.Length }
    $sum = [int64]0
    foreach ($f in (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue)) {
        if (-not $f.PSIsContainer -and -not ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $sum += $f.Length
        }
    }
    return $sum
}

# -- merge rule libraries (learned wins on same id). PS 5.1: two-step unwrap.
$builtinJson = Get-Content -LiteralPath (Join-Path $RulesDir 'builtin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$builtin = @($builtinJson)
$learnedFile = Join-Path $RulesDir 'learned.json'
$learned = @()
if (Test-Path $learnedFile) {
    $learnedJson = Get-Content -LiteralPath $learnedFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $learned = @($learnedJson)
}
$byId = [ordered]@{}
foreach ($r in $builtin) { $byId[$r.id] = $r }
foreach ($r in $learned) { $byId[$r.id] = $r }
$rules = @($byId.Values)
if ($OnlyIds) { $rules = @($rules | Where-Object { $OnlyIds -contains $_.id }) }

$isAdmin = Test-IsAdmin

# -ProgressFile: one small JSON heartbeat per evaluated rule (last write wins).
$ruleTotal = $rules.Count
$doneCount = 0
$bytesSoFar = [int64]0
if ($ProgressFile) {
    $pdir = Split-Path -Parent $ProgressFile
    if ($pdir -and -not (Test-Path -LiteralPath $pdir)) { New-Item -ItemType Directory -Path $pdir -Force | Out-Null }
}
$findings = @()
foreach ($r in $rules) {
    $needsAdmin = @($r.guard) -contains 'admin-required'
    $pathResults = @()
    $total = [int64]0
    $anyExists = $false
    foreach ($p in @($r.paths)) {
        $expanded = Expand-RulePath $p
        if ($driveSet) {
            # Drive filter active: keep only drive-letter paths (X:\...) whose letter is selected.
            if (-not $expanded -or $expanded -notmatch '^[A-Za-z]:') { continue }
            if (-not $driveSet.ContainsKey($expanded.Substring(0,1).ToUpperInvariant())) { continue }
        }
        if (-not $expanded) { $pathResults += @{ path = $p; expanded = $null; exists = $false; bytes = 0 }; continue }
        $bytes = Get-PathBytes $expanded
        $exists = ($bytes -ge 0)
        if ($exists) { $anyExists = $true; $total += $bytes }
        $pathResults += @{ path = $p; expanded = $expanded; exists = $exists; bytes = [int64][Math]::Max($bytes, 0) }
    }
    $doneCount++
    if ($anyExists) {
        $findings += [pscustomobject]@{
            id = $r.id; level = [int]$r.level; name = $r.name; type = $r.type
            strategy = $r.strategy; desc = $r.desc; auto_select = [bool]$r.auto_select
            source = $r.source; bytes = $total; needs_admin = $needsAdmin
            paths = $pathResults
        }
        $bytesSoFar += $total
    }
    if ($ProgressFile) {
        [pscustomobject]@{ done = $doneCount; total = $ruleTotal; currentId = [string]$r.id; currentName = [string]$r.name; bytesSoFar = $bytesSoFar } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $ProgressFile -Encoding UTF8
    }
}
if ($ProgressFile) {
    [pscustomobject]@{ done = $doneCount; total = $ruleTotal; currentId = ''; currentName = ''; bytesSoFar = $bytesSoFar } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $ProgressFile -Encoding UTF8
}

# Named $driveList, NOT $drives: PS 5.1 keeps the [string] constraint of the $Drives
# parameter on the same (case-insensitive) variable, which would coerce this array to a string.
$driveList = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{ letter = $_.DeviceID; total = [uint64]$_.Size; free = [uint64]$_.FreeSpace }
})
if ($driveSet) {
    $driveList = @($driveList | Where-Object { $_.letter -match '^[A-Za-z]:' -and $driveSet.ContainsKey($_.letter.Substring(0,1).ToUpperInvariant()) })
}

# Stable schema: totalBytes must always be a number, never null/absent.
$totalBytes = ($findings | Measure-Object -Property bytes -Sum).Sum
if (-not $totalBytes) { $totalBytes = [int64]0 }

$result = [pscustomobject]@{
    timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    host      = $env:COMPUTERNAME
    drives    = $driveList
    findings  = $findings
    totalBytes = $totalBytes
    isAdmin   = $isAdmin
}
$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Output ("SCAN OK: {0} findings, {1:N0} bytes" -f $findings.Count, $totalBytes)
exit 0
