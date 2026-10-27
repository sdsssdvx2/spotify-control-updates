from __future__ import annotations
import argparse, hashlib, json, shutil, subprocess, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'validation/marketplace-record-discovery-v0.1.0'
DIST=HERE/'dist'
PKG=HERE/'package'
READER_HEAD='14a2f9bfacc54e617aec024b44b7f367dec28bbe'
READER_PATH='validation/star-ratings-runtime-topology-collector-v0.1.0/LevelDbReadOnly.cs'
READER_BLOB='66de32a1dafcb4fbca9ebe0509cf326fd8a65a5e'
UPSTREAM_MARKETPLACE_COMMIT='7f357885a3514a55d426fd43edfd705d583a5cdd'

def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def git_bytes(commit:str,path:str)->bytes:return subprocess.check_output(['git','show',f'{commit}:{path}'],cwd=ROOT)
def git_blob(commit:str,path:str)->str:return subprocess.check_output(['git','rev-parse',f'{commit}:{path}'],cwd=ROOT,text=True).strip()
def build():
 if git_blob(READER_HEAD,READER_PATH)!=READER_BLOB:raise RuntimeError('pinned LevelDB reader blob drift')
 if PKG.exists():shutil.rmtree(PKG)
 if DIST.exists():shutil.rmtree(DIST)
 PKG.mkdir(parents=True);DIST.mkdir(parents=True)
 reader=git_bytes(READER_HEAD,READER_PATH);collector=(HERE/'Collect-Marketplace-Records.ps1').read_bytes()
 (PKG/'LevelDbReadOnly.cs').write_bytes(reader);(PKG/'Collect-Marketplace-Records.ps1').write_bytes(collector)
 cmd='''@echo off\r\nsetlocal\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-Marketplace-Records.ps1" -OutputPath "%~dp0marketplace-records-latest.json"\r\nset ERR=%ERRORLEVEL%\r\necho.\r\nif not "%ERR%"=="0" echo Collector failed with exit code %ERR%.\r\nif "%ERR%"=="0" echo Done. Upload marketplace-records-latest.json to the ChatGPT conversation.\r\npause\r\nexit /b %ERR%\r\n'''.encode('ascii')
 (PKG/'Run-Marketplace-Records.cmd').write_bytes(cmd)
 contract={'schema':1,'collector_version':'0.1.0','read_only':True,'reader':{'head':READER_HEAD,'path':READER_PATH,'blob':READER_BLOB,'size':len(reader),'sha256':sha(reader)},'marketplace_upstream_commit':UPSTREAM_MARKETPLACE_COMMIT,'production_base':'d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2','mutation_authority_expanded':False}
 (PKG/'SOURCE_CONTRACT.json').write_text(json.dumps(contract,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
 files=sorted(p for p in PKG.iterdir() if p.is_file()); sums=''.join(f'{sha(p.read_bytes())}  {p.name}\n' for p in files)
 (PKG/'SHA256SUMS.txt').write_text(sums,encoding='ascii',newline='\n')
 out=DIST/'marketplace-record-discovery-v0.1.0.zip'
 with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for p in sorted(PKG.iterdir(),key=lambda x:x.name.lower()):
   info=zipfile.ZipInfo(p.name,date_time=(2026,10,28,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,p.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
 print('MARKETPLACE_RECORD_PACKAGE_PASS',out.stat().st_size,sha(out.read_bytes()),len(reader),sha(reader))
def main():
 p=argparse.ArgumentParser();p.add_argument('--build',action='store_true');a=p.parse_args()
 if not a.build:p.error('use --build')
 build()
if __name__=='__main__':main()
