from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'reproduction-report.json'

PRODUCTION_BASE = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
SOURCE_HEAD = '36471b7193324d117c3c9b40c1cc27cc25dc2c86'
SOURCE_BUILDER_PATH = 'validation/marketplace-source-topology-v0.1.0/build_candidate.py'
SOURCE_BUILDER_BLOB = '1e32dd57c95f718f2aeaae6149da36762ca7f6fd'
SOURCE_TOPOLOGY_PATH = 'validation/marketplace-source-topology-v0.1.0/marketplace-source-topology.ps1'
SOURCE_TOPOLOGY_BLOB = 'fff349f3fc765e2fc187b9ccdc249b48e09df6c8'
INTEGRATED_HEAD = '71ebf04ec6744383161bc16376a6a292dd3a5e33'
INTEGRATED_GLUE_PATH = 'validation/marketplace-integrated-engine-v0.2.0/integration-glue.ps1'
INTEGRATED_GLUE_BLOB = 'a720b0ccd23eefd00cbc770835c762581c5f11af'
ARTIFACT_ID = 12751942370
ARTIFACT_DIGEST = 'sha256:879b827da7b0b4bb9f743e6f73d6232dbf543830d20d1cc83d5df55b4f02d55c'
EXPECTED = {
    'spotify-control.ps1': (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99'),
    'addon-manager.ps1': (398615, '8ef832bde22bb147d17bd5c901da0706c8dc9f90e6db0eaf446e274c1df3c3ef'),
    'Collect-Marketplace-Records.ps1': (16052, 'b261a13f7683d43a9bd79f58d7ada12b173201753bfcf2b5c95d892fbd0a6127'),
    'LevelDbReadOnly.cs': (30567, '391e10c108c8316dd7422b02a45302e696bc1da20ea4f4303160b252c6624a5d'),
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git', 'rev-parse', f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def require_blob(commit: str, path: str, expected: str, label: str) -> bytes:
    actual = git_blob(commit, path)
    if actual != expected:
        raise RuntimeError(f'{label} blob drift: {actual} != {expected}')
    return git_bytes(commit, path)


def materialize_inputs() -> tuple[Path, Path]:
    source_builder = require_blob(SOURCE_HEAD, SOURCE_BUILDER_PATH, SOURCE_BUILDER_BLOB, 'source-topology builder')
    topology = require_blob(SOURCE_HEAD, SOURCE_TOPOLOGY_PATH, SOURCE_TOPOLOGY_BLOB, 'source-topology ownership contract')
    glue = require_blob(INTEGRATED_HEAD, INTEGRATED_GLUE_PATH, INTEGRATED_GLUE_BLOB, 'integrated Marketplace glue')

    source_dir = ROOT / 'validation/marketplace-source-topology-v0.1.0'
    integrated_dir = ROOT / 'validation/marketplace-integrated-engine-v0.2.0'
    source_dir.mkdir(parents=True, exist_ok=True)
    integrated_dir.mkdir(parents=True, exist_ok=True)
    source_builder_path = source_dir / 'build_candidate.py'
    topology_path = source_dir / 'marketplace-source-topology.ps1'
    glue_path = integrated_dir / 'integration-glue.ps1'
    source_builder_path.write_bytes(source_builder)
    topology_path.write_bytes(topology)
    glue_path.write_bytes(glue)
    return source_builder_path, topology_path


def validate_output(source_out: Path) -> dict:
    identities = {}
    for name, (expected_size, expected_sha) in EXPECTED.items():
        path = source_out / name
        if not path.is_file():
            raise RuntimeError(f'reproduced output missing: {name}')
        data = path.read_bytes()
        actual = (len(data), sha(data))
        if actual != (expected_size, expected_sha):
            raise RuntimeError(f'reproduced output drift: {name} {actual} != {(expected_size, expected_sha)}')
        identities[name] = {'size': actual[0], 'sha256': actual[1]}
    addon = (source_out / 'addon-manager.ps1').read_text(encoding='utf-8-sig')
    required = (
        'function Test-LocalSpicetifyUserIntentAllowsMutation',
        'current-local-user-intent-confirmed',
        'local-lifecycle-evidence-stale',
        'local-lifecycle-ambiguous-or-unsafe',
        'function Test-MarketplaceSourceUserIntentAllowsMutation',
        'marketplace-ledger-authority-drift',
        'New-RequiredSpotifyPersistenceBackup',
        'Restore-SpotifyPersistenceBackup',
        'never-disable-or-optimize',
        'playlist-backed-ratings-preserve',
        'preserve-ratings-tags-notes-and-browser-storage',
    )
    for marker in required:
        if marker.lower() not in addon.lower():
            raise RuntimeError(f'reproduced candidate safety marker missing: {marker}')
    return identities


def build() -> None:
    if subprocess.check_output(['git', 'merge-base', PRODUCTION_BASE, 'HEAD'], cwd=ROOT, text=True).strip() != PRODUCTION_BASE:
        raise RuntimeError('independent reproduction branch is not based on exact production main')
    source_builder_path, topology_path = materialize_inputs()
    subprocess.check_call([sys.executable, str(source_builder_path), '--build'], cwd=ROOT)
    source_out = ROOT / 'validation/marketplace-source-topology-v0.1.0/out/bin'
    identities = validate_output(source_out)

    if OUT.parent.exists():
        shutil.rmtree(OUT.parent)
    OUT.mkdir(parents=True, exist_ok=True)
    for name in EXPECTED:
        shutil.copy2(source_out / name, OUT / name)
    shutil.copy2(topology_path, HERE / 'marketplace-source-topology.ps1')

    source_report = ROOT / 'validation/marketplace-source-topology-v0.1.0/candidate-validation.json'
    if not source_report.is_file():
        raise RuntimeError('exact source-topology candidate report was not reproduced')
    source_report_obj = json.loads(source_report.read_text(encoding='utf-8'))
    if source_report_obj.get('generic_marketplace_mutation_authority_expanded') is not False:
        raise RuntimeError('source candidate unexpectedly expands generic Marketplace mutation authority')
    if source_report_obj.get('production_surface_changed') is not False:
        raise RuntimeError('source candidate unexpectedly reports production surface changes')
    if source_report_obj.get('marketplace_record_kinds') != ['extension', 'theme', 'snippet']:
        raise RuntimeError('source candidate Marketplace type topology drifted')

    report = {
        'schema': 1,
        'production_base': PRODUCTION_BASE,
        'source_head': SOURCE_HEAD,
        'source_builder': {'path': SOURCE_BUILDER_PATH, 'blob': SOURCE_BUILDER_BLOB},
        'source_topology': {'path': SOURCE_TOPOLOGY_PATH, 'blob': SOURCE_TOPOLOGY_BLOB},
        'integrated_glue': {'head': INTEGRATED_HEAD, 'path': INTEGRATED_GLUE_PATH, 'blob': INTEGRATED_GLUE_BLOB},
        'validated_push_artifact': {'id': ARTIFACT_ID, 'digest': ARTIFACT_DIGEST},
        'exact_outputs': identities,
        'generic_marketplace_mutation_authority_expanded': False,
        'production_surface_changed': False,
        'reproduction_mode': 'main-based-exact-commit-and-blob-pin',
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('SOURCE_TOPOLOGY_MAIN_REPRODUCTION_PASS', identities['addon-manager.ps1']['size'], identities['addon-manager.ps1']['sha256'])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    if not args.build:
        parser.error('use --build')
    build()


if __name__ == '__main__':
    main()
