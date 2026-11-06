"""Read-only structural inventory of the *generated actual Addon Manager*.
First stage of the cohesive normal-entrypoint integration candidate. We don't
guess source from partial patches or turn on production. All output remains
hosted-CI-only, no secrets, no active Spotify reads or network update calls.
"""
from __future__ import annotations
import hashlib, json, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PARENT='22c548aad75d2dc59699062b4d01f8c4020e5b15'
PARENT_BUILDER='validation/custom-app-user-transaction-terminal-journal/build_candidate.py'
PARENT_BLOB='20902d142ed5a2270ece4ab75671959dd178bd1e'
PARENT_ADDON=(1448757,'6fe25f592fddd30424d670bc20fc68f0a8b78a01c4fa29f8dc2268d2714b46f9')
PARENT_MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
INTERESTING=re.compile(r'addon|custom|update|due|action|tick|startup|scheduler|policy|refresh|install|run',re.I)
FUNC=re.compile(r'(?im)^[ \t]*function\s+([A-Za-z_][A-Za-z0-9_-]*)\s*\{')
CALLS=('Invoke-CustomAppProductionFullChainV010','Invoke-AddonUpdate','Invoke-AddonAutoUpdate',
       'Invoke-AddonSelfTest','Get-AddonPolicyRegistry','Test-Due','Invoke-CustomApp')
def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def inspect():
    got=subprocess.check_output(['git','rev-parse',f'{PARENT}:{PARENT_BUILDER}'],cwd=ROOT,text=True).strip()
    if got!=PARENT_BLOB:raise RuntimeError('qualified terminal parent builder drift')
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    d=ROOT/'validation/custom-app-user-transaction-terminal-journal/out/bin'
    addon=(d/'addon-manager.ps1').read_bytes()
    main=(d/'spotify-control.ps1').read_bytes()
    if (len(addon),sha(addon))!=PARENT_ADDON:raise RuntimeError('previous signed real ZIP terminal candidate drift')
    if (len(main),sha(main))!=PARENT_MAIN:raise RuntimeError('qualified Spotify control candidate drift')
    text=addon.decode('utf-8-sig').replace('\r\n','\n')
    lines=text.splitlines()
    matches=list(FUNC.finditer(text))
    selected=[]
    for i,m in enumerate(matches):
        n=m.group(1)
        if not INTERESTING.search(n):continue
        b=m.start();e=matches[i+1].start() if i+1<len(matches) else len(text)
        chunk=text[b:e]
        start=text[:b].count('\n')+1
        inv=[c for c in CALLS if c in chunk and c!=n]
        selected.append(dict(name=n,line=start,lines=chunk.count('\n'),calls=inv,
                             first_code=' '.join(x.strip() for x in chunk.splitlines()[1:4])[:240]))
    # Static action and lifecycle references, NOT actual execution.
    patterns=[
        r'\bswitch\s*\(\s*\$Action\s*\)',r'\bif\s*\(\s*\$Action\b',
        r'(?im)^[ \t]*param\s*\(',r'\bInvoke-Addon[A-Za-z0-9_-]+\b',
        r'\bInvoke-CustomAppProductionFullChainV010\b',
        r'\bStart-Addon[A-Za-z0-9_-]+\b',
        r'\bTest-Due\b',
        r'\bCustomAppProductionPipelineEnabled\b'
    ]
    anchors=[]
    for p in patterns:
        found=list(re.finditer(p,text))
        for m in found[:35]:
            ln=text.count('\n',0,m.start())
            anchors.append(dict(pattern=p,line=ln+1,context='\n'.join(lines[max(0,ln-2):min(len(lines),ln+7)])[:850]))
    # Top-level entrypoint candidate: last nontrivial 90 lines, with literals
    # sanitized to avoid writing production/secret argument paths into reports.
    tail='\n'.join(lines[-110:])
    report=dict(schema=1,qualified_parent=PARENT,addon_sha256=sha(addon),addon_size=len(addon),
                total_functions=len(matches),selected=selected,anchors=anchors,
                top_110_lines='\n'.join(lines[:110]),tail_110_lines=tail,
                full_chain_call_occurrences=len(re.findall(r'\bInvoke-CustomAppProductionFullChainV010\b',text)),
                production_wiring_enabled=False,operating_main_unchanged=True)
    HERE.mkdir(parents=True,exist_ok=True)
    (HERE/'entrypoint-inventory.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print('ACTUAL_ADDON_ENTRYPOINT_INVENTORY_PASS candidate_sha256='+sha(addon)+
          ' functions='+str(len(matches))+' selected='+str(len(selected))+
          ' full_chain_refs='+str(report['full_chain_call_occurrences']))
    for x in selected:
        if x['calls'] or re.search(r'(?i)^(Invoke-Addon|Test-Due|Invoke-CustomAppProductionFullChain)',x['name']):
            print('ENTRYPOINT_FUNC',x['name'],x['line'],x['lines'],'calls='+','.join(x['calls']))
    for a in anchors:
        if re.search(r'switch|FullChainV010',a['pattern']):
            print('ENTRYPOINT_ANCHOR line='+str(a['line'])+' snippet='+a['context'].replace('\n',' ')[:350])
if __name__=='__main__':inspect()
