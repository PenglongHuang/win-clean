#Requires -Version 5.1
param([string]$DataDir=(Join-Path $env:LOCALAPPDATA 'win-clean'),[switch]$NoBrowser,[string]$InitialDrives,[string]$OpenRun)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\http.ps1"
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
$session=Join-Path (Join-Path $DataDir 'runs') ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $session -Force | Out-Null
$token=[guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start()
$port=([Net.IPEndPoint]$listener.LocalEndpoint).Port;$url="http://127.0.0.1:$port/"
@{url=$url;pid=$PID;session=$session} | ConvertTo-Json | Set-Content -LiteralPath "$session\product-info.json" -Encoding UTF8
Write-Output "WIN-CLEAN: $url"
Write-Output "SESSION: $session"
$phase='idle';$worker=$null;$run=$null;$errorText=$null;$activeTask=$null;$previewReady=$false;$previewId=$null;$selectionHash=$null
$disks=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {@{letter=$_.DeviceID.Substring(0,1);label=$_.VolumeName;total=[long]$_.Size;free=[long]$_.FreeSpace}})
function Read-Json($Path){if(Test-Path -LiteralPath $Path){try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json}catch{return $null}}}
if($OpenRun){
 $resolved=[IO.Path]::GetFullPath($OpenRun).TrimEnd('\')
 $allowed=[IO.Path]::GetFullPath((Join-Path $DataDir 'runs')).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Result run must be inside the local runs directory'}
 $previous=Read-Json "$resolved\worker-state.json"
 if(-not $previous.ok -or $previous.task -ne 'scan' -or -not (Test-Path -LiteralPath "$resolved\scan-result.json")){throw 'Only a completed scan can be reopened'}
 $run=$resolved;$phase='results'
}
function Start-Worker($Task,$Letters='',$Mode='standard'){
 foreach($v in @($PSScriptRoot,$run,$DataDir)){if($v.Contains('"')){throw 'Unsupported quote in path'}}
 $args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\product-worker.ps1" -Task '+$Task+' -Run "'+$run+'" -Data "'+$DataDir+'" -Mode '+$Mode
 if($Letters){$args+=' -Drives '+$Letters}
 # Old state must not be used by a subsequent task.
 @{ok=$false;pending=$true} | ConvertTo-Json | Set-Content -LiteralPath "$run\worker-state.json" -Encoding UTF8
 $script:activeTask=$Task
 $script:worker=Start-Process powershell -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput "$run\$Task.stdout.log" -RedirectStandardError "$run\$Task.stderr.log"
}
function Update-Worker {
 if($worker -and $worker.HasExited){
  $result=Read-Json "$run\worker-state.json"
  if(-not $result -or -not $result.ok){$script:phase='error';$script:errorText=if($result.error){$result.error}else{'后台任务未完成，请查看会话日志。'}}
  elseif($activeTask -eq 'scan'){$script:phase='results'}
  elseif($activeTask -eq 'dryrun'){$script:phase='preview';$script:previewReady=$true}
  else{$script:phase='done'}
  $script:worker=$null
 }
}
if(-not $NoBrowser){try{Start-Process $url}catch{Write-Warning "请在浏览器打开 $url"}}
$lastRequest=Get-Date
try {
 while($true){
  Update-Worker
  if(-not $listener.Pending()){
   if(-not $worker -and ((Get-Date)-$lastRequest).TotalMinutes -gt 30){break}
   Start-Sleep -Milliseconds 80;continue
  }
  $client=$listener.AcceptTcpClient();$client.ReceiveTimeout=3000;$client.SendTimeout=3000
  try {
   $stream=$client.GetStream();$req=Read-HttpRequest $stream
   if(-not $req){continue}
   if($req.Headers['host'] -ne ('127.0.0.1:'+ $port)){Send-HttpResponse $stream 'text/plain' 'Invalid host' 403;continue}
   $lastRequest=Get-Date
   if($req.Path -like '/api/*'){
    if($req.Headers['x-session-token'] -ne $token){Send-HttpResponse $stream 'application/json' '{"error":"unauthorized"}' 403;continue}
    if($req.Method -eq 'POST' -and $req.Headers['origin'] -ne $url.TrimEnd('/')){Send-HttpResponse $stream 'application/json' '{"error":"origin"}' 403;continue}
    Update-Worker
    $response=@{ok=$true}
    switch($req.Path){
     '/api/state' {
      if($req.Method -ne 'GET'){throw 'GET required'}
      $response=@{phase=$phase;disks=$disks;initialDrives=$InitialDrives;error=$errorText;run=$run}
      if($run){
       $response.progress=Read-Json "$run\progress.json"
       if($phase -in @('results','previewing','preview','executing','done')){
        $response.scan=Read-Json "$run\scan-result.json";$response.discovery=Read-Json "$run\discovery.json"
        $response.cancelled=Test-Path -LiteralPath "$run\cancel"
        $selection=Read-Json "$run\selections.json"
        $response.selectedIds=@($selection.ids)
       }
       if($phase -eq 'preview'){$response.summary=Read-Json "$run\preview\exec-summary.json";$response.previewId=$previewId}
       if($phase -eq 'done'){$response.summary=Read-Json "$run\execution\exec-summary.json"}
      }
     }
     '/api/scan' {
      if($req.Method -ne 'POST' -or $worker){throw 'Task already running'}
      $payload=$req.Body | ConvertFrom-Json
      $letters=@($payload.drives | Select-Object -Unique)
      if($letters.Count -eq 0){throw 'Choose a drive'}
      foreach($letter in $letters){if($letter -cnotmatch '^[A-Z]$' -or $letter -notin @($disks.letter)){throw 'Invalid drive'}}
      if($payload.mode -notin @('standard','deep')){throw 'Invalid mode'}
      $script:run=Join-Path $session ([guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $run | Out-Null
      $phase='scanning';$errorText=$null;$previewReady=$false
      Start-Worker 'scan' ($letters -join ',') $payload.mode
     }
     '/api/cancel' {
      if($req.Method -ne 'POST' -or $phase -ne 'scanning'){throw 'No scan running'}
      Set-Content -LiteralPath "$run\cancel" -Value 'cancel' -Encoding UTF8
     }
     '/api/preview' {
      if($req.Method -ne 'POST' -or $worker -or $phase -notin @('results','preview')){throw 'Scan first'}
      $payload=$req.Body | ConvertFrom-Json;$scan=Read-Json "$run\scan-result.json"
      $ids=@($payload.ids | Select-Object -Unique)
      if($ids.Count -eq 0){throw 'Choose an item'}
      foreach($id in $ids){if(-not @($scan.findings | Where-Object {$_.id -eq $id -and $_.strategy -in @('delete-permanent','recycle-bin')}).Count){throw 'Invalid selection'}}
      @{ids=$ids;scanHash=(Get-FileHash -LiteralPath "$run\scan-result.json" -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content -LiteralPath "$run\selections.json" -Encoding UTF8
      $previewId=[guid]::NewGuid().ToString('N')
      $selectionHash=(Get-FileHash -LiteralPath "$run\selections.json" -Algorithm SHA256).Hash
      $phase='previewing';$previewReady=$false;Start-Worker 'dryrun'
     }
     '/api/execute' {
      if($req.Method -ne 'POST' -or $worker -or $phase -ne 'preview' -or -not $previewReady){throw 'Preview required'}
      $payload=$req.Body | ConvertFrom-Json
      if($payload.previewId -ne $previewId -or (Get-FileHash -LiteralPath "$run\selections.json" -Algorithm SHA256).Hash -ne $selectionHash){throw 'Preview changed; review again'}
      $phase='executing';$previewReady=$false;Start-Worker 'execute'
     }
     default {Send-HttpResponse $stream 'application/json' '{"error":"not found"}' 404;continue}
    }
    Send-HttpResponse $stream 'application/json' ($response | ConvertTo-Json -Depth 12 -Compress)
   }elseif($req.Method -eq 'GET'){
    if($req.Path -eq '/favicon.ico'){Send-HttpResponse $stream 'text/plain' '' 204;continue}
    $assets=@{'/'=@('product.html','text/html');'/product.css'=@('product.css','text/css');'/product.js'=@('product.js','application/javascript');'/product-model.js'=@('product-model.js','application/javascript')}
    if($req.Path -eq '/final-report' -and $phase -eq 'done'){
     Send-HttpResponse $stream 'text/html' (Get-Content -LiteralPath "$run\execution\final-report.html" -Raw -Encoding UTF8)
    }elseif($assets.ContainsKey($req.Path)){
     $asset=$assets[$req.Path];$body=Get-Content -LiteralPath (Join-Path "$PSScriptRoot\..\report" $asset[0]) -Raw -Encoding UTF8
     if($req.Path -eq '/'){$body=$body.Replace('__SESSION_TOKEN__',$token)}
     Send-HttpResponse $stream $asset[1] $body
    }else{Send-HttpResponse $stream 'text/plain' 'Not found' 404}
   }else{Send-HttpResponse $stream 'text/plain' 'Method not allowed' 405}
  }catch{try{Send-HttpResponse $stream 'application/json' '{"error":"请求未完成，请检查当前任务状态或重新扫描。"}' 400}catch{}}
  finally{$client.Close()}
 }
}finally{$listener.Stop()}
