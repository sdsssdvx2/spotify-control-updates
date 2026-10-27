from __future__ import annotations
from pathlib import Path
import hashlib, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PIN_HEAD = 'a328879854acb69a7a777393d946378b7e39840e'
PIN_PATH = 'validation/marketplace-lifecycle-tagify-state-preserving-v0.1.1/build_candidate.py'
PIN_BLOB = '4aa3dca27771dfc0b5868b83ce2abe03daa6ea2f'
EXPECTED_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
EXPECTED_ADDON = (341952, '2754b8d32f96bc8368436cced0b5969a9f1c97a61d61f1082bb070b6f2dd67a7')


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    subprocess.check_call(['git', 'cat-file', '-e', f'{PIN_HEAD}^{{commit}}'], cwd=ROOT)
    blob = subprocess.check_output(['git', 'rev-parse', f'{PIN_HEAD}:{PIN_PATH}'], cwd=ROOT, text=True).strip()
    if blob != PIN_BLOB:
        raise RuntimeError(f'pinned v0.1.1 builder blob drift: {blob}')
    source = subprocess.check_output(['git', 'show', f'{PIN_HEAD}:{PIN_PATH}'], cwd=ROOT)
    temp = HERE / '_pinned_v011_builder.py'
    try:
        temp.write_bytes(source)
        subprocess.check_call([sys.executable, str(temp)], cwd=ROOT)
    finally:
        temp.unlink(missing_ok=True)

    main_path = HERE / 'out/bin/spotify-control.ps1'
    addon_path = HERE / 'out/bin/addon-manager.ps1'
    main_bytes = main_path.read_bytes()
    addon_bytes = addon_path.read_bytes()
    if (len(main_bytes), sha(main_bytes)) != EXPECTED_MAIN:
        raise RuntimeError(f'v0.1.2 reproduced main identity drift: {len(main_bytes)} {sha(main_bytes)}')
    if (len(addon_bytes), sha(addon_bytes)) != EXPECTED_ADDON:
        raise RuntimeError(f'v0.1.2 reproduced addon identity drift: {len(addon_bytes)} {sha(addon_bytes)}')

    report_path = HERE / 'candidate-validation.json'
    report = json.loads(report_path.read_text(encoding='utf-8'))
    report['validation_v012'] = {
        'schema': 1,
        'pinned_v011_head': PIN_HEAD,
        'pinned_v011_builder_blob': PIN_BLOB,
        'candidate_bytes_changed': False,
        'purpose': 'rerun the exact v0.1.1 candidate with a corrected production-surface assertion; the previous final red was caused only by referencing nonexistent package paths'
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('TAGIFY_STATE_PRESERVING_V012_REPRODUCTION_PASS', len(main_bytes), sha(main_bytes), len(addon_bytes), sha(addon_bytes))


if __name__ == '__main__':
    main()
