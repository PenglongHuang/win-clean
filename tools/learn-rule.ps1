#Requires -Version 5.1
# Appends a Claude-exploration discovery to learned.json (user must have approved it first).
param(
    [Parameter(Mandatory=$true)][string]$RulesDir,
    [string]$LearnedFile,
    [Parameter(Mandatory=$true)][string]$Id,
    [Parameter(Mandatory=$true)][ValidateRange(1,5)][int]$Level,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string[]]$Paths,
    [Parameter(Mandatory=$true)][ValidateSet('cache','temp','leftover','installer','log','dump','system')][string]$Type,
    [Parameter(Mandatory=$true)][string]$Desc,
    [string]$AutoSelect = 'false'
)
$ErrorActionPreference = 'Stop'
$levelStrategy = @{ 1='delete-permanent'; 2='delete-permanent'; 3='recycle-bin'; 4='recycle-bin'; 5='report-only' }

# powershell -File binds '-Paths a,b' as ONE string (same trap as scan.ps1 -OnlyIds);
# the [string[]] param then holds a single comma-joined element, so split every element.
$Paths = @($Paths | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# powershell -File cannot convert string args to [bool]/[switch], so AutoSelect is a string here;
# coerce 'true'/'1' (or a real $true from in-session callers) to boolean.
# NOTE: name it $autoSel -- $autoSelect would case-insensitively collide with $AutoSelect.
$autoSel = ([string]$AutoSelect) -ieq 'true' -or ([string]$AutoSelect) -eq '1' -or ($AutoSelect -eq $true)

$learnedPath = if ($LearnedFile) { $LearnedFile } else { Join-Path $RulesDir 'learned.json' }
$learnedParent = Split-Path -Parent $learnedPath
if (-not (Test-Path -LiteralPath $learnedParent)) { New-Item -ItemType Directory -Path $learnedParent -Force | Out-Null }
$learned = @()
if (Test-Path $learnedPath) {
    # PS 5.1: ConvertFrom-Json emits a JSON array as ONE pipeline object; two-step unwrap
    # (assign, then @()) or @() inline collapses multi-element arrays. Same for builtin below.
    $learnedJson = Get-Content -LiteralPath $learnedPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $learned = @($learnedJson)
}
foreach ($r in $learned) { if ($r.id -eq $Id) { Write-Output "ERROR: id '$Id' already in learned.json"; exit 1 } }
$builtinJson = Get-Content -LiteralPath (Join-Path $RulesDir 'builtin.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$builtin = @($builtinJson)
foreach ($r in $builtin) { if ($r.id -eq $Id) { Write-Output "ERROR: id '$Id' collides with builtin (overriding builtin means editing builtin.json, not learning)"; exit 1 } }

$rule = [pscustomobject]@{
    id = $Id; level = $Level; name = $Name; paths = @($Paths); type = $Type
    strategy = $levelStrategy[$Level]; desc = $Desc; guard = @()
    auto_select = [bool]$autoSel; source = 'learned'
    discovered = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
}
$learned += $rule
$learned | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $learnedPath -Encoding UTF8
Write-Output "LEARNED: $Id appended to $learnedPath"
exit 0
