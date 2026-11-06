$ErrorActionPreference='Stop'
. "$PSScriptRoot\assert.ps1"
$fx=Join-Path $PSScriptRoot ('product-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fx\data\rules" -Force | Out-Null
$target="$fx\cache.bin"
[IO.File]::WriteAllBytes($target,(New-Object byte[] 2048))
$rulesJson=Get-Content "$PSScriptRoot\..\rules\builtin.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$rules=@($rulesJson)
foreach($r in $rules){$r.paths=@("$fx\absent")}
$rules+= [pscustomobject]@{id='fixture';level=1;name='Fixture';paths=@($target);type='cache';strategy='delete-permanent';desc='Test';guard=@();auto_select=$false;source='learned'}
$rules | ConvertTo-Json -Depth 6 | Set-Content "$fx\data\rules\learned.json" -Encoding UTF8
$scriptPath=(Resolve-Path "$PSScriptRoot\..\engine\product-server.ps1").Path
$proc=Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'" -NoBrowser -DataDir "'+$fx+'\data"') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$fx\stdout.log" -RedirectStandardError "$fx\stderr.log"
try{
 $deadline=(Get-Date).AddSeconds(20);$info=$null
 do{Start-Sleep -Milliseconds 200;$info=Get-ChildItem "$fx\data" -Filter product-info.json -Recurse | Select-Object -First 1}while(-not $info -and (Get-Date)-lt $deadline)
 if(-not $info){throw (Get-Content "$fx\stderr.log" -Raw)}
 $url=(Get-Content $info.FullName -Raw | ConvertFrom-Json).url
 $html=(Invoke-WebRequest -UseBasicParsing $url).Content
 $token=[regex]::Match($html,'SESSION_TOKEN="([a-f0-9]+)"').Groups[1].Value
 $headers=@{'X-Session-Token'=$token;Origin=$url.TrimEnd('/')}
 function Api($Path,$Body){
  if($null -eq $Body){return Invoke-RestMethod ($url+'api/'+$Path) -Headers $headers}
  Invoke-RestMethod ($url+'api/'+$Path) -Method Post -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Compress)
 }
 function Wait-Phase($Expected){
  $end=(Get-Date).AddSeconds(40)
  do{Start-Sleep -Milliseconds 200;$s=Api 'state' $null;if($s.phase -eq 'error'){throw ($s.error+' run='+$s.run)}}while($s.phase -ne $Expected -and (Get-Date)-lt $end)
  Assert-Equal $Expected $s.phase ('phase '+$Expected)
  return $s
 }
 Assert-Equal 64 $token.Length 'session token present'
 $hostRequest=[Net.HttpWebRequest]::Create($url)
 $hostRequest.Host='attacker.invalid'
 try{$hostRequest.GetResponse().Close();$reject=$false}catch{$reject=$true}
 Assert-True $reject 'foreign host rejected before token disclosure'
 try{Invoke-RestMethod ($url+'api/state') | Out-Null;$reject=$false}catch{$reject=$true}
 Assert-True $reject 'unauthenticated request rejected'
 try{Api 'scan' @{drives=@('INVALID');mode='standard'} | Out-Null;$reject=$false}catch{$reject=$true}
 Assert-True $reject 'invalid drive rejected'
 try{Api 'execute' @{} | Out-Null;$reject=$false}catch{$reject=$true}
 Assert-True $reject 'execute requires preview'
 $letter=[IO.Path]::GetPathRoot($fx).Substring(0,1)
 Api 'scan' @{drives=@($letter);mode='standard'} | Out-Null
 $s=Wait-Phase 'results'
 Assert-Equal 1 @($s.scan.findings).Count 'fixture-only scan'
 Assert-True (Test-Path $target) 'scan never deletes'
 Api 'preview' @{ids=@('fixture')} | Out-Null
 $s=Wait-Phase 'preview'
 Assert-True (Test-Path $target) 'preview never deletes'
 Assert-Equal 2048 $s.summary.freedBytes 'preview estimate'
 $oldPreview=$s.previewId
 Api 'preview' @{ids=@('fixture')} | Out-Null
 $s=Wait-Phase 'preview'
 Assert-True ($s.previewId -ne $oldPreview) 'new preview invalidates old confirmation'
 try{Api 'execute' @{previewId=$oldPreview} | Out-Null;$reject=$false}catch{$reject=$true}
 Assert-True $reject 'another tab cannot execute a replaced preview'
 try{Api 'execute' @{previewId='stale'} | Out-Null;$reject=$false}catch{$reject=$true}
 Assert-True $reject 'stale confirmation rejected'
 Api 'execute' @{previewId=$s.previewId} | Out-Null
 $s=Wait-Phase 'done'
 Assert-True (-not(Test-Path $target)) 'confirmed execution deletes fixture only'
 Assert-Equal 2048 $s.summary.freedBytes 'execution result'
 Assert-True ((Invoke-WebRequest -UseBasicParsing ($url+'final-report')).StatusCode -eq 200) 'final report served'
}finally{if(-not $proc.HasExited){Stop-Process -Id $proc.Id};Write-Host "Fixture logs: $fx"}
Get-TestSummary 'product-server'
