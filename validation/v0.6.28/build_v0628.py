from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'validation/v0.6.28/out/bin'
REPORT = ROOT / 'validation/v0.6.28/candidate-validation.json'

BASE_MAIN_SIZE = 284317
BASE_MAIN_SHA = '9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787'
BASE_ADDON_SIZE = 303745
BASE_ADDON_SHA = 'c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'
TARGET_MAIN_SIZE = 284321
TARGET_MAIN_SHA = 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
TARGET_ADDON_SIZE = 323385
TARGET_ADDON_SHA = '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']

VALIDATION_HEAD = 'f8ed342f0f414abba3d2a42f93720057ae8b55e5'
VALIDATION_PATH = 'validation/sc-cover-ambience-commit-provenance-v0.1.0/build_candidate.py'
VALIDATION_BLOB = 'a52961092730a3216ea2d4b4dceaaa814f33ce4e'
VALIDATION_PR = 93
VALIDATION_PR_RUN = '40503043002'
VALIDATION_STABLE_PR_RUN = '40503042928'
VALIDATION_ARTIFACT = 12733622589
VALIDATION_ARTIFACT_DIGEST = 'sha256:de9a7f8b1bdb5aae2c13b7914df8dea783e7fa4f59b9e23a451280a48a9be2e8'
CATALOG_FINGERPRINT = 'c12391e57a393d37d70ffd7a984bdbb6af9f4a83cf3c2b0a8c9bf040247c731f'
CURRENT_COMMIT = '9454b55e454fb354ecedcf3f72c5a4f0a9671651'
CURRENT_SHA = '0aea69246e14156b22a10261af07b84f3abc58bed4368e03f740ed76db329738'
REAL_PC_REPORT_SIZE = 16730
REAL_PC_REPORT_SHA = '7349326c6567806f6c45bacb741d32649a6afc424b797d7249358cd9b8f5b38b'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git', 'rev-parse', f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def function_block(text: str, name: str) -> str:
    marker = f'function {name} {{'
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f'missing function {name}')
    nxt = text.find('\nfunction ', start + len(marker))
    if nxt < 0:
        nxt = len(text)
    return text[start:nxt].rstrip()


def build_validated_candidate():
    blob = git_blob(VALIDATION_HEAD, VALIDATION_PATH)
    if blob != VALIDATION_BLOB:
        raise RuntimeError(f'validated SC Cover Ambience builder blob drift: {blob}')
    source = git_bytes(VALIDATION_HEAD, VALIDATION_PATH)
    fake = ROOT / VALIDATION_PATH
    ns = {'__file__': str(fake), '__name__': 'spotify_control_validated_sc_cover_ambience_v010'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()
    source_out = ROOT / 'validation/sc-cover-ambience-commit-provenance-v0.1.0/out/bin'
    main = (source_out / 'spotify-control.ps1').read_bytes()
    addon = (source_out / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (TARGET_MAIN_SIZE, TARGET_MAIN_SHA):
        raise RuntimeError(f'validated v0.6.28 main drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (TARGET_ADDON_SIZE, TARGET_ADDON_SHA):
        raise RuntimeError(f'validated r17 addon drift: {len(addon)} {sha(addon)}')
    return main, addon


def validate_candidate(main: bytes, addon: bytes):
    main_text = main.decode('utf-8-sig').replace('\r\n', '\n')
    addon_text = addon.decode('utf-8-sig').replace('\r\n', '\n')
    if '$ScriptVersion = "0.6.28"' not in main_text or 'SC Cover Ambience Commit Provenance r17' not in main_text:
        raise RuntimeError('v0.6.28 main identity markers missing')
    if '$Version = "0.6.5-r17"' not in addon_text:
        raise RuntimeError('r17 Addon Manager version marker missing')
    registry = function_block(addon_text, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED_NAMES):
        raise RuntimeError(f'auto authority drift: {auto}')
    for marker in (
        "name='sc-cover-ambience.js'", "inventory_policy='rescue-copy-cleanup-only'", "mutation_mode='deny'",
        "install_mode='recovery-owned'", "version_strategy='owner-cleanup-only'", "rollback_strategy='external-owner'",
        "data_policy='never-disable-or-optimize'", "name='star-ratings'", "playlist-backed-ratings-preserve",
        "name='tagify'", "protect-ratings-tags-notes", "name='splitify'", "preserve-installed-content"
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected policy missing: {marker}')
    update = function_block(addon_text, 'Update-AutoApps')
    if 'sc-cover-ambience' in update.lower():
        raise RuntimeError('SC Cover Ambience gained an automatic mutation route')
    rollback = function_block(addon_text, 'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback:
        raise RuntimeError('RollbackLast became source-adapter-dependent')
    inv = function_block(addon_text, 'Get-AddonInventory')
    for required in (
        'Resolve-SCCoverAmbienceInstalledSnapshotProvenance', 'Get-SCCoverAmbienceRemoteHead',
        'ownership_migration_authorized', 'disable_or_optimize_authorized', CATALOG_FINGERPRINT,
        'watched-current-proven', 'watched-upstream-head-unproven-new-snapshot',
        'Resolve-StarRatingsInstalledReleaseProvenance', 'Resolve-TagifyInstalledReleaseProvenance',
        'Resolve-SplitifyInstalledReleaseProvenance'
    ):
        if required not in inv:
            raise RuntimeError(f'provenance inventory contract missing: {required}')


def build():
    main, addon = build_validated_candidate()
    validate_candidate(main, addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(addon)
    report = {
        'schema': 2,
        'base_version': '0.6.27',
        'version': '0.6.28',
        'addon_version': '0.6.5-r17',
        'base_main': {'size': BASE_MAIN_SIZE, 'sha256': BASE_MAIN_SHA},
        'base_addon': {'size': BASE_ADDON_SIZE, 'sha256': BASE_ADDON_SHA},
        'candidate_main': {'size': TARGET_MAIN_SIZE, 'sha256': TARGET_MAIN_SHA},
        'candidate_addon': {'size': TARGET_ADDON_SIZE, 'sha256': TARGET_ADDON_SHA},
        'validated_source': {
            'head': VALIDATION_HEAD, 'path': VALIDATION_PATH, 'blob': VALIDATION_BLOB,
            'pr': VALIDATION_PR, 'pr_closed_unmerged': True,
            'pr_run': VALIDATION_PR_RUN, 'stable_pr_run': VALIDATION_STABLE_PR_RUN,
            'artifact_id': VALIDATION_ARTIFACT, 'artifact_digest': VALIDATION_ARTIFACT_DIGEST,
        },
        'sc_cover_ambience_provenance': {
            'mode': 'official-git-file-commit-snapshot-v1', 'snapshot_count': 35,
            'catalog_payload_sha256': CATALOG_FINGERPRINT,
            'current_commit': CURRENT_COMMIT, 'current_size': 10267, 'current_sha256': CURRENT_SHA,
            'real_pc_report_size': REAL_PC_REPORT_SIZE, 'real_pc_report_sha256': REAL_PC_REPORT_SHA,
            'real_pc_topology': 'dual-owned-risk', 'marketplace_installed': True,
            'persistent_configured': True, 'source_current_proven': True, 'active_current_proven': True,
            'raw_real_pc_report_committed': False,
        },
        'authority_expanded': False,
        'new_auto_install_authority': False,
        'ownership_migration_authorized': False,
        'direct_copy_cleanup_authorized': False,
        'disable_or_optimize_authorized': False,
        'auto_authority': AUTHORIZED_NAMES,
        'registry_fingerprint': REGISTRY_SHA,
        'source_adapter_fingerprint': ADAPTER_SHA,
        'cover_ambience_policy': {
            'inventory_policy': 'rescue-copy-cleanup-only', 'mutation_mode': 'deny',
            'install_mode': 'recovery-owned', 'version_strategy': 'owner-cleanup-only',
            'rollback_strategy': 'external-owner', 'data_policy': 'never-disable-or-optimize',
        },
        'star_ratings_provenance_preserved': True,
        'tagify_provenance_preserved': True,
        'splitify_provenance_preserved': True,
        'rollback_last_source_adapter_independent': True,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('V0628_R17_BUILD_PASS', len(main), sha(main), len(addon), sha(addon), VALIDATION_BLOB, CATALOG_FINGERPRINT)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--build', action='store_true')
    args = p.parse_args()
    if not args.build:
        p.error('use --build')
    build()


if __name__ == '__main__':
    main()
