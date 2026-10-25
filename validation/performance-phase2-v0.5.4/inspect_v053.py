from pathlib import Path
import hashlib, io, subprocess, sys, tempfile, zipfile, shutil
ROOT=Path.cwd()
COMMIT='ba031d1fd4bc01a1a1ee54d7f15cb998a6640785'
ZIP='SpotifyControl-Track-Transition-Background-Guarded-Acceptance-v0.5.3.zip'
SIZE=126853
SHA='b7aea344cd9a67c0b46886b41118bc3a33c76d2a2d7d6c8facdfa284b5baea43'
def h(b): return hashlib.sha256(b).hexdigest()
def function(text,name):
    a=text.index('function '+name+' {')
    b=text.find('\nfunction ',a+1)
    if b<0:b=text.find('\ntry{',a+1)
    if b<0:b=len(text)
    return text[a:b]
subprocess.run(['git','fetch','--no-tags','origin',COMMIT],check=True)
wd=Path(tempfile.mkdtemp(prefix='v053-worktree-'))
try:
    subprocess.run(['git','worktree','add','--detach',str(wd),COMMIT],check=True)
    subprocess.run([sys.executable,'validation/performance-phase2-v0.5.3/build_v053.py'],cwd=wd,check=True)
    raw=(wd/ZIP).read_bytes(); assert len(raw)==SIZE and h(raw)==SHA,(len(raw),h(raw))
    with zipfile.ZipFile(io.BytesIO(raw)) as z: s=z.read('track-transition-direct-patch-acceptance.ps1').decode('utf-8-sig').replace('\r\n','\n')
    for n in ['Build-FocusedPatchVariantMatrix','Assert-DirectPatchEligibility','Restore-DirectPatches','Prepare-Variant','Invoke-Lab','Invoke-SelfTest','Restore-OriginalXpui','Build-TextReport']:
        print('\n===== FUNCTION',n,'=====')
        print(function(s,n))
finally:
    try: subprocess.run(['git','worktree','remove','--force',str(wd)],check=False)
    finally: shutil.rmtree(wd,ignore_errors=True)
