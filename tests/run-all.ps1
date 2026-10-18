# Runs every PS test file; stops on first failure. Node test runs last if node exists.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$tests = @('test-validate-rules.ps1','test-scan.ps1','test-execute.ps1','test-serve.ps1','test-report-gen.ps1','test-learn-rule.ps1')
foreach ($t in $tests) {
    $p = Join-Path $PSScriptRoot $t
    if (Test-Path $p) {
        Write-Host "`n>>> $t" -ForegroundColor Yellow
        & powershell -NoProfile -ExecutionPolicy Bypass -File $p
        if ($LASTEXITCODE -ne 0) { Write-Host "SUITE ABORTED at $t" -ForegroundColor Red; exit 1 }
    }
}
$js = Join-Path $PSScriptRoot 'test-app.js'
if ((Test-Path $js) -and (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "`n>>> test-app.js" -ForegroundColor Yellow
    & node $js
    if ($LASTEXITCODE -ne 0) { Write-Host "SUITE ABORTED at test-app.js" -ForegroundColor Red; exit 1 }
}
Write-Host "`nALL TESTS PASSED" -ForegroundColor Green
