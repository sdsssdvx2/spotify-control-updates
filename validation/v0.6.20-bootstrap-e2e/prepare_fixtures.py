from pathlib import Path
import copy, hashlib, importlib.util, json, runpy, shutil

ROOT=Path(__file__).resolve().parents[2]
V0618_MAIN_SHA='27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f'
V0618_ADDON_SHA='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
V0619_MAIN_SHA='45795b9622953a10c6eca2ee2f5a19fc4467c5143d5bdf7a9f2ad64841b9416f'
V0619_ADDON_SHA='df17018bdb5f62f55624070d047933387f62c049dae73cf5cefcc541bc412afa'
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP_SHA='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
MAIN_MANIFEST_URL=b'https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
CI_MANIFEST_URL=b'http://127.0.0.1:8765/manifest.json'


def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def sha_file(p): return hashlib.sha256(p.read_bytes()).hexdigest()

production_manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))
assert production_manifest['latest_version']=='0.6.20'
assert production_manifest['source_commit']=='3543ee39bd9afa353a4d276c2b6b0f86dccafd74'
assert production_manifest['payload_set_sha256']=='65bf8dff2f563ce5caf80f660db64b1f6b34ced3029c24dfbfa3463f2ba3bf52'
assert production_manifest['bootstrap']=={'version':'1.0.6','sha256':BOOTSTRAP_SHA,'size':42963}

# Build the previously-proven installed-layout carrier. This consumes the exact
# validated-v0614-repair-artifact.zip downloaded by the workflow and gives us
# Bootstrap 1.0.6, the resident agent, installed helper fixtures and Marketplace.
runpy.run_path(str(ROOT/'validation/bootstrap-contract-repair/build_bootstrap_fixture.py'),run_name='__main__')
carrier=ROOT/'ci-bootstrap-fixture'
assert carrier.is_dir()

# Reconstruct exact released v0.6.18/r7 and v0.6.19/r8 using the already released
# v0.6.19 deterministic builder rather than copying candidate text by hand.
spec=importlib.util.spec_from_file_location('v0619_builder',ROOT/'validation/v0.6.19/build_v0619.py')
mod=importlib.util.module_from_spec(spec); assert spec.loader is not None; spec.loader.exec_module(mod)
m=mod.load_base_manifest()
v18_main=mod.reconstruct_base_main(m); v18_addon=mod.reconstruct_base_addon(m)
v19_main,_=mod.build_main(v18_main); v19_addon,_,_=mod.build_addon(v18_addon)
assert len(v18_main)==281593 and sha_bytes(v18_main)==V0618_MAIN_SHA
assert len(v18_addon)==154926 and sha_bytes(v18_addon)==V0618_ADDON_SHA
assert len(v19_main)==281580 and sha_bytes(v19_main)==V0619_MAIN_SHA
assert len(v19_addon)==202849 and sha_bytes(v19_addon)==V0619_ADDON_SHA

for version,main,addon,main_sha,addon_sha in (
    ('v0619',v19_main,v19_addon,V0619_MAIN_SHA,V0619_ADDON_SHA),
    ('v0618',v18_main,v18_addon,V0618_MAIN_SHA,V0618_ADDON_SHA),
):
    fixture=ROOT/f'ci-bootstrap-fixture-{version}'
    shutil.rmtree(fixture,ignore_errors=True)
    shutil.copytree(carrier,fixture)
    root=fixture/'LocalAppData'/'SpotifyControl'; bin_dir=root/'bin'; bootstrap_dir=root/'bootstrap'
    (bin_dir/'spotify-control.ps1').write_bytes(main)
    (bin_dir/'addon-manager.ps1').write_bytes(addon)
    assert sha_file(bin_dir/'spotify-control.ps1')==main_sha
    assert sha_file(bin_dir/'addon-manager.ps1')==addon_sha
    assert sha_file(bin_dir/'spotify-control-agent.vbs')==AGENT_SHA
    exact_bootstrap=bootstrap_dir/'spotify-control-self-updater.ps1'
    exact_bytes=exact_bootstrap.read_bytes()
    assert len(exact_bytes)==42963 and sha_bytes(exact_bytes)==BOOTSTRAP_SHA

    # Released Bootstrap 1.0.6 pins main/manifest.json and pins its own running hash.
    # For a pre-merge branch E2E, make one CI-only execution copy that changes exactly
    # the manifest URL to localhost. The installed exact Bootstrap remains untouched.
    assert exact_bytes.count(MAIN_MANIFEST_URL)==1
    assert CI_MANIFEST_URL not in exact_bytes
    injected=exact_bytes.replace(MAIN_MANIFEST_URL,CI_MANIFEST_URL,1)
    assert injected.count(CI_MANIFEST_URL)==1
    restored=injected.replace(CI_MANIFEST_URL,MAIN_MANIFEST_URL,1)
    assert restored==exact_bytes and sha_bytes(restored)==BOOTSTRAP_SHA
    ci_bootstrap=bootstrap_dir/'spotify-control-self-updater-ci-local-manifest.ps1'
    ci_bootstrap.write_bytes(injected)

    # Serve a derived manifest locally. It is byte-for-byte semantically identical to
    # the release manifest except the bootstrap trust pin is changed to the CI execution
    # copy. Restore those two fields and the JSON object must equal production exactly.
    ci_manifest=copy.deepcopy(production_manifest)
    ci_manifest['bootstrap']['sha256']=sha_bytes(injected)
    ci_manifest['bootstrap']['size']=len(injected)
    restored_manifest=copy.deepcopy(ci_manifest)
    restored_manifest['bootstrap']={'version':'1.0.6','sha256':BOOTSTRAP_SHA,'size':42963}
    assert restored_manifest==production_manifest
    manifest_dir=fixture/'ci-manifest'
    manifest_dir.mkdir(parents=True,exist_ok=True)
    (manifest_dir/'manifest.json').write_text(json.dumps(ci_manifest,separators=(',',':')),encoding='utf-8',newline='')

    for name in ('update-state.json','update-transaction.json','rollback-state.json'):
        p=root/name
        if p.exists(): p.unlink()
    print('V0620_BOOTSTRAP_FIXTURE_PASS',version,len(main),main_sha,len(addon),addon_sha,'exact_bootstrap',len(exact_bytes),BOOTSTRAP_SHA,'ci_bootstrap',len(injected),sha_bytes(injected),'manifest_only_trust_pin_adjusted',True)

shutil.rmtree(carrier,ignore_errors=True)
