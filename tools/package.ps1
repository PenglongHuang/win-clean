#Requires -Version 5.1
param([string]$Version='0.2.1-preview.3')
$ErrorActionPreference='Stop'
if($Version -notmatch '^[a-zA-Z0-9.\-]+$'){throw 'Invalid version'}
$root=Split-Path -Parent $PSScriptRoot
$dist=Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$archive=Join-Path $dist ("win-clean-$Version.zip")
if(Test-Path -LiteralPath $archive){throw 'Archive already exists; use another version'}
$stage=Join-Path $dist ("win-clean-$Version")
if(Test-Path -LiteralPath $stage){throw 'Staging directory already exists; use another version'}
New-Item -ItemType Directory -Path $stage | Out-Null
$names=@('Start-WinClean.cmd','Start-WinClean.ps1','README.md','SKILL.md','engine','report','rules','docs/advanced-workflow.md','docs/commercial-roadmap.md','tools/learn-rule.ps1','tools/validate-rules.ps1')
foreach($name in $names){
 $dest=Join-Path $stage $name
 New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
 Copy-Item -LiteralPath (Join-Path $root $name) -Destination $dest -Recurse
}
$paths=@(Get-ChildItem -LiteralPath $stage | ForEach-Object {$_.FullName})
Compress-Archive -LiteralPath $paths -DestinationPath $archive
Get-FileHash -LiteralPath $archive -Algorithm SHA256 | Format-List
Write-Output "PACKAGE: $archive"
