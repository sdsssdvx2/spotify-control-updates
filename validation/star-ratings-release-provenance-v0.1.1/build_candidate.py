from pathlib import Path
import argparse, hashlib, subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'validation/star-ratings-release-provenance-v0.1.1/out/bin'
REPORT = ROOT / 'validation/star-ratings-release-provenance-v0.1.1/candidate-report.json'

SOURCE_COMMIT = '8c1daad685db41b0de5ef73422b6e49c5ddc823e'
SOURCE_PATH = 'validation/star-ratings-release-provenance-v0.1.0/build_candidate.py'
SOURCE_BLOB = '34ad67d7a3b5def12b7e514178052e48c260a678'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git', 'rev-parse', f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def build():
    blob = git_blob(SOURCE_COMMIT, SOURCE_PATH)
    if blob != SOURCE_BLOB:
        raise RuntimeError(f'pinned v0.1.0 builder blob drifted: {blob}')

    source = git_bytes(SOURCE_COMMIT, SOURCE_PATH)
    fake_file = ROOT / SOURCE_PATH
    ns = {'__file__': str(fake_file), '__name__': 'star_ratings_provenance_v010_pinned'}
    exec(compile(source, str(fake_file), 'exec'), ns)

    original_function_map = ns['function_map']

    def whitespace_safe_function_map(text: str):
        # v0.1.0 compared function blocks through the next `function` marker,
        # so inserting a new helper changed only the trailing inter-function
        # blank lines of the preceding Splitify function and caused a false red.
        # Keep every non-whitespace byte exact while excluding only trailing
        # whitespace that is outside the PowerShell function body.
        return {name: block.rstrip() for name, block in original_function_map(text).items()}

    ns['function_map'] = whitespace_safe_function_map
    ns['OUT'] = OUT
    ns['REPORT'] = REPORT
    ns['build']()

    main = (OUT / 'spotify-control.ps1').read_bytes()
    addon = (OUT / 'addon-manager.ps1').read_bytes()
    print('STAR_RATINGS_V011_BUILD_PASS', len(main), sha(main), len(addon), sha(addon), SOURCE_COMMIT, SOURCE_BLOB)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--build', action='store_true')
    args = p.parse_args()
    if not args.build:
        p.error('use --build')
    build()


if __name__ == '__main__':
    main()
