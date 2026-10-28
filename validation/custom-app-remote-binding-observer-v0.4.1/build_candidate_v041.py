from __future__ import annotations
from pathlib import Path
import argparse, subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE_HEAD = 'da3bf726c2c888bd6ac8c4aaee8fd13660a9235f'
BASE_PATH = 'validation/custom-app-remote-binding-observer-v0.4.0/build_candidate.py'
BASE_BLOB = '7b13595a185bead3f1c3cee80caee10dd19ea996'
OLD_STATE_BLOB = '7d1a14227cb357bbe34d8846d5ddb295b17990c1'
NEW_STATE_BLOB = 'bd19cbb3da2087e68b2452fe62471d4eca2cd990'


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git', 'rev-parse', f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def build() -> None:
    actual = git_blob(BASE_HEAD, BASE_PATH)
    if actual != BASE_BLOB:
        raise RuntimeError(f'v0.4.0 builder drift: {actual} != {BASE_BLOB}')
    state_actual = git_blob(BASE_HEAD, 'validation/custom-app-remote-binding-observer-v0.4.0/custom-app-remote-binding-state.ps1')
    if state_actual != NEW_STATE_BLOB:
        raise RuntimeError(f'v0.4.1 state-core parent drift: {state_actual} != {NEW_STATE_BLOB}')
    source = git_bytes(BASE_HEAD, BASE_PATH).decode('utf-8')
    if source.count(OLD_STATE_BLOB) != 1:
        raise RuntimeError('v0.4.0 stale state blob anchor drift')
    source = source.replace(OLD_STATE_BLOB, NEW_STATE_BLOB, 1)
    fake = ROOT / 'validation/custom-app-remote-binding-observer-v0.4.0/_v041_pinned_builder.py'
    ns = {'__file__': str(fake), '__name__': 'v041_pinned_builder'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()


def main() -> None:
    p = argparse.ArgumentParser(); p.add_argument('--build', action='store_true'); args = p.parse_args()
    if not args.build: p.error('use --build')
    build()

if __name__ == '__main__': main()
