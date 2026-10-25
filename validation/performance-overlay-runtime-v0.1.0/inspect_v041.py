from pathlib import Path
import subprocess, tempfile, zipfile, re, shutil, os

SRC_COMMIT='4d9eb71d1fa97b70d839dc887cdc8f5531d2ff8b'
BUILDER='validation/performance-phase2-v0.4.1/build_and_validate.py'

with tempfile.TemporaryDirectory() as td:
    td=Path(td)
    subprocess.run(['git','worktree','add','--detach',str(td/'src'),SRC_COMMIT],check=True)
    src=td/'src'
    subprocess.run(['python',BUILDER],cwd=src,check=True)
    z=src/'SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.1.zip'
    with zipfile.ZipFile(z) as zz:
        s=zz.read('track-transition-isolation.ps1').decode('utf-8-sig')

    print('SCRIPT_LENGTH',len(s.encode('utf-8-sig')))
    print('=== FUNCTIONS ===')
    for m in re.finditer(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',s):
        print(m.group(1))

    wanted=[
        'Assert-ExactRuntime','Suspend-Resident','Resume-Resident','Stop-SpotifyResiduals',
        'Close-SpotifyForMutation','Get-TreeFingerprint','Restore-OriginalXpui','Get-ProcessSnapshot',
        'Measure-Condition','Send-MediaKey','Write-IndexVariantAtomic','Backup-ProtectedPersistence',
        'Get-ActiveXpui','Get-ConfigSnapshot'
    ]
    def function_block(name):
        pat=re.compile(r'(?m)^function\s+'+re.escape(name)+r'\s*\{')
        m=pat.search(s)
        if not m:return None
        start=m.start(); depth=0; in_s=False; in_d=False; esc=False
        i=m.end()-1
        while i<len(s):
            ch=s[i]
            if ch=='`':
                i+=2; continue
            if not in_d and ch=="'": in_s=not in_s
            elif not in_s and ch=='"': in_d=not in_d
            elif not in_s and not in_d:
                if ch=='{': depth+=1
                elif ch=='}':
                    depth-=1
                    if depth==0:return s[start:i+1]
            i+=1
        return None
    print('=== SELECTED BLOCKS ===')
    for n in wanted:
        b=function_block(n)
        print('---',n,'FOUND' if b else 'MISSING','---')
        if b: print(b[:12000])

    print('=== PARAM HEAD ===')
    print(s[:8000])
    print('=== MAIN TAIL ===')
    print(s[-18000:])
