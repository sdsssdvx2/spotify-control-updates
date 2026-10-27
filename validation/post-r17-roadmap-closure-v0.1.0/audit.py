from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE='d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
V20_MAIN=(281585,'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18')
V20_ADDON=(225044,'3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86')
V28_MAIN=(284321,'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0')
V28_ADDON=(323385,'5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285')
OUT=ROOT/'validation/post-r17-roadmap-closure-v0.1.0/audit-result.json'
SPOTIFY_TARGETS=[
 'Normalize-Etag','Get-SpotifyVersion','Get-SpotifyPublisherSignature','Test-SpotifyInstallerIdentity',
 'Get-LatestSpotifyWindowsCandidate','Get-VerifiedSpotifyInstaller','Get-SmartUpdateGuardPlan',
 'Set-SpotifyUpdateGuardState','Invoke-SmartUpdateGuard','Invoke-SpotifyPreflight',
 'Invoke-SpotifyTransactionalMaintenance','Restore-SpotifyTransactionSnapshot',
 'Rollback-SpotifyTransaction','Repair-PendingSpotifyTransaction'
]
KNOWN_COMPLETED={
 'spicetify_compat':{'pr':47,'head':'9d4c4ff6f2b2c772f9b2801e6b55b25bfabf7325','run':40277933764},
 'spicetify_updater':{'pr':48,'head':'fe4b626d53b62141458b8697197a27a8b103bf3b','run':40279100539},
 'spotify_updater':{'pr':49,'head':'34db9740d18c9ad3d8104cd03f5d05169b60aa70','run':40280796016},
 'generic_registry_roadmap':{'pr':50,'head':'f5d2e1037e325c79f44993595571370c81f6de42','run':40281729870},
}

def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def git(*a:str)->str:return subprocess.check_output(['git',*a],cwd=ROOT,text=True).strip()
def identity(path:Path,exp:tuple[int,str],label:str)->bytes:
    b=path.read_bytes(); got=(len(b),sha(b))
    if got!=exp:raise SystemExit(f'{label} identity drift {got} != {exp}')
    return b

def funcs(text:str)->dict[str,str]:
    hits=list(re.finditer(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text));out={}
    for i,h in enumerate(hits):
        end=hits[i+1].start() if i+1<len(hits) else len(text)
        out[h.group(1)]=text[h.start():end].rstrip()
    return out

def norm_function(body:str)->str:
    # Ignore only the global script/addon version literals when comparing updater semantics.
    body=re.sub(r'(?m)^\$ScriptVersion\s*=\s*"[^"]+"\s*$','',body)
    body=re.sub(r'(?m)^\$Version\s*=\s*"[^"]+"\s*$','',body)
    return body.strip()
def hash_fn(body:str)->str:return sha(norm_function(body).encode('utf-8'))
def spicetify_updater_names(fs:dict[str,str])->list[str]:
    out=[]
    for name,body in fs.items():
        low=(name+'\n'+body).lower()
        if 'spicetify' in low and any(k in low for k in ('update','release','preflight','transaction','download','backup','apply','rollback','restore','official')):
            out.append(name)
    return sorted(out)
def changed(fs20:dict[str,str],fs28:dict[str,str],names:list[str]):
    rows=[]
    for name in names:
        a=fs20.get(name);b=fs28.get(name)
        rows.append({'name':name,'v20_present':a is not None,'v28_present':b is not None,
                     'v20_sha256':hash_fn(a) if a else None,'v28_sha256':hash_fn(b) if b else None,
                     'changed':a is None or b is None or hash_fn(a)!=hash_fn(b)})
    return rows

def main():
    if git('merge-base',BASE,'HEAD')!=BASE:raise SystemExit('wrong exact production base')
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.20/build_v0620.py'),'--build'],cwd=ROOT)
    p20=ROOT/'validation/v0.6.20/out/bin'
    m20=identity(p20/'spotify-control.ps1',V20_MAIN,'v0.6.20 main').decode('utf-8-sig')
    a20=identity(p20/'addon-manager.ps1',V20_ADDON,'v0.6.20 addon').decode('utf-8-sig')
    f20=funcs(m20);af20=funcs(a20)

    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.28/build_v0628.py'),'--build'],cwd=ROOT)
    p28=ROOT/'validation/v0.6.28/out/bin'
    m28=identity(p28/'spotify-control.ps1',V28_MAIN,'v0.6.28 main').decode('utf-8-sig')
    a28=identity(p28/'addon-manager.ps1',V28_ADDON,'v0.6.28 addon').decode('utf-8-sig')
    f28=funcs(m28);af28=funcs(a28)

    missing_spotify=[n for n in SPOTIFY_TARGETS if n not in f20 or n not in f28]
    if missing_spotify:raise SystemExit('Spotify updater target missing: '+','.join(missing_spotify))
    spotify_rows=changed(f20,f28,SPOTIFY_TARGETS)

    spice20=spicetify_updater_names(f20);spice28=spicetify_updater_names(f28)
    spice_union=sorted(set(spice20)|set(spice28))
    spice_rows=changed(f20,f28,spice_union)

    semver20=sorted(set(re.findall(r'(?<![0-9])2\.\d+\.\d+(?![0-9])',m20)))
    semver28=sorted(set(re.findall(r'(?<![0-9])2\.\d+\.\d+(?![0-9])',m28)))
    registry=af28.get('Get-AddonPolicyRegistry','')
    auto=sorted(re.findall(r"name='([^']+)'.*?mutation_mode='auto'",registry,flags=re.I))
    if auto!=sorted(['better-local-files','eternal-jukebox','ivLyrics','playlist-maker']):raise SystemExit(f'auto authority drift: {auto}')
    protected={
      'tagify': all(x.lower() in registry.lower() for x in ("name='tagify'","mutation_mode='deny'","protect-ratings-tags-notes")),
      'splitify': "name='splitify'".lower() in registry.lower() and "mutation_mode='deny'".lower() in registry.lower(),
      'star_ratings': "name='star-ratings'".lower() in registry.lower() and 'playlist-backed-ratings-preserve' in registry,
      'sc_cover_ambience': "name='sc-cover-ambience.js'".lower() in registry.lower() and 'never-disable-or-optimize' in registry,
    }
    if not all(protected.values()):raise SystemExit(f'protected policy drift: {protected}')

    # Later releases intentionally added archive/resource hardening and provenance to Addon Manager.
    # This audit does not assume updater functions are unchanged; it records exact semantic function deltas.
    spotify_changed=[r['name'] for r in spotify_rows if r['changed']]
    spice_changed=[r['name'] for r in spice_rows if r['changed']]
    new_spice=[n for n in spice28 if n not in spice20]
    removed_spice=[n for n in spice20 if n not in spice28]

    report={
      'schema':1,'audit':'post-r17-roadmap-closure-v0.1.0','production_base':BASE,'validation_head':git('rev-parse','HEAD'),
      'read_only':True,'mutation_performed':False,'authority_expanded':False,
      'exact_versions':{'v0.6.20':{'main':{'size':V20_MAIN[0],'sha256':V20_MAIN[1]},'addon':{'size':V20_ADDON[0],'sha256':V20_ADDON[1]}},
                        'v0.6.28':{'main':{'size':V28_MAIN[0],'sha256':V28_MAIN[1]},'addon':{'size':V28_ADDON[0],'sha256':V28_ADDON[1]}}},
      'prior_validation_evidence':KNOWN_COMPLETED,
      'spotify_updater_function_comparison':{'targets':spotify_rows,'changed':spotify_changed},
      'spicetify_updater_function_comparison':{'v20_names':spice20,'v28_names':spice28,'rows':spice_rows,'changed':spice_changed,'new':new_spice,'removed':removed_spice},
      'spicetify_semver_literals':{'v0.6.20':semver20,'v0.6.28':semver28},
      'addon_policy':{'automatic_authority':auto,'protected_contracts':protected},
      'completed_current_r17_evidence':{
        'pithaya_provenance_audit_run':40508042354,
        'ivlyrics_v7016_acceptance_run':40509106218,
        'sc_cover_ambience_production_release':'0.6.28/r17',
        'star_ratings_provenance':'0.6.27/r16',
        'tagify_provenance':'0.6.26/r15',
        'splitify_provenance':'0.6.25/r14',
      },
      'decision':{
        'production_change_justified':False,
        'r18_release_justified':False,
        'needs_external_updater_retest':bool(spotify_changed or spice_changed or new_spice or removed_spice),
        'reason':'current-vs-v0.6.20 updater function delta inventory completed; any changed updater functions require semantic review against the already-successful current-upstream audits before declaring roadmap closure',
      }
    }
    OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('POST_R17_SPOTIFY_CHANGED='+','.join(spotify_changed))
    print('POST_R17_SPICETIFY_CHANGED='+','.join(spice_changed))
    print('POST_R17_SPICETIFY_NEW='+','.join(new_spice))
    print('POST_R17_SPICETIFY_REMOVED='+','.join(removed_spice))
    print('POST_R17_SEMVER_LITERALS='+','.join(semver28))
    print('POST_R17_ROADMAP_CLOSURE_AUDIT_PASS')

if __name__=='__main__':main()
