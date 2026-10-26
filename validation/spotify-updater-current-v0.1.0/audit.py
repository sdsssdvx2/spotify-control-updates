from pathlib import Path
import hashlib, json, re, subprocess, sys

ROOT=Path(__file__).resolve().parents[2]
BASE='29d6c52c6a79559e513b367ec57edcccebae5fd0'
MAIN=(281585,'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18')
ADDON=(225044,'3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86')
TARGETS=[
    'Get-SpotifyVersion','Get-SpotifyPublisherSignature','Get-LatestSpotifyWindowsCandidate',
    'Get-VerifiedSpotifyInstaller','Get-SmartUpdateGuardPlan','Set-SpotifyUpdateGuardState',
    'Invoke-SmartUpdateGuard','Invoke-SpotifyPreflight','Invoke-SpotifyTransactionalMaintenance',
    'Restore-SpotifyTransactionSnapshot','Rollback-SpotifyTransaction','Repair-PendingSpotifyTransaction'
]

def sha(b): return hashlib.sha256(b).hexdigest()
def identity(path,expected,label):
    b=path.read_bytes(); actual=(len(b),sha(b))
    if actual!=expected: raise RuntimeError(f'{label} identity drift {actual} != {expected}')
    return b

def functions(text):
    starts=list(re.finditer(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text))
    out={}
    for i,m in enumerate(starts):
        end=starts[i+1].start() if i+1<len(starts) else len(text)
        block=text[m.start():end]
        out[m.group(1)]={'start_line':text.count('\n',0,m.start())+1,'text':block}
    return out

def main():
    if subprocess.check_output(['git','merge-base',BASE,'HEAD'],text=True).strip()!=BASE:
        raise RuntimeError('validation branch is not based on exact production main')
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.20/build_v0620.py'),'--build'],cwd=ROOT)
    out=ROOT/'validation/v0.6.20/out/bin'
    main_bytes=identity(out/'spotify-control.ps1',MAIN,'production main')
    identity(out/'addon-manager.ps1',ADDON,'production addon')
    text=main_bytes.decode('utf-8-sig')
    fn=functions(text)
    missing=[n for n in TARGETS if n not in fn]
    if missing: raise RuntimeError('required Spotify updater function(s) missing: '+', '.join(missing))
    selected={}
    for n in TARGETS:
        block=fn[n]['text']
        selected[n]={
            'start_line':fn[n]['start_line'],
            'length':len(block),
            'urls':sorted(set(re.findall(r"https?://[^\s\"'\)]+",block))),
            'markers':sorted(k for k in [
                'etag','sha256','signature','authenticode','productversion','download','installer','cache',
                'silent','skip-app-launch','rollback','protected','registry','shortcuts','apply --no-restart',
                'spotify-updates','acl','blocked','unblocked','spicetify','compatibility','transaction'
            ] if k in block.lower()),
            'excerpt':block[:30000]
        }
    all_urls=sorted(set(re.findall(r"https?://[^\s\"'\)]+",text)))
    spotify_urls=[u for u in all_urls if any(k in u.lower() for k in ('spotify','scdn','spotcdn'))]
    candidate_literals=[]
    for i,line in enumerate(text.splitlines(),1):
        low=line.lower()
        if any(k in low for k in ('spotifysetup','etag','candidate','installer')) and any(k in low for k in ('http','spotify','etag','installer')):
            candidate_literals.append({'line':i,'text':line[:1000]})
    report={
        'schema':1,'audit':'spotify-updater-current-v0.1.0-discovery','result':'DISCOVERY_PASS',
        'production_base':BASE,'validation_head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
        'production_main':{'size':MAIN[0],'sha256':MAIN[1]},
        'production_addon':{'size':ADDON[0],'sha256':ADDON[1]},
        'target_functions':selected,'production_spotify_urls':spotify_urls,'candidate_related_lines':candidate_literals
    }
    (ROOT/'spotify-updater-current-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('SPOTIFY_UPDATER_DISCOVERY_PASS functions=%d urls=%d candidate_lines=%d' % (len(selected),len(spotify_urls),len(candidate_literals)))

if __name__=='__main__': main()
