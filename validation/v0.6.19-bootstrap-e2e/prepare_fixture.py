from pathlib import Path
import hashlib, importlib.util, runpy

ROOT = Path(__file__).resolve().parents[2]
BASE_MAIN_SHA = '27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f'
BASE_ADDON_SHA = 'b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
AGENT_SHA = '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP_SHA = 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# Build the already-proven installed-layout fixture, including exact Bootstrap 1.0.6,
# long-lived helper files, Spotify root, and Marketplace structure used by SelfTests.
runpy.run_path(str(ROOT / 'validation/bootstrap-contract-repair/build_bootstrap_fixture.py'), run_name='__main__')

# Reconstruct exact production v0.6.18 main + Addon Manager r7 from the frozen v0.6.18
# payload chain using the same deterministic builder that produces v0.6.19.
spec = importlib.util.spec_from_file_location('v0619_builder', ROOT / 'validation/v0.6.19/build_v0619.py')
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)
manifest = mod.load_base_manifest()
main = mod.reconstruct_base_main(manifest)
addon = mod.reconstruct_base_addon(manifest)
assert len(main) == mod.BASE_MAIN_SIZE and hashlib.sha256(main).hexdigest() == BASE_MAIN_SHA
assert len(addon) == mod.BASE_ADDON_SIZE and hashlib.sha256(addon).hexdigest() == BASE_ADDON_SHA

fixture = ROOT / 'ci-bootstrap-fixture'
root = fixture / 'LocalAppData' / 'SpotifyControl'
bin_dir = root / 'bin'
main_path = bin_dir / 'spotify-control.ps1'
addon_path = bin_dir / 'addon-manager.ps1'
agent_path = bin_dir / 'spotify-control-agent.vbs'
bootstrap_path = root / 'bootstrap' / 'spotify-control-self-updater.ps1'

main_path.write_bytes(main)
addon_path.write_bytes(addon)

assert sha(main_path) == BASE_MAIN_SHA
assert sha(addon_path) == BASE_ADDON_SHA
assert sha(agent_path) == AGENT_SHA
assert sha(bootstrap_path) == BOOTSTRAP_SHA

for name in ('update-state.json', 'update-transaction.json', 'rollback-state.json'):
    p = root / name
    if p.exists():
        p.unlink()

print(
    'V0618_BOOTSTRAP_FIXTURE_PASS',
    len(main), BASE_MAIN_SHA,
    len(addon), BASE_ADDON_SHA,
    agent_path.stat().st_size, AGENT_SHA,
    bootstrap_path.stat().st_size, BOOTSTRAP_SHA,
)
