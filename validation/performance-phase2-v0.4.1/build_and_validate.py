from pathlib import Path
import subprocess, io, zipfile, hashlib, shutil
BASE_COMMIT='e07a2e720d0887b7a55879c2b0cd66ecfade41cc'
BASE_PATH='validation/performance-phase2-v0.4.0/SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.0.zip'
BASE_SIZE=19764
BASE_SHA='ac014e2f5621d8460d307a5df689ce11f9378ba9504b894c5ed54e29b87b3a1d'
OUT='SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.1.zip'
def sha(b): return hashlib.sha256(b).hexdigest()

def replace1(s,a,b):
    assert s.count(a)==1,(a,s.count(a)); return s.replace(a,b,1)

subprocess.run(['git','fetch','--no-tags','--depth=1','origin',BASE_COMMIT],check=True)
base=subprocess.check_output(['git','show',f'{BASE_COMMIT}:{BASE_PATH}'])
assert len(base)==BASE_SIZE and sha(base)==BASE_SHA,(len(base),sha(base))
with zipfile.ZipFile(io.BytesIO(base)) as z:
    assert z.testzip() is None
    f={n:z.read(n) for n in z.namelist()}

s=f['track-transition-isolation.ps1'].decode('utf-8-sig').replace('\r\n','\n')
s=replace1(s,'    $presentationTags=@($themeHooks.tag+$cssHooks.tag)','    $presentationTags=@(@($themeHooks|ForEach-Object{$_.tag})+@($cssHooks|ForEach-Object{$_.tag}))')
for a,b in [
 ('# Spotify Control Track Transition Single-Hook Isolation v0.4.0','# Spotify Control Track Transition Single-Hook Isolation v0.4.1'),
 ('$Version = "0.4.0"','$Version = "0.4.1"'),
 ('backups\\performance-phase2-single-hook-v040','backups\\performance-phase2-single-hook-v041'),
 ('$LatestJson = Join-Path $Reports "track-transition-single-hook-latest.json"','$LatestJson = Join-Path $Reports "track-transition-single-hook-v041-latest.json"'),
 ('$LatestTxt = Join-Path $Reports "track-transition-single-hook-latest.txt"','$LatestTxt = Join-Path $Reports "track-transition-single-hook-v041-latest.txt"'),
 ('$LatestCsv = Join-Path $Reports "track-transition-single-hook-raw-latest.csv"','$LatestCsv = Join-Path $Reports "track-transition-single-hook-v041-raw-latest.csv"'),
 ('$Log = Join-Path $LogRoot ("track-transition-single-hook-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))','$Log = Join-Path $LogRoot ("track-transition-single-hook-v041-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))'),
]: s=replace1(s,a,b)
needle='$LatestCsv = Join-Path $Reports "track-transition-single-hook-v041-raw-latest.csv"\n'
s=replace1(s,needle,needle+'$ProgressJson = Join-Path $Reports "track-transition-single-hook-v041-progress.json"\n$ProgressCsv = Join-Path $Reports "track-transition-single-hook-v041-progress.csv"\n')
old='''    $clock.Stop()\n    if($events.Count -ne $NextOffsets.Count){throw "$Label did not emit all expected NEXT events: $($events.Count)/$($NextOffsets.Count)"}\n    Send-MediaKey "PlayPause";Start-Sleep -Seconds 2\n    return [pscustomobject]@{rows=$rows.ToArray();events=$events.ToArray()}\n}'''
new='''    $clock.Stop()\n    if($events.Count -ne $NextOffsets.Count){throw "$Label did not emit all expected NEXT events: $($events.Count)/$($NextOffsets.Count)"}\n    $rowArray=$rows.ToArray()\n    $minProcessCount=[int](($rowArray|Select-Object -ExpandProperty process_count|Measure-Object -Minimum).Minimum)\n    $endProcessCount=@(Get-Process Spotify -ErrorAction SilentlyContinue).Count\n    if($minProcessCount -lt 1 -or $endProcessCount -lt 1){throw "$Label lost all Spotify processes during the transition workload."}\n    Send-MediaKey "PlayPause";Start-Sleep -Seconds 2\n    return [pscustomobject]@{rows=$rowArray;events=$events.ToArray();min_spotify_process_count=$minProcessCount;end_spotify_process_count=$endProcessCount}\n}'''
s=replace1(s,old,new)
policy=r'''function Get-WorkloadPolicy {
    param([string]$Label,$Analysis)
    $strictBaseline=($Label -like 'BASELINE_*')
    $canary=[bool]$Analysis.workload_canary_pass
    $status=if($canary){'active-response'}elseif($strictBaseline){'baseline-invalid'}else{'low-response-accepted'}
    return [pscustomobject]@{accepted=($canary -or -not $strictBaseline);strict_baseline=$strictBaseline;status=$status}
}
function Write-ProgressCheckpoint {
    param([object[]]$Analyses,[object[]]$Mutations,[object[]]$Raw,[int]$VariantCount,[string]$CurrentLabel)
    if($Action -eq 'SelfTest' -or [string]::IsNullOrWhiteSpace([string]$script:Session)){return}
    $p=[pscustomobject]@{version=$Version;generated_at=(Get-Date).ToString('o');complete=($Analyses.Count -eq $VariantCount);current_label=$CurrentLabel;completed_condition_count=$Analyses.Count;variant_count=$VariantCount;conditions=$Analyses;variant_mutations=$Mutations;raw_sample_count=$Raw.Count;note='Partial checkpoint only. Final baseline-averaged ranking is produced only after BASELINE_B and exact restore.'}
    $j=Join-Path $script:Session 'track-transition-single-hook-v041-progress.json';$c=Join-Path $script:Session 'track-transition-single-hook-v041-progress.csv'
    $p|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $j -Encoding UTF8;if($Raw.Count -gt 0){$Raw|Export-Csv -LiteralPath $c -NoTypeInformation -Encoding UTF8};Copy-Item $j $ProgressJson -Force;if(Test-Path -LiteralPath $c){Copy-Item $c $ProgressCsv -Force}
}

'''
s=replace1(s,'function Average-TwoMetricSummaries {\n',policy+'function Average-TwoMetricSummaries {\n')
s=replace1(s,'        working_set_p95_saved_mb=[Math]::Round([double]$Baseline.working_set_mb.p95-[double]$Condition.metrics.working_set_mb.p95,1)\n    }','        working_set_p95_saved_mb=[Math]::Round([double]$Baseline.working_set_mb.p95-[double]$Condition.metrics.working_set_mb.p95,1)\n        workload_policy_status=[string]$Condition.workload_policy_status\n        active_transition_windows=[int]$Condition.active_transition_windows\n    }')
selfneedle="        $ev=@([pscustomobject]@{index=1;actual_seconds=5.0},[pscustomobject]@{index=2;actual_seconds=15.0});$a=Analyze-Transitions -Label 'SYNTH' -Rows $rows -Events $ev;if($a.transitions.Count-ne2 -or [double]$a.metrics.cpu_percent.max-ne10.0){throw 'Transition window extraction self-test failed.'}\n"
selfadd=selfneedle+"        $highPolicy=Get-WorkloadPolicy -Label 'BASELINE_A' -Analysis $a;if(-not $highPolicy.accepted){throw 'Active baseline workload policy self-test failed.'}\n        $lowRows=@();for($i=0;$i -le 80;$i++){$e=$i/4.0;$lowRows+=[pscustomobject]@{elapsed_seconds=$e;cpu_percent=0.4;main_cpu_percent=0.2;renderer_cpu_percent=0.2;gpu_cpu_percent=0;utility_cpu_percent=0;working_set_mb=100;renderer_working_set_mb=40;gpu_working_set_mb=10}}\n        $low=Analyze-Transitions -Label 'LOW' -Rows $lowRows -Events $ev;$singleLow=Get-WorkloadPolicy -Label 'SINGLE_DIRECT_TEST_OFF' -Analysis $low;$baselineLow=Get-WorkloadPolicy -Label 'BASELINE_B' -Analysis $low;if(-not $singleLow.accepted -or $singleLow.status -ne 'low-response-accepted' -or $baselineLow.accepted){throw 'Low-response workload policy self-test failed.'}\n"
s=replace1(s,selfneedle,selfadd)
s=replace1(s,'SELFTEST PASS: single-hook hook inventory/matrix, UTF-8 BOM+CRLF preservation, exact tree restore, failure injection, percentile/process/transition math.','SELFTEST PASS: single-hook inventory/matrix, low-response workload policy, UTF-8 BOM+CRLF preservation, exact tree restore, failure injection, percentile/process/transition math.')
old='''        $a=Analyze-Transitions -Label $v.label -Rows $m.rows -Events $m.events\n        if(-not $a.workload_canary_pass){throw "$($v.label) transition workload canary failed: only $($a.active_transition_windows)/5 windows reached 1.5% CPU. Playback/NEXT context may not be active."}\n        $analyses.Add($a)\n        Write-LabLog ("Completed {0}: CPU p95={1}% p99={2}% max={3}% renderer p95={4}%" -f $v.label,$a.metrics.cpu_percent.p95,$a.metrics.cpu_percent.p99,$a.metrics.cpu_percent.max,$a.metrics.renderer_cpu_percent.p95) 'OK'\n'''
new='''        $a=Analyze-Transitions -Label $v.label -Rows $m.rows -Events $m.events\n        $policy=Get-WorkloadPolicy -Label $v.label -Analysis $a\n        Add-Member -InputObject $a -NotePropertyName workload_policy_status -NotePropertyValue ([string]$policy.status) -Force;Add-Member -InputObject $a -NotePropertyName min_spotify_process_count -NotePropertyValue ([int]$m.min_spotify_process_count) -Force;Add-Member -InputObject $a -NotePropertyName end_spotify_process_count -NotePropertyValue ([int]$m.end_spotify_process_count) -Force\n        if(-not $policy.accepted){throw "$($v.label) baseline workload canary failed: only $($a.active_transition_windows)/5 windows reached 1.5% CPU."}\n        if(-not $a.workload_canary_pass){Write-LabLog ("{0} low transition response ({1}/5 windows >=1.5% CPU) retained as causal evidence; Spotify stayed alive and all five NEXT keys were emitted." -f $v.label,$a.active_transition_windows) 'WARN'}\n        $analyses.Add($a);Write-ProgressCheckpoint -Analyses $analyses.ToArray() -Mutations $mutations.ToArray() -Raw $raw.ToArray() -VariantCount $variantCount -CurrentLabel $v.label\n        Write-LabLog ("Completed {0}: CPU p95={1}% p99={2}% max={3}% renderer p95={4}% evidence={5}" -f $v.label,$a.metrics.cpu_percent.p95,$a.metrics.cpu_percent.p99,$a.metrics.cpu_percent.max,$a.metrics.renderer_cpu_percent.p95,$a.workload_policy_status) 'OK'\n'''
s=replace1(s,old,new)
s=s.replace("'track-transition-single-hook.json'","'track-transition-single-hook-v041.json'").replace("'track-transition-single-hook.txt'","'track-transition-single-hook-v041.txt'").replace("'track-transition-single-hook-raw.csv'","'track-transition-single-hook-v041-raw.csv'").replace('Join-Path $LogRoot "track-transition-single-hook-error.log"','Join-Path $LogRoot "track-transition-single-hook-v041-error.log"')
script=('\r\n'.join(s.split('\n'))).encode('utf-8-sig')
r=f['README.md'].decode('utf-8').replace('v0.4.0','v0.4.1').replace('track-transition-single-hook-latest','track-transition-single-hook-v041-latest').replace('track-transition-single-hook-raw-latest','track-transition-single-hook-v041-raw-latest').replace('track-transition-single-hook-error.log','track-transition-single-hook-v041-error.log')
r += '\r\n\r\nv0.4.1 workload-policy correction\r\n---------------------------------\r\nBASELINE_A/B keep the strict 4/5 >=1.5% CPU canary. Non-baseline low-response conditions are retained and flagged instead of being rejected, because low CPU may be the causal effect under test. Spotify process survival and all five NEXT injections remain mandatory. Progress JSON/CSV is checkpointed after every completed condition.\r\n'
cmd=f['RUN_TRACK_TRANSITION_ISOLATION.cmd'].decode('ascii').replace('v0.4.0','v0.4.1').replace('Do NOT rerun this package. Send the console output/error log for review.','Do NOT rerun this package. Send the console output/error log and v0.4.1 progress JSON for review.')
entries={'README.md':r.encode('utf-8'),'RUN_TRACK_TRANSITION_ISOLATION.cmd':cmd.encode('ascii'),'SELFTEST.cmd':f['SELFTEST.cmd'],'track-transition-isolation.ps1':script}
entries['SHA256SUMS.txt']=''.join(f'{sha(entries[n])}  {n}\r\n' for n in ['README.md','RUN_TRACK_TRANSITION_ISOLATION.cmd','SELFTEST.cmd','track-transition-isolation.ps1']).encode('ascii')
order=['README.md','RUN_TRACK_TRANSITION_ISOLATION.cmd','SELFTEST.cmd','SHA256SUMS.txt','track-transition-isolation.ps1']
out=io.BytesIO()
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_STORED) as z:
    for n in order:
        info=zipfile.ZipInfo(n,date_time=(2026,10,25,15,0,0));info.compress_type=zipfile.ZIP_STORED;info.create_system=0;z.writestr(info,entries[n])
raw=out.getvalue();Path(OUT).write_bytes(raw)
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
        h,n=line.split('  ',1);assert sha(z.read(n))==h
    for n in z.namelist():
        if n.lower().endswith(('.md','.cmd','.ps1','.txt')):
            b=z.read(n);assert not [i for i,x in enumerate(b) if x==13 and (i+1>=len(b) or b[i+1]!=10)];assert b'\t' not in b
shutil.rmtree('phase2-v041',ignore_errors=True);Path('phase2-v041').mkdir()
with zipfile.ZipFile(io.BytesIO(raw)) as z:z.extractall('phase2-v041')
print('PHASE2_V041_PACKAGE_PASS',len(raw),sha(raw))
print('PHASE2_V041_SCRIPT_PASS',len(script),sha(script))
