from pathlib import Path
import argparse, base64, gzip, hashlib, io, json, re, shutil, subprocess, sys, zipfile

STAGE14_OUTER=(23600,'190a792e6f6cb09daebcc1dbd4d99213daf80110e7f06b133df460aa282b2019')
STAGE14_INNER=(23382,'390303445b9d0f9218320bb5bc50ae5008987067bbf7661099112440c09bf5f4')
BOOT_OUTER=(31098,'5e4f30a2aeab4936840a8ac0d935120cf704b8fc586f57d19d67ed82b8b867ec')
BOOT_INNER=(30856,'6b6d5d9e8ac44fc77bb95918164a3c862f14494c329fdfd267bd95f6c6ddcf06')
BOOT=(42963,'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6')
RELEASE_HEAD='5eac4f39920b84f22e2a5ee07422f6080bfc7ef7'
SOURCE='9a90d5f13eb63023d8f965a004be14d309d99429'
PAYLOAD='7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55'
BASE_MAIN=(281585,'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18')
BASE_ADDON=(225044,'3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86')
TARGET_MAIN=(281579,'f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828')
TARGET_ADDON=(250616,'7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2')
AGENT=(4855,'2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278')
DEFAULT_URL='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
RELEASE_URL=f'https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/{RELEASE_HEAD}/manifest.json'
FINAL='SpotifyControl-v0.6.21-Runtime-Acceptance-v0.1.0.zip'
HELPERS=['ConvertTo-NativeQuotedArgument','Invoke-Capture','Invoke-PowerShellScript','Get-AgentProcesses','Stop-AgentProcesses','Get-AgentTask','Get-ComCollectionItems','Start-AgentTask','Stop-AgentTask','Get-AgentTaskEvidence','Wait-Until','Test-SpotifyRunning','Stop-SpotifyProcesses','Backup-IfPresent','Get-StringSha','Get-TreeFingerprint','Snapshot-Equal','Assert-SpotifyPersistencePresent','Get-SpotifyWebPersistenceStructure','Assert-WebStructurePreserved','Copy-DirectoryContents','Get-TransactionStatus','Test-TerminalTransactionStatus','Assert-NoUnresolvedLiveTransactions']

def sha(b): return hashlib.sha256(b).hexdigest()
def ident(b,spec,label):
    assert len(b)==spec[0] and sha(b)==spec[1],(label,len(b),sha(b),spec)
def single(raw,name=None):
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        assert z.testzip() is None
        names=z.namelist(); assert (names==[name] if name else len(names)==1),names
        return z.read(name or names[0])
def func(text,name):
    m=re.search(rf'(?m)^function\s+{re.escape(name)}(?:\s*\([^\n]*\))?\s*\{{',text); assert m,name
    n=re.search(r'(?m)^function\s+[A-Za-z0-9_-]+',text[m.end():]); end=m.end()+n.start() if n else len(text)
    return text[m.start():end].rstrip().replace('\r\n','\n')
def fixed_zip(root,out):
    if out.exists(): out.unlink()
    with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(x for x in root.rglob('*') if x.is_file()):
            info=zipfile.ZipInfo(p.relative_to(root).as_posix(),date_time=(2026,10,26,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; info.external_attr=0o100644<<16
            z.writestr(info,p.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
    with zipfile.ZipFile(out) as z: assert z.testzip() is None

def precheck_bytes():
    s=r'''$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
$sum=Join-Path $Root 'SHA256SUMS.txt'
if(-not(Test-Path -LiteralPath $sum -PathType Leaf)){Write-Host 'SHA256SUMS.txt is missing.' -ForegroundColor Red;exit 2}
foreach($line in @(Get-Content -LiteralPath $sum)){if([string]::IsNullOrWhiteSpace($line)){continue};$parts=$line -split '  ',2;if($parts.Count -ne 2){exit 2};$p=Join-Path $Root $parts[1];if(-not(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -cne $parts[0]){Write-Host ('Package hash verification failed: '+$parts[1]) -ForegroundColor Red;exit 2}}
foreach($rel in @('RUN_RUNTIME_ACCEPTANCE.ps1','bootstrap\spotify-control-self-updater-v0621-acceptance.ps1')){$p=Join-Path $Root $rel;$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)|Out-Null;if(@($errors).Count){foreach($e in @($errors)){Write-Host ('line {0}: {1}' -f $e.Extent.StartLineNumber,$e.Message) -ForegroundColor Red};exit 2}}
& (Join-Path $Root 'RUN_RUNTIME_ACCEPTANCE.ps1')
exit $LASTEXITCODE
'''
    return s.replace('\n','\r\n').encode('utf-8-sig')

def readme_bytes(patched_sha,manifest_sha):
    s=f'''Spotify Control v0.6.21 / Addon Manager r10 Runtime Acceptance v0.1.0
=======================================================================

One-shot hands-off acceptance for exact production v0.6.20/r9. It temporarily verifies exact draft PR #52 head {RELEASE_HEAD} as v0.6.21/r10 and ALWAYS restores exact v0.6.20/r9 before success.

Before running: fully close Spotify; extract this ZIP; run RUN_RUNTIME_ACCEPTANCE.cmd normally (not Administrator). The acceptance never launches Spotify.

Protected: ivLyrics (never deleted/auto-installed), Tagify ratings/tags/notes, Star Ratings playlist-backed ratings, Splitify, Marketplace assets, SC Cover Ambience, Spicetify config, Spotify Users/Browser/Default/WebStorage persistence.

Pinned target: main {TARGET_MAIN[0]} / {TARGET_MAIN[1]}; Addon r10 {TARGET_ADDON[0]} / {TARGET_ADDON[1]}; source {SOURCE}; payload {PAYLOAD}. Bootstrap 1.0.6 remains installed unchanged. Packaged execution Bootstrap SHA-256 {patched_sha}; bundled manifest SHA-256 {manifest_sha}.

Flow: exact preflight -> resident stop -> Bootstrap SelfTest/Check/RollbackTest -> temporary Update -> target main/r10 SelfTests -> Addon r10 read-only Check/registry proof -> protected-state proof -> Bootstrap Rollback -Force -> exact control-state/report restore -> acceptance-only backup cleanup -> one resident restored.

Success: WINDOWS V0.6.21 RUNTIME ACCEPTANCE VERIFIED / BASELINE RESTORED
Success report: %LOCALAPPDATA%\SpotifyControl\reports\v0621-runtime-acceptance-latest.json
Failure report: %LOCALAPPDATA%\SpotifyControl\reports\v0621-runtime-acceptance-failure-latest.txt
'''
    return s.replace('\n','\r\n').encode('utf-8')

def validator_text():
    return f'''from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
c=[]
def ck(n,x):c.append((n,bool(x)));assert x,n
for line in (r/'SHA256SUMS.txt').read_text().splitlines():
 x,p=line.split('  ',1);ck('sum '+p,h(r/p)==x)
s=(r/'RUN_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig');b=(r/'bootstrap/spotify-control-self-updater-v0621-acceptance.ps1').read_text(encoding='utf-8-sig');m=json.loads((r/'release/manifest.json').read_text(encoding='utf-8-sig'))
ck('release','{RELEASE_HEAD}' in s and '{RELEASE_URL}' in s);ck('baseline','{BASE_MAIN[1]}' in s and '{BASE_ADDON[1]}' in s);ck('target','{TARGET_MAIN[1]}' in s and '{TARGET_ADDON[1]}' in s);ck('manifest',m['latest_version']=='0.6.21' and m['source_commit']=='{SOURCE}' and m['payload_set_sha256']=='{PAYLOAD}');ck('bootstrap pin',b.count('{RELEASE_URL}')==1 and '{DEFAULT_URL}' not in b);ck('restore marker','WINDOWS V0.6.21 RUNTIME ACCEPTANCE VERIFIED / BASELINE RESTORED' in s);ck('no launch','Start-Spotify' not in s and 'spotify.exe' not in s.lower());ck('no media keys',all(x not in s for x in ['keybd_event','SpotifyControlMediaKeys','Send-MediaKey','0xB0','0xB3']));ck('no addon mutation','Update-AutoApps' not in s and "Invoke-PowerShellScript $Addon @('-Action','Update')" not in s);ck('protected',all(x in s for x in ['ivLyrics','tagify','splitify','star-ratings','sc-cover-ambience.js','playlist-maker']));ck('rollback',"Invoke-AcceptanceBootstrap 'Rollback' -Force" in s and 'Restore-BinFromAcceptanceBackup' in s);ck('stage14 provenance','fb1666d8a1add725b476d31ed4650bfc162bad08' in s)
o={{'schema':1,'passed':sum(v for _,v in c),'total':len(c),'checks':[{{'name':n,'pass':v}} for n,v in c],'runtime_sha256':h(r/'RUN_RUNTIME_ACCEPTANCE.ps1')}};(r/'evidence/SELF_VALIDATION_REPORT.json').write_text(json.dumps(o,indent=2)+'\n');print('V0621_RUNTIME_ACCEPTANCE_SELF_VALIDATION_PASS',o['passed'],o['total'],o['runtime_sha256'])
'''

def build(stage14,carrier,manifest_path,template_path,outdir):
    so=stage14.read_bytes(); ident(so,STAGE14_OUTER,'stage14 outer'); si=single(so,'SpotifyControl-Windows-Runtime-Acceptance-v1.4.1.zip'); ident(si,STAGE14_INNER,'stage14 inner')
    with zipfile.ZipFile(io.BytesIO(si)) as z: oldrun=z.read('RUN_RUNTIME_ACCEPTANCE.ps1').decode('utf-8-sig')
    bo=carrier.read_bytes(); ident(bo,BOOT_OUTER,'bootstrap outer'); bi=single(bo); ident(bi,BOOT_INNER,'bootstrap inner')
    with zipfile.ZipFile(io.BytesIO(bi)) as z: boot=z.read('bootstrap/spotify-control-self-updater.ps1')
    ident(boot,BOOT,'bootstrap script'); old=DEFAULT_URL.encode('ascii'); new=RELEASE_URL.encode('ascii'); assert boot.count(old)==1 and new not in boot; patched=boot.replace(old,new,1); assert patched.replace(new,old,1)==boot
    manifest=manifest_path.read_bytes(); m=json.loads(manifest.decode('utf-8-sig')); assert m['latest_version']=='0.6.21' and m['source_commit']==SOURCE and m['payload_set_sha256']==PAYLOAD; edge=[e for e in m['updates'] if e['from_version']=='0.6.20' and e['to_version']=='0.6.21']; assert len(edge)==1 and len(edge[0]['patches'])==2
    template=gzip.decompress(base64.b64decode(template_path.read_text(encoding='ascii'))).decode('utf-8-sig').replace('\r\n','\n')
    for h in HELPERS: assert func(oldrun,h) in template,('Stage14 helper provenance mismatch',h)
    run=template.replace('@@MANIFEST_SHA@@',sha(manifest)).replace('@@MANIFEST_SIZE@@',str(len(manifest))); assert '@@' not in run
    runb=run.replace('\n','\r\n').encode('utf-8-sig')
    work=outdir/'stage'; shutil.rmtree(work,ignore_errors=True); (work/'bootstrap').mkdir(parents=True); (work/'release').mkdir(); (work/'evidence').mkdir()
    (work/'RUN_RUNTIME_ACCEPTANCE.ps1').write_bytes(runb); (work/'bootstrap/spotify-control-self-updater-v0621-acceptance.ps1').write_bytes(patched); (work/'release/manifest.json').write_bytes(manifest); (work/'PRECHECK_RUNTIME_ACCEPTANCE.ps1').write_bytes(precheck_bytes())
    (work/'RUN_RUNTIME_ACCEPTANCE.cmd').write_bytes(b'@echo off\r\nsetlocal\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PRECHECK_RUNTIME_ACCEPTANCE.ps1"\r\nset "RC=%ERRORLEVEL%"\r\necho.\r\nif not "%RC%"=="0" echo Runtime acceptance failed with exit code %RC%.\r\npause\r\nexit /b %RC%\r\n'); (work/'README.txt').write_bytes(readme_bytes(sha(patched),sha(manifest)))
    meta={'schema':1,'acceptance_version':'0.1.0','release_head':RELEASE_HEAD,'stage14_outer':{'size':len(so),'sha256':sha(so)},'stage14_inner':{'size':len(si),'sha256':sha(si)},'bootstrap_outer':{'size':len(bo),'sha256':sha(bo)},'bootstrap_exact':{'size':len(boot),'sha256':sha(boot)},'bootstrap_patched':{'size':len(patched),'sha256':sha(patched)},'release_manifest':{'size':len(manifest),'sha256':sha(manifest)},'runtime':{'size':len(runb),'sha256':sha(runb)}}; (work/'evidence/package-metadata.json').write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    rels=['RUN_RUNTIME_ACCEPTANCE.ps1','PRECHECK_RUNTIME_ACCEPTANCE.ps1','RUN_RUNTIME_ACCEPTANCE.cmd','README.txt','bootstrap/spotify-control-self-updater-v0621-acceptance.ps1','release/manifest.json','evidence/package-metadata.json']; (work/'SHA256SUMS.txt').write_text(''.join(sha((work/r).read_bytes())+'  '+r+'\n' for r in rels),encoding='ascii'); (work/'evidence/validate_acceptance.py').write_text(validator_text(),encoding='utf-8')
    rr=subprocess.run([sys.executable,str(work/'evidence/validate_acceptance.py')],capture_output=True,text=True); assert rr.returncode==0,rr.stdout+rr.stderr; (work/'evidence/VALIDATION_OUTPUT.txt').write_text(rr.stdout+rr.stderr,encoding='utf-8')
    out=outdir/FINAL; fixed_zip(work,out); print(rr.stdout.strip()); print('V0621_RUNTIME_ACCEPTANCE_BUILD_PASS',out.stat().st_size,sha(out.read_bytes()),len(runb),sha(runb),len(patched),sha(patched),len(manifest),sha(manifest)); return out

def main():
    p=argparse.ArgumentParser(); p.add_argument('--stage14-artifact',type=Path,required=True); p.add_argument('--bootstrap-artifact',type=Path,required=True); p.add_argument('--release-manifest',type=Path,required=True); p.add_argument('--runtime-template',type=Path,required=True); p.add_argument('--out-dir',type=Path,required=True); a=p.parse_args(); a.out_dir.mkdir(parents=True,exist_ok=True); build(a.stage14_artifact,a.bootstrap_artifact,a.release_manifest,a.runtime_template,a.out_dir)
if __name__=='__main__': main()
