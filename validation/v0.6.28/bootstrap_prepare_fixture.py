from pathlib import Path
import copy,hashlib,json,runpy,shutil,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
START_MAIN_SHA='9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787'
START_MAIN_SIZE=284317
START_ADDON_SHA='c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'
START_ADDON_SIZE=303745
TARGET_MAIN_SHA='af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
TARGET_MAIN_SIZE=284321
TARGET_ADDON_SHA='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
TARGET_ADDON_SIZE=323385
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP_SHA='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
SOURCE_COMMIT='bb6d90146f20b73d36fbf8cb813f1b190f403c48'
PAYLOAD_SET='4be96c5d41c2160ed9ac96001b469998595629232929b82c8b0f34b11fda3b43'
MAIN_MANIFEST_URL=b'https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
CI_MANIFEST_URL=b'http://127.0.0.1:8765/manifest.json'


def sha_bytes(b):return hashlib.sha256(b).hexdigest()
def sha_file(p):return hashlib.sha256(p.read_bytes()).hexdigest()

release_manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))
assert release_manifest['latest_version']=='0.6.28'
assert release_manifest['source_commit']==SOURCE_COMMIT
assert release_manifest['payload_set_sha256']==PAYLOAD_SET
assert release_manifest['bootstrap']=={'version':'1.0.6','sha256':BOOTSTRAP_SHA,'size':42963}
latest={x['path']:x for x in release_manifest['latest_files']}
assert latest['bin/spotify-control.ps1']=={'path':'bin/spotify-control.ps1','sha256':TARGET_MAIN_SHA,'size':TARGET_MAIN_SIZE}
assert latest['bin/addon-manager.ps1']=={'path':'bin/addon-manager.ps1','sha256':TARGET_ADDON_SHA,'size':TARGET_ADDON_SIZE}
assert latest['bin/spotify-control-agent.vbs']=={'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':4855}
edges=[e for e in release_manifest['updates'] if e['from_version']=='0.6.27' and e['to_version']=='0.6.28']
assert len(edges)==1 and len(edges[0]['patches'])==2

runpy.run_path(str(ROOT/'validation/bootstrap-contract-repair/build_bootstrap_fixture.py'),run_name='__main__')
carrier=ROOT/'ci-bootstrap-fixture'
assert carrier.is_dir()
subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.27/build_v0627.py'),'--build'],cwd=ROOT)
base_out=ROOT/'validation/v0.6.27/out/bin'
start_main=(base_out/'spotify-control.ps1').read_bytes();start_addon=(base_out/'addon-manager.ps1').read_bytes()
assert (len(start_main),sha_bytes(start_main))==(START_MAIN_SIZE,START_MAIN_SHA)
assert (len(start_addon),sha_bytes(start_addon))==(START_ADDON_SIZE,START_ADDON_SHA)

fixture=ROOT/'ci-bootstrap-fixture-v0627-to-v0628'
shutil.rmtree(fixture,ignore_errors=True);shutil.copytree(carrier,fixture)
root=fixture/'LocalAppData'/'SpotifyControl';bin_dir=root/'bin';bootstrap_dir=root/'bootstrap'
(bin_dir/'spotify-control.ps1').write_bytes(start_main);(bin_dir/'addon-manager.ps1').write_bytes(start_addon)
assert sha_file(bin_dir/'spotify-control.ps1')==START_MAIN_SHA
assert sha_file(bin_dir/'addon-manager.ps1')==START_ADDON_SHA
assert sha_file(bin_dir/'spotify-control-agent.vbs')==AGENT_SHA

exact_bootstrap=bootstrap_dir/'spotify-control-self-updater.ps1';exact_bytes=exact_bootstrap.read_bytes()
assert (len(exact_bytes),sha_bytes(exact_bytes))==(42963,BOOTSTRAP_SHA)
assert exact_bytes.count(MAIN_MANIFEST_URL)==1 and CI_MANIFEST_URL not in exact_bytes
injected=exact_bytes.replace(MAIN_MANIFEST_URL,CI_MANIFEST_URL,1)
assert injected.count(CI_MANIFEST_URL)==1 and injected.replace(CI_MANIFEST_URL,MAIN_MANIFEST_URL,1)==exact_bytes
(bootstrap_dir/'spotify-control-self-updater-ci-local-manifest.ps1').write_bytes(injected)
ci_manifest=copy.deepcopy(release_manifest);ci_manifest['bootstrap']['sha256']=sha_bytes(injected);ci_manifest['bootstrap']['size']=len(injected)
restored=copy.deepcopy(ci_manifest);restored['bootstrap']={'version':'1.0.6','sha256':BOOTSTRAP_SHA,'size':42963};assert restored==release_manifest
manifest_dir=fixture/'ci-manifest';manifest_dir.mkdir(parents=True,exist_ok=True)
(manifest_dir/'manifest.json').write_text(json.dumps(ci_manifest,separators=(',',':')),encoding='utf-8',newline='')
for name in ('update-state.json','update-transaction.json','rollback-state.json'):
    p=root/name
    if p.exists():p.unlink()
print('V0628_BOOTSTRAP_FIXTURE_PASS',len(start_main),START_MAIN_SHA,len(start_addon),START_ADDON_SHA,'exact_bootstrap',len(exact_bytes),BOOTSTRAP_SHA,'ci_bootstrap',len(injected),sha_bytes(injected),'release_source',SOURCE_COMMIT,'payload',PAYLOAD_SET)
shutil.rmtree(carrier,ignore_errors=True)
