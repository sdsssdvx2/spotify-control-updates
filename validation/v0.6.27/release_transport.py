from pathlib import Path
import argparse, hashlib, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE_COMMIT = '5cf131e7bc168f686c7b6fc933a713f4d96b9dd3'
SOURCE_PATH = 'validation/v0.6.26/release_transport.py'
SOURCE_BLOB = '8f12f3cb808be7909570556f69b8a1eb13fdcde8'

BASE_COMMIT = '5cf131e7bc168f686c7b6fc933a713f4d96b9dd3'
BASE_VERSION = '0.6.26'
NEW_VERSION = '0.6.27'
BASE_MAIN_SIZE = 284311
BASE_MAIN_SHA = 'd7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1'
BASE_ADDON_SIZE = 291294
BASE_ADDON_SHA = '4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f'
TARGET_MAIN_SIZE = 284317
TARGET_MAIN_SHA = '9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787'
TARGET_ADDON_SIZE = 303745
TARGET_ADDON_SHA = 'c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'
AGENT_SIZE = 4855
AGENT_SHA = '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP = {'version':'1.0.6','sha256':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6','size':42963}
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files','eternal-jukebox','ivLyrics','playlist-maker']
VALIDATION_HEAD = 'ac6a89298af835b65d4948ed0587341bb3cc7ff9'
VALIDATION_BLOB = '99efd34930aca9f463983f801fe91593539017f1'
VALIDATION_PUSH_RUN = '40462233405'
VALIDATION_PR_RUN = '40462367886'
VALIDATION_STABLE_PR_RUN = '40462367892'
VALIDATION_PR = 85
VALIDATION_PUSH_ARTIFACT = 12714414518
VALIDATION_PUSH_ARTIFACT_DIGEST = 'sha256:5f88fb01df3c01f21474934421b642884c28b83f090d01462cb543a973e81d04'
VALIDATION_PR_ARTIFACT = 12714813864
VALIDATION_PR_ARTIFACT_DIGEST = 'sha256:a3906fbf60c23ff660339b84e90f3b1087e59e6a7dca7c27dec1d288bdb7570e'
AUDIT_HEAD = '52a9c0f633c87a0f4ce70077aaec22e72f9b9d8f'
AUDIT_RUN = '40460929873'
AUDIT_ARTIFACT = 12714720971
AUDIT_ARTIFACT_DIGEST = 'sha256:161a1619ffea938eec444add714f4cbb330d3fc05c2aa88c7dc3190d3d63d05a'
AUDIT_CATALOG_JSON_SHA = '2592f43a26c3c49b9d58b8244654d27448d801995465c7c8e4ba8d3159b9aa27'

BASE_OUT = ROOT / 'validation/v0.6.26/out/bin'
TARGET_OUT = ROOT / 'validation/v0.6.27/out/bin'
REPORT = ROOT / 'validation/v0.6.27/candidate-validation.json'
META = ROOT / 'validation/v0.6.27/release-metadata.json'
MAIN_DIR = ROOT / 'packages/v0.6.27/main-v0626-to-v0627'
ADDON_DIR = ROOT / 'packages/v0.6.27/addon-v065r15-to-v065r16'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_engine():
    blob = subprocess.check_output(['git','rev-parse',f'{SOURCE_COMMIT}:{SOURCE_PATH}'], cwd=ROOT, text=True).strip()
    if blob != SOURCE_BLOB:
        raise RuntimeError(f'pinned v0.6.26 release transport blob drifted: {blob}')
    source = subprocess.check_output(['git','show',f'{SOURCE_COMMIT}:{SOURCE_PATH}'], cwd=ROOT)
    fake = ROOT / SOURCE_PATH
    ns = {'__file__': str(fake), '__name__': 'v0626_release_transport_pinned'}
    exec(compile(source, str(fake), 'exec'), ns)

    overrides = {
        'ROOT': ROOT,
        'BASE_COMMIT': BASE_COMMIT, 'BASE_VERSION': BASE_VERSION, 'NEW_VERSION': NEW_VERSION,
        'BASE_MAIN_SHA': BASE_MAIN_SHA, 'BASE_MAIN_SIZE': BASE_MAIN_SIZE,
        'BASE_ADDON_SHA': BASE_ADDON_SHA, 'BASE_ADDON_SIZE': BASE_ADDON_SIZE,
        'TARGET_MAIN_SHA': TARGET_MAIN_SHA, 'TARGET_MAIN_SIZE': TARGET_MAIN_SIZE,
        'TARGET_ADDON_SHA': TARGET_ADDON_SHA, 'TARGET_ADDON_SIZE': TARGET_ADDON_SIZE,
        'AGENT_SHA': AGENT_SHA, 'AGENT_SIZE': AGENT_SIZE, 'BOOTSTRAP': BOOTSTRAP,
        'REGISTRY_SHA': REGISTRY_SHA, 'ADAPTER_SHA': ADAPTER_SHA, 'AUTHORIZED_NAMES': AUTHORIZED_NAMES,
        'VALIDATION_HEAD': VALIDATION_HEAD, 'VALIDATION_BLOB': VALIDATION_BLOB,
        'VALIDATION_PUSH_RUN': VALIDATION_PUSH_RUN, 'VALIDATION_PR_RUN': VALIDATION_PR_RUN,
        'VALIDATION_STABLE_PR_RUN': VALIDATION_STABLE_PR_RUN, 'VALIDATION_PR': VALIDATION_PR,
        'VALIDATION_PUSH_ARTIFACT': VALIDATION_PUSH_ARTIFACT,
        'VALIDATION_PUSH_ARTIFACT_DIGEST': VALIDATION_PUSH_ARTIFACT_DIGEST,
        'VALIDATION_PR_ARTIFACT': VALIDATION_PR_ARTIFACT,
        'VALIDATION_PR_ARTIFACT_DIGEST': VALIDATION_PR_ARTIFACT_DIGEST,
        'AUDIT_HEAD': AUDIT_HEAD, 'AUDIT_RUN': AUDIT_RUN, 'AUDIT_ARTIFACT': AUDIT_ARTIFACT,
        'AUDIT_ARTIFACT_DIGEST': AUDIT_ARTIFACT_DIGEST, 'AUDIT_CATALOG_JSON_SHA': AUDIT_CATALOG_JSON_SHA,
        'BASE_OUT': BASE_OUT, 'TARGET_OUT': TARGET_OUT, 'REPORT': REPORT, 'META': META,
        'MAIN_DIR': MAIN_DIR, 'ADDON_DIR': ADDON_DIR,
    }
    ns.update(overrides)

    def build_candidate():
        subprocess.check_call([sys.executable, str(ROOT/'validation/v0.6.27/build_v0627.py'), '--build'], cwd=ROOT)
        main = (TARGET_OUT/'spotify-control.ps1').read_bytes()
        addon = (TARGET_OUT/'addon-manager.ps1').read_bytes()
        if (len(main), sha(main)) != (TARGET_MAIN_SIZE, TARGET_MAIN_SHA):
            raise RuntimeError('validated v0.6.27 main identity mismatch')
        if (len(addon), sha(addon)) != (TARGET_ADDON_SIZE, TARGET_ADDON_SHA):
            raise RuntimeError('validated r16 addon identity mismatch')
        return main, addon

    def base_payloads():
        subprocess.check_call([sys.executable, str(ROOT/'validation/v0.6.26/build_v0626.py'), '--build'], cwd=ROOT)
        main = (BASE_OUT/'spotify-control.ps1').read_bytes()
        addon = (BASE_OUT/'addon-manager.ps1').read_bytes()
        if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
            raise RuntimeError('v0.6.26 main base identity mismatch')
        if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
            raise RuntimeError('r15 addon base identity mismatch')
        return main, addon

    ns['build_candidate'] = build_candidate
    ns['base_payloads'] = base_payloads

    def build_packages():
        target_main, target_addon = build_candidate()
        base_main, base_addon = base_payloads()
        main_patch = ns['build_full_file_patch']('bin/spotify-control.ps1', base_main, target_main, MAIN_DIR)
        addon_patch = ns['build_full_file_patch']('bin/addon-manager.ps1', base_addon, target_addon, ADDON_DIR)
        report_bytes = REPORT.read_bytes()
        report_sha = sha(report_bytes)
        metadata = {
            'schema':1, 'base_commit':BASE_COMMIT, 'base_version':BASE_VERSION, 'version':NEW_VERSION, 'addon_version':'0.6.5-r16',
            'candidate_main':{'size':TARGET_MAIN_SIZE,'sha256':TARGET_MAIN_SHA},
            'candidate_addon':{'size':TARGET_ADDON_SIZE,'sha256':TARGET_ADDON_SHA},
            'resident_agent':{'size':AGENT_SIZE,'sha256':AGENT_SHA}, 'bootstrap':BOOTSTRAP,
            'authority_expanded':False, 'new_auto_install_authority':False,
            'auto_authority':AUTHORIZED_NAMES, 'registry_fingerprint':REGISTRY_SHA, 'source_adapter_fingerprint':ADAPTER_SHA,
            'star_ratings_provenance':{
                'mode':'authenticated-release-dist-catalog-v1','source_watch_only':True,'mutation_mode':'deny','install_mode':'marketplace-owned',
                'data_policy':'playlist-backed-ratings-preserve','catalog_json_sha256':AUDIT_CATALOG_JSON_SHA,
                'versions':['2.0.0','2.0.1','2.0.2','2.0.3','2.0.4','2.0.5','2.0.6','2.0.7','2.0.8','2.1.0','2.1.1','2.1.2','2.1.3'],
                'active_original_proof':True,'performance_original_backup_proof':True,'rescue_copy_excluded':True,
                'known_transform_sha256':'6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3',
                'production_anchor_version':'2.1.3','production_anchor_sha256':'198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1',
            },
            'validation':{
                'head':VALIDATION_HEAD,'builder_blob':VALIDATION_BLOB,'push_run':VALIDATION_PUSH_RUN,'pr_run':VALIDATION_PR_RUN,
                'stable_pr_run':VALIDATION_STABLE_PR_RUN,'pr':VALIDATION_PR,'pr_closed_unmerged':True,
                'push_artifact_id':VALIDATION_PUSH_ARTIFACT,'push_artifact_digest':VALIDATION_PUSH_ARTIFACT_DIGEST,
                'pr_artifact_id':VALIDATION_PR_ARTIFACT,'pr_artifact_digest':VALIDATION_PR_ARTIFACT_DIGEST,
                'audit_head':AUDIT_HEAD,'audit_run':AUDIT_RUN,'audit_artifact_id':AUDIT_ARTIFACT,'audit_artifact_digest':AUDIT_ARTIFACT_DIGEST,
                'audit_catalog_json_sha256':AUDIT_CATALOG_JSON_SHA,'deterministic_report_sha256':report_sha,
            },
            'transport':{'main':main_patch,'addon':addon_patch},
        }
        META.parent.mkdir(parents=True, exist_ok=True)
        META.write_text(json.dumps(metadata, indent=2, sort_keys=True)+'\n', encoding='utf-8', newline='\n')
        print('V0627_RELEASE_PACKAGES_PASS', TARGET_MAIN_SIZE, TARGET_MAIN_SHA, TARGET_ADDON_SIZE, TARGET_ADDON_SHA, report_sha)
        return metadata

    ns['build_packages'] = build_packages
    return ns


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--build-packages', action='store_true')
    p.add_argument('--write-manifest', action='store_true')
    p.add_argument('--source-commit')
    p.add_argument('--validate-published', action='store_true')
    args = p.parse_args()
    modes = sum(bool(x) for x in (args.build_packages, args.write_manifest, args.validate_published))
    if modes != 1:
        p.error('choose exactly one mode')
    ns = load_engine()
    if args.build_packages:
        ns['build_packages']()
    elif args.write_manifest:
        if not args.source_commit:
            p.error('--source-commit is required with --write-manifest')
        ns['write_manifest'](args.source_commit)
    else:
        ns['validate_published']()


if __name__ == '__main__':
    main()
