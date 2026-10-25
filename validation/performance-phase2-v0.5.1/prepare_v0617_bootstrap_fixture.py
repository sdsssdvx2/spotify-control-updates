from pathlib import Path
import hashlib,runpy,shutil,subprocess

ROOT=Path(__file__).resolve().parents[2]
MAIN17='5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'
ADDON_R7='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
AGENT='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
V0617_MANIFEST_COMMIT='36b15a2ed2f9a23fffbeaf91de78b7854f6108b2'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

runpy.run_path(str(ROOT/'validation/bootstrap-contract-repair/build_bootstrap_fixture.py'),run_name='__main__')
manifest=ROOT/'manifest.json';current=manifest.read_bytes()
old=subprocess.check_output(['git','show',f'{V0617_MANIFEST_COMMIT}:manifest.json'])
try:
    manifest.write_bytes(old)
    runpy.run_path(str(ROOT/'validation/v0.6.17/publish_v0617.py'),run_name='__main__')
finally:
    manifest.write_bytes(current)

pub=ROOT/'publication-v0.6.17'
main=pub/'candidate-main-v0.6.17.ps1';addon=pub/'candidate-addon-v0.6.5-r7.ps1'
assert main.stat().st_size==266318 and sha(main)==MAIN17
assert addon.stat().st_size==154926 and sha(addon)==ADDON_R7
fixture=ROOT/'ci-bootstrap-fixture';root=fixture/'LocalAppData'/'SpotifyControl';bin_dir=root/'bin'
shutil.copyfile(main,bin_dir/'spotify-control.ps1');shutil.copyfile(addon,bin_dir/'addon-manager.ps1')
assert sha(bin_dir/'spotify-control.ps1')==MAIN17
assert sha(bin_dir/'addon-manager.ps1')==ADDON_R7
assert sha(bin_dir/'spotify-control-agent.vbs')==AGENT
assert sha(root/'bootstrap'/'spotify-control-self-updater.ps1')==BOOTSTRAP
for name in ('update-state.json','update-transaction.json','rollback-state.json'):
    p=root/name
    if p.exists():p.unlink()
print('V0617_BOOTSTRAP_FIXTURE_PASS',main.stat().st_size,MAIN17,addon.stat().st_size,ADDON_R7)
