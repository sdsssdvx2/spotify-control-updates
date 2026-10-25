from pathlib import Path
import io,zipfile,hashlib,re,subprocess,sys,tempfile,shutil

V058_COMMIT="811073d1cc0846d2da308fc3379a08f031a42cda"
V058_PACKAGE="SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.8.zip"
OUT=Path.cwd()/"SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.9.zip"
BASE_PS1=(127185,"e189dd1b5b07f54feaf6015c10501359446033cb0fa800e52e2bd83e0fef45d1")
OUT_PS1=(129843,"a032e0bc6ef03889464e46281951562eeb56ac60a5bade7c6667b3bfbf98c74d")
OUT_ZIP=(163324,"2930fc1607e9306054494b82be850552bb2df46ea707acfef7b9c4225511ff60")
OVERLAY={
"overlay/apply-overlay.ps1":(16748,"053a597e834aab959a588350160ce81046ceda66e2a2ac233eeff8af78fea544"),
"overlay/lazy-custom-app-loader.js":(10600,"c38af0f6266747f50d2a0c05e9a49d5ffb34135738715fab6321ff4ae79623d9"),
"overlay/targets.json":(1756,"c255e53066abbd730467e0c1d92e81dd907e1ea2f245daf6f0d080d2239fea35")}
def sha(b): return hashlib.sha256(b).hexdigest()
def ident(b,e,label):
    if len(b)!=e[0] or sha(b)!=e[1]: raise RuntimeError(f"{label} drift: {len(b)}/{sha(b)}")
def replfn(s,n,b):
    a=s.index(f"function {n} {{");m=re.search(r"\r?\nfunction [A-Za-z0-9_-]+ \{",s[a+10:])
    if not m: raise RuntimeError("next function missing: "+n)
    z=a+10+m.start();return s[:a]+b.rstrip()+s[z:]
tmp=Path(tempfile.mkdtemp(prefix="spotify-v059-"));wt=tmp/"v058"
try:
    subprocess.run(["git","cat-file","-e",V058_COMMIT+"^{commit}"],check=True)
    subprocess.run(["git","worktree","add","--detach",str(wt),V058_COMMIT],check=True)
    subprocess.run([sys.executable,str(wt/"validation/performance-phase2-v0.5.8/build_v058.py")],cwd=wt,check=True)
    with zipfile.ZipFile(wt/V058_PACKAGE) as z: f={n:z.read(n) for n in z.namelist()}
finally:
    if wt.exists(): subprocess.run(["git","worktree","remove","--force",str(wt)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(tmp,ignore_errors=True)
ident(f["idle-overlay-media-command-free-revalidation.ps1"],BASE_PS1,"v0.5.8 PS1")
for n,e in OVERLAY.items(): ident(f[n],e,n)
s=f["idle-overlay-media-command-free-revalidation.ps1"].decode("utf-8-sig")
s=s.replace("v0.5.8","v0.5.9").replace("V058","V059").replace("v058","v059")
NEW_LOGICAL='function Get-LogicalCpuCount {\n    if($null -ne $script:LogicalCpuCount -and [int]$script:LogicalCpuCount -gt 0){return [int]$script:LogicalCpuCount}\n    try{$cpu=Get-CimInstance Win32_Processor|Select-Object -First 1;$script:LogicalCpuCount=[Math]::Max(1,[int]$cpu.NumberOfLogicalProcessors)}\n    catch{$script:LogicalCpuCount=[Math]::Max(1,[Environment]::ProcessorCount)}\n    return [int]$script:LogicalCpuCount\n}'
NEW_ROLE='function Update-RoleCache {\n    param([int[]]$Pids)\n    if($null -eq $script:RoleCache){$script:RoleCache=@{}}\n    $live=@{}\n    foreach($procId in @($Pids|Sort-Object -Unique)){\n        $pidInt=[int]$procId;$live[$pidInt]=$true\n        if($script:RoleCache.ContainsKey($pidInt)){continue}\n        $cmd=$null\n        try{$cmd=(Get-CimInstance Win32_Process -Filter "ProcessId=$pidInt" -ErrorAction Stop).CommandLine;$script:RoleCimLookups=[int]$script:RoleCimLookups+1}catch{}\n        $script:RoleCache[$pidInt]=Get-ProcessRoleFromCommandLine $cmd\n    }\n    foreach($cachedId in @($script:RoleCache.Keys)){if(-not $live.ContainsKey([int]$cachedId)){$script:RoleCache.Remove([int]$cachedId)}}\n}'
s=replfn(s,"Get-LogicalCpuCount",NEW_LOGICAL);s=replfn(s,"Update-RoleCache",NEW_ROLE)
s=s.replace("$script:Session = $null","$script:Session = $null\r\n$script:LogicalCpuCount = $null\r\n$script:RoleCimLookups = 0",1)
s=s.replace("$script:RoleCacheSignature='';$script:RoleCache=@{}","$script:RoleCache=@{};$script:RoleCimLookups=0",1)
old="    $rows=New-Object System.Collections.Generic.List[object]\r\n    $prev=@{};foreach($p in @(Get-Process Spotify -ErrorAction SilentlyContinue)){if($null -ne $p.CPU){$prev[[int]$p.Id]=[double]$p.CPU}}\r\n    $clock=[Diagnostics.Stopwatch]::StartNew();$lastSample=0.0;$maxGuardSessions=0"
new="    $logical=[int](Get-LogicalCpuCount)\r\n    $initialProcs=@(Get-Process Spotify -ErrorAction SilentlyContinue)\r\n    Update-RoleCache -Pids @($initialProcs|Select-Object -ExpandProperty Id|Sort-Object)\r\n    $script:RoleCimLookups=0\r\n    $rows=New-Object System.Collections.Generic.List[object]\r\n    $prev=@{};foreach($p in $initialProcs){if($null -ne $p.CPU){$prev[[int]$p.Id]=[double]$p.CPU}}\r\n    $clock=[Diagnostics.Stopwatch]::StartNew();$lastSample=0.0;$maxGuardSessions=0"
if old not in s: raise RuntimeError("measurement prime anchor missing")
s=s.replace(old,new,1)
s=s.replace('Write-LabLog "Starting $Label media-command-free idle phase: $MeasurementSeconds sec, interval=${SampleIntervalMs}ms; Play/Next/Pause are not issued."','Write-LabLog "Starting $Label media-command-free idle phase: $MeasurementSeconds sec, interval=${SampleIntervalMs}ms; logical_cpu_count=$logical; Play/Next/Pause are not issued."',1)
s=s.replace("timestamp=(Get-Date).ToString('o');condition=$Label;elapsed_seconds=[Math]::Round($elapsed,3);process_count=$snap.count;","timestamp=(Get-Date).ToString('o');condition=$Label;elapsed_seconds=[Math]::Round($elapsed,3);sample_interval_ms=[Math]::Round($interval*1000.0,1);process_count=$snap.count;",1)
s=s.replace("return [pscustomobject]@{rows=$rowArray;min_spotify_process_count=$minProcessCount;end_spotify_process_count=$endProcessCount;sample_count=$rowArray.Count;max_guard_sessions=$maxGuardSessions;media_commands_used=$false;idle_design=$true}","return [pscustomobject]@{rows=$rowArray;min_spotify_process_count=$minProcessCount;end_spotify_process_count=$endProcessCount;sample_count=$rowArray.Count;expected_sample_count=[Math]::Floor($MeasurementSeconds*1000.0/$SampleIntervalMs);sample_coverage_ratio=[Math]::Round($rowArray.Count/[Math]::Max(1.0,[double][Math]::Floor($MeasurementSeconds*1000.0/$SampleIntervalMs)),3);sample_interval_p95_ms=[Math]::Round((Get-Percentile @($rowArray|Select-Object -ExpandProperty sample_interval_ms) 95),1);role_cim_lookups_during_measurement=[int]$script:RoleCimLookups;logical_cpu_count=$logical;max_guard_sessions=$maxGuardSessions;media_commands_used=$false;idle_design=$true}",1)
a="Add-Member -InputObject $a -NotePropertyName max_guard_sessions -NotePropertyValue ([int]$m.max_guard_sessions) -Force;Add-Member -InputObject $a -NotePropertyName media_commands_used -NotePropertyValue ([bool]$m.media_commands_used) -Force"
s=s.replace(a,a+";Add-Member -InputObject $a -NotePropertyName expected_sample_count -NotePropertyValue ([int]$m.expected_sample_count) -Force;Add-Member -InputObject $a -NotePropertyName sample_coverage_ratio -NotePropertyValue ([double]$m.sample_coverage_ratio) -Force;Add-Member -InputObject $a -NotePropertyName sample_interval_p95_ms -NotePropertyValue ([double]$m.sample_interval_p95_ms) -Force;Add-Member -InputObject $a -NotePropertyName role_cim_lookups_during_measurement -NotePropertyValue ([int]$m.role_cim_lookups_during_measurement) -Force;Add-Member -InputObject $a -NotePropertyName logical_cpu_count -NotePropertyValue ([int]$m.logical_cpu_count) -Force",1)
r="preflight_spotify_processes_autoclosed=$preflightSpotifyCount;sample_interval_ms=$SampleIntervalMs;idle_warmup_seconds=$IdleWarmupSeconds;measurement_seconds=$MeasurementSeconds"
s=s.replace(r,r+";sampler_revision='v0.5.9-cached-logical-cpu-incremental-role-cache';sampler_cim_policy='Win32_Processor cached before timed window; Win32_Process only for unseen Spotify PIDs'",1)
c="    Write-Host 'One integrated run: 4 states x 4 Williams-counterbalanced blocks = 16 idle conditions.'"
s=s.replace(c,c+"\r\n    Write-Host 'v0.5.9 primes logical CPU count and initial process roles before each timed window; no per-sample Win32_Processor CIM query remains.'",1)
q='    Write-LabLog "Media-command-free idle counterbalanced revalidation v$Version self-test passed; production paths were not mutated." \'OK\''
s=s.replace(q,"    $script:LogicalCpuCount=$null\r\n    $lc1=[int](Get-LogicalCpuCount);$lc2=[int](Get-LogicalCpuCount)\r\n    if($lc1 -lt 1 -or $lc2 -ne $lc1 -or [int]$script:LogicalCpuCount -ne $lc1){throw 'Logical CPU cache self-test failed.'}\r\n    $script:RoleCache=@{};$script:RoleCimLookups=0;Update-RoleCache -Pids @()\r\n    if($script:RoleCimLookups -ne 0){throw 'Empty incremental role-cache self-test unexpectedly performed CIM lookup.'}\r\n"+q,1)
s=s.replace("SELFTEST PASS: v0.6.20/r9 classifier, 16-condition Williams matrix, factorial contrasts, exact production engine package identity, subset transform, and fail-open unknown-byte behavior.","SELFTEST PASS: v0.6.20/r9 classifier, 16-condition Williams matrix, factorial contrasts, cached logical CPU count, incremental role cache, exact production engine package identity, subset transform, and fail-open unknown-byte behavior.",1)
s=s.replace("\r\n","\n").replace("\n","\r\n");ps=b"\xef\xbb\xbf"+s.encode()
ident(ps,OUT_PS1,"v0.5.9 PS1")
for x in ("TryPlayAsync","TryPauseAsync","TrySkipNextAsync","Invoke-SpotifyMediaCommand","keybd_event","Send-MediaKey","[byte]0xB0","[byte]0xB3"):
    if x.lower() in s.lower(): raise RuntimeError("forbidden media surface: "+x)
README='Spotify Control Production Lazy-Overlay Media-Command-Free Idle Revalidation v0.5.9\n\nPurpose:\n- Resolve BLF / Playlist Maker lazy-loading policy without any Spotify transport command.\n- 4 states x 4 Williams-counterbalanced blocks = 16 conditions.\n- Each condition warms up, then measures steady-state Spotify CPU / renderer / GPU / memory while idle.\n- v0.5.9 fixes the v0.5.8 sampler bottleneck: logical CPU count is cached before the timed window, and process-role CIM lookups are incremental instead of rebuilding the entire role map whenever PIDs change.\n\nSafety:\n- No Play, Next, Pause, global media key, or keyboard injection is issued during measurement.\n- Spotify-only CoreAudio guard is armed before launch and enforces master volume 0 + mute with read-back verification.\n- Spotify windows use WS_EX_NOACTIVATE and cannot take keyboard focus.\n- If Spotify reports Playing spontaneously, the run fails closed without corrective media commands.\n- Chrome and other media apps are never controlled or muted.\n- Target extension payloads, config, protected persistence, Star Ratings, ivLyrics, Tagify, Splitify, SC Cover Ambience, Marketplace and unknown hooks are untouched.\n- Production xpui/index/overlay state is restored exactly.\n- Each condition records expected sample count, achieved sample coverage, p95 actual sample interval, logical CPU count, and any new-PID role CIM lookups.\n\nRun RUN_MEDIA_COMMAND_FREE_IDLE_REVALIDATION.cmd normally, not as Administrator.\nYou may use Chrome normally; avoid starting heavy new CPU/GPU work while the measurement runs.\n'.replace("\n","\r\n").encode()
RUN='@echo off\nsetlocal\ncd /d "%~dp0"\necho Spotify Control Media-Command-Free Idle Counterbalanced Revalidation v0.5.9\necho ------------------------------------------------------------------------\necho This profiler sends NO Play, Next, Pause, or global media-key command.\necho v0.5.9 fixes the v0.5.8 sampler bottleneck by caching CPU/process-role invariants before timing.\necho Spotify windows cannot take keyboard focus; any Spotify audio session is mute + volume 0 guarded.\necho You may use Chrome normally; avoid starting heavy new CPU/GPU work during measurement.\necho.\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0idle-overlay-media-command-free-revalidation.ps1" -Action Run\nif errorlevel 1 (\n  echo.\n  echo FAILED. Do not rerun automatically; provide the v0.5.9 error log.\n) else (\n  echo.\n  echo VERIFIED. Provide idle-overlay-v059-latest.txt and preferably JSON.\n)\npause\n'.replace("\n","\r\n").encode()
SELF='@echo off\nsetlocal\ncd /d "%~dp0"\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0idle-overlay-media-command-free-revalidation.ps1" -Action SelfTest\npause\n'.replace("\n","\r\n").encode()
o={"idle-overlay-media-command-free-revalidation.ps1":ps,"overlay/apply-overlay.ps1":f["overlay/apply-overlay.ps1"],"overlay/lazy-custom-app-loader.js":f["overlay/lazy-custom-app-loader.js"],"overlay/targets.json":f["overlay/targets.json"],"README.md":README,"RUN_MEDIA_COMMAND_FREE_IDLE_REVALIDATION.cmd":RUN,"SELFTEST.cmd":SELF}
order=list(o);o["SHA256SUMS.txt"]=("\n".join(f"{sha(o[n])}  {n}" for n in order)+"\n").encode("ascii");order.append("SHA256SUMS.txt")
b=io.BytesIO()
with zipfile.ZipFile(b,"w",compression=zipfile.ZIP_STORED) as z:
    for n in order:
        i=zipfile.ZipInfo(n,(2026,10,26,0,0,0));i.compress_type=zipfile.ZIP_STORED;i.create_system=0;i.external_attr=0;i.flag_bits=0;z.writestr(i,o[n])
pkg=b.getvalue();ident(pkg,OUT_ZIP,"v0.5.9 ZIP");OUT.write_bytes(pkg)
print("PHASE2_V059_SCRIPT_PASS",len(ps),sha(ps));print("PHASE2_V059_PACKAGE_PASS",len(pkg),sha(pkg))
