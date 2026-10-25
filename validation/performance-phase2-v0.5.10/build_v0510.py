from pathlib import Path
import io,zipfile,hashlib,re,subprocess,sys,tempfile,shutil

V059_COMMIT="d725f4ef532c5a7811b07e0d539c9488d7aebc7c"
V059_PACKAGE="SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.9.zip"
OUT=Path.cwd()/"SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.10.zip"
BASE_PS1=(129843,"a032e0bc6ef03889464e46281951562eeb56ac60a5bade7c6667b3bfbf98c74d")
BASE_ZIP=(163324,"2930fc1607e9306054494b82be850552bb2df46ea707acfef7b9c4225511ff60")
OUT_PS1=(131328,"928fc049710a026d4d1c7c28c5c92273a3f914d4f5c66f7be8df8dc0642c562a")
OUT_ZIP=(165031,"ad8d9f7149a82073131beef63038fd8fa58d2fb40a33d3b061826cf7b0235aa8")
OVERLAY={
"overlay/apply-overlay.ps1":(16748,"053a597e834aab959a588350160ce81046ceda66e2a2ac233eeff8af78fea544"),
"overlay/lazy-custom-app-loader.js":(10600,"c38af0f6266747f50d2a0c05e9a49d5ffb34135738715fab6321ff4ae79623d9"),
"overlay/targets.json":(1756,"c255e53066abbd730467e0c1d92e81dd907e1ea2f245daf6f0d080d2239fea35")}

def sha(b): return hashlib.sha256(b).hexdigest()
def ident(b,e,label):
    if len(b)!=e[0] or sha(b)!=e[1]: raise RuntimeError(f"{label} drift: {len(b)}/{sha(b)}")
def replfn(s,n,b):
    a=s.index("function "+n+" {")
    m=re.search(r"\r?\nfunction [A-Za-z0-9_-]+ \{",s[a+10:])
    if not m: raise RuntimeError("next function missing: "+n)
    z=a+10+m.start()
    return s[:a]+b.rstrip()+s[z:]

tmp=Path(tempfile.mkdtemp(prefix="spotify-v0510-"));wt=tmp/"v059"
try:
    subprocess.run(["git","cat-file","-e",V059_COMMIT+"^{commit}"],check=True)
    subprocess.run(["git","worktree","add","--detach",str(wt),V059_COMMIT],check=True)
    subprocess.run([sys.executable,str(wt/"validation/performance-phase2-v0.5.9/build_v059.py")],cwd=wt,check=True)
    base_pkg=(wt/V059_PACKAGE).read_bytes()
    ident(base_pkg,BASE_ZIP,"v0.5.9 ZIP")
    with zipfile.ZipFile(io.BytesIO(base_pkg)) as z: f={n:z.read(n) for n in z.namelist()}
finally:
    if wt.exists(): subprocess.run(["git","worktree","remove","--force",str(wt)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(tmp,ignore_errors=True)

ident(f["idle-overlay-media-command-free-revalidation.ps1"],BASE_PS1,"v0.5.9 PS1")
for n,e in OVERLAY.items(): ident(f[n],e,n)

s=f["idle-overlay-media-command-free-revalidation.ps1"].decode("utf-8-sig")
s=s.replace("v0.5.9","v0.5.10").replace("V059","V0510").replace("v059","v0510")
NEW_MEASURE='function Measure-IdleCondition {\r\n    param([string]$Label)\r\n    if(-not(Wait-SpotifyReady 20)){throw "Spotify is not running for $Label"}\r\n    $session=Get-SpotifyMediaSession -AllowNone\r\n    [void](Assert-SpotifyIdleGuardV0510 -Session $session -Context "$Label preflight")\r\n    $logical=[int](Get-LogicalCpuCount)\r\n    $initialProcs=@(Get-Process Spotify -ErrorAction SilentlyContinue)\r\n    Update-RoleCache -Pids @($initialProcs|Select-Object -ExpandProperty Id|Sort-Object)\r\n    $script:RoleCimLookups=0\r\n    $rows=New-Object System.Collections.Generic.List[object]\r\n    $prev=@{};foreach($p in $initialProcs){if($null -ne $p.CPU){$prev[[int]$p.Id]=[double]$p.CPU}}\r\n    $clock=[Diagnostics.Stopwatch]::StartNew();$lastSample=0.0;$maxGuardSessions=0\r\n    $expectedSampleCount=[int][Math]::Floor($MeasurementSeconds*1000.0/$SampleIntervalMs)\r\n    $sampleSlot=1;$missedScheduleSlots=0\r\n    Write-LabLog "Starting $Label media-command-free idle phase: $MeasurementSeconds sec, interval=${SampleIntervalMs}ms; logical_cpu_count=$logical; absolute_deadline_scheduler=True; Play/Next/Pause are not issued."\r\n    while($sampleSlot -le $expectedSampleCount){\r\n        $targetMs=[double]$sampleSlot*[double]$SampleIntervalMs\r\n        $remainingMs=$targetMs-$clock.Elapsed.TotalMilliseconds\r\n        if($remainingMs -gt 0){Start-Sleep -Milliseconds ([Math]::Max(1,[int][Math]::Ceiling($remainingMs)))}\r\n        $nowMs=$clock.Elapsed.TotalMilliseconds\r\n        if($nowMs -ge ($targetMs+$SampleIntervalMs)){\r\n            $missed=[int][Math]::Floor(($nowMs-$targetMs)/$SampleIntervalMs)\r\n            if($missed -lt 1){$missed=1}\r\n            $missedScheduleSlots+=$missed;$sampleSlot+=$missed\r\n            continue\r\n        }\r\n        $elapsed=$nowMs/1000.0\r\n        $captured=[int](Refresh-SpotifySilentForTest);if($captured -gt $maxGuardSessions){$maxGuardSessions=$captured}\r\n        if([SpotifyControlWindowHost]::IsSpotifyForeground()){[void](Show-SpotifyBehindUserForMeasurement)}\r\n        if([SpotifyControlWindowHost]::IsSpotifyForeground()){throw "$Label Spotify unexpectedly owns keyboard focus during idle measurement."}\r\n        $session=Get-SpotifyMediaSession -AllowNone\r\n        $status=Get-SpotifyPlaybackStatusV0510 -Session $session\r\n        if([string]$status -eq \'Playing\'){\r\n            [void](Refresh-SpotifySilentForTest)\r\n            throw "$Label Spotify unexpectedly entered Playing during media-command-free idle measurement. Audio was kept mute+volume-zero; sample rejected without corrective media commands."\r\n        }\r\n        $interval=$elapsed-$lastSample;if($interval -le 0){$interval=$SampleIntervalMs/1000.0}\r\n        $snap=Get-RoleSnapshot -Previous $prev -IntervalSeconds $interval;$prev=$snap.next;$lastSample=$elapsed\r\n        $rows.Add([pscustomobject]@{\r\n            timestamp=(Get-Date).ToString(\'o\');condition=$Label;elapsed_seconds=[Math]::Round($elapsed,3);sample_slot=$sampleSlot;sample_target_ms=[Math]::Round($targetMs,1);sample_schedule_lag_ms=[Math]::Round($nowMs-$targetMs,1);sample_interval_ms=[Math]::Round($interval*1000.0,1);process_count=$snap.count;playback_status=[string]$status;guard_captured_sessions=$captured\r\n            cpu_percent=[Math]::Round([double]$snap.cpu.total,3);main_cpu_percent=[Math]::Round([double]$snap.cpu.main,3);renderer_cpu_percent=[Math]::Round([double]$snap.cpu.renderer,3);gpu_cpu_percent=[Math]::Round([double]$snap.cpu.gpu,3);utility_cpu_percent=[Math]::Round([double]$snap.cpu.utility,3)\r\n            working_set_mb=[Math]::Round([double]$snap.ws.total/1MB,2);private_mb=[Math]::Round([double]$snap.private/1MB,2);main_working_set_mb=[Math]::Round([double]$snap.ws.main/1MB,2);renderer_working_set_mb=[Math]::Round([double]$snap.ws.renderer/1MB,2);gpu_working_set_mb=[Math]::Round([double]$snap.ws.gpu/1MB,2)\r\n        })\r\n        $sampleSlot++\r\n    }\r\n    $clock.Stop();$rowArray=$rows.ToArray()\r\n    if($rowArray.Count -lt [Math]::Floor(($MeasurementSeconds*1000.0/$SampleIntervalMs)*0.75)){throw "$Label produced too few idle samples: $($rowArray.Count)."}\r\n    $minProcessCount=[int](($rowArray|Select-Object -ExpandProperty process_count|Measure-Object -Minimum).Minimum);$endProcessCount=@(Get-Process Spotify -ErrorAction SilentlyContinue).Count\r\n    if($minProcessCount -lt 1 -or $endProcessCount -lt 1){throw "$Label lost all Spotify processes during idle measurement."}\r\n    $session=Get-SpotifyMediaSession -AllowNone;[void](Assert-SpotifyIdleGuardV0510 -Session $session -Context "$Label completion");[void](Refresh-SpotifySilentForTest)\r\n    return [pscustomobject]@{rows=$rowArray;min_spotify_process_count=$minProcessCount;end_spotify_process_count=$endProcessCount;sample_count=$rowArray.Count;expected_sample_count=$expectedSampleCount;sample_coverage_ratio=[Math]::Round($rowArray.Count/[Math]::Max(1.0,[double]$expectedSampleCount),3);sample_interval_p95_ms=[Math]::Round((Get-Percentile @($rowArray|Select-Object -ExpandProperty sample_interval_ms) 95),1);sample_schedule_lag_p95_ms=[Math]::Round((Get-Percentile @($rowArray|Select-Object -ExpandProperty sample_schedule_lag_ms) 95),1);sample_schedule_lag_max_ms=[Math]::Round((Get-Percentile @($rowArray|Select-Object -ExpandProperty sample_schedule_lag_ms) 100),1);missed_schedule_slots=$missedScheduleSlots;role_cim_lookups_during_measurement=[int]$script:RoleCimLookups;logical_cpu_count=$logical;max_guard_sessions=$maxGuardSessions;media_commands_used=$false;idle_design=$true}\r\n}'
README_TEXT='Spotify Control Production Lazy-Overlay Media-Command-Free Idle Revalidation v0.5.10\n\nPurpose:\n- Resolve BLF / Playlist Maker lazy-loading policy without any Spotify transport command.\n- 4 states x 4 Williams-counterbalanced blocks = 16 conditions.\n- Each condition warms up, then measures steady-state Spotify CPU / renderer / GPU / memory while idle.\n- v0.5.10 keeps the v0.5.9 cached CPU/process-role invariants and fixes sampling cadence itself: samples are scheduled against absolute 250 ms deadlines, so measurement work no longer stretches every interval.\n- If a sample is more than one full interval late, the missed schedule slot is counted instead of fabricating a burst sample.\n\nSafety:\n- No Play, Next, Pause, global media key, or keyboard injection is issued during measurement.\n- Spotify-only CoreAudio guard is armed before launch and enforces master volume 0 + mute with read-back verification.\n- Spotify windows use WS_EX_NOACTIVATE and cannot take keyboard focus.\n- If Spotify reports Playing spontaneously, the run fails closed without corrective media commands.\n- Chrome and other media apps are never controlled or muted.\n- Target extension payloads, config, protected persistence, Star Ratings, ivLyrics, Tagify, Splitify, SC Cover Ambience, Marketplace and unknown hooks are untouched.\n- Production xpui/index/overlay state is restored exactly.\n- The original 24 s / 250 ms / 75% sample-quality threshold remains unchanged.\n- Each condition records sample coverage, actual interval p95, schedule-lag p95/max, missed schedule slots, logical CPU count, and new-PID role CIM lookups.\n\nRun RUN_MEDIA_COMMAND_FREE_IDLE_REVALIDATION.cmd normally, not as Administrator.\nYou may use Chrome normally; avoid starting heavy new CPU/GPU work while the measurement runs.\n'
RUN_TEXT='@echo off\nsetlocal\ncd /d "%~dp0"\necho Spotify Control Media-Command-Free Idle Counterbalanced Revalidation v0.5.10\necho -------------------------------------------------------------------------\necho This profiler sends NO Play, Next, Pause, or global media-key command.\necho v0.5.10 uses absolute 250ms sample deadlines so profiler work no longer accumulates into the interval.\necho Spotify windows cannot take keyboard focus; any Spotify audio session is mute + volume 0 guarded.\necho You may use Chrome normally; avoid starting heavy new CPU/GPU work during measurement.\necho.\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0idle-overlay-media-command-free-revalidation.ps1" -Action Run\nif errorlevel 1 (\n  echo.\n  echo FAILED. Do not rerun automatically; provide the v0.5.10 error log.\n) else (\n  echo.\n  echo VERIFIED. Provide idle-overlay-v0510-latest.txt and preferably JSON.\n)\npause\n'
SELF_TEXT='@echo off\nsetlocal\ncd /d "%~dp0"\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0idle-overlay-media-command-free-revalidation.ps1" -Action SelfTest\npause\n'

s=replfn(s,"Measure-IdleCondition",NEW_MEASURE)

anchor=";Add-Member -InputObject $a -NotePropertyName logical_cpu_count -NotePropertyValue ([int]$m.logical_cpu_count) -Force"
if anchor not in s: raise RuntimeError("summary metadata anchor missing")
s=s.replace(anchor,anchor+";Add-Member -InputObject $a -NotePropertyName sample_schedule_lag_p95_ms -NotePropertyValue ([double]$m.sample_schedule_lag_p95_ms) -Force;Add-Member -InputObject $a -NotePropertyName sample_schedule_lag_max_ms -NotePropertyValue ([double]$m.sample_schedule_lag_max_ms) -Force;Add-Member -InputObject $a -NotePropertyName missed_schedule_slots -NotePropertyValue ([int]$m.missed_schedule_slots) -Force",1)
s=s.replace("sampler_revision='v0.5.10-cached-logical-cpu-incremental-role-cache'","sampler_revision='v0.5.10-absolute-deadline-cached-sampler'",1)
s=s.replace("v0.5.10 primes logical CPU count and initial process roles before each timed window; no per-sample Win32_Processor CIM query remains.","v0.5.10 keeps the cached CPU/process-role invariants and schedules samples against absolute 250ms deadlines so measurement work no longer accumulates into the sampling period.",1)
s=s.replace("\r\n","\n").replace("\n","\r\n")
ps=b"\xef\xbb\xbf"+s.encode()
ident(ps,OUT_PS1,"v0.5.10 PS1")
for x in ("TryPlayAsync","TryPauseAsync","TrySkipNextAsync","Invoke-SpotifyMediaCommand","keybd_event","Send-MediaKey","[byte]0xB0","[byte]0xB3"):
    if x.lower() in s.lower(): raise RuntimeError("forbidden media surface: "+x)
if "Start-Sleep -Milliseconds $SampleIntervalMs" in s: raise RuntimeError("drifting fixed-sleep sampler survived")
for x in ("$targetMs=[double]$sampleSlot*[double]$SampleIntervalMs","$remainingMs=$targetMs-$clock.Elapsed.TotalMilliseconds","$missedScheduleSlots+=$missed","sample_schedule_lag_p95_ms","missed_schedule_slots=$missedScheduleSlots","*0.75"):
    if x not in s: raise RuntimeError("deadline sampler contract missing: "+x)

README=README_TEXT.replace("\n","\r\n").encode()
RUN=RUN_TEXT.replace("\n","\r\n").encode()
SELF=SELF_TEXT.replace("\n","\r\n").encode()
o={
"idle-overlay-media-command-free-revalidation.ps1":ps,
"overlay/apply-overlay.ps1":f["overlay/apply-overlay.ps1"],
"overlay/lazy-custom-app-loader.js":f["overlay/lazy-custom-app-loader.js"],
"overlay/targets.json":f["overlay/targets.json"],
"README.md":README,
"RUN_MEDIA_COMMAND_FREE_IDLE_REVALIDATION.cmd":RUN,
"SELFTEST.cmd":SELF}
order=list(o)
o["SHA256SUMS.txt"]=("\n".join(f"{sha(o[n])}  {n}" for n in order)+"\n").encode("ascii")
order.append("SHA256SUMS.txt")
b=io.BytesIO()
with zipfile.ZipFile(b,"w",compression=zipfile.ZIP_STORED) as z:
    for n in order:
        i=zipfile.ZipInfo(n,(2026,10,26,0,0,0));i.compress_type=zipfile.ZIP_STORED;i.create_system=0;i.external_attr=0;i.flag_bits=0
        z.writestr(i,o[n])
pkg=b.getvalue()
ident(pkg,OUT_ZIP,"v0.5.10 ZIP")
OUT.write_bytes(pkg)
print("PHASE2_V0510_SCRIPT_PASS",len(ps),sha(ps))
print("PHASE2_V0510_PACKAGE_PASS",len(pkg),sha(pkg))
