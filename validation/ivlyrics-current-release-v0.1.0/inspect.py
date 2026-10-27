from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE='d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
ADDON=ROOT/'validation/v0.6.28/out/bin/addon-manager.ps1'
EXPECTED=(323385,'5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285')
TARGETS=[
 'Get-IvLyricsReleaseInfo','Download-IvLyricsReleaseStage','Find-StagedAppRoot',
 'Get-IvLyricsOfficialTagTree','Test-IvLyricsTreeAgainstOfficialTag',
 'Test-IvLyricsStageRoot','Test-IvLyricsZipArchiveSafety',
 'Get-IvLyricsInstalledBaselineProof','Test-IvLyricsOfficialTagFallbackEligible',
 'Invoke-IvLyricsOfficialTagProofOnlineSelfTest','Get-DirectoryGitSnapshot'
]

def sha(b):return hashlib.sha256(b).hexdigest()
def git(*a):return subprocess.check_output(['git',*a],cwd=ROOT,text=True).strip()
def blocks(text):
    hits=list(re.finditer(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text))
    out={}
    for i,h in enumerate(hits):
        e=hits[i+1].start() if i+1<len(hits) else len(text)
        out[h.group(1)]=text[h.start():e].rstrip()
    return out

def main():
    if git('merge-base',BASE,'HEAD')!=BASE:raise SystemExit('wrong base')
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.28/build_v0628.py'),'--build'],cwd=ROOT)
    raw=ADDON.read_bytes()
    if (len(raw),sha(raw))!=EXPECTED:raise SystemExit(f'r17 drift {len(raw)} {sha(raw)}')
    text=raw.decode('utf-8-sig'); fs=blocks(text)
    miss=[n for n in TARGETS if n not in fs]
    if miss:raise SystemExit(f'missing {miss}')
    fnames=set(fs)
    report={'base':BASE,'head':git('rev-parse','HEAD'),'addon':{'size':len(raw),'sha256':sha(raw)},'functions':{}}
    for name in TARGETS:
        body=fs[name]
        calls=[]
        for c in sorted(fnames):
            if c!=name and re.search(r'(?i)(?<![A-Za-z0-9_-])'+re.escape(c)+r'(?![A-Za-z0-9_-])',body):calls.append(c)
        report['functions'][name]={'sha256':sha(body.encode()),'chars':len(body),'calls':calls,'source':body}
        print(f'===== BEGIN {name} =====')
        print(body)
        print(f'===== END {name} =====')
        print(f'CALLS {name}: '+', '.join(calls))
    p=ROOT/'validation/ivlyrics-current-release-v0.1.0/inspection.json'
    p.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('IVLYRICS_R17_EXACT_HANDLER_INSPECTION_PASS')
if __name__=='__main__':main()
