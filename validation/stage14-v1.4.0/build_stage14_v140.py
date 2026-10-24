from pathlib import Path
import subprocess, hashlib, zipfile, shutil, json, re, os

def one(s,a,b):
    assert s.count(a)==1,(a,s.count(a)); return s.replace(a,b,1)

# Reuse v1.3 builder only as a deterministic bridge from already-validated v1.2.1.
# Fix its path-only reconstruction bug; then derive v1.4 from the resulting r6 candidate.
subprocess.check_call(['git','fetch','origin','refs/heads/validate/stage14-v1.3.0:refs/remotes/origin/validate/stage14-v1.3.0'])
v130=subprocess.check_output(['git','show','origin/validate/stage14-v1.3.0:validation/stage14-v1.3.0/build_stage14_v130.py']).decode('utf-8')
v130=v130.replace("code=code.replace(\"out=Path('stage14-v121')\",\"out=Path('stage14-v120-unpacked')\",1)\n",'')
v130=v130.replace("out=Path('stage14-v120-unpacked')","out=Path('stage14-v121')")
exec(compile(v130,'fixed-build-stage14-v130.py','exec'),{'__name__':'__main__'})
base=Path('SpotifyControl-Windows-Runtime-Acceptance-v1.3.0.zip')
assert base.is_file()
out=Path('stage14-v121'); assert out.is_dir()
runp=out/'RUN_RUNTIME_ACCEPTANCE.ps1'; run=runp.read_text(encoding='utf-8-sig')
for a,b in [
("$AcceptanceVersion = '1.3.0'","$AcceptanceVersion = '1.4.0'"),
("$ExpectedMainSha = '6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad'","$ExpectedMainSha = '5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'"),
("$ExpectedAddonSha = 'fb2bd974ee795bb697a0e5b534e03477be77b655e60353d82064b1e751bdc686'","$ExpectedAddonSha = 'b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'"),
("$ExpectedMainVersion = '0.6.16'","$ExpectedMainVersion = '0.6.17'"),
("$ExpectedAddonVersion = '0.6.5-r6'","$ExpectedAddonVersion = '0.6.5-r7'"),
("$ExpectedSourceCommit = 'c97b6bae845c46730120b08821f8515cfa9ad199'","$ExpectedSourceCommit = 'e51f73c90c50cb55e3e3dffe3b55a6f6b1af0b4c'"),
("$ExpectedPayloadSet = 'fbeffb5f594c3feeb621f50e391246bb035dd0fffce5300a575aa74883a7acfb'","$ExpectedPayloadSet = '0f7fe384630e027466aa734ac669b410774b4569db231982212b7fa565b691a0'"),
("$Phase='self-update-v0616'","$Phase='self-update-v0617'"),
("[0/10] Trusted 0.6.15 -> 0.6.16 self-update rollback acceptance + fresh commit...","[0/10] Trusted 0.6.15 -> 0.6.16 -> 0.6.17 chained self-update rollback acceptance + fresh commit..."),
("pre-v0616-code","pre-v0617-code"),
("exact v0.6.15/r5 baseline nor exact v0.6.16/r6 target","exact v0.6.15/r5 baseline nor exact v0.6.17/r7 target"),
("Bootstrap Check did not resolve the exact 0.6.15 -> 0.6.16 edge.","Bootstrap Check did not resolve the exact trusted 0.6.15 -> 0.6.16 -> 0.6.17 chain."),
("Bootstrap Check v0.6.16 trust anchor mismatch.","Bootstrap Check v0.6.17 trust anchor mismatch."),
("v0.6.16 rollback acceptance did not report rolled-back.","v0.6.17 chain rollback acceptance did not report rolled-back."),
("v0.6.16 rollback acceptance did not restore exact v0.6.15/r5 baseline.","v0.6.17 chain rollback acceptance did not restore exact v0.6.15/r5 baseline."),
("Fresh v0.6.16 self-update did not commit.","Fresh v0.6.17 chained self-update did not commit."),
("v0.6.16 main SelfTest failed after commit.","v0.6.17 main SelfTest failed after commit."),
("Addon Manager r6 SelfTest failed after commit.","Addon Manager r7 SelfTest failed after commit."),
("Post-update bootstrap Check is not already-current v0.6.16.","Post-update bootstrap Check is not already-current v0.6.17."),
("resident recovery after v0.6.16 self-update","resident recovery after v0.6.17 chained self-update"),
("Invoke-TrustedV0616SelfUpdateAcceptance","Invoke-TrustedV0617SelfUpdateAcceptance"),
("Self-update v0.6.16/r6:","Self-update v0.6.17/r7:"),
]: run=one(run,a,b)
run=one(run,'[int]$check.result.edge_count -ne 1','[int]$check.result.edge_count -ne 2')
anchor="$RepairPayloadSet = '7a57bc6970ca4f328fd8a417380421f6094c911008b46c2ef407c9cc2ee28879'\n"
run=one(run,anchor,anchor+"$RepairMainVersion = '0.6.14'\n$RepairMainSha = '5306acbe610b06f2c638ebbdc305db9741bbe145392933a38f648906acd302d1'\n$RepairAddonSha = 'd6a11c73c561662579c9b28b59e9f2845563e8050eceeb8e5cec0f5f3618759a'\n")
run=one(run,"[string]$r.spotify_control_after -cne $BaselineMainVersion","[string]$r.spotify_control_after -cne $RepairMainVersion")
run=one(run,"[string]$r.main_sha256 -cne $BaselineMainSha -or [string]$r.addon_sha256 -cne $BaselineAddonSha","[string]$r.main_sha256 -cne $RepairMainSha -or [string]$r.addon_sha256 -cne $RepairAddonSha")
needle="    if($addonTest.Output -notmatch 'Commit-cycle self-test passed'){throw 'Addon Manager r6 SelfTest did not prove awaiting-apply -> CommitLast -> pending-zero.'}\n"
run=one(run,needle,needle+"    if($addonTest.Output -notmatch 'ivLyrics unproven-current fallback self-test passed'){throw 'Addon Manager r7 SelfTest did not prove unproven legacy monitor fallback.'}\n")
run=run.replace('Addon Manager r6 SelfTest did not prove','Addon Manager r7 SelfTest did not prove')
needle="    foreach($proof in @('ivLyrics official-tag fallback gate self-test passed','Commit-cycle self-test passed','Pending-aware schedule-bypass self-test passed')){if($addonSelf.Output -notmatch [regex]::Escape($proof)){throw (\"Addon r6 SelfTest is missing required proof: \"+$proof)}}\n"
run=one(run,needle,"    foreach($proof in @('ivLyrics official-tag fallback gate self-test passed','ivLyrics unproven-current fallback self-test passed','Commit-cycle self-test passed','Pending-aware schedule-bypass self-test passed')){if($addonSelf.Output -notmatch [regex]::Escape($proof)){throw (\"Addon r7 SelfTest is missing required proof: \"+$proof)}}\n")
old="""    if([string]$ivRow.status -ceq 'update-available'){
        if([string]$ivRow.local_safety -notin @('trusted-baseline','release-proof-required')){throw ('Installed ivLyrics update lacks accepted transactional safety: '+[string]$ivRow.local_safety)}
        if(([string]$ivRow.digest).ToLowerInvariant() -notmatch '^sha256:[0-9a-f]{64}$' -or [int64]$ivRow.asset_size -le 0){throw 'Installed ivLyrics update lacks canonical published digest/asset-size proof.'}
    }
"""
new=old.replace("    }\n","    } elseif([string]$ivRow.status -ceq 'monitor-update-available-unproven'){\n        if([string]$ivRow.local_safety -cne 'monitor-unproven-baseline'){throw ('Unproven legacy ivLyrics monitor state has unexpected safety classification: '+[string]$ivRow.local_safety)}\n        if([string]::IsNullOrWhiteSpace([string]$ivRow.proof_error)){throw 'Unproven legacy ivLyrics monitor state is missing proof_error evidence.'}\n        if(([string]$ivRow.digest).ToLowerInvariant() -notmatch '^sha256:[0-9a-f]{64}$' -or [int64]$ivRow.asset_size -le 0){throw 'Unproven legacy ivLyrics monitor state lacks latest-release digest/size evidence.'}\n    }\n",1)
run=one(run,old,new)
oldpat="'ivLyrics installed-only transaction self-test passed','ivLyrics official-tag fallback gate self-test passed','Commit-cycle self-test passed','Pending-aware schedule-bypass self-test passed','Get-DiscoveredActionableAutoUpdateCount'"
newpat="'ivLyrics installed-only transaction self-test passed','ivLyrics official-tag fallback gate self-test passed','ivLyrics unproven-current fallback self-test passed','Commit-cycle self-test passed','Pending-aware schedule-bypass self-test passed','Get-DiscoveredActionableAutoUpdateCount','monitor-update-available-unproven','monitor-unproven-baseline'"
run=one(run,oldpat,newpat)
run=run.replace("Write-Host 'ivLyrics installed-only:    VERIFIED / transactional'","Write-Host 'ivLyrics installed-only:    VERIFIED / transactional-or-monitor-preserve'")
runp.write_text(run,encoding='utf-8-sig',newline='\n')

readme='''Spotify Control Windows Runtime Acceptance v1.4.0\n=================================================\n\nOne-shot final Stage14 acceptance for exact v0.6.15/r5 baseline. Bootstrap 1.0.6 must resolve and rollback-test the exact two-edge 0.6.15 -> 0.6.16 -> 0.6.17 chain, then commit exact v0.6.17 / Addon Manager r7.\n\nRoot cause fixed before this package: installed ivLyrics v6.1.18 has no historical release zip/checksum assets. r7 proves an exact legacy install against the immutable official Git tag before transactional update; if that exact proof fails, the install is preserved and reported monitor-update-available-unproven / monitor-unproven-baseline rather than falsely actionable. Absent ivLyrics is never auto-installed. Force/current-app reinstall semantics remain disabled.\n\nTrusted target:\n- main 0.6.17 SHA-256 5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b\n- addon 0.6.5-r7 SHA-256 b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977\n- source commit e51f73c90c50cb55e3e3dffe3b55a6f6b1af0b4c\n- payload set 0f7fe384630e027466aa734ac669b410774b4569db231982212b7fa565b691a0\n- agent 0.1.1 and Bootstrap 1.0.6 unchanged.\n\nBefore mutation arm this package requires r7 built-in fallback/monitor/commit-cycle tests plus the online official-tag proof. It preserves Spotify/Spicetify/WebView/Marketplace/ratings/Tagify state and never deletes ivLyrics. On any failure it repairs nonterminal transactions and restores the pre-run resident mutation-gate value.\n\nRun: fully close Spotify, extract to a new folder, run RUN_RUNTIME_ACCEPTANCE.cmd as normal user (not Administrator), and do not interact with Spotify while it opens/closes automatically.\n\nSuccess marker: WINDOWS RUNTIME ACCEPTANCE VERIFIED\nFailure report: %LOCALAPPDATA%\\SpotifyControl\\reports\\runtime-acceptance-failure-latest.txt\n'''
(out/'README.txt').write_text(readme,encoding='utf-8',newline='\n')
validator=out/'evidence'/'validate_stage14.py'
validator.write_text('''from pathlib import Path\nimport hashlib,re,json,sys\nr=Path(__file__).resolve().parents[1]; s=(r/'RUN_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig'); checks=[]\ndef c(n,x): checks.append((n,bool(x)))\nneed=["$AcceptanceVersion = '1.4.0'","$ExpectedMainVersion = '0.6.17'","$ExpectedAddonVersion = '0.6.5-r7'",'5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b','b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977','e51f73c90c50cb55e3e3dffe3b55a6f6b1af0b4c','0f7fe384630e027466aa734ac669b410774b4569db231982212b7fa565b691a0','[int]$check.result.edge_count -ne 2','ivLyrics official-tag fallback gate self-test passed','ivLyrics unproven-current fallback self-test passed','Commit-cycle self-test passed','IvLyricsTagProofSelfTest','monitor-update-available-unproven','monitor-unproven-baseline','agent_mutation_enabled=$OriginalMutationEnabled','check-only-running','maintenance-closed']\nfor x in need:c('contains:'+x,x in s)\nfor f in ['RUN_RUNTIME_ACCEPTANCE.ps1','RUN_RUNTIME_ACCEPTANCE.cmd','PRECHECK_RUNTIME_ACCEPTANCE.ps1','README.txt']:c('exists:'+f,(r/f).is_file())\nc('no-stale-v0616','Invoke-TrustedV0616SelfUpdateAcceptance' not in s);c('has-v0617','Invoke-TrustedV0617SelfUpdateAcceptance' in s);c('no-runas','RunAs' not in s)\nn=re.findall(r'(?im)^function\\s+([A-Za-z0-9_-]+)',s);c('no-dup-functions',len(n)==len(set(x.lower() for x in n)))\np=sum(v for _,v in checks); o={'passed':p,'total':len(checks),'script_sha256':hashlib.sha256((r/'RUN_RUNTIME_ACCEPTANCE.ps1').read_bytes()).hexdigest(),'checks':checks};(r/'evidence'/'SELF_VALIDATION_REPORT.json').write_text(json.dumps(o,indent=2),encoding='utf-8');(r/'evidence'/'SELF_VALIDATION_REPORT.txt').write_text(f"STAGE14 V1.4.0 SELF VALIDATION: {p}/{len(checks)} {'PASS' if p==len(checks) else 'FAIL'}\\nScript SHA256: {o['script_sha256']}\\n"+''.join(f"{'PASS' if v else 'FAIL'}: {n}\\n" for n,v in checks),encoding='utf-8');print(f"STAGE14 V1.4.0 SELF VALIDATION: {p}/{len(checks)} {'PASS' if p==len(checks) else 'FAIL'}");sys.exit(0 if p==len(checks) else 1)\n''',encoding='utf-8',newline='\n')
for p in [out/'evidence'/'SELF_VALIDATION_REPORT.json',out/'evidence'/'SELF_VALIDATION_REPORT.txt',out/'evidence'/'VALIDATION_OUTPUT.txt']:
    if p.exists(): p.unlink()
rels=['RUN_RUNTIME_ACCEPTANCE.ps1','RUN_RUNTIME_ACCEPTANCE.cmd','PRECHECK_RUNTIME_ACCEPTANCE.ps1','README.txt','evidence/validate_stage14.py']
(out/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256((out/x).read_bytes()).hexdigest()+'  '+x+'\n' for x in rels),encoding='ascii')
res=subprocess.run(['python',str(validator)],text=True,capture_output=True); (out/'evidence'/'VALIDATION_OUTPUT.txt').write_text(res.stdout+res.stderr,encoding='utf-8'); assert res.returncode==0,res.stdout+res.stderr
final=Path('SpotifyControl-Windows-Runtime-Acceptance-v1.4.0.zip')
if final.exists():final.unlink()
with zipfile.ZipFile(final,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(out.rglob('*')):
        if p.is_file(): z.write(p,p.relative_to(out).as_posix())
print('V140_ZIP',final.stat().st_size,hashlib.sha256(final.read_bytes()).hexdigest())
print('V140_SCRIPT',hashlib.sha256(runp.read_bytes()).hexdigest())
