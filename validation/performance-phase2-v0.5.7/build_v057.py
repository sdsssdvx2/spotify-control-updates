from pathlib import Path
import base64, lzma, subprocess

root = Path(__file__).parent
repo = root.parents[1]
v056_commit = 'dd0937f84151fd6533484ae4cefb6f3eb174e689'
v056_dir = repo / 'validation' / 'performance-phase2-v0.5.6'
v056_files = ['build_v056.py'] + [f'build_v056.part{i:02d}.b64' for i in range(1, 7)]

# The v0.5.7 builder intentionally derives from the exact, already-CI-validated
# v0.5.6 builder. On a clean validation branch, materialize those immutable
# source bytes directly from the pinned Git object. GitHub Actions uses
# fetch-depth: 0, so this is local, deterministic, and requires no network.
if not (v056_dir / 'build_v056.py').is_file():
    v056_dir.mkdir(parents=True, exist_ok=True)
    for name in v056_files:
        rel = f'validation/performance-phase2-v0.5.6/{name}'
        data = subprocess.check_output(['git', 'show', f'{v056_commit}:{rel}'], cwd=repo)
        (v056_dir / name).write_bytes(data)

payload = (root / 'build_v057.payload.b64').read_text(encoding='ascii').strip()
code = lzma.decompress(base64.b64decode(payload))
exec(compile(code, 'build_v057.selfcontained.py', 'exec'), globals(), globals())
