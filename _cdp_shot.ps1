# CUBETRIO 3D — visual capture script (run via Invoke-Expression)
$stamp=Get-Date -Format 'HHmmss'
$script:port=9500 + (Get-Random -Minimum 0 -Maximum 60)
$script:ud="$env:TEMP\ct_cdp_udata_$stamp"
$script:win="1280,760"
$html=Resolve-Path "cubetrio-3d\index.html"
$script:url="file:///" + $html.Path.Replace('\','/') + "?v=" + $stamp
$script:outdir=Join-Path (Split-Path $html.Path) "shots"
Invoke-Expression ([IO.File]::ReadAllText((Join-Path (Split-Path $html.Path) "_cdp_lib.ps1")))

Write-Host ("ready=" + (Eval 'String(!!window.__CUBETRIO_READY__)') + " errs=" + $script:errs.Count)

# 1) japanese title
Eval '__CT.langSet("ja")' | Out-Null
Pump 500
Shot 'v_title_ja.png'

# 2) desktop gameplay framing (big level)
Eval '__CT.langSet("en"); __CT.start(8);' | Out-Null
Pump 1600
Shot 'v_level8.png'

# 3) picks + chips + combo
for($i=0;$i -lt 9;$i++){ Eval '__CT.pickSmart()' | Out-Null; Pump 190 }
Shot 'v_combo.png'
Write-Host ("stats=" + (Eval 'JSON.stringify(__CT.stats())') + " tray=" + (Eval '__CT.colors()'))

# 4) let the greedy bot finish the level -> clear modal
Eval '__CT.bot(true,true)' | Out-Null
$dl=(Get-Date).AddSeconds(90)
while((Get-Date) -lt $dl){ Pump 2000; if((Eval 'JSON.stringify(__CT.stats())') -like '*running*:false*'){ break } }
Write-Host ("endOfLevel=" + (Eval 'JSON.stringify(__CT.stats())') + " screens=" + (Eval '__CT.screens()'))
Eval '__CT.bot(false)' | Out-Null
Pump 600
Shot 'v_clear.png'

# 5) fail modal
Click-El '#btn-clear-home'
Pump 700
Eval '__CT.start(5)' | Out-Null
Pump 1200
Eval '__CT.failNow(); 1' | Out-Null
Pump 700
Shot 'v_fail.png'
Click-El '#btn-fail-home'
Pump 700

# 6) help modal (japanese)
Eval '__CT.langSet("ja")' | Out-Null
Click-El '#btn-help2'
Pump 600
Shot 'v_help_ja.png'
Eval '(()=>{ document.querySelector("[data-close]").click(); return 1; })()' | Out-Null
Pump 400

# 7) phone landscape
Set-Viewport 844 390 $true
Eval '__CT.start(4)' | Out-Null
Pump 1600
Shot 'v_phone_landscape.png'

# 8) phone portrait -> rotate hint
Set-Viewport 390 844 $true
Pump 900
Write-Host ("portraitScreens=" + (Eval '__CT.screens()'))
Shot 'v_phone_portrait.png'

Report-Errors
Close-Browser
Write-Host 'DONE'
