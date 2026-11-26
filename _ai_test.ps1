# CUBETRIO 3D — playability test: greedy bot plays every level (run via Invoke-Expression)
$stamp=Get-Date -Format 'HHmmss'
$script:port=9600 + (Get-Random -Minimum 0 -Maximum 50)
$script:ud="$env:TEMP\ct_cdp_udata_$stamp"
$script:win="1024,640"
$html=Resolve-Path "cubetrio-3d\index.html"
$script:url="file:///" + $html.Path.Replace('\','/') + "?a=" + $stamp
$script:outdir=Join-Path (Split-Path $html.Path) "shots"
Invoke-Expression ([IO.File]::ReadAllText((Join-Path (Split-Path $html.Path) "_cdp_lib.ps1")))

Write-Host ("ready=" + (Eval 'String(!!window.__CUBETRIO_READY__)') + " errs=" + $script:errs.Count)
$pass=0
foreach($lv in 1..12){
  Eval ('__CT.bot(false); __CT.start(' + $lv + '); 1') | Out-Null
  Pump 900
  Eval '__CT.bot(true,true)' | Out-Null
  $dl=(Get-Date).AddSeconds(100)
  $st=''
  while((Get-Date) -lt $dl){
    Pump 1500
    $st=Eval 'JSON.stringify(__CT.stats())'
    if($st -like '*running*:false*'){ break }
  }
  $scr=Eval '__CT.screens()'
  Write-Host ("LEVEL " + $lv + " | " + $st + " | screens=" + $scr)
  if($scr -like '*clear*'){ $pass++ }
  Eval '__CT.bot(false)' | Out-Null
  Eval '(()=>{ document.querySelectorAll(".screen").forEach(s=>s.classList.remove("on")); return 1; })()' | Out-Null
  Pump 300
}
Write-Host ("LEVELS CLEARED BY BOT: " + $pass + "/12")
Write-Host ("save=" + (Eval '__CT.saved()'))
Report-Errors
Close-Browser
Write-Host 'DONE'
