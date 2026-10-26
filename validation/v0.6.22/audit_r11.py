from pathlib import Path
import hashlib,json,re,sys
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'validation/v0.6.21/out/bin/addon-manager.ps1'
CAND=ROOT/'validation/v0.6.22/out/bin/addon-manager.ps1'
MAIN_BASE=ROOT/'validation/v0.6.21/out/bin/spotify-control.ps1'
MAIN_CAND=ROOT/'validation/v0.6.22/out/bin/spotify-control.ps1'
ENGINE=ROOT/'validation/v0.6.22/addon_source_adapter_engine.ps1.inc'
ALLOWED_CHANGED={'Update-AutoApps','Normalize-PithayaTransaction','Commit-LastTransaction','Invoke-AddonSelfTest'}
EXPECTED_MAIN=(281586,'b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe')
EXPECTED_ADDON=(268670,'0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc')
EXPECTED_ENGINE=(17020,'8d51607ec3b7371c6777475ae9e301fe19a7b9fada8325626889e528ef0ab466')

def need(v,m):
    if not v: raise AssertionError(m)
def funcs(text):
    out={}
    for h in re.finditer(r'(?m)^function\s+([^\s{]+)\s*\{',text):
        close=re.search(r'(?m)^}\s*$',text[h.end():])
        if close is None:raise AssertionError(f'cannot find top-level close for {h.group(1)}')
        end=h.end()+close.end()
        out[h.group(1)]=text[h.start():end].rstrip()
    return out
def sha(b):return hashlib.sha256(b).hexdigest()

def main():
    b=BASE.read_bytes();c=CAND.read_bytes();need(b.startswith(b'\xef\xbb\xbf') and c.startswith(b'\xef\xbb\xbf'),'addon BOM drift')
    need((len(c),sha(c))==EXPECTED_ADDON,f'candidate addon identity drift {(len(c),sha(c))}')
    engine_bytes=ENGINE.read_bytes();need((len(engine_bytes),sha(engine_bytes))==EXPECTED_ENGINE,f'engine identity drift {(len(engine_bytes),sha(engine_bytes))}')
    bt=b[3:].decode('utf-8');ct=c[3:].decode('utf-8');bf=funcs(bt);cf=funcs(ct);ef=funcs(ENGINE.read_text(encoding='utf-8'))
    need('$Version = "0.6.5-r10"' in bt and '$Version = "0.6.5-r11"' in ct,'version markers')
    added=set(cf)-set(bf);need(added==set(ef),f'unexpected added functions: {sorted(added^set(ef))}')
    removed=set(bf)-set(cf);need(not removed,f'removed functions: {sorted(removed)}')
    changed=[n for n in bf if bf[n]!=cf[n]]
    need(set(changed)==ALLOWED_CHANGED,f'existing function drift: {sorted(changed)}')
    for n in bf:
        if n not in ALLOWED_CHANGED:need(bf[n]==cf[n],f'unexpected function change {n}')
    need(bf['Get-AddonInventory']==cf['Get-AddonInventory'],'inventory behavior drift')
    for protected in ('Check','Get-PithayaRemoteMap','Get-IvLyricsRemote','Resolve-IvLyricsRemote','Rollback-LastTransaction','Invoke-AddonRegistryCommitCycleSelfTest'):
        if protected in bf:need(bf[protected]==cf[protected],f'protected function drift: {protected}')
    need('Get-AddonSourceAdapterPlan -Item $item' in cf['Update-AutoApps'],'Update does not route through source plan')
    need('Get-AddonMutationAuthorization -Item $item' not in cf['Update-AutoApps'],'Update still directly routes authorization')
    need('$item.source -eq "Pithaya/spicetify-apps-dist"' not in cf['Update-AutoApps'],'literal Pithaya routing remains')
    need('$item.source -eq "ivLis-Studio/ivLyrics"' not in cf['Update-AutoApps'],'literal ivLyrics routing remains')
    need('Assert-AddonSourceAdapterTransactionAuthorization' in cf['Commit-LastTransaction'],'CommitLast adapter guard missing')
    need('Assert-AddonSourceAdapterTransactionAuthorization' not in cf['Rollback-LastTransaction'],'Rollback became adapter-dependent')
    need('source_adapter_sha256' not in cf['Rollback-LastTransaction'],'Rollback source adapter dependency')
    need('Invoke-AddonSourceAdapterSelfTest' in cf['Invoke-AddonSelfTest'],'source adapter selftest missing')
    engine=ENGINE.read_text(encoding='utf-8')
    for bad in ('Invoke-WebRequest','Invoke-RestMethod','Expand-Archive','Remove-Item','Move-Item','Copy-Item','Start-Process','spicetify apply','spicetify backup','spicetify restore'):
        need(bad.lower() not in engine.lower(),f'engine side effect {bad}')
    mb=MAIN_BASE.read_bytes();mc=MAIN_CAND.read_bytes();need(mb.startswith(b'\xef\xbb\xbf') and mc.startswith(b'\xef\xbb\xbf'),'main BOM drift')
    need((len(mc),sha(mc))==EXPECTED_MAIN,f'candidate main identity drift {(len(mc),sha(mc))}')
    bl=mb[3:].decode('ascii').splitlines(True);cl=mc[3:].decode('ascii').splitlines(True)
    need(len(bl)==len(cl),'main line count drift');diff=[i for i,(x,y) in enumerate(zip(bl,cl)) if x!=y];need(diff==[0,12],f'main diff lines {diff}')
    report={'result':'AUDIT_PASS','base_addon':{'size':len(b),'sha256':sha(b)},'candidate_addon':{'size':len(c),'sha256':sha(c)},'candidate_main':{'size':len(mc),'sha256':sha(mc)},'engine':{'size':len(engine_bytes),'sha256':sha(engine_bytes)},'added_functions':sorted(added),'changed_existing_functions':sorted(changed),'unchanged_existing_functions':len(bf)-len(changed),'rollback_adapter_independent':True,'inventory_byte_identical':True,'authority_expanded':False}
    print(json.dumps(report,sort_keys=True));print('R11_STRUCTURAL_AUDIT_PASS')
if __name__=='__main__':
    try:main()
    except Exception as e:print(f'R11_STRUCTURAL_AUDIT_FAIL: {e}',file=sys.stderr);raise
