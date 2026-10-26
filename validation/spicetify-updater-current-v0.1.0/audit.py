from pathlib import Path
import hashlib, json, re, subprocess, sys, urllib.request

ROOT=Path(__file__).resolve().parents[2]
BASE='29d6c52c6a79559e513b367ec57edcccebae5fd0'
MAIN=(281585,'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18')
ADDON=(225044,'3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86')


def sha(b): return hashlib.sha256(b).hexdigest()
def read_json(url):
    req=urllib.request.Request(url,headers={'User-Agent':'spotify-control-spicetify-updater-audit/0.1.0','Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(req,timeout=30) as r: return json.loads(r.read().decode('utf-8'))

def identity(path,expected,label):
    b=path.read_bytes(); actual=(len(b),sha(b))
    if actual!=expected: raise RuntimeError(f'{label} drift {actual} != {expected}')
    return b

def function_blocks(text):
    starts=list(re.finditer(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text))
    out=[]
    for idx,m in enumerate(starts):
        end=starts[idx+1].start() if idx+1<len(starts) else len(text)
        out.append((m.group(1),m.start(),end,text[m.start():end]))
    return out

def main():
    merge=subprocess.check_output(['git','merge-base',BASE,'HEAD'],text=True).strip()
    if merge!=BASE: raise RuntimeError(f'wrong merge base {merge}')
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.20/build_v0620.py'),'--build'],cwd=ROOT)
    out=ROOT/'validation/v0.6.20/out/bin'
    main_bytes=identity(out/'spotify-control.ps1',MAIN,'production main')
    identity(out/'addon-manager.ps1',ADDON,'production addon')
    text=main_bytes.decode('utf-8-sig')
    lines=text.splitlines()

    spice_lines=[]
    for i,line in enumerate(lines,1):
        low=line.lower()
        if 'spicetify' in low or ('spice' in low and any(k in low for k in ('release','asset','update','transaction'))):
            spice_lines.append({'line':i,'text':line[:800]})

    funcs=[]
    for name,start,end,block in function_blocks(text):
        low=(name+'\n'+block).lower()
        if 'spicetify' in low and any(k in low for k in ('update','release','preflight','transaction','download','backup','apply','rollback','restore','official')):
            start_line=text.count('\n',0,start)+1
            urls=sorted(set(re.findall(r"https?://[^\s\"'\)]+",block)))
            funcs.append({
                'name':name,'start_line':start_line,'length':len(block),
                'urls':urls,
                'markers':sorted(k for k in [
                    'releases/latest','releases/tags','windows-x64','sha256','digest','attestation',
                    'spicetify-preflight','spicetify-transaction','rollback','restore','backup','apply',
                    'extras_preserved','post_apply_guard','root_transaction','official'
                ] if k in low),
                'excerpt':'\n'.join(block.splitlines()[:120])[:14000]
            })

    urls=sorted(set(re.findall(r"https?://[^\s\"'\)]+",text)))
    spice_urls=[u for u in urls if 'spicetify' in u.lower()]
    literals=sorted(set(re.findall(r'(?<![0-9])2\.\d+\.\d+(?![0-9])',text)))

    latest=read_json('https://api.github.com/repos/spicetify/cli/releases/latest')
    tag=str(latest.get('tag_name') or '').strip()
    m=re.fullmatch(r'v(\d+\.\d+\.\d+)',tag)
    if not m: raise RuntimeError(f'invalid current latest Spicetify tag {tag!r}')
    if latest.get('draft') or latest.get('prerelease'): raise RuntimeError('current latest release is draft/prerelease')
    body=str(latest.get('body') or '')
    win_lines=[line for line in re.split(r'\r?\n',body) if re.search(r'Spotify\s+for\s+\*\*[^*]*Windows[^*]*\*\*',line)]
    if not win_lines: raise RuntimeError('current latest release has no Windows compatibility line')
    compat_versions=re.findall(r'(?<!\d)(\d+\.\d+\.\d+)(?!\d)',win_lines[0])
    if len(compat_versions)!=2: raise RuntimeError(f'current latest Windows compatibility line must contain exactly two versions: {win_lines[0]}')

    assets=[]
    for a in latest.get('assets',[]):
        if 'windows' in a.get('name','').lower():
            assets.append({k:a.get(k) for k in ('name','size','digest','browser_download_url','content_type','state')})

    report={
        'schema':1,
        'audit':'spicetify-updater-current-v0.1.0',
        'production_base':BASE,
        'validation_head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
        'production_main':{'size':MAIN[0],'sha256':MAIN[1]},
        'production_addon':{'size':ADDON[0],'sha256':ADDON[1]},
        'current_latest_release':{
            'tag_name':tag,'version':m.group(1),'name':latest.get('name'),'published_at':latest.get('published_at'),
            'html_url':latest.get('html_url'),'draft':bool(latest.get('draft')),'prerelease':bool(latest.get('prerelease')),
            'windows_compatibility_line':win_lines[0],'windows_compatibility_versions':compat_versions,'assets':assets
        },
        'production_spicetify_urls':spice_urls,
        'production_semver_literals':literals,
        'spicetify_related_lines':spice_lines,
        'candidate_updater_functions':funcs,
        'result':'AUDIT_PASS'
    }
    (ROOT/'spicetify-updater-current-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('SPICETIFY_UPDATER_CURRENT_AUDIT_PASS')
    print('latest',tag,'compat',compat_versions,'windows_assets',len(assets),'functions',len(funcs),'lines',len(spice_lines),'urls',len(spice_urls))

if __name__=='__main__': main()
