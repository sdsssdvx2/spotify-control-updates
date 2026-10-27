from pathlib import Path
import argparse, hashlib, subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'validation/star-ratings-release-provenance-v0.1.2/out/bin'
REPORT = ROOT / 'validation/star-ratings-release-provenance-v0.1.2/candidate-report.json'

SOURCE_COMMIT = 'd4d7e2d23c740f2c24920b45ee2e1a10427eda57'
SOURCE_PATH = 'validation/star-ratings-release-provenance-v0.1.1/build_candidate.py'
SOURCE_BLOB = '0c5b40b470d628fb3c7ea76942ee050d1a36eef9'
EXPECTED_MAIN_SIZE = 284317
EXPECTED_MAIN_SHA = '9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787'
EXPECTED_ADDON_SIZE = 303745
EXPECTED_ADDON_SHA = 'c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build():
    blob = subprocess.check_output(
        ['git', 'rev-parse', f'{SOURCE_COMMIT}:{SOURCE_PATH}'], cwd=ROOT, text=True
    ).strip()
    if blob != SOURCE_BLOB:
        raise RuntimeError(f'pinned v0.1.1 builder blob drifted: {blob}')
    source = subprocess.check_output(['git', 'show', f'{SOURCE_COMMIT}:{SOURCE_PATH}'], cwd=ROOT)
    fake_file = ROOT / SOURCE_PATH
    ns = {'__file__': str(fake_file), '__name__': 'star_ratings_provenance_v011_pinned'}
    exec(compile(source, str(fake_file), 'exec'), ns)
    ns['OUT'] = OUT
    ns['REPORT'] = REPORT
    ns['build']()

    main = (OUT / 'spotify-control.ps1').read_bytes()
    addon = (OUT / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (EXPECTED_MAIN_SIZE, EXPECTED_MAIN_SHA):
        raise RuntimeError(f'v0.1.2 main identity drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (EXPECTED_ADDON_SIZE, EXPECTED_ADDON_SHA):
        raise RuntimeError(f'v0.1.2 addon identity drift: {len(addon)} {sha(addon)}')
    print('STAR_RATINGS_V012_BUILD_PASS', len(main), sha(main), len(addon), sha(addon), SOURCE_COMMIT, SOURCE_BLOB)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--build', action='store_true')
    args = p.parse_args()
    if not args.build:
        p.error('use --build')
    build()


if __name__ == '__main__':
    main()
