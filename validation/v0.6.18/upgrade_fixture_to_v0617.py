from pathlib import Path
import runpy, hashlib
ns=runpy.run_path('validation/bootstrap-contract-repair/build_bootstrap_fixture.py',run_name='bootstrap_fixture_v15')
root=Path('ci-bootstrap-fixture/LocalAppData/SpotifyControl/bin')
m=ns['load_manifest']()
main=(root/'spotify-control.ps1').read_bytes()
assert hashlib.sha256(main).hexdigest()=='4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f'
for a,b in [('0.6.15','0.6.16'),('0.6.16','0.6.17')]: main=ns['apply_main'](main,m,a,b)
assert len(main)==266318 and hashlib.sha256(main).hexdigest()=='5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'
(root/'spotify-control.ps1').write_bytes(main)
addon=(root/'addon-manager.ps1').read_bytes()
for a,b in [('0.6.15','0.6.16'),('0.6.16','0.6.17')]:
    patch,addon2=ns['decoded_payload'](m,a,b,'bin/addon-manager.ps1')
    assert hashlib.sha256(addon).hexdigest()==patch['from_sha256']
    addon=addon2
assert len(addon)==154926 and hashlib.sha256(addon).hexdigest()=='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
(root/'addon-manager.ps1').write_bytes(addon)
print('V0617_FIXTURE_OK',len(main),hashlib.sha256(main).hexdigest(),len(addon),hashlib.sha256(addon).hexdigest())
