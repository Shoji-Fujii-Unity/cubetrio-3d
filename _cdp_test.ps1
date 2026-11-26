# CUBETRIO 3D — smoke test (run via Invoke-Expression; execution policy blocks direct file runs)
$stamp=Get-Date -Format 'HHmmss'
$script:port=9400 + (Get-Random -Minimum 0 -Maximum 80)
$script:ud="$env:TEMP\ct_cdp_udata_$stamp"
$script:win="1180,700"
$html=Resolve-Path "cubetrio-3d\index.html"
$script:url="file:///" + $html.Path.Replace('\','/') + "?t=" + $stamp
$script:outdir=Join-Path (Split-Path $html.Path) "shots"
Invoke-Expression ([IO.File]::ReadAllText((Join-Path (Split-Path $html.Path) "_cdp_lib.ps1")))

# ---- boot ----
Write-Host ("ready=" + (Eval 'String(!!window.__CUBETRIO_READY__)') + " fatalHidden=" + (Eval 'String(document.getElementById("fatal").hidden)'))
Write-Host ("dom=" + (Eval 'String(document.querySelectorAll("#lvls .lv").length) + " lvls / " + String(document.querySelectorAll("#rules li").length) + " rules / " + String(document.querySelectorAll("#tray .slot").length) + " slots"'))
Write-Host ("attract=" + (Eval '(window.__CT ? JSON.stringify(__CT.stats()) : "nohook")'))
Shot 't_title.png'

# ---- start with a real mouse click ----
Click-El '#btn-start'
Pump 1500
Write-Host ("afterStart=" + (Eval 'JSON.stringify(__CT.stats())') + " screens=[" + (Eval '__CT.screens()') + "]")
Shot 't_game.png'

# ---- a multi-touch pinch must never be treated as a block tap ----
$pinch=Eval '(()=>{const p=__CT.tapPoint(0),c=document.getElementById("scene"),n=__CT.G.tray.length;const ev=(type,id,x,y)=>c.dispatchEvent(new PointerEvent(type,{pointerId:id,clientX:x,clientY:y,bubbles:true}));ev("pointerdown",101,p.x,p.y);ev("pointerdown",102,p.x+40,p.y+40);ev("pointerup",102,p.x+40,p.y+40);ev("pointerup",101,p.x,p.y);return n+"->"+__CT.G.tray.length;})()'
Write-Host ("pinchDoesNotPick=" + $pinch)

# ---- power actions are ignored while a tray match is resolving ----
$busyPowers=Eval '(()=>{const g=__CT.G;g.tray.push({color:0,orig:{gx:999,gy:999,gz:999},seq:999,el:null});g.busy=true;const u=g.undos,s=g.shuffles;__CT.undo();__CT.shuffle();const ok=g.tray.length===1&&g.undos===u&&g.shuffles===s;g.tray.pop();g.busy=false;return String(ok);})()'
Write-Host ("busyPowersIgnored=" + $busyPowers)

# ---- drag rotates the camera ----
Send-Msg 'Input.dispatchMouseEvent' ([ordered]@{type='mousePressed';x=560.0;y=300.0;button='left';buttons=1;clickCount=1}) | Out-Null
for($i=1;$i -le 12;$i++){ $mx=[double](560-($i*14)); $my=[double](300-($i*4)); Send-Msg 'Input.dispatchMouseEvent' ([ordered]@{type='mouseMoved';x=$mx;y=$my;button='left';buttons=1}) | Out-Null; Pump 40 }
Send-Msg 'Input.dispatchMouseEvent' ([ordered]@{type='mouseReleased';x=392.0;y=252.0;button='left';buttons=0;clickCount=1}) | Out-Null
Pump 700
Write-Host ("camAfterDrag=" + (Eval '"theta=" + __CT.cam.theta.toFixed(2) + " phi=" + __CT.cam.phi.toFixed(2) + " r=" + __CT.cam.radius.toFixed(1)'))

# ---- a real tap on a cube must put a chip into the tray ----
$ok=$false
for($k=0;$k -lt 10 -and -not $ok;$k++){
  $tp=Eval ('JSON.stringify(__CT.tapPoint(' + $k + ') || 0)')
  if($tp -isnot [string] -or -not $tp.StartsWith('{')){ break }
  $o=$tp | ConvertFrom-Json
  $before=Eval 'String(document.querySelectorAll("#tray .chip").length)'
  Click-XY $o.x $o.y; Pump 420
  $after=Eval 'String(document.querySelectorAll("#tray .chip").length)'
  if($after -ne $before){ $ok=$true; Write-Host ("realTap OK at cube #" + $k + " chips " + $before + " -> " + $after) }
}
if(-not $ok){ Write-Host 'realTap FAILED (no tap produced a tray chip)' }

# ---- greedy play: triples must clear and score must grow ----
Eval '__CT.bot(true,true); 1' | Out-Null
Pump 6000
Write-Host ("midPlay=" + (Eval 'JSON.stringify(__CT.stats())') + " chips=" + (Eval 'String(document.querySelectorAll("#tray .chip").length)'))
Eval '__CT.bot(false); 1' | Out-Null
Shot 't_played.png'

# ---- powers ----
Write-Host ("undo=" + (Eval 'String(__CT.undo())'))
Pump 500
Write-Host ("afterUndo=" + (Eval 'JSON.stringify(__CT.stats())'))
Eval '__CT.shuffle(); 1' | Out-Null
Pump 900
Write-Host ("afterShuffle=" + (Eval 'JSON.stringify(__CT.stats())'))

# ---- level clear flow ----
Eval '(()=>{ const g=__CT.G; while(g.cubes.length){ const c=g.cubes.pop(); g.grid.delete(c.gx+","+c.gy+","+c.gz); c.mesh.parent&&c.mesh.parent.remove(c.mesh);} g.tray.length=0; __CT.check(); return 1; })()' | Out-Null
Pump 900
Write-Host ("win=" + (Eval '__CT.screens()') + " | " + (Eval 'document.getElementById("clear-title").textContent') + " | " + (Eval 'document.getElementById("clear-score").textContent'))
Shot 't_clear.png'
Click-El '#btn-next'
Pump 1200
Write-Host ("nextLevel=" + (Eval 'JSON.stringify(__CT.stats())') + " screens=[" + (Eval '__CT.screens()') + "]")

# ---- fail flow ----
Eval '__CT.failNow(); 1' | Out-Null
Pump 600
Write-Host ("fail=" + (Eval '__CT.screens()') + " | " + (Eval 'document.getElementById("fail-title").textContent'))
Click-El '#btn-fail-home'
Pump 800

# ---- languages ----
Eval '__CT.langSet("ja"); 1' | Out-Null; Pump 300
Write-Host ("ja: start=" + (Eval 'document.getElementById("btn-start").textContent') + " rule1=" + (Eval 'document.querySelector("#rules li").textContent.slice(0,14)'))
Eval '__CT.langSet("zh"); 1' | Out-Null; Pump 300
Write-Host ("zh: start=" + (Eval 'document.getElementById("btn-start").textContent') + " level=" + (Eval 'document.querySelector(".stat span").textContent'))
Shot 't_title_zh.png'
Eval '__CT.langSet("en"); 1' | Out-Null; Pump 300
Write-Host ("en: start=" + (Eval 'document.getElementById("btn-start").textContent'))
Click-El '#seg-lang button[data-l="ja"]'
Pump 400
Write-Host ("langBtnJa=" + (Eval '__CT.save.lang + " / " + document.getElementById("btn-start").textContent + " / html.lang=" + document.documentElement.lang'))

# ---- sound: title segment (OFF) then HUD button during play (back ON) ----
Click-El '#seg-sound button[data-s="0"]'
Pump 400
Write-Host ("titleSoundOff=" + (Eval 'JSON.stringify(__CT.save.sound)') + " saved=" + (Eval '__CT.saved()'))
Eval '__CT.start(2); 1' | Out-Null
Pump 1000
Click-El '#btn-sound'
Pump 400
Write-Host ("hudSoundToggle=" + (Eval 'JSON.stringify(__CT.save.sound)') + " saved=" + (Eval '__CT.saved()'))
Eval '(()=>{ document.getElementById("btn-home").click(); return 1; })()' | Out-Null
Pump 700
Write-Host ("hudHiddenOnTitle=" + (Eval 'String(getComputedStyle(document.getElementById("hud")).opacity)') + " screens=[" + (Eval '__CT.screens()') + "]")

# ---- portrait hint ----
Set-Viewport 420 820 $true
Write-Host ("portraitScreens=[" + (Eval '__CT.screens()') + "]")
Shot 't_portrait.png'
Clear-Viewport
Write-Host ("landscapeScreens=[" + (Eval '__CT.screens()') + "]")

# ---- reload: save must survive ----
Send-Msg 'Page.navigate' ([ordered]@{url=($url + "&r=2")}) | Out-Null
Pump 10000
Write-Host ("afterReload=" + (Eval '(__CT ? ("ready=" + (window.__CUBETRIO_READY__?1:0) + " unlocked=" + __CT.save.unlocked + " best=" + __CT.save.best + " lang=" + __CT.save.lang + " sound=" + __CT.save.sound) : "NOHOOK")'))

# ---- malformed saved fields are normalized without breaking startup ----
Send-Msg 'Runtime.evaluate' ([ordered]@{expression='localStorage.setItem("cubetrio3d.save.v1",JSON.stringify({v:1,best:-7,unlocked:999,sound:"yes",lang:"invalid"}));location.reload()';returnByValue=$true}) | Out-Null
Pump 10000
Write-Host ("afterCorruptSave=" + (Eval '(__CT ? ("ready=" + (window.__CUBETRIO_READY__?1:0) + " unlocked=" + __CT.save.unlocked + " best=" + __CT.save.best + " lang=" + __CT.save.lang + " sound=" + __CT.save.sound) : "NOHOOK")'))

Report-Errors
Close-Browser
Write-Host 'DONE'
