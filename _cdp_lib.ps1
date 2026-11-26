# CDP harness library (ASCII only). Caller must set: $port, $ud, $url, $outdir
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $outdir | Out-Null

$edge="${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if(-not (Test-Path $edge)){ $edge="${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe" }

# 前回実行で取り残したヘッドレスEdge(this profile)だけを掃除する
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*ct_cdp_udata*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1
Remove-Item -Recurse -Force $ud -ErrorAction SilentlyContinue

$bp=Start-Process -FilePath $edge -ArgumentList @('--headless=new',"--remote-debugging-port=$port","--user-data-dir=$ud",'--enable-unsafe-swiftshader','--disable-dev-shm-usage','--remote-allow-origins=*','--mute-audio',"--window-size=$win",$url) -PassThru
Start-Sleep -Seconds 2
$target=$null
for($i=0;$i -lt 40;$i++){
  try{
    $list=Invoke-RestMethod "http://127.0.0.1:$port/json/list"
    $page=$list | Where-Object { $_.type -eq 'page' -and $_.url -like 'file://*' -and $_.webSocketDebuggerUrl } | Select-Object -First 1
    if($page){ $target=$page; break }
  }catch{}
  Start-Sleep -Milliseconds 500
}
if(-not $target){ Write-Host 'FAIL: no CDP page target'; Stop-Process -Id $bp.Id -Force -ErrorAction SilentlyContinue; exit 1 }

$ws=[System.Net.WebSockets.ClientWebSocket]::new()
$ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl,[Threading.CancellationToken]::None).Wait()
$script:msgId=0; $script:pending=$null; $script:acc=''; $script:results=@{}; $script:errs=@()

function Send-Msg($method,$params){
  $o=[ordered]@{id=(++$script:msgId);method=$method}
  if($null -ne $params){ $o.params=$params }
  $json=$o | ConvertTo-Json -Compress -Depth 8
  $bytes=[Text.Encoding]::UTF8.GetBytes($json)
  $ws.SendAsync([ArraySegment[byte]]::new($bytes),[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).Wait()
  return $script:msgId
}
function Handle-Event($obj){
  if($null -eq $obj){ return }
  if($obj.method -eq 'Runtime.exceptionThrown'){
    $d=$obj.params.exceptionDetails; $desc=''
    if($d.exception){ $desc=$d.exception.description }
    $script:errs += ('EXC: ' + $d.text + ' | ' + $desc + ' | line:' + $d.lineNumber)
  } elseif($obj.method -eq 'Runtime.consoleAPICalled' -and ($obj.params.type -eq 'error')){
    $a=($obj.params.args | ForEach-Object { if($_.description){$_.description}else{$_.value} }) -join ' '
    $script:errs += ('CONSOLE.error: ' + $a)
  } elseif($obj.method -eq 'Log.entryAdded' -and $obj.params.entry.level -eq 'error'){
    $script:errs += ('LOG: ' + $obj.params.entry.text + ' | ' + $obj.params.entry.url)
  }
  if($obj.id){ $script:results[[int]$obj.id]=$obj }
  if($obj.error){ $script:errs += ('CDPERR id='+$obj.id+' '+$obj.error.message) }
}
function Pump($ms){
  $deadline=(Get-Date).AddMilliseconds($ms)
  while($true){
    $rem=[int]($deadline-(Get-Date)).TotalMilliseconds
    if($rem -le 0){ return }
    if($null -eq $script:pending){
      $buf=New-Object byte[] 262144
      $script:pending=@{task=$ws.ReceiveAsync([ArraySegment[byte]]::new($buf),[Threading.CancellationToken]::None);buf=$buf}
    }
    if($script:pending.task.Wait($rem)){
      $res=$script:pending.task.Result
      $script:acc += [Text.Encoding]::UTF8.GetString($script:pending.buf,0,$res.Count)
      if($res.EndOfMessage){
        $txt=$script:acc; $script:acc=''
        $obj=$null; try{ $obj=$txt | ConvertFrom-Json }catch{}
        Handle-Event $obj; $script:pending=$null
      } else {
        $buf2=New-Object byte[] 262144
        $script:pending=@{task=$ws.ReceiveAsync([ArraySegment[byte]]::new($buf2),[Threading.CancellationToken]::None);buf=$buf2}
      }
    } else { return }
  }
}
function Eval($expr){
  $id=Send-Msg 'Runtime.evaluate' ([ordered]@{expression=$expr;returnByValue=$true})
  $deadline=(Get-Date).AddSeconds(20)
  while(-not $script:results.ContainsKey($id) -and (Get-Date) -lt $deadline){ Pump 300 }
  if(-not $script:results.ContainsKey($id)){ return '<timeout>' }
  $r=$script:results[$id].result
  if($r.exceptionDetails){ return 'EVALERR: ' + $r.exceptionDetails.exception.description }
  return $r.result.value
}
function Click-XY($x,$y){
  Send-Msg 'Input.dispatchMouseEvent' ([ordered]@{type='mouseMoved';x=[double]$x;y=[double]$y;button='none'}) | Out-Null
  Pump 100
  Send-Msg 'Input.dispatchMouseEvent' ([ordered]@{type='mousePressed';x=[double]$x;y=[double]$y;button='left';buttons=1;clickCount=1}) | Out-Null
  Pump 120
  Send-Msg 'Input.dispatchMouseEvent' ([ordered]@{type='mouseReleased';x=[double]$x;y=[double]$y;button='left';buttons=0;clickCount=1}) | Out-Null
  Pump 350
}
function Click-El($sel){
  $js='(()=>{const e=document.querySelector(`' + $sel + '`); if(!e) return "NOEL"; const r=e.getBoundingClientRect(); if(r.width<1) return "HIDDEN"; return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()'
  $v=Eval $js
  if($v -isnot [string] -or $v -eq 'NOEL' -or $v -eq 'HIDDEN' -or ($v -like 'EVALERR*')){ Write-Host ("CLICKFAIL " + $sel + " -> " + $v); return }
  $o=$v | ConvertFrom-Json; Click-XY $o.x $o.y
}
function Shot($name){
  $path=Join-Path $outdir $name
  $id=Send-Msg 'Page.captureScreenshot' ([ordered]@{format='png'})
  $dl=(Get-Date).AddSeconds(12)
  while(-not $script:results.ContainsKey($id) -and (Get-Date) -lt $dl){ Pump 300 }
  if($script:results.ContainsKey($id)){ [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($script:results[$id].result.data)); Write-Host ("SHOT " + $name) }
  else { Write-Host ("SHOT TIMEOUT " + $name) }
}
function Set-Viewport($w,$h,$mobile){
  Send-Msg 'Emulation.setDeviceMetricsOverride' ([ordered]@{width=$w;height=$h;deviceScaleFactor=1;mobile=$mobile}) | Out-Null
  Pump 900
}
function Clear-Viewport($w,$h){
  Send-Msg 'Emulation.clearDeviceMetricsOverride' $null | Out-Null
  Pump 700
}
function Report-Errors{
  Write-Host '--- ERRORS ---'
  if($script:errs.Count -eq 0){ Write-Host 'none' } else { $script:errs | Select-Object -First 25 | ForEach-Object { Write-Host $_ } }
}
function Close-Browser{ Stop-Process -Id $bp.Id -Force -ErrorAction SilentlyContinue }
Send-Msg 'Runtime.enable' $null | Out-Null
Send-Msg 'Log.enable' $null | Out-Null
Send-Msg 'Page.enable' $null | Out-Null
Pump 9000
