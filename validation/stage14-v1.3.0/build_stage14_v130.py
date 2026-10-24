from pathlib import Path
import hashlib, json, re, shutil, subprocess, sys, zipfile

def rep_once(text, old, new):
    c=text.count(old)
    assert c==1, (old,c)
    return text.replace(old,new,1)

# Rebuild the exact previously Windows-validated v1.2.1 package from its existing validation branch.
subprocess.check_call(['git','fetch','origin','refs/heads/validate/stage14-v1.2.1:refs/remotes/origin/validate/stage14-v1.2.1'])
wf=subprocess.check_output(['git','show','origin/validate/stage14-v1.2.1:.github/workflows/validate-stage14-v1.2.1.yml']).decode('utf-8')
marker="      - name: Rebuild trusted v1.2.0, derive v1.2.1, and validate stable manifest\n        shell: python\n        run: |\n"
end="\n      - name: Windows PowerShell 5.1 parser validation\n"
assert wf.count(marker)==1 and wf.count(end)==1
block=wf.split(marker,1)[1].split(end,1)[0]
lines=block.splitlines()
code='\n'.join(x[10:] if x.startswith('          ') else x for x in lines)+'\n'
assert "out=Path('stage14-v121')" in code
code=code.replace("out=Path('stage14-v121')","out=Path('stage14-v120-unpacked')",1)
exec(compile(code,'rebuild-stage14-v1.2.1.py','exec'),{'__name__':'__main__'})
base_zip=Path('SpotifyControl-Windows-Runtime-Acceptance-v1.2.1.zip')
base_raw=base_zip.read_bytes()
assert len(base_raw)==34841
assert hashlib.sha256(base_raw).hexdigest()=='962a09cd5adbcb4dd49046dd672b44252238f43859f5b97a4ce70f8492068fd8'

out=Path('stage14-v120-unpacked')
runp=out/'RUN_RUNTIME_ACCEPTANCE.ps1'
run=runp.read_text(encoding='utf-8-sig')
for old,new in [
("$AcceptanceVersion = '1.2.1'","$AcceptanceVersion = '1.3.0'"),
("$ExpectedMainSha = '4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f'","$ExpectedMainSha = '6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad'"),
("$ExpectedAddonSha = '56185d3b23c4b0df455673ad3f601d67c7980b7428f1d15b3e0465d1a7859022'","$ExpectedAddonSha = 'fb2bd974ee795bb697a0e5b534e03477be77b655e60353d82064b1e751bdc686'"),
("$ExpectedMainVersion = '0.6.15'","$ExpectedMainVersion = '0.6.16'"),
("$ExpectedAddonVersion = '0.6.5-r5'","$ExpectedAddonVersion = '0.6.5-r6'"),
("$ExpectedSourceCommit = '2f8377829ab61dcb88d265bdbd484181f084aef9'","$ExpectedSourceCommit = 'c97b6bae845c46730120b08821f8515cfa9ad199'"),
("$ExpectedPayloadSet = '86dbfea3b22c110a2a1425b0340bbf333329c51a5ae9253b0a45a955f0ae67dd'","$ExpectedPayloadSet = 'fbeffb5f594c3feeb621f50e391246bb035dd0fffce5300a575aa74883a7acfb'"),
("$BaselineMainSha = '5306acbe610b06f2c638ebbdc305db9741bbe145392933a38f648906acd302d1'","$BaselineMainSha = '4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f'"),
("$BaselineAddonSha = 'd6a11c73c561662579c9b28b59e9f2845563e8050eceeb8e5cec0f5f3618759a'","$BaselineAddonSha = '56185d3b23c4b0df455673ad3f601d67c7980b7428f1d15b3e0465d1a7859022'"),
("$BaselineMainVersion = '0.6.14'","$BaselineMainVersion = '0.6.15'"),
("$BaselineAddonVersion = '0.6.5-r4'","$BaselineAddonVersion = '0.6.5-r5'"),
("$Phase='self-update-v0615'","$Phase='self-update-v0616'"),
("[0/10] Trusted 0.6.14 -> 0.6.15 self-update rollback acceptance + fresh commit...","[0/10] Trusted 0.6.15 -> 0.6.16 self-update rollback acceptance + fresh commit..."),
("pre-v0615-code","pre-v0616-code"),
("Installed main/addon is neither exact v0.6.14/r4 baseline nor exact v0.6.15/r5 target.","Installed main/addon is neither exact v0.6.15/r5 baseline nor exact v0.6.16/r6 target."),
("Bootstrap Check did not resolve the exact 0.6.14 -> 0.6.15 edge.","Bootstrap Check did not resolve the exact 0.6.15 -> 0.6.16 edge."),
("Bootstrap Check v0.6.15 trust anchor mismatch.","Bootstrap Check v0.6.16 trust anchor mismatch."),
("v0.6.15 rollback acceptance did not report rolled-back.","v0.6.16 rollback acceptance did not report rolled-back."),
("v0.6.15 rollback acceptance did not restore exact v0.6.14/r4 baseline.","v0.6.16 rollback acceptance did not restore exact v0.6.15/r5 baseline."),
("Fresh v0.6.15 self-update did not commit.","Fresh v0.6.16 self-update did not commit."),
("v0.6.15 main SelfTest failed after commit.","v0.6.16 main SelfTest failed after commit."),
("Addon Manager r5 SelfTest failed after commit.","Addon Manager r6 SelfTest failed after commit."),
("Addon Manager r5 SelfTest did not prove the pending-aware schedule-bypass fixture.","Addon Manager r6 SelfTest did not prove the pending-aware schedule-bypass fixture."),
("Post-update bootstrap Check is not already-current v0.6.15.","Post-update bootstrap Check is not already-current v0.6.16."),
("resident recovery after v0.6.15 self-update","resident recovery after v0.6.16 self-update"),
("Self-update failure rollback did not restore exact v0.6.14/r4 baseline.","Self-update failure rollback did not restore exact v0.6.15/r5 baseline.")
]:
    run=rep_once(run,old,new)
assert run.count('Invoke-TrustedV0615SelfUpdateAcceptance')==2
run=run.replace('Invoke-TrustedV0615SelfUpdateAcceptance','Invoke-TrustedV0616SelfUpdateAcceptance')

needle="    if($addonTest.Output -notmatch 'Pending-aware schedule-bypass self-test passed'){throw 'Addon Manager r6 SelfTest did not prove the pending-aware schedule-bypass fixture.'}\n"
run=rep_once(run,needle,needle+
"    if($addonTest.Output -notmatch 'ivLyrics official-tag fallback gate self-test passed'){throw 'Addon Manager r6 SelfTest did not prove the exact historical missing-asset fallback gate.'}\n"
"    if($addonTest.Output -notmatch 'Commit-cycle self-test passed'){throw 'Addon Manager r6 SelfTest did not prove awaiting-apply -> CommitLast -> pending-zero.'}\n")
run=rep_once(run,
"'ivLyrics installed-only transaction self-test passed','Pending-aware schedule-bypass self-test passed','Get-DiscoveredActionableAutoUpdateCount'",
"'ivLyrics installed-only transaction self-test passed','ivLyrics official-tag fallback gate self-test passed','Commit-cycle self-test passed','Pending-aware schedule-bypass self-test passed','Get-DiscoveredActionableAutoUpdateCount'")
run=rep_once(run,
"    $addonSelf=Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','SelfTest');if($addonSelf.ExitCode -ne 0){throw \"Addon SelfTest failed. $($addonSelf.Output)\"}\n    Assert-ProductionRollbackBranches\n",
"    $addonSelf=Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','SelfTest');if($addonSelf.ExitCode -ne 0){throw \"Addon SelfTest failed. $($addonSelf.Output)\"}\n"
"    foreach($proof in @('ivLyrics official-tag fallback gate self-test passed','Commit-cycle self-test passed','Pending-aware schedule-bypass self-test passed')){if($addonSelf.Output -notmatch [regex]::Escape($proof)){throw (\"Addon r6 SelfTest is missing required proof: \"+$proof)}}\n"
"    $ivTagProof=Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','IvLyricsTagProofSelfTest')\n"
"    if($ivTagProof.ExitCode -ne 0 -or $ivTagProof.Output -notmatch 'ivLyrics official-tag online self-test passed'){throw \"ivLyrics official-tag online proof failed before mutation arm. exit=$($ivTagProof.ExitCode); output=$($ivTagProof.Output)\"}\n"
"    Assert-ProductionRollbackBranches\n")
runp.write_text(run,encoding='utf-8-sig',newline='\n')

readp=out/'README.txt'
readme=readp.read_text(encoding='utf-8')
readme=rep_once(readme,"Spotify Control Windows Runtime Acceptance v1.2.1","Spotify Control Windows Runtime Acceptance v1.3.0")
readme=rep_once(readme,
"It first accepts and commits the stable Spotify Control v0.6.15 / Addon Manager v0.6.5-r5\npending-aware schedule fix, then immediately runs the real hands-off Windows runtime acceptance.",
"It first accepts and commits the stable Spotify Control v0.6.16 / Addon Manager v0.6.5-r6\nivLyrics historical-tag trust-bootstrap fix, then immediately runs the real hands-off Windows runtime acceptance.")
oldwhy="""Why v1.2.1 exists
-----------------
Stage14 v1.2.0 stopped safely before the live mutation window because bootstrap 1.0.6
rejected two publication-format defects in the stable manifest: a duplicated 0.6.12 -> 0.6.13
edge, and a split r5 transport name that did not satisfy the required sequential chunk-005.txt
contract. Both defects were repaired in the update repository without changing the v0.6.15/r5
payload bytes or target hashes. The stable manifest now pins a source commit that contains the
canonical sequential transport. v1.2.1 keeps the validated v1.2.0 runtime logic and changes only
the acceptance-package version/trust pin needed to accept that repaired publication.
The r5 behavior itself is unchanged: fresh actionable pending may bypass only the 168-hour
schedule gate, and the acceptance never uses Force or current-app reinstall semantics.
"""
newwhy="""Why v1.3.0 exists
-----------------
Stage14 v1.2.1 reached the real unattended SpotifyExit maintenance window safely, but the
fresh post-maintenance check still reported addon-updates:1. Exact deployed-code reconstruction
showed this was a real recurring ivLyrics pending item, not stale report state. The installed
ivLyrics v6.1.18 release exists but contains no ivLyrics.zip / ivLyrics.zip.sha256 assets, while
r5 required those assets to prove the currently installed tree before any overwrite. That made
r5 correctly fail closed on every maintenance attempt, so the same pending update returned.

r6 keeps the strict release-asset proof for normal/current releases and adds a fallback only for
that exact historical missing-asset condition: the installed tree must match the official
v<installed-version> Git tag exactly by path, case, file count, size, and Git blob SHA. Extra,
missing, modified, symlink/submodule, ambiguous, network-error, or identity-error cases remain
blocked. r6 also adds the previously missing successful awaiting-apply -> CommitLast ->
fresh-pending-zero regression fixture. The acceptance still never uses Force or current-app
reinstall semantics; fresh actionable pending may bypass only the 168-hour schedule gate.
"""
readme=rep_once(readme,oldwhy,newwhy)
for old,new in [
("- Spotify Control target: 0.6.15","- Spotify Control target: 0.6.16"),
("- Addon Manager target: 0.6.5-r5","- Addon Manager target: 0.6.5-r6"),
("- Stable source commit: 2f8377829ab61dcb88d265bdbd484181f084aef9","- Stable source commit: c97b6bae845c46730120b08821f8515cfa9ad199"),
("- Stable payload set: 86dbfea3b22c110a2a1425b0340bbf333329c51a5ae9253b0a45a955f0ae67dd","- Stable payload set: fbeffb5f594c3feeb621f50e391246bb035dd0fffce5300a575aa74883a7acfb"),
("- Target main SHA-256: 4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f","- Target main SHA-256: 6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad"),
("- Target addon SHA-256: 56185d3b23c4b0df455673ad3f601d67c7980b7428f1d15b3e0465d1a7859022","- Target addon SHA-256: fb2bd974ee795bb697a0e5b534e03477be77b655e60353d82064b1e751bdc686"),
("0. Exact starting-state gate: accepts only exact v0.6.14/r4 or an exact already-updated v0.6.15/r5.","0. Exact starting-state gate: accepts only exact v0.6.15/r5 or an exact already-updated v0.6.16/r6."),
("2. Real 0.6.14 -> 0.6.15 RollbackTest and exact baseline restoration.","2. Real 0.6.15 -> 0.6.16 RollbackTest and exact baseline restoration."),
("3. Fresh trusted self-update commit + v0.6.15/r5 SelfTests + already-current trust check.","3. Fresh trusted self-update commit + v0.6.16/r6 SelfTests + already-current trust check."),
("4. Stage13 Critical=0 / High=0 and historical v0.6.14 ivLyrics repair verification.","4. Stage13 Critical=0 / High=0 and historical ivLyrics repair verification."),
("6. Fresh CheckOnly and installed-only ivLyrics actionability proof.","6. r6 official-tag online proof, then fresh CheckOnly and installed-only ivLyrics actionability proof."),
("10. If actionable pending exists while the 168-hour addon schedule is not due, the new r5\n    log must prove the pending-aware gate bypass occurred and explicitly did not use Force.","10. If actionable pending exists while the 168-hour addon schedule is not due, the r6\n    log must prove the pending-aware gate bypass occurred and explicitly did not use Force."),
("- Pending updates require unique resolution, accepted local safety, canonical GitHub SHA-256,\n  positive published asset size, and the installed-only transactional production path.","- Pending updates require unique resolution, accepted local safety, canonical latest-release\n  GitHub SHA-256/positive asset size, and the installed-only transactional production path.\n- For an asset-less historical installed release, baseline adoption is allowed only after an exact\n  official Git tag tree match; this does not weaken latest-release staging or auto-install policy.")
]:
    readme=rep_once(readme,old,new)
readp.write_text(readme,encoding='utf-8',newline='\n')

vp=out/'evidence'/'validate_stage14.py'
v=vp.read_text(encoding='utf-8')
for old,new in [
("expected={'main':'4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f','addon':'56185d3b23c4b0df455673ad3f601d67c7980b7428f1d15b3e0465d1a7859022','agent':'2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278','bootstrap':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'}","expected={'main':'6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad','addon':'fb2bd974ee795bb697a0e5b534e03477be77b655e60353d82064b1e751bdc686','agent':'2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278','bootstrap':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'}"),
("for n,v in [('main','0.6.15'),('addon','0.6.5-r5'),('agent','0.1.1'),('bootstrap','1.0.6')]:","for n,v in [('main','0.6.16'),('addon','0.6.5-r6'),('agent','0.1.1'),('bootstrap','1.0.6')]:"),
("ck('acceptance-version',\"$AcceptanceVersion = '1.2.1'\" in s)","ck('acceptance-version',\"$AcceptanceVersion = '1.3.0'\" in s)"),
("ck('target-source-commit','2f8377829ab61dcb88d265bdbd484181f084aef9' in s)","ck('target-source-commit','c97b6bae845c46730120b08821f8515cfa9ad199' in s)"),
("ck('target-payload-set','86dbfea3b22c110a2a1425b0340bbf333329c51a5ae9253b0a45a955f0ae67dd' in s)","ck('target-payload-set','fbeffb5f594c3feeb621f50e391246bb035dd0fffce5300a575aa74883a7acfb' in s)"),
("ck('baseline-main-sha','5306acbe610b06f2c638ebbdc305db9741bbe145392933a38f648906acd302d1' in s)","ck('baseline-main-sha','4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f' in s)"),
("ck('baseline-addon-sha','d6a11c73c561662579c9b28b59e9f2845563e8050eceeb8e5cec0f5f3618759a' in s)","ck('baseline-addon-sha','56185d3b23c4b0df455673ad3f601d67c7980b7428f1d15b3e0465d1a7859022' in s)"),
("'Invoke-TrustedV0615SelfUpdateAcceptance'","'Invoke-TrustedV0616SelfUpdateAcceptance'"),
("'phase':\"[0/10] Trusted 0.6.14 -> 0.6.15 self-update rollback acceptance + fresh commit\"","'phase':\"[0/10] Trusted 0.6.15 -> 0.6.16 self-update rollback acceptance + fresh commit\""),
("'post-current':'Post-update bootstrap Check is not already-current v0.6.15'","'post-current':'Post-update bootstrap Check is not already-current v0.6.16'"),
("'phase-boundary':\"Invoke-TrustedV0615SelfUpdateAcceptance\\n    $Phase='preflight'\"","'phase-boundary':\"Invoke-TrustedV0616SelfUpdateAcceptance\\n    $Phase='preflight'\""),
("'r5-selftest':'Pending-aware schedule-bypass self-test passed'","'r6-selftest':'Pending-aware schedule-bypass self-test passed'"),
("s.find('function Invoke-TrustedV0615SelfUpdateAcceptance')","s.find('function Invoke-TrustedV0616SelfUpdateAcceptance')"),
("ck('readme-v121','Runtime Acceptance v1.2.1' in readme)","ck('readme-v130','Runtime Acceptance v1.3.0' in readme)"),
("ck('readme-root-cause','168-hour' in readme and 'never uses Force' in readme)","ck('readme-root-cause','v6.1.18' in readme and 'no ivLyrics.zip / ivLyrics.zip.sha256 assets' in readme and '168-hour' in readme and 'never uses Force' in readme)"),
("f'STAGE14 V1.2.1 SELF VALIDATION: {passed}/{total} PASS'","f'STAGE14 V1.3.0 SELF VALIDATION: {passed}/{total} PASS'")
]:
    v=rep_once(v,old,new)
v=rep_once(v,"for n,patt in self_patterns.items():ck('self-update-'+n,patt in s,patt)\n",
"for n,patt in self_patterns.items():ck('self-update-'+n,patt in s,patt)\n"
"for n,patt in [('official-tag-fallback','ivLyrics official-tag fallback gate self-test passed'),('commit-cycle','Commit-cycle self-test passed'),('online-proof-action',\"@('-Action','IvLyricsTagProofSelfTest')\"),('online-proof-result','ivLyrics official-tag online self-test passed')]: ck('r6-'+n,patt in s,patt)\n")
v=rep_once(v,"'RollbackLast','ivLyrics installed-only transaction self-test passed','Pithaya transaction self-test passed']:",
"'RollbackLast','ivLyrics installed-only transaction self-test passed','ivLyrics official-tag fallback gate self-test passed','Commit-cycle self-test passed','ivLyrics official-tag online self-test passed','Pithaya transaction self-test passed']:")
vp.write_text(v,encoding='utf-8',newline='\n')

check=subprocess.run([sys.executable,'evidence/validate_stage14.py'],cwd=out,capture_output=True,text=True)
print(check.stdout)
print(check.stderr)
assert check.returncode==0
assert 'STAGE14 V1.3.0 SELF VALIDATION: 163/163 PASS' in check.stdout

rels=['PRECHECK_RUNTIME_ACCEPTANCE.ps1','README.txt','RUN_RUNTIME_ACCEPTANCE.cmd','RUN_RUNTIME_ACCEPTANCE.ps1','evidence/SELF_VALIDATION_REPORT.json','evidence/SELF_VALIDATION_REPORT.txt','evidence/VALIDATION_OUTPUT.txt','evidence/validate_stage14.py']
(out/'SHA256SUMS.txt').write_text('\n'.join(f"{hashlib.sha256((out/r).read_bytes()).hexdigest()}  {r}" for r in rels)+'\n',encoding='ascii',newline='\n')
with zipfile.ZipFile(base_zip) as zin: infos=zin.infolist()
final=Path('SpotifyControl-Windows-Runtime-Acceptance-v1.3.0.zip')
with zipfile.ZipFile(final,'w') as zout:
    for info in infos:
        ni=zipfile.ZipInfo(info.filename,date_time=info.date_time)
        ni.compress_type=info.compress_type; ni.comment=info.comment; ni.extra=info.extra
        ni.create_system=info.create_system; ni.create_version=info.create_version; ni.extract_version=info.extract_version
        ni.flag_bits=info.flag_bits; ni.external_attr=info.external_attr; ni.internal_attr=info.internal_attr; ni.volume=info.volume
        zout.writestr(ni,(out/info.filename).read_bytes(),compress_type=info.compress_type,compresslevel=6)
with zipfile.ZipFile(final) as z:
    assert z.testzip() is None
    for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
        digest,rel=line.split('  ',1); assert hashlib.sha256(z.read(rel)).hexdigest()==digest
print('V130_ZIP',final.stat().st_size,hashlib.sha256(final.read_bytes()).hexdigest())
