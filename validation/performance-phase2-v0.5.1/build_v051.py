from pathlib import Path
import hashlib,io,runpy,zipfile
R=Path.cwd(); BASE='SpotifyControl-Track-Transition-Direct-Patch-Acceptance-v0.5.0.zip'; OUT='SpotifyControl-Track-Transition-Direct-Patch-Acceptance-v0.5.1.zip'
def h(b): return hashlib.sha256(b).hexdigest()
def r1(s,a,b):
    assert s.count(a)==1,(a[:80],s.count(a)); return s.replace(a,b,1)
def body(s,n):
    a=s.index('function '+n+' {');b=s.find('\nfunction ',a+1)
    if b<0:b=s.find('\ntry{',a+1)
    assert b>a,n;return s[a:b].strip()
def rf(s,n,x):
    a=s.index('function '+n+' {');b=s.find('\nfunction ',a+1);assert b>a,n
    return s[:a]+x.rstrip()+'\n\n'+s[b+1:]
runpy.run_path('validation/performance-phase2-v0.5.0/build_and_validate.py',run_name='__main__')
raw=(R/BASE).read_bytes();assert len(raw)==90517 and h(raw)=='8bbd3465f99426b485d1a400aecd87b9ce7f75978f18b786b6b14d11727227c0'
with zipfile.ZipFile(io.BytesIO(raw)) as z:f={n:z.read(n) for n in z.namelist()}
old=f['track-transition-direct-patch-acceptance.ps1'];s=old.decode('utf-8-sig').replace('\r\n','\n')
helper=(R/'validation/performance-phase2-v0.5.1/runtime_alignment.ps1.inc').read_text(encoding='utf-8').replace('\r\n','\n').strip()
assert h((helper+'\n').encode())=='e73315d7b482479ac49538e05f3a38b0e8b9e8fb121fdefd7d1864cd3a898ae1'
s=r1(s,'$Version = "0.5.0"\n$AcceptedMainShas = @("45795b9622953a10c6eca2ee2f5a19fc4467c5143d5bdf7a9f2ad64841b9416f")\n$ExpectedAddonSha = "df17018bdb5f62f55624070d047933387f62c049dae73cf5cefcc541bc412afa"','$Version = "0.5.1"\n$ExpectedMainSha = "45795b9622953a10c6eca2ee2f5a19fc4467c5143d5bdf7a9f2ad64841b9416f"\n$ExpectedAddonSha = "df17018bdb5f62f55624070d047933387f62c049dae73cf5cefcc541bc412afa"\n$PreviousMainSha = "27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f"\n$PreviousAddonSha = "b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977"')
s=rf(s,'Assert-AcceptedRuntimeBaseline',helper)
s=r1(s,'$script:DirectPatchPreflight = $null\n','$script:DirectPatchPreflight = $null\n$script:ProductionAlignment = $null\n')
a="        Write-LabLog 'Residual Spotify processes closed before any xpui mutation.' 'OK'\n    }\n\n    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'"
b="        Write-LabLog 'Residual Spotify processes closed before any xpui mutation.' 'OK'\n    }\n    $script:ProductionAlignment=Align-ReleasedProductionBaseline -Accepted $accepted\n\n    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'";s=r1(s,a,b)
s=r1(s,"version=$Version;generated_at=(Get-Date).ToString('o');verified_run=$true;accepted_baseline=$accepted;preflight_spotify_processes_autoclosed=$preflightSpotifyCount;","version=$Version;generated_at=(Get-Date).ToString('o');verified_run=$true;accepted_baseline=$accepted;production_alignment=$script:ProductionAlignment;production_alignment_precedes_snapshot=$true;preflight_spotify_processes_autoclosed=$preflightSpotifyCount;")
a='    $focused=@(Build-FocusedPatchVariantMatrix)\n';b="    $cur=[pscustomobject]@{main=$ExpectedMainSha;addon=$ExpectedAddonSha;agent=$ExpectedAgentSha;bootstrap=$ExpectedBootstrapSha}\n    $prev=[pscustomobject]@{main=$PreviousMainSha;addon=$PreviousAddonSha;agent=$ExpectedAgentSha;bootstrap=$ExpectedBootstrapSha}\n    $bad=[pscustomobject]@{main='bad';addon=$ExpectedAddonSha;agent=$ExpectedAgentSha;bootstrap=$ExpectedBootstrapSha}\n    if((Get-ComponentBaselineKind $cur) -ne 'current-v0619-r8' -or (Get-ComponentBaselineKind $prev) -ne 'previous-v0618-r7' -or (Get-ComponentBaselineKind $bad) -ne 'unknown-or-partial'){throw 'Production component baseline classifier self-test failed.'}\n"+a;s=r1(s,a,b)
s=s.replace('v0.5.0','v0.5.1').replace('v050','v051');script=('\r\n'.join(s.split('\n'))).encode('utf-8-sig')
assert len(script)==77641 and h(script)=='065bf91e4ea2928b38877da2f9b9ca0d1cd1505375ff8514bac6a2b70265370f'
o=old.decode('utf-8-sig').replace('\r\n','\n');n=script.decode('utf-8-sig').replace('\r\n','\n')
for fn in ['Get-TreeFingerprint','Backup-ProtectedPersistence','Stop-SpotifyForVariant','Suspend-Resident','Restore-Resident','Send-MediaKey','Wait-SpotifyReady','Get-ProcessRoleFromCommandLine','Measure-TransitionCondition','Analyze-Transitions','Get-WorkloadPolicy','Average-TwoMetricSummaries','Build-Comparison','Assert-DirectPatchEligibility','Invoke-DirectPatchEngine','Restore-DirectPatches','Prepare-Variant','Build-FocusedPatchVariantMatrix']:
    assert body(o,fn)==body(n,fn),fn
assert h(f['apply-direct-extension-patches.ps1'])=='486254bc032bbcb2380f69ba01470bb2bda2e23718cc7bbaef1063fdb18c1803'
assert h(f['targets.json'])=='9b49d43bb8ff568f9e1a4f7009e2958edce0f77b857d948e563b81bb514aefa3'
rd=f['README.md'].decode().replace('v0.5.0','v0.5.1').replace('v050','v051')+'\r\n\r\nv0.5.1 self-healing preflight: exact previous production is aligned to released current production only after resident/Spotify suspension; unknown/partial identities fail closed with detailed hashes. Released Addon Manager r8 alignment precedes the measurement snapshot.\r\n'
cmd=f['RUN_TRACK_TRANSITION_DIRECT_PATCH_ACCEPTANCE.cmd'].decode('ascii').replace('v0.5.0','v0.5.1').replace('v050','v051')
e={'README.md':rd.encode(),'RUN_TRACK_TRANSITION_DIRECT_PATCH_ACCEPTANCE.cmd':cmd.encode('ascii'),'SELFTEST.cmd':f['SELFTEST.cmd'],'apply-direct-extension-patches.ps1':f['apply-direct-extension-patches.ps1'],'targets.json':f['targets.json'],'track-transition-direct-patch-acceptance.ps1':script}
co=['README.md','RUN_TRACK_TRANSITION_DIRECT_PATCH_ACCEPTANCE.cmd','SELFTEST.cmd','apply-direct-extension-patches.ps1','targets.json','track-transition-direct-patch-acceptance.ps1'];e['SHA256SUMS.txt']=''.join(f'{h(e[x])}  {x}\r\n' for x in co).encode('ascii');order=['README.md','RUN_TRACK_TRANSITION_DIRECT_PATCH_ACCEPTANCE.cmd','SELFTEST.cmd','SHA256SUMS.txt','apply-direct-extension-patches.ps1','targets.json','track-transition-direct-patch-acceptance.ps1']
b=io.BytesIO()
with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_STORED) as z:
    for x in order:
        i=zipfile.ZipInfo(x,date_time=(2026,10,26,0,30,0));i.compress_type=zipfile.ZIP_STORED;i.create_system=0;z.writestr(i,e[x])
out=b.getvalue();(R/OUT).write_bytes(out);assert len(out)==97951 and h(out)=='21cbd979a66ee10e7a65617ea8a6c46cdcc9dfdfe501926e8a5aa038450d9689'
print('PHASE2_V051_PACKAGE_PASS',len(out),h(out));print('PHASE2_V051_SCRIPT_PASS',len(script),h(script))
