# Tiny assert helpers. Dot-source from test files.
# ASCII-only by design (see Engineering Rules).
$script:__pass = 0
$script:__fail = 0

function Assert-Equal($Expected, $Actual, $Label) {
    if ("$Expected" -ne "$Actual") {
        $script:__fail++
        Write-Host "  FAIL ${Label}: expected [$Expected] actual [$Actual]" -ForegroundColor Red
        return
    }
    $script:__pass++
    Write-Host "  ok   ${Label}" -ForegroundColor Green
}

function Assert-True($Condition, $Label) {
    if (-not $Condition) {
        $script:__fail++
        Write-Host "  FAIL ${Label}: condition false" -ForegroundColor Red
        return
    }
    $script:__pass++
    Write-Host "  ok   ${Label}" -ForegroundColor Green
}

function Assert-FileContains([string]$Path, [string]$Needle, $Label) {
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    Assert-True ($content -match [regex]::Escape($Needle)) $Label
}

function Get-TestSummary([string]$Name) {
    Write-Host "=== ${Name}: $($script:__pass) passed, $($script:__fail) failed ===" -ForegroundColor Cyan
    if ($script:__fail -gt 0) { exit 1 }
    exit 0
}
