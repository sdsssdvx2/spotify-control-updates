from pathlib import Path
import hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
BASE_HEAD='750c5dca0087d9bc8dd69b75dcc301b5e83ad0ec'
BASE_PATH='validation/marketplace-lifecycle-tagify-state-preserving-v0.1.0/build_candidate.py'
BASE_TEST_PATH='validation/marketplace-lifecycle-tagify-state-preserving-v0.1.0/test_tagify_state_preserving.ps1'
OUT=HERE/'out/bin'
REPORT=HERE/'candidate-validation.json'

def sha(b): return hashlib.sha256(b).hexdigest()

def main():
    subprocess.check_call(['git','cat-file','-e',f'{BASE_HEAD}^{{commit}}'],cwd=ROOT)
    source=subprocess.check_output(['git','show',f'{BASE_HEAD}:{BASE_PATH}'],cwd=ROOT)
    if b"if(([string]$pkg.name).ToLowerInvariant() -ne 'tagify')" not in source:
        raise RuntimeError('Pinned v0.1.0 builder no longer contains the expected Tagify package-identity bug anchor.')
    temp=HERE/'_pinned_v010_builder.py'
    try:
        temp.write_bytes(source)
        subprocess.check_call([sys.executable,str(temp)],cwd=ROOT)
    finally:
        temp.unlink(missing_ok=True)
    main_path=OUT/'spotify-control.ps1'; addon_path=OUT/'addon-manager.ps1'
    main_bytes=main_path.read_bytes(); addon_bytes=addon_path.read_bytes()
    if (len(main_bytes),sha(main_bytes))!=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99'):
        raise RuntimeError(f'v0.1.0 candidate main drift: {len(main_bytes)} {sha(main_bytes)}')
    if (len(addon_bytes),sha(addon_bytes))!=(341958,'5931e7e425d7fa715b4fd18bc0d74301309c08cd5d3b756415d853f24aa716b8'):
        raise RuntimeError(f'v0.1.0 candidate addon drift: {len(addon_bytes)} {sha(addon_bytes)}')
    bom=b'\xef\xbb\xbf' if addon_bytes.startswith(b'\xef\xbb\xbf') else b''
    text=addon_bytes[len(bom):].decode('utf-8')
    old="if(([string]$pkg.name).ToLowerInvariant() -ne 'tagify'){throw 'Tagify package identity mismatch.'}"
    new="if([string]$pkg.name -cne 'tagify-secret'){throw 'Tagify package identity mismatch.'}"
    if text.count(old)!=1:
        raise RuntimeError(f'Tagify package identity correction anchor count drifted: {text.count(old)}')
    text=text.replace(old,new,1)
    corrected=bom+text.encode('utf-8')
    addon_path.write_bytes(corrected)
    report=json.loads(REPORT.read_text(encoding='utf-8'))
    report['correction']={
        'schema':1,
        'supersedes_validation':'v0.1.0',
        'pinned_validation_head':BASE_HEAD,
        'reason':'official authenticated Tagify v2.5.0-v3.3.2 release assets use package.json name tagify-secret under common root tagify',
        'package_name_contract':'tagify-secret',
        'manifest_name_contract':'Tagify',
        'production_surface_changed':False
    }
    report['candidate_addon']={'size':len(corrected),'sha256':sha(corrected)}
    REPORT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('TAGIFY_STATE_PRESERVING_V011_BUILD_PASS',len(main_bytes),sha(main_bytes),len(corrected),sha(corrected))

if __name__=='__main__': main()
