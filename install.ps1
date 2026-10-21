# Deploys the skill to %USERPROFILE%\.claude\skills\win-clean (dev artifacts excluded).
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
if (-not (Test-Path (Join-Path $src 'SKILL.md'))) {
    Write-Output 'ERROR: run this from the win-clean repo root (SKILL.md not found)'
    exit 1
}
$dst = Join-Path $env:USERPROFILE '.claude\skills\win-clean'
if (Test-Path $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
New-Item -ItemType Directory -Path $dst -Force | Out-Null
$keep = @('SKILL.md','README.md','engine','tools','rules','report')
foreach ($k in $keep) {
    Copy-Item -LiteralPath (Join-Path $src $k) -Destination $dst -Recurse -Force
}
Write-Output "INSTALLED: $dst (excluded: tests/, docs/, logs/, .git/)"
