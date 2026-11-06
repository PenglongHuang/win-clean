#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string[]]$Roots,[Parameter(Mandatory=$true)][string]$OutFile,
 [string]$ProgressFile,[string]$CancelFile,[long]$MinBytes=100MB,[long]$CandidateMinBytes=1MB,[double]$BudgetSeconds=0,[int]$Top=60)
$ErrorActionPreference='Stop'
function Normalize-Path([string]$Path){$v=[IO.Path]::GetFullPath($Path).TrimEnd('\');if($v -match '^[A-Za-z]:$'){$v+='\'};return $v}
function Is-Within([string]$Child,[string]$Parent){return $Child.Equals($Parent,[StringComparison]::OrdinalIgnoreCase) -or $Child.StartsWith($Parent.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)}
function Save-Json($Value,$Path){$tmp=$Path+'.tmp';$Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $Path -Force}
$rootSet=New-Object 'System.Collections.Generic.List[string]'
foreach($r in @($Roots | ForEach-Object {$_ -split ','} | ForEach-Object {Normalize-Path $_} | Sort-Object Length)){
 if(-not @($rootSet | Where-Object {Is-Within $r $_}).Count){$rootSet.Add($r)}
}
$clock=[Diagnostics.Stopwatch]::StartNew();$queue=New-Object 'System.Collections.Generic.Queue[string]'
$totals=@{};$direct=@{};$parents=@{};$complete=@{};$containsProject=@{};$cachePaths=New-Object 'System.Collections.Generic.List[string]'
foreach($r in $rootSet){$queue.Enqueue($r);$totals[$r]=[long]0;$parents[$r]='';$complete[$r]=$false}
$large=New-Object 'System.Collections.Generic.List[object]';$partials=New-Object 'System.Collections.Generic.List[object]'
$bytes=[long]0;$files=0;$denied=0;$links=0;$reason='completed';$last=0
while($queue.Count -gt 0){
 if($CancelFile -and (Test-Path -LiteralPath $CancelFile)){$reason='cancelled';break}
 if($BudgetSeconds -gt 0 -and $clock.Elapsed.TotalSeconds -ge $BudgetSeconds){$reason='budget';break}
 $dir=$queue.Dequeue();$sum=[long]0;$interrupted=$false
 try{
  $item=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){$links++;continue}
  $entries=@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
 }catch{$denied++;continue}
 foreach($e in $entries){
  if(($files % 256) -eq 0){
   if($CancelFile -and (Test-Path -LiteralPath $CancelFile)){$reason='cancelled';$interrupted=$true;break}
   if($BudgetSeconds -gt 0 -and $clock.Elapsed.TotalSeconds -ge $BudgetSeconds){$reason='budget';$interrupted=$true;break}
  }
  if($e.Attributes -band [IO.FileAttributes]::ReparsePoint){$links++;continue}
  if($e.PSIsContainer){
   $child=Normalize-Path $e.FullName
   if($totals.ContainsKey($child)){continue}
   $queue.Enqueue($child);$parents[$child]=$dir;$totals[$child]=[long]0;$complete[$child]=$false
   $containsProject[$child]=($e.Name -in @('.git','node_modules','venv','.venv','.conda'))
   if($e.Name -in @('Cache','Caches','Code Cache','GPUCache','Cache_Data','.cache','npm-cache','.npm','.pnpm-store','__pycache__','.pytest_cache','云盘缓存') -and $child -notmatch '(?i)\\(\.git|node_modules|venv|\.venv|\.conda|\$RECYCLE\.BIN)(\\|$)'){$cachePaths.Add($child)}
   continue
  }
  $size=[long]$e.Length;$sum+=$size;$bytes+=$size;$files++
  if($size -ge $MinBytes){$large.Add([pscustomobject]@{path=$e.FullName;bytes=$size;modified=$e.LastWriteTime.ToString('o')})
   if($large.Count -gt ($Top*2)){$keep=@($large | Sort-Object bytes -Descending | Select-Object -First $Top);$large.Clear();foreach($k in $keep){$large.Add($k)}}
  }
  if($size -ge $CandidateMinBytes -and $e.Name -match '(?i)\.(xltd|crdownload|part)$' -and $dir -notmatch '(?i)\\(\.git|node_modules|venv|\.venv|\$RECYCLE\.BIN)(\\|$)'){
   $partials.Add([pscustomobject]@{path=$e.FullName;bytes=$size;kind='partial-download';complete=$true})
  }
 }
 $totals[$dir]=$sum;$direct[$dir]=$sum;$complete[$dir]=(-not $interrupted)
 if($ProgressFile -and ($clock.ElapsedMilliseconds-$last) -gt 500){
  Save-Json @{phase='discovery';currentName=$dir;files=$files;bytesSoFar=$bytes;elapsedSeconds=[int]$clock.Elapsed.TotalSeconds;pendingDirectories=$queue.Count} $ProgressFile
  $last=$clock.ElapsedMilliseconds
 }
 if($interrupted){break}
}
# Sum each subtree once, after enumeration; no per-file ancestor walk.
foreach($dir in @($totals.Keys | Sort-Object Length -Descending)){
 $parent=$parents[$dir]
 if($parent){$totals[$parent]+=$totals[$dir];if(-not $complete[$dir]){$complete[$parent]=$false};if($containsProject[$dir]){$containsProject[$parent]=$true}}
}
$directories=@($totals.Keys | Where-Object {$totals[$_] -ge $MinBytes -or $rootSet.Contains($_)} | ForEach-Object {
 [pscustomobject]@{path=$_;parent=$parents[$_];bytes=$totals[$_];directBytes=[long]$direct[$_];complete=[bool]$complete[$_]}
} | Sort-Object bytes -Descending)
$candidates=New-Object 'System.Collections.Generic.List[object]';$claimed=New-Object 'System.Collections.Generic.List[string]'
foreach($path in @($cachePaths | Sort-Object Length)){
 if($complete[$path] -and -not $containsProject[$path] -and $totals[$path] -ge $CandidateMinBytes -and -not @($claimed | Where-Object {Is-Within $path $_}).Count){
  $candidates.Add([pscustomobject]@{path=$path;bytes=$totals[$path];kind='cache';complete=$true});$claimed.Add($path)
 }
}
foreach($part in $partials){if(-not @($claimed | Where-Object {Is-Within $part.path $_}).Count){$candidates.Add($part)}}
Save-Json ([pscustomobject]@{scannedBytes=$bytes;files=$files;inaccessible=$denied;skippedLinks=$links;complete=($reason -eq 'completed' -and $denied -eq 0);reason=$reason;elapsedSeconds=[int]$clock.Elapsed.TotalSeconds;budgetSeconds=$BudgetSeconds;largeFiles=@($large | Sort-Object bytes -Descending | Select-Object -First $Top);directories=$directories;roots=@($rootSet);candidates=@($candidates | Sort-Object bytes -Descending)}) $OutFile
