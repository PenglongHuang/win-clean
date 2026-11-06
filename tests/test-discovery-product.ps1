$ErrorActionPreference='Stop'
. "$PSScriptRoot\assert.ps1"
$fx=Join-Path $env:TEMP ('wc-depth-'+[guid]::NewGuid().ToString('N'))
foreach($dir in @('app\Cache\Cache_Data','docs','downloads','project\.git\Cache')){New-Item -ItemType Directory -Path (Join-Path $fx $dir) -Force | Out-Null}
foreach($name in @('app\Cache\Cache_Data\one.bin','docs\personal.mp4','downloads\pending.xltd','downloads\keep.mp4','project\.git\Cache\keep.bin')){[IO.File]::WriteAllBytes((Join-Path $fx $name),(New-Object byte[] 4096))}
$engine="$PSScriptRoot\..\engine"
& powershell -NoProfile -ExecutionPolicy Bypass -File "$engine\discover.ps1" -Roots "$fx,$fx\app" -OutFile "$fx\result.json" -MinBytes 1024 -CandidateMinBytes 1024
Assert-Equal 0 $LASTEXITCODE 'product discovery succeeds'
if(Test-Path "$fx\result.json"){
 $d=Get-Content "$fx\result.json" -Raw -Encoding UTF8 | ConvertFrom-Json
 Assert-Equal 20480 $d.scannedBytes 'overlapping roots scanned once'
 Assert-Equal 1 @($d.roots).Count 'nested root removed'
 Assert-Equal 2 @($d.candidates).Count 'cache and partial download discovered'
 $cache=@($d.candidates | Where-Object {$_.kind -eq 'cache'})
 Assert-Equal 1 $cache.Count 'nested caches collapsed'
 Assert-Equal 4096 $cache[0].bytes 'cache bytes counted once'
 Assert-True ($cache[0].path -eq "$fx\app\Cache") 'outer cache selected'
 Assert-True (-not @($d.candidates | Where-Object {$_.path -match '\.git|personal|keep.mp4'}).Count) 'personal and git data not cleanup candidates'
 Assert-True (@($d.directories | Where-Object {$_.parent -eq $fx}).Count -eq 4) 'directory hierarchy keeps sibling partitions'
 $scan=@{findings=@();totalBytes=0;drives=@();isAdmin=$false}
 $scan | ConvertTo-Json | Set-Content "$fx\scan.json" -Encoding UTF8
 & powershell -NoProfile -ExecutionPolicy Bypass -File "$engine\merge-discovery.ps1" -ScanFile "$fx\scan.json" -DiscoveryFile "$fx\result.json"
 Assert-Equal 0 $LASTEXITCODE 'merge succeeds'
 $s=Get-Content "$fx\scan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
 Assert-Equal 2 @($s.findings).Count 'deep discoveries enter cleanup list'
 Assert-Equal 8192 $s.totalBytes 'unique cleanup candidate total'
 Assert-True (-not @($s.findings | Where-Object {$_.level -ne 4 -or $_.auto_select -or $_.strategy -ne 'recycle-bin'}).Count) 'discovered candidates require manual review'
 & powershell -NoProfile -ExecutionPolicy Bypass -File "$engine\merge-discovery.ps1" -ScanFile "$fx\scan.json" -DiscoveryFile "$fx\result.json"
 $s=Get-Content "$fx\scan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
 Assert-Equal 8192 $s.totalBytes 'repeated merge does not duplicate'
}
New-Item -ItemType Directory -Path "$fx\mixed\Cache\.git\objects" -Force | Out-Null
[IO.File]::WriteAllBytes("$fx\mixed\Cache\.git\objects\keep",(New-Object byte[] 4096))
& powershell -NoProfile -ExecutionPolicy Bypass -File "$engine\discover.ps1" -Roots "$fx\mixed" -OutFile "$fx\mixed-result.json" -MinBytes 1024 -CandidateMinBytes 1024
$mixed=Get-Content "$fx\mixed-result.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 0 @($mixed.candidates).Count 'cache containing project data is not actionable'
$unsafe=@{candidates=@(@{path="$fx\mixed\Cache";bytes=4096;kind='cache';complete=$true})}
$unsafe | ConvertTo-Json -Depth 5 | Set-Content "$fx\unsafe.json" -Encoding UTF8
@{findings=@();totalBytes=0} | ConvertTo-Json | Set-Content "$fx\unsafe-scan.json" -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File "$engine\merge-discovery.ps1" -ScanFile "$fx\unsafe-scan.json" -DiscoveryFile "$fx\unsafe.json"
$unsafeScan=Get-Content "$fx\unsafe-scan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 0 @($unsafeScan.findings).Count 'merge rejects project data even in older snapshot'
$blocked=@{findings=@(@{id='system';source='builtin';bytes=4096;strategy='report-only';paths=@(@{expanded="$fx\app";exists=$true;bytes=4096})});totalBytes=4096}
$blocked | ConvertTo-Json -Depth 6 | Set-Content "$fx\blocked-scan.json" -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File "$engine\merge-discovery.ps1" -ScanFile "$fx\blocked-scan.json" -DiscoveryFile "$fx\result.json"
$blocked=Get-Content "$fx\blocked-scan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True (-not @($blocked.findings | Where-Object {$_.source -eq 'discovery' -and $_.paths[0].expanded -like "$fx\app\*"}).Count) 'report-only subtree cannot become actionable'
Get-TestSummary 'discovery-product'
