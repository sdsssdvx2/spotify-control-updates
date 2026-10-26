from pathlib import Path
import base64,hashlib,io,json,re,shutil,zipfile
ROOT=Path(__file__).resolve().parent
GEN=ROOT/'generated';OUT=ROOT/'out'
PKG=OUT/'SpotifyControl-v0.6.21-r10-Runtime-Acceptance-v2.0.3'
ZIP=OUT/'SpotifyControl-v0.6.21-r10-Runtime-Acceptance-v2.0.3.zip'
SOURCE_FILES=['RUN_RUNTIME_ACCEPTANCE.ps1','RUN_RUNTIME_ACCEPTANCE.cmd','PRECHECK_RUNTIME_ACCEPTANCE.ps1','BOOTSTRAP_RUNNER.ps1','README.txt']
BUNDLE_SHA256='c619ecf278f59f55e38e62c9fa3336b7a29b107a4a2bf29d19dee77a202cc415'
CHUNK_DIR=ROOT/'source-b64'

def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def sha_path(p): return sha_bytes(p.read_bytes())
def ck(name,ok,checks): checks.append((name,bool(ok)))
def get_bundle_b64():
    fs=sorted(CHUNK_DIR.glob('chunk-*.txt'))
    if not fs: raise RuntimeError('source bundle chunks missing')
    return ''.join(''.join(p.read_text(encoding='ascii').split()) for p in fs)
def unpack_source():
    raw=base64.b64decode(get_bundle_b64(),validate=True)
    if sha_bytes(raw)!=BUNDLE_SHA256: raise RuntimeError('embedded source bundle SHA drift')
    shutil.rmtree(GEN,ignore_errors=True);GEN.mkdir(parents=True)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        if z.testzip() is not None: raise RuntimeError('embedded source bundle CRC failure')
        if sorted(z.namelist())!=sorted(SOURCE_FILES): raise RuntimeError(f'embedded source entries drift: {z.namelist()}')
        z.extractall(GEN)
    return raw

def validate_sources():
    s=(GEN/'RUN_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig')
    r=(GEN/'BOOTSTRAP_RUNNER.ps1').read_text(encoding='utf-8-sig')
    pre=(GEN/'PRECHECK_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig')
    readme=(GEN/'README.txt').read_text(encoding='utf-8')
    checks=[]
    pins={
      'acceptance':"$AcceptanceVersion='2.0.3'",'baseline_main':"$BaselineMainVersion='0.6.20'",'baseline_addon':"$BaselineAddonVersion='0.6.5-r9'",
      'target_main':"$TargetMainVersion='0.6.21'",'target_addon':"$TargetAddonVersion='0.6.5-r10'",
      'baseline_main_sha':'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18','baseline_addon_sha':'3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86',
      'target_main_sha':'f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828','target_addon_sha':'7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2',
      'agent_sha':'2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278','bootstrap_sha':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6',
      'release_head':'5eac4f39920b84f22e2a5ee07422f6080bfc7ef7','transport':'9a90d5f13eb63023d8f965a004be14d309d99429','payload':'7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55'}
    for k,v in pins.items(): ck('pin:'+k,v in s,checks)
    for name in SOURCE_FILES: ck('exists:'+name,(GEN/name).is_file(),checks)
    required_main=[
      'Assert-BaselineComponents','Assert-TargetComponents','Assert-TransactionsTerminal','Assert-PinnedReleaseManifest','Fetch-PinnedReleaseManifest',
      "Invoke-BootstrapRun -Action 'RollbackTest'","Invoke-BootstrapRun -Action 'Update'",'manifest-shim evidence invalid',
      "Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','SelfTest')","Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','Check','-Force')",'Assert-RegistryEvidence',
      'protect-ratings-tags-notes','never-disable-or-optimize','playlist-backed-ratings-preserve','preserve-unknown-source','Restore-ResidentSafely',
      'Timed out after $TimeoutSeconds seconds.','FailurePhase','manifest_preflight=$ManifestPreflight','check_shim=$CheckShim','rollback_shim=$RollbackShim','update_shim=$UpdateShim','post_check_shim=$PostCheckShim',
      'V0.6.21/R10 WINDOWS RUNTIME ACCEPTANCE VERIFIED']
    for x in required_main: ck('main-contains:'+x,x in s,checks)
    forbidden_main=['LOCAL_MANIFEST_SERVER','Start-LocalManifestServer','Get-FreeTcpPort','New-BootstrapExecutionCopy','Invoke-BootstrapProxyProbe','127.0.0.1',
      'SpotifyControlLoopbackBypassProxy',"Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','Update'",'Start-Spotify','Get-Process Spotify | Stop-Process',
      'Remove-Item -LiteralPath $env:APPDATA','Remove-Item -LiteralPath $env:LOCALAPPDATA']
    for x in forbidden_main: ck('main-forbidden-absent:'+x,x not in s,checks)
    ck('preflight-before-quiesce',s.index("$Phase='transport-preflight'")<s.index("$Phase='quiesce'"),checks)
    ck('fetch-before-resident-touch',s.index('$ManifestPreflight=Fetch-PinnedReleaseManifest')<s.index('$RestoreNeeded=$true'),checks)
    ck('restore-needed-after-fetch',s.index('$RestoreNeeded=$true')>s.index('$ManifestPreflight=Fetch-PinnedReleaseManifest'),checks)
    ck('exact-bootstrap-path-runner',"@('-BootstrapPath',$Bootstrap,'-Action',$Action,'-ManifestPath',$ManifestPath" in s,checks)
    ck('bootstrap-update-count',s.count("-Action 'Update'")==1,checks)
    ck('addon-update-call-absent',not re.search(r"Invoke-PowerShellScript[^\n]+\$Addon[^\n]+['\"]Update['\"]",s,re.I),checks)
    ck('release-manifest-exact-commit-url',"$ReleaseManifestUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/5eac4f39920b84f22e2a5ee07422f6080bfc7ef7/manifest.json'" in s,checks)
    ck('reported-main-manifest-url',"$MainManifestUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'" in s,checks)
    required_runner=[
      "$ExpectedBootstrapSha='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'",'$ExpectedBootstrapSize=42963',
      "if($FetchUrl -notmatch '^https://raw\\.githubusercontent\\.com/sdsssdvx2/spotify-control-updates/[0-9a-f]{40}/manifest\\.json$')",
      'Microsoft.PowerShell.Utility\\Invoke-WebRequest','BOOTSTRAP_MANIFEST_FETCH_PASS','function Invoke-RestMethod','Manifest shim refused unexpected Invoke-RestMethod URI',
      '$script:ShimHits++','$script:ShimHits -ne 1','manifest_sha256=(Get-Sha $script:ShimManifestPath)','bootstrap_sha256=(Get-Sha $BootstrapPath)',
      '& $BootstrapPath -Action $Action -Json','BOOTSTRAP_MANIFEST_SHIM_SELFTEST_PASS']
    for x in required_runner: ck('runner-contains:'+x,x in r,checks)
    forbidden_runner=['Invoke-WebRequest{','function Invoke-WebRequest','WebRequest]::DefaultWebProxy','IWebProxy','127.0.0.1','LOCAL_MANIFEST_SERVER']
    for x in forbidden_runner: ck('runner-forbidden-absent:'+x,x not in r,checks)
    ck('runner-irm-two-mode-definitions',r.count('function Invoke-RestMethod')==2,checks) # one self-test definition + one run-mode definition
    ck('bootstrap-runner-no-bootstrap-copy',"Replace($MainManifestUrl" not in r and 'ExecutionCopy' not in r,checks)
    ck('precheck-runner-only','BOOTSTRAP_RUNNER.ps1' in pre and 'LOCAL_MANIFEST_SERVER' not in pre,checks)
    ck('readme-no-localhost','removes localhost HTTP entirely' in readme and 'v2.0.2 was never approved' in readme,checks)
    ck('readme-exact-bootstrap','exact installed Bootstrap 1.0.6 file is executed byte-for-byte unchanged' in readme,checks)
    funcs=re.findall(r'(?im)^function\s+([A-Za-z0-9_-]+)',s);ck('no-duplicate-main-functions',len(funcs)==len(set(x.lower() for x in funcs)),checks)
    passed=sum(v for _,v in checks)
    report={'schema':1,'acceptance':'v0.6.21-r10-runtime-v2.0.3','passed':passed,'total':len(checks),'checks':checks,
      'embedded_bundle':{'size':len(base64.b64decode(get_bundle_b64())),'sha256':BUNDLE_SHA256},
      'files':{x:{'size':(GEN/x).stat().st_size,'sha256':sha_path(GEN/x)} for x in SOURCE_FILES}}
    if passed!=len(checks):
        for n,v in checks:
            if not v: print('FAIL',n)
        raise RuntimeError(f'source contract failed {passed}/{len(checks)}')
    return report

def build():
    unpack_source();report=validate_sources();shutil.rmtree(OUT,ignore_errors=True);PKG.mkdir(parents=True)
    for name in SOURCE_FILES: shutil.copy2(GEN/name,PKG/name)
    ev=PKG/'evidence';ev.mkdir()
    (ev/'SELF_VALIDATION_REPORT.json').write_text(json.dumps(report,indent=2,ensure_ascii=True)+'\n',encoding='utf-8',newline='\n')
    (ev/'SELF_VALIDATION_REPORT.txt').write_text(f"V0.6.21/R10 RUNTIME ACCEPTANCE v2.0.3 SELF VALIDATION: {report['passed']}/{report['total']} PASS\n"+''.join(f"PASS: {n}\n" for n,v in report['checks']),encoding='utf-8',newline='\n')
    rels=SOURCE_FILES+['evidence/SELF_VALIDATION_REPORT.json','evidence/SELF_VALIDATION_REPORT.txt']
    (PKG/'SHA256SUMS.txt').write_text(''.join(f"{sha_path(PKG/r)}  {r}\n" for r in rels),encoding='ascii',newline='\n')
    if ZIP.exists(): ZIP.unlink()
    # ZIP_STORED intentionally used: exact bytes remain cross-platform deterministic across zlib versions.
    with zipfile.ZipFile(ZIP,'w',compression=zipfile.ZIP_STORED) as z:
        for p in sorted(PKG.rglob('*')):
            if not p.is_file(): continue
            rel=p.relative_to(PKG).as_posix();info=zipfile.ZipInfo(rel,(2026,10,26,0,0,0));info.compress_type=zipfile.ZIP_STORED;info.external_attr=(0o100644<<16);z.writestr(info,p.read_bytes())
    with zipfile.ZipFile(ZIP) as z:
        if z.testzip() is not None: raise RuntimeError('final package CRC failure')
        for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
            h,rel=line.split('  ',1)
            if sha_bytes(z.read(rel))!=h: raise RuntimeError('internal checksum mismatch '+rel)
    print('V0621_R10_RUNTIME_ACCEPTANCE_V203_BUILD_PASS',ZIP.stat().st_size,sha_path(ZIP),report['passed'],report['total'],report['files']['RUN_RUNTIME_ACCEPTANCE.ps1']['sha256'],report['files']['BOOTSTRAP_RUNNER.ps1']['sha256'])
    return report
if __name__=='__main__':build()
