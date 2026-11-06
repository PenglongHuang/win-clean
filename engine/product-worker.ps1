#Requires -Version 5.1
param([string]$Task,[string]$Run,[string]$Drives,[string]$Mode='standard',[string]$Data)
$ErrorActionPreference='Stop'
try {
 $scan=Join-Path $Run 'scan-result.json';$cancel=Join-Path $Run 'cancel'
 switch($Task){
 'scan' {
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\scan.ps1" -Drives $Drives -LearnedFile "$Data\rules\learned.json" -OutFile $scan -ProgressFile "$Run\progress.json" -CancelFile $cancel
  if($LASTEXITCODE -ne 0){throw 'Rule scan failed'}
  if($Mode -eq 'deep' -and -not(Test-Path $cancel)){
   $roots=($Drives -split ',' | ForEach-Object {$_+':\'}) -join ','
   & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\discover.ps1" -Roots $roots -OutFile "$Run\discovery.json" -ProgressFile "$Run\progress.json" -CancelFile $cancel
   if($LASTEXITCODE -ne 0){throw 'Directory scan failed'}
   & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\merge-discovery.ps1" -ScanFile $scan -DiscoveryFile "$Run\discovery.json"
   if($LASTEXITCODE -ne 0){throw 'Discovery merge failed'}
  }
 }
 'dryrun' {
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\execute.ps1" -ScanFile $scan -SelectionsFile "$Run\selections.json" -HistoryDir "$Run\preview" -DryRun
  if($LASTEXITCODE -ne 0){throw 'Preview failed'}
 }
 'execute' {
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\execute.ps1" -ScanFile $scan -SelectionsFile "$Run\selections.json" -HistoryDir "$Run\execution"
  if($LASTEXITCODE -ne 0){throw 'Execution failed; inspect execution log'}
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\report-gen.ps1" -ScanFile $scan -ExecSummaryFile "$Run\execution\exec-summary.json" -SessionDir "$Run\execution" -HistoryRoot "$Data\history"
  if($LASTEXITCODE -ne 0){throw 'Report generation failed; execution log retained'}
 }
 default {throw 'Unknown task'}
 }
 @{ok=$true;task=$Task} | ConvertTo-Json | Set-Content -LiteralPath "$Run\worker-state.json" -Encoding UTF8
}catch{
 @{ok=$false;error=$_.Exception.Message;task=$Task} | ConvertTo-Json | Set-Content -LiteralPath "$Run\worker-state.json" -Encoding UTF8
 exit 1
}
