# Validates a rule library JSON against the schema in spec section 8.
param([Parameter(Mandatory=$true)][string]$RulesFile)
$ErrorActionPreference = 'Stop'

$required = @('id','level','name','paths','type','strategy','desc','auto_select','source')
$validTypes      = @('cache','temp','leftover','installer','log','dump','system')
$validStrategies = @('delete-permanent','recycle-bin','report-only')
$levelStrategy   = @{ 1='delete-permanent'; 2='delete-permanent'; 3='recycle-bin'; 4='recycle-bin'; 5='report-only' }

$errors = @()
try {
    # PS 5.1: ConvertFrom-Json emits a JSON array as ONE pipeline object, so
    # unwrap first, then let @() enumerate (avoids the nested-array trap).
    $json = Get-Content -LiteralPath $RulesFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $rules = @($json)
} catch {
    Write-Output "PARSE ERROR: $($_.Exception.Message)"
    exit 1
}
$seen = @{}
foreach ($r in $rules) {
    foreach ($f in $required) {
        if (-not $r.PSObject.Properties[$f]) { $errors += "$($r.id): missing field '$f'" }
    }
    if ($r.PSObject.Properties['level'] -and ($r.level -notin 1..5)) { $errors += "$($r.id): level must be 1-5, got $($r.level)" }
    if ($r.PSObject.Properties['type'] -and ($validTypes -notcontains $r.type)) { $errors += "$($r.id): bad type '$($r.type)'" }
    if ($r.PSObject.Properties['strategy'] -and ($validStrategies -notcontains $r.strategy)) { $errors += "$($r.id): bad strategy '$($r.strategy)'" }
    if ($r.PSObject.Properties['level'] -and $r.PSObject.Properties['strategy'] -and $r.strategy -ne 'report-only' -and $levelStrategy[[int]$r.level] -ne $r.strategy) {
        $errors += "$($r.id): level $($r.level) must use strategy '$($levelStrategy[[int]$r.level])', got '$($r.strategy)'"
    }
    if ($r.PSObject.Properties['paths'] -and @($r.paths).Count -eq 0) { $errors += "$($r.id): paths empty" }
    if ($r.PSObject.Properties['id']) {
        if ($seen.ContainsKey($r.id)) { $errors += "$($r.id): duplicate id" }
        $seen[$r.id] = $true
    }
}
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Output "RULE ERROR: $_" }
    exit 1
}
Write-Output "OK: $($rules.Count) rules valid"
exit 0
