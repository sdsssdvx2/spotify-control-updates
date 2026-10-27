from pathlib import Path
import argparse, hashlib, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE_COMMIT = '25daf4a295e7737bd12e96b584467da53245e37a'
SOURCE_PATH = 'validation/v0.6.27/release_transport.py'
SOURCE_BLOB = 'e3da85b3f8320cc98a519d304456188362af63bc'

BASE_COMMIT = '25daf4a295e7737bd12e96b584467da53245e37a'
BASE_VERSION = '0.6.27'
NEW_VERSION = '0.6.28'
BASE_MAIN_SIZE = 284317
BASE_MAIN_SHA = '9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787'
BASE_ADDON_SIZE = 303745
BASE_ADDON_SHA = 'c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'
TARGET_MAIN_SIZE = 284321
TARGET_MAIN_SHA = 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
TARGET_ADDON_SIZE = 323385
TARGET_ADDON_SHA = '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
AGENT_SIZE = 4855
AGENT_SHA = '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP = {'version':'1.0.6','sha256':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6','size':42963}
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files','eternal-jukebox','ivLyrics','playlist-maker']

VALIDATION_HEAD = 'f8ed342f0f414abba3d2a42f93720057ae8b55e5'
VALIDATION_BLOB = 'a52961092730a3216ea2d4b4dceaaa814f33ce4e'
VALIDATION_PR_RUN = '40503043002'
VALIDATION_STABLE_PR_RUN = '40503042928'
VALIDATION_PR = 93
VALIDATION_ARTIFACT = 12733622589
VALIDATION_ARTIFACT_DIGEST = 'sha256:de9a7f8b1bdb5aae2c13b7914df8dea783e7fa4f59b9e23a451280a48a9be2e8'

AUDIT_HEAD = 'cc304a1b1c4b3178c7269884a0d24332a5525ec6'
AUDIT_RUN = '40498778865'
AUDIT_ARTIFACT = 12731962049
AUDIT_ARTIFACT_DIGEST = 'sha256:157291e1d54b68e8ad5a90662f301f6cb8f48a9e67ab3b0d01f88e0e0d47991b'
COLLECTOR_HEAD = '008daeb5c57992b79fabc2ad9ca54192f1d78463'
COLLECTOR_RUN = '40499795044'
COLLECTOR_ARTIFACT = 12732098347
COLLECTOR_ARTIFACT_DIGEST = 'sha256:77c0c4a9976fcbb699608d41e3f10d64c82420b6e3ffed85d7f390d7c86d395b'
CATALOG_PAYLOAD_SHA = 'c12391e57a393d37d70ffd7a984bdbb6af9f4a83cf3c2b0a8c9bf040247c731f'
CURRENT_COMMIT = '9454b55e454fb354ecedcf3f72c5a4f0a9671651'
CURRENT_SIZE = 10267
CURRENT_SHA = '0aea69246e14156b22a10261af07b84f3abc58bed4368e03f740ed76db329738'
REAL_PC_REPORT_SIZE = 16730
REAL_PC_REPORT_SHA = '7349326c6567806f6c45bacb741d32649a6afc424b797d7249358cd9b8f5b38b'

BASE_OUT = ROOT / 'validation/v0.6.27/out/bin'
TARGET_OUT = ROOT / 'validation/v0.6.28/out/bin'
REPORT = ROOT / 'validation/v0.6.28/candidate-validation.json'
META = ROOT / 'validation/v0.6.28/release-metadata.json'
MAIN_DIR = ROOT / 'packages/v0.6.28/main-v0627-to-v0628'
ADDON_DIR = ROOT / 'packages/v0.6.28/addon-v065r16-to-v065r17'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_engine():
    blob = subprocess.check_output(['git','rev-parse',f'{SOURCE_COMMIT}:{SOURCE_PATH}'], cwd=ROOT, text=True).strip()
    if blob != SOURCE_BLOB:
        raise RuntimeError(f'pinned v0.6.27 release transport blob drifted: {blob}')
    source = subprocess.check_output(['git','show',f'{SOURCE_COMMIT}:{SOURCE_PATH}'], cwd=ROOT)
    fake = ROOT / SOURCE_PATH
    outer = {'__file__': str(fake), '__name__': 'v0627_release_transport_pinned'}
    exec(compile(source, str(fake), 'exec'), outer)
    ns = outer['load_engine']()

    overrides = {
        'ROOT': ROOT,
        'BASE_COMMIT': BASE_COMMIT, 'BASE_VERSION': BASE_VERSION, 'NEW_VERSION': NEW_VERSION,
        'BASE_MAIN_SHA': BASE_MAIN_SHA, 'BASE_MAIN_SIZE': BASE_MAIN_SIZE,
        'BASE_ADDON_SHA': BASE_ADDON_SHA, 'BASE_ADDON_SIZE': BASE_ADDON_SIZE,
        'TARGET_MAIN_SHA': TARGET_MAIN_SHA, 'TARGET_MAIN_SIZE': TARGET_MAIN_SIZE,
        'TARGET_ADDON_SHA': TARGET_ADDON_SHA, 'TARGET_ADDON_SIZE': TARGET_ADDON_SIZE,
        'AGENT_SHA': AGENT_SHA, 'AGENT_SIZE': AGENT_SIZE, 'BOOTSTRAP': BOOTSTRAP,
        'REGISTRY_SHA': REGISTRY_SHA, 'ADAPTER_SHA': ADAPTER_SHA, 'AUTHORIZED_NAMES': AUTHORIZED_NAMES,
        'BASE_OUT': BASE_OUT, 'TARGET_OUT': TARGET_OUT, 'REPORT': REPORT, 'META': META,
        'MAIN_DIR': MAIN_DIR, 'ADDON_DIR': ADDON_DIR,
    }
    ns.update(overrides)

    def build_candidate():
        subprocess.check_call([sys.executable, str(ROOT/'validation/v0.6.28/build_v0628.py'), '--build'], cwd=ROOT)
        main = (TARGET_OUT/'spotify-control.ps1').read_bytes()
        addon = (TARGET_OUT/'addon-manager.ps1').read_bytes()
        if (len(main), sha(main)) != (TARGET_MAIN_SIZE, TARGET_MAIN_SHA):
            raise RuntimeError('validated v0.6.28 main identity mismatch')
        if (len(addon), sha(addon)) != (TARGET_ADDON_SIZE, TARGET_ADDON_SHA):
            raise RuntimeError('validated r17 addon identity mismatch')
        return main, addon

    def base_payloads():
        subprocess.check_call([sys.executable, str(ROOT/'validation/v0.6.27/build_v0627.py'), '--build'], cwd=ROOT)
        main = (BASE_OUT/'spotify-control.ps1').read_bytes()
        addon = (BASE_OUT/'addon-manager.ps1').read_bytes()
        if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
            raise RuntimeError('v0.6.27 main base identity mismatch')
        if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
            raise RuntimeError('r16 addon base identity mismatch')
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
            'schema':1, 'base_commit':BASE_COMMIT, 'base_version':BASE_VERSION, 'version':NEW_VERSION, 'addon_version':'0.6.5-r17',
            'candidate_main':{'size':TARGET_MAIN_SIZE,'sha256':TARGET_MAIN_SHA},
            'candidate_addon':{'size':TARGET_ADDON_SIZE,'sha256':TARGET_ADDON_SHA},
            'resident_agent':{'size':AGENT_SIZE,'sha256':AGENT_SHA}, 'bootstrap':BOOTSTRAP,
            'authority_expanded':False, 'new_auto_install_authority':False,
            'ownership_migration_authorized':False, 'direct_copy_cleanup_authorized':False, 'disable_or_optimize_authorized':False,
            'auto_authority':AUTHORIZED_NAMES, 'registry_fingerprint':REGISTRY_SHA, 'source_adapter_fingerprint':ADAPTER_SHA,
            'sc_cover_ambience_provenance':{
                'mode':'official-git-file-commit-snapshot-v1','monitor_only':True,'mutation_mode':'deny',
                'inventory_policy':'rescue-copy-cleanup-only','install_mode':'recovery-owned','version_strategy':'owner-cleanup-only',
                'rollback_strategy':'external-owner','data_policy':'never-disable-or-optimize',
                'catalog_payload_sha256':CATALOG_PAYLOAD_SHA,'snapshot_count':35,
                'current_commit':CURRENT_COMMIT,'current_size':CURRENT_SIZE,'current_sha256':CURRENT_SHA,
                'real_pc_topology':'dual-owned-risk','real_pc_report_size':REAL_PC_REPORT_SIZE,'real_pc_report_sha256':REAL_PC_REPORT_SHA,
                'marketplace_installed':True,'persistent_configured':True,'source_current_proven':True,'active_current_proven':True,
                'raw_real_pc_report_committed':False,
            },
            'validation':{
                'head':VALIDATION_HEAD,'builder_blob':VALIDATION_BLOB,'pr_run':VALIDATION_PR_RUN,
                'stable_pr_run':VALIDATION_STABLE_PR_RUN,'pr':VALIDATION_PR,'pr_closed_unmerged':True,
                'artifact_id':VALIDATION_ARTIFACT,'artifact_digest':VALIDATION_ARTIFACT_DIGEST,
                'audit_head':AUDIT_HEAD,'audit_run':AUDIT_RUN,'audit_artifact_id':AUDIT_ARTIFACT,'audit_artifact_digest':AUDIT_ARTIFACT_DIGEST,
                'collector_head':COLLECTOR_HEAD,'collector_run':COLLECTOR_RUN,'collector_artifact_id':COLLECTOR_ARTIFACT,'collector_artifact_digest':COLLECTOR_ARTIFACT_DIGEST,
                'deterministic_report_sha256':report_sha,
            },
            'protected_provenance_preserved':{'star_ratings':True,'tagify':True,'splitify':True},
            'transport':{'main':main_patch,'addon':addon_patch},
        }
        META.parent.mkdir(parents=True, exist_ok=True)
        META.write_text(json.dumps(metadata, indent=2, sort_keys=True)+'\n', encoding='utf-8', newline='\n')
        print('V0628_RELEASE_PACKAGES_PASS', TARGET_MAIN_SIZE, TARGET_MAIN_SHA, TARGET_ADDON_SIZE, TARGET_ADDON_SHA, report_sha)
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
