#Requires -Version 5.1
# Install or update runtime files without removing local history or learned rules.
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dst = Join-Path $env:USERPROFILE '.claude\skills\win-clean'
if (-not (Test-Path -LiteralPath (Join-Path $src 'SKILL.md'))) { throw 'SKILL.md not found' }
New-Item -ItemType Directory -Path $dst -Force | Out-Null
foreach ($name in @('SKILL.md', 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $src $name) -Destination (Join-Path $dst $name) -Force
}
foreach ($name in @('engine', 'tools', 'report', 'rules')) {
    $sourceDir = Join-Path $src $name
    $targetDir = Join-Path $dst $name
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceDir -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($sourceDir.Length).TrimStart('\')
        $target = Join-Path $targetDir $relative
        if ($name -eq 'rules' -and $relative -eq 'learned.json' -and (Test-Path -LiteralPath $target)) { return }
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}
Write-Output "INSTALLED: $dst (local logs and learned rules preserved)"
