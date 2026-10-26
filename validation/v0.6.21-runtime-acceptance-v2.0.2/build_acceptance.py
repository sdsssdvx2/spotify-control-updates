from pathlib import Path
import base64,hashlib,io,json,re,shutil,zipfile

ROOT=Path(__file__).resolve().parent
GEN=ROOT/'generated'
OUT=ROOT/'out'
PKG=OUT/'SpotifyControl-v0.6.21-r10-Runtime-Acceptance-v2.0.2'
ZIP=OUT/'SpotifyControl-v0.6.21-r10-Runtime-Acceptance-v2.0.2.zip'
SOURCE_FILES=['RUN_RUNTIME_ACCEPTANCE.ps1','RUN_RUNTIME_ACCEPTANCE.cmd','PRECHECK_RUNTIME_ACCEPTANCE.ps1','LOCAL_MANIFEST_SERVER.ps1','BOOTSTRAP_RUNNER.ps1','README.txt']
BUNDLE_SHA256='de2d4841ebd3a8e0a588b5f3de4aa7a504cd467787c67c4b8fa9b1505c4bc9b4'
SERVER_OVERRIDE=ROOT/'LOCAL_MANIFEST_SERVER_CONCURRENT.ps1'
CHUNK_DIR=ROOT/'source-b64'

def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def sha_path(p): return sha_bytes(p.read_bytes())
def ck(name,ok,checks): checks.append((name,bool(ok)))

def get_bundle_b64():
    fs=sorted(CHUNK_DIR.glob('chunk-*.txt'))
    if [p.name for p in fs] != [f'chunk-{i:03}.txt' for i in range(6)]:
        raise RuntimeError('source bundle chunk set drift')
    return ''.join(''.join(p.read_text(encoding='ascii').split()) for p in fs)

def unpack_source():
    raw=base64.b64decode(get_bundle_b64(),validate=True)
    if sha_bytes(raw)!=BUNDLE_SHA256: raise RuntimeError('embedded source bundle SHA drift')
    shutil.rmtree(GEN,ignore_errors=True);GEN.mkdir(parents=True)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        if z.testzip() is not None: raise RuntimeError('embedded source bundle CRC failure')
        if sorted(z.namelist())!=sorted(SOURCE_FILES): raise RuntimeError(f'embedded source entries drift: {sorted(z.namelist())}')
        z.extractall(GEN)
    if not SERVER_OVERRIDE.is_file(): raise RuntimeError('concurrent server override missing')
    shutil.copy2(SERVER_OVERRIDE,GEN/'LOCAL_MANIFEST_SERVER.ps1')
    return raw

def validate_sources(raw):
    s=(GEN/'RUN_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig')
    r=(GEN/'BOOTSTRAP_RUNNER.ps1').read_text(encoding='utf-8-sig')
    srv=(GEN/'LOCAL_MANIFEST_SERVER.ps1').read_text(encoding='utf-8-sig')
    pre=(GEN/'PRECHECK_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig')
    readme=(GEN/'README.txt').read_text(encoding='utf-8-sig')
    checks=[]
    pins={
      'acceptance':"$AcceptanceVersion='2.0.2'",
      'baseline_main':"$BaselineMainVersion='0.6.20'",
      'baseline_addon':"$BaselineAddonVersion='0.6.5-r9'",
      'target_main':"$TargetMainVersion='0.6.21'",
      'target_addon':"$TargetAddonVersion='0.6.5-r10'",
      'baseline_main_sha':'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18',
      'baseline_addon_sha':'3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86',
      'target_main_sha':'f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828',
      'target_addon_sha':'7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2',
      'agent_sha':'2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278',
      'bootstrap_sha':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6',
      'release_head':'5eac4f39920b84f22e2a5ee07422f6080bfc7ef7',
      'transport':'9a90d5f13eb63023d8f965a004be14d309d99429',
      'payload':'7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55'}
    for k,v in pins.items(): ck('pin:'+k,v in s,checks)
    for name in SOURCE_FILES: ck('exists:'+name,(GEN/name).is_file(),checks)
    required=[
      'Assert-BaselineComponents','Assert-TargetComponents','Assert-TransactionsTerminal','New-BootstrapExecutionCopy','Prepare-LocalManifest',
      'Invoke-BootstrapProxyProbe','BOOTSTRAP_RUNNER.ps1','$RestoreNeeded=$true','if($RestoreNeeded)','FailurePhase','Timed out after $TimeoutSeconds seconds.',
      "Invoke-BootstrapRun -BootstrapRun $bootRun -Action 'RollbackTest'","Invoke-BootstrapRun -BootstrapRun $bootRun -Action 'Update'",
      "Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','SelfTest')","Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','Check','-Force')",'Assert-RegistryEvidence',
      'protect-ratings-tags-notes','never-disable-or-optimize','playlist-backed-ratings-preserve','preserve-unknown-source','Restore-ResidentSafely','V0.6.21/R10 WINDOWS RUNTIME ACCEPTANCE VERIFIED']
    for x in required: ck('contains:'+x,x in s,checks)
    forbidden=['Start-Spotify','Get-Process Spotify | Stop-Process',"Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','Update'",'Remove-Item -LiteralPath $env:APPDATA','Remove-Item -LiteralPath $env:LOCALAPPDATA']
    for x in forbidden: ck('forbidden-absent:'+x,x not in s,checks)
    ck('preflight-before-quiesce',s.index("$Phase='transport-preflight'")<s.index("$Phase='quiesce'"),checks)
    ck('proxy-probe-before-resident-touch',s.index('Invoke-BootstrapProxyProbe -LocalManifestUrl $localUrl')<s.index('$RestoreNeeded=$true'),checks)
    ck('bootstrap-via-runner',"Invoke-PowerShellScript -Path $RunnerScript -Arguments @('-BootstrapPath',$BootstrapRun,'-Action',$Action)" in s,checks)
    ck('no-direct-bootstrap-run',not re.search(r'Invoke-PowerShellScript\s+-Path\s+\$BootstrapRun',s,re.I),checks)
    ck('bootstrap-check-timeout',"$limit=if($Action -in @('Update','RollbackTest')){300}else{90}" in s,checks)
    ck('bootstrap-update-count',s.count("-Action 'Update'")==1,checks)
    ck('addon-update-call-absent',not re.search(r"Invoke-PowerShellScript[^\n]+\$Addon[^\n]+['\"]Update['\"]",s,re.I),checks)
    ck('server-loopback-only','IPAddress.Loopback' in srv and 'IPAddress.Any' not in srv,checks)
    ck('server-bounded-read-write','ClientReadTimeoutMs = 1500' in srv and 'ClientWriteTimeoutMs = 1500' in srv,checks)
    ck('server-concurrent-client-thread','new Thread(delegate() { HandleClient(client); })' in srv and 'thread.IsBackground = true' in srv,checks)
    ck('server-backlog-bounded','listener.Start(128)' in srv,checks)
    ck('server-header-bounds','MaxHeaderLines = 100' in srv and 'MaxLineChars = 8192' in srv,checks)
    ck('server-only-manifest','String.Equals(path, "/manifest.json", StringComparison.Ordinal)' in srv,checks)
    ck('server-no-serial-handler-comment','single-threaded server' not in srv,checks)
    ck('runner-implements-iwebproxy','SpotifyControlLoopbackBypassProxy : IWebProxy' in r,checks)
    ck('runner-loopback-bypass','uri.IsLoopback' in r and 'localhost' in r and 'return destination;' in r,checks)
    ck('runner-remote-delegation','inner.GetProxy(destination)' in r and 'inner.IsBypassed(host)' in r,checks)
    ck('runner-webrequest-defaultproxy','[Net.WebRequest]::DefaultWebProxy=New-LoopbackProxy' in r,checks)
    ck('runner-same-process-bootstrap','& $BootstrapPath -Action $Action -Json' in r,checks)
    ck('runner-probe-invokerestmethod','Invoke-RestMethod -Uri $uri' in r and '-TimeoutSec $TimeoutSec' in r,checks)
    ck('runner-trap-proxy-selftest','TestInnerProxyUri' in r and 'BOOTSTRAP_RUNNER_LOOPBACK_PROXY_SELFTEST_PASS' in r,checks)
    ck('precheck-includes-runner','BOOTSTRAP_RUNNER.ps1' in pre,checks)
    ck('readme-old-runs-prohibited','v2.0.0/v2.0.1 must not be rerun' in readme,checks)
    ck('readme-preflight-before-mutation','before resident/mutation state is touched' in readme,checks)
    funcs=re.findall(r'(?im)^function\s+([A-Za-z0-9_-]+)',s);ck('no-duplicate-main-functions',len(funcs)==len(set(x.lower() for x in funcs)),checks)
    rfuncs=re.findall(r'(?im)^function\s+([A-Za-z0-9_-]+)',r);ck('no-duplicate-runner-functions',len(rfuncs)==len(set(x.lower() for x in rfuncs)),checks)
    passed=sum(v for _,v in checks)
    report={'schema':1,'acceptance':'v0.6.21-r10-runtime-v2.0.2','passed':passed,'total':len(checks),'checks':checks,
      'embedded_bundle':{'size':len(raw),'sha256':BUNDLE_SHA256},
      'server_override':{'size':SERVER_OVERRIDE.stat().st_size,'sha256':sha_path(SERVER_OVERRIDE)},
      'files':{x:{'size':(GEN/x).stat().st_size,'sha256':sha_path(GEN/x)} for x in SOURCE_FILES}}
    if passed!=len(checks):
        for n,v in checks:
            if not v: print('FAIL',n)
        raise RuntimeError(f'source contract failed {passed}/{len(checks)}')
    return report

def build():
    raw=unpack_source();report=validate_sources(raw)
    shutil.rmtree(OUT,ignore_errors=True);PKG.mkdir(parents=True)
    for name in SOURCE_FILES: shutil.copy2(GEN/name,PKG/name)
    ev=PKG/'evidence';ev.mkdir()
    (ev/'SELF_VALIDATION_REPORT.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    (ev/'SELF_VALIDATION_REPORT.txt').write_text(f"V0.6.21/R10 RUNTIME ACCEPTANCE v2.0.2 SELF VALIDATION: {report['passed']}/{report['total']} PASS\n"+''.join(f"PASS: {n}\n" for n,v in report['checks']),encoding='utf-8',newline='\n')
    rels=SOURCE_FILES+['evidence/SELF_VALIDATION_REPORT.json','evidence/SELF_VALIDATION_REPORT.txt']
    (PKG/'SHA256SUMS.txt').write_text(''.join(f"{sha_path(PKG/r)}  {r}\n" for r in rels),encoding='ascii',newline='\n')
    if ZIP.exists(): ZIP.unlink()
    with zipfile.ZipFile(ZIP,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(PKG.rglob('*')):
            if not p.is_file(): continue
            rel=p.relative_to(PKG).as_posix();info=zipfile.ZipInfo(rel,(2026,10,26,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=(0o100644<<16);z.writestr(info,p.read_bytes())
    with zipfile.ZipFile(ZIP) as z:
        if z.testzip() is not None: raise RuntimeError('final package CRC failure')
        for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
            h,rel=line.split('  ',1)
            if sha_bytes(z.read(rel))!=h: raise RuntimeError('internal checksum mismatch '+rel)
    print('V0621_R10_RUNTIME_ACCEPTANCE_V202_BUILD_PASS',ZIP.stat().st_size,sha_path(ZIP),report['passed'],report['total'],report['files']['RUN_RUNTIME_ACCEPTANCE.ps1']['sha256'],report['files']['LOCAL_MANIFEST_SERVER.ps1']['sha256'],report['files']['BOOTSTRAP_RUNNER.ps1']['sha256'])
    return report

if __name__=='__main__': build()
