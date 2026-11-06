$ErrorActionPreference='Stop'
. "$PSScriptRoot\assert.ps1"
$fx=Join-Path $env:TEMP ('wc-discover-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fx\nested" -Force | Out-Null
[IO.File]::WriteAllBytes("$fx\nested\large.bin", (New-Object byte[] 8192))
$out="$fx\result.json"
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\..\engine\discover.ps1" -Roots "$fx\nested" -OutFile $out -MinBytes 1024 -BudgetSeconds 10
Assert-Equal 0 $LASTEXITCODE 'discovery exits successfully'
if(Test-Path $out){
 $d=Get-Content $out -Raw | ConvertFrom-Json
 Assert-Equal 8192 $d.scannedBytes 'counts bytes once'
 Assert-Equal 1 $d.files 'counts files'
 Assert-True (@($d.largeFiles).Count -eq 1) 'finds large file'
 Assert-True (@($d.directories).Count -ge 1) 'finds directory'
 Assert-True $d.complete 'completed traversal'
}
$cancel="$fx\cancel"
Set-Content $cancel 'cancel'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\..\engine\discover.ps1" -Roots "$fx\nested" -OutFile "$fx\cancelled.json" -CancelFile $cancel
if(Test-Path "$fx\cancelled.json"){
 $d=Get-Content "$fx\cancelled.json" -Raw | ConvertFrom-Json
 Assert-True (-not $d.complete) 'cancel marked incomplete'
 Assert-Equal 'cancelled' $d.reason 'cancel reason'
}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\..\engine\discover.ps1" -Roots "$fx\nested" -OutFile "$fx\budget.json" -BudgetSeconds 0.00001
$d=Get-Content "$fx\budget.json" -Raw | ConvertFrom-Json
Assert-Equal 'budget' $d.reason 'budget termination explicit'
Assert-True (-not $d.complete) 'budget result incomplete'
New-Item -ItemType Junction -Path "$fx\nested\loop" -Target "$fx\nested" | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\..\engine\discover.ps1" -Roots "$fx\nested" -OutFile "$fx\junction.json" -MinBytes 1024
$d=Get-Content "$fx\junction.json" -Raw | ConvertFrom-Json
Assert-Equal 8192 $d.scannedBytes 'junction not traversed'
Assert-Equal 1 $d.skippedLinks 'junction reported'
Get-TestSummary 'discovery'
