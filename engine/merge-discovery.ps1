#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ScanFile,[Parameter(Mandatory=$true)][string]$DiscoveryFile)
$ErrorActionPreference='Stop'
$scan=Get-Content -LiteralPath $ScanFile -Raw -Encoding UTF8 | ConvertFrom-Json
$discovery=Get-Content -LiteralPath $DiscoveryFile -Raw -Encoding UTF8 | ConvertFrom-Json
function Overlaps([string]$A,[string]$B){$a=$A.TrimEnd('\');$b=$B.TrimEnd('\');return $a.Equals($b,[StringComparison]::OrdinalIgnoreCase) -or $a.StartsWith($b+'\',[StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a+'\',[StringComparison]::OrdinalIgnoreCase)}
function Test-CacheTree([string]$Path){
 $pending=New-Object 'System.Collections.Generic.Stack[string]';$pending.Push($Path)
 try{
  while($pending.Count -gt 0){
   $dir=$pending.Pop();$item=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){return $false}
   foreach($child in [IO.Directory]::EnumerateDirectories($dir)){
    if([IO.Path]::GetFileName($child) -in @('.git','node_modules','venv','.venv','.conda')){return $false}
    $pending.Push($child)
   }
  }
 }catch{return $false}
 return $true
}
$findings=New-Object 'System.Collections.Generic.List[object]';$claimed=New-Object 'System.Collections.Generic.List[string]'
if($env:SystemRoot){$claimed.Add($env:SystemRoot)}
foreach($f in @($scan.findings)){
 if($f.source -eq 'discovery'){continue}
 $findings.Add($f)
 foreach($p in @($f.paths)){if($p.exists){$claimed.Add([string]$p.expanded)}}
}
$sha=[Security.Cryptography.SHA256]::Create()
try{
 foreach($c in @($discovery.candidates)){
  if(-not $c.complete -or $c.bytes -le 0 -or @($claimed | Where-Object {Overlaps $c.path $_}).Count){continue}
  if($c.kind -eq 'cache' -and -not (Test-CacheTree $c.path)){continue}
  $id='discovered-'+[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($c.path.ToLowerInvariant()))).Replace('-','').Substring(0,16).ToLowerInvariant()
  $name=if($c.kind -eq 'cache'){'发现的缓存目录：'+(Split-Path -Leaf $c.path)}else{'未完成下载：'+(Split-Path -Leaf $c.path)}
  $desc=if($c.kind -eq 'cache'){'根据目录名称识别，尚未经应用专属规则验证。请先退出所属应用并核对路径；移走后可能需要重新下载或生成缓存。'}else{'下载临时文件，可能仍在使用。先关闭或取消对应下载任务；移走会中断下载，恢复文件不保证恢复任务。'}
  $findings.Add([pscustomobject]@{id=$id;level=4;name=$name;type=$c.kind;strategy='recycle-bin';desc=$desc;auto_select=$false;source='discovery';bytes=[long]$c.bytes;needs_admin=$false;paths=@([pscustomobject]@{path=$c.path;expanded=$c.path;exists=$true;bytes=[long]$c.bytes})})
  $claimed.Add($c.path)
 }
}finally{$sha.Dispose()}
$scan.findings=$findings.ToArray();$scan.totalBytes=[long](($findings | Measure-Object bytes -Sum).Sum)
$scan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ScanFile -Encoding UTF8
