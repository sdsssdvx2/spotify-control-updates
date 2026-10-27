from pathlib import Path
import argparse, hashlib, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.26/out/bin'
OUT = ROOT / 'validation/v0.6.27/out/bin'
REPORT = ROOT / 'validation/v0.6.27/candidate-validation.json'

BASE_MAIN_SIZE = 284311
BASE_MAIN_SHA = 'd7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1'
BASE_ADDON_SIZE = 291294
BASE_ADDON_SHA = '4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f'
TARGET_MAIN_SIZE = 284317
TARGET_MAIN_SHA = '9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787'
TARGET_ADDON_SIZE = 303745
TARGET_ADDON_SHA = 'c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']

VALIDATION_HEAD = 'ac6a89298af835b65d4948ed0587341bb3cc7ff9'
VALIDATION_PATH = 'validation/star-ratings-release-provenance-v0.1.2/build_candidate.py'
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


def build_base():
    subprocess.check_call([sys.executable, str(ROOT/'validation/v0.6.26/build_v0626.py'), '--build'], cwd=ROOT)
    main = (BASE_OUT/'spotify-control.ps1').read_bytes()
    addon = (BASE_OUT/'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError(f'v0.6.26 main base drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError(f'r15 addon base drift: {len(addon)} {sha(addon)}')
    return main, addon


def build_validated_candidate():
    blob = git_blob(VALIDATION_HEAD, VALIDATION_PATH)
    if blob != VALIDATION_BLOB:
        raise RuntimeError(f'validated Star Ratings builder blob drift: {blob}')
    source = git_bytes(VALIDATION_HEAD, VALIDATION_PATH)
    fake = ROOT / VALIDATION_PATH
    ns = {'__file__': str(fake), '__name__': 'spotify_control_validated_star_ratings_v012'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()
    source_out = ROOT / 'validation/star-ratings-release-provenance-v0.1.2/out/bin'
    main = (source_out/'spotify-control.ps1').read_bytes()
    addon = (source_out/'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (TARGET_MAIN_SIZE, TARGET_MAIN_SHA):
        raise RuntimeError(f'validated v0.6.27 main drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (TARGET_ADDON_SIZE, TARGET_ADDON_SHA):
        raise RuntimeError(f'validated r16 addon drift: {len(addon)} {sha(addon)}')
    return main, addon


def validate_candidate(base_addon: bytes, candidate_addon: bytes):
    base = base_addon.decode('utf-8-sig').replace('\r\n', '\n')
    cand = candidate_addon.decode('utf-8-sig').replace('\r\n', '\n')
    for name in ('Get-AddonPolicyRegistry', 'Get-AddonSourceAdapterCatalog'):
        if function_block(base, name) != function_block(cand, name):
            raise RuntimeError(f'{name} changed unexpectedly')
    registry = function_block(cand, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED_NAMES):
        raise RuntimeError(f'auto authority drift: {auto}')
    for marker in (
        "name='star-ratings'", "source='brimell/spicetify-star-ratings'", "inventory_policy='source-watch-only'",
        "mutation_mode='deny'", "install_mode='marketplace-owned'", "data_policy='playlist-backed-ratings-preserve'",
        "protect-ratings-tags-notes", "name='splitify'", "preserve-installed-content", "never-disable-or-optimize"
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected policy missing: {marker}')
    update = function_block(cand, 'Update-AutoApps')
    if 'star-ratings' in update.lower():
        raise RuntimeError('Star Ratings gained an automatic update route')
    rollback = function_block(cand, 'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback:
        raise RuntimeError('RollbackLast became source-adapter-dependent')
    for helper in ('Get-StarRatingsReleaseCatalog', 'Get-StarRatingsReleaseFileProvenance', 'Resolve-StarRatingsInstalledReleaseProvenance'):
        block = function_block(cand, helper)
        for forbidden in ('Invoke-WebRequest','Invoke-RestMethod','Remove-Item','Copy-Item','Move-Item','Start-Process','Expand-Archive','spicetify apply','spicetify backup','spicetify restore','Test-SpotifyStorageMarker','IndexedDB','localStorage','\\Browser\\','\\Default\\'):
            if forbidden.lower() in block.lower():
                raise RuntimeError(f'{helper} gained forbidden side effect/data access: {forbidden}')
    resolver = function_block(cand, 'Resolve-StarRatingsInstalledReleaseProvenance')
    for required in ('runtime-v1','active-state.json','original.bin','6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3','performance-original-backup-v1','active-exact-upstream-dist-v1'):
        if required not in resolver:
            raise RuntimeError(f'Star Ratings provenance resolver contract missing: {required}')
    inv = function_block(cand, 'Get-AddonInventory')
    for required in ('Resolve-StarRatingsInstalledReleaseProvenance','watched-current-proven','watched-update-available-proven-local',AUDIT_CATALOG_JSON_SHA,'Ratings remain Spotify playlists','Resolve-TagifyInstalledReleaseProvenance','75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a','Resolve-SplitifyInstalledReleaseProvenance','60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454'):
        if required not in inv:
            raise RuntimeError(f'provenance inventory contract missing: {required}')


def build():
    _, base_addon = build_base()
    main, addon = build_validated_candidate()
    validate_candidate(base_addon, addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(main)
    (OUT/'addon-manager.ps1').write_bytes(addon)
    report = {
        'schema': 2,
        'base_version': '0.6.26',
        'version': '0.6.27',
        'addon_version': '0.6.5-r16',
        'base_main': {'size': BASE_MAIN_SIZE, 'sha256': BASE_MAIN_SHA},
        'base_addon': {'size': BASE_ADDON_SIZE, 'sha256': BASE_ADDON_SHA},
        'candidate_main': {'size': TARGET_MAIN_SIZE, 'sha256': TARGET_MAIN_SHA},
        'candidate_addon': {'size': TARGET_ADDON_SIZE, 'sha256': TARGET_ADDON_SHA},
        'validated_source': {
            'head': VALIDATION_HEAD, 'path': VALIDATION_PATH, 'blob': VALIDATION_BLOB,
            'push_run': VALIDATION_PUSH_RUN, 'pr_run': VALIDATION_PR_RUN, 'stable_pr_run': VALIDATION_STABLE_PR_RUN,
            'pr': VALIDATION_PR, 'pr_closed_unmerged': True,
            'push_artifact_id': VALIDATION_PUSH_ARTIFACT, 'push_artifact_digest': VALIDATION_PUSH_ARTIFACT_DIGEST,
            'pr_artifact_id': VALIDATION_PR_ARTIFACT, 'pr_artifact_digest': VALIDATION_PR_ARTIFACT_DIGEST,
        },
        'audit_evidence': {
            'head': AUDIT_HEAD, 'run': AUDIT_RUN, 'artifact_id': AUDIT_ARTIFACT,
            'artifact_digest': AUDIT_ARTIFACT_DIGEST, 'catalog_json_sha256': AUDIT_CATALOG_JSON_SHA,
        },
        'release_catalog_versions': ['2.0.0','2.0.1','2.0.2','2.0.3','2.0.4','2.0.5','2.0.6','2.0.7','2.0.8','2.1.0','2.1.1','2.1.2','2.1.3'],
        'historical_performance_anchor': {'version':'2.1.3','size':43396,'sha256':'198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1','transformed_sha256':'6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3'},
        'provenance_inputs': ['active-xpui-exact-official-dist','performance-active-state-bound-original-backup'],
        'excluded_inputs': ['spicetify-rescue-copy','known-transformed-active-bytes-without-valid-state','spotify-playlist-data','browser-indexeddb-localstorage'],
        'authority_expanded': False,
        'new_auto_install_authority': False,
        'auto_authority': AUTHORIZED_NAMES,
        'registry_fingerprint': REGISTRY_SHA,
        'source_adapter_fingerprint': ADAPTER_SHA,
        'star_ratings_policy': {'inventory_policy':'source-watch-only','mutation_mode':'deny','install_mode':'marketplace-owned','data_policy':'playlist-backed-ratings-preserve'},
        'tagify_provenance_preserved': True,
        'splitify_provenance_preserved': True,
        'rollback_last_source_adapter_independent': True,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n', encoding='utf-8', newline='\n')
    print('V0627_R16_BUILD_PASS', len(main), sha(main), len(addon), sha(addon), VALIDATION_BLOB, AUDIT_CATALOG_JSON_SHA)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--build', action='store_true')
    args = p.parse_args()
    if not args.build:
        p.error('use --build')
    build()


if __name__ == '__main__':
    main()
