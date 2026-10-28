from __future__ import annotations
from pathlib import Path
import argparse, subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE_HEAD = 'da3bf726c2c888bd6ac8c4aaee8fd13660a9235f'
BASE_PATH = 'validation/custom-app-remote-binding-observer-v0.4.0/build_candidate.py'
BASE_BLOB = '7b13595a185bead3f1c3cee80caee10dd19ea996'
OLD_STATE_BLOB = '7d1a14227cb357bbe34d8846d5ddb295b17990c1'
NEW_STATE_BLOB = 'bd19cbb3da2087e68b2452fe62471d4eca2cd990'
OLD_HOOK_CALL = "    inventory = replace_once(inventory, state_anchor, state_replacement, 'v0.4 remote observer inventory hook')"
NEW_HOOK_CALL = """    # The validated v0.3 inventory performs Marketplace discovery earlier in the
    # function, then refreshes local lifecycle/provenance later.  Remote-source observation
    # must therefore be ordered from the safety state that matters, not from Marketplace:
    # current provenance refresh -> persist provenance -> bounded remote observation -> persist
    # remote observation.  Find the first state save *after* the exact provenance update loop.
    provenance_marker = '        $provRow=Update-CustomAppProvenanceEnrollment -State $state -Evidence $evidence -ObservedAt $now'
    save_marker = '    Save-AddonState $state'
    if inventory.count(provenance_marker) != 1:
        raise RuntimeError(f'v0.4 provenance semantic anchor drift: {inventory.count(provenance_marker)}')
    provenance_pos = inventory.index(provenance_marker)
    save_pos = inventory.find(save_marker, provenance_pos)
    if save_pos < 0 or save_pos <= provenance_pos:
        raise RuntimeError(f'v0.4 persisted-provenance ordering drift: provenance={provenance_pos} save={save_pos}')
    if inventory.count('Invoke-CustomAppRemoteBindingObserverCycleV040') != 0:
        raise RuntimeError('v0.4 remote observer hook already present before integration')
    save_end = save_pos + len(save_marker)
    remote_block = '''\n\n    # Generic remote-source observation is state-only and deliberately rate-limited.
    # It never changes the existing five mutation-authorized registry entries.
    $customAppRemoteBindingSummary=Invoke-CustomAppRemoteBindingObserverCycleV040 -State $state -ObservedAt $now -MinimumIntervalHours 24 -MaxNetworkObservationsPerCycle 2
    Save-AddonState $state'''
    inventory = inventory[:save_end] + remote_block + inventory[save_end:]"""


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
    if source.count(OLD_HOOK_CALL) != 1:
        raise RuntimeError(f'v0.4.0 inventory hook call anchor drift: {source.count(OLD_HOOK_CALL)}')
    source = source.replace(OLD_HOOK_CALL, NEW_HOOK_CALL, 1)
    fake = ROOT / 'validation/custom-app-remote-binding-observer-v0.4.0/_v041_pinned_builder.py'
    ns = {'__file__': str(fake), '__name__': 'v041_pinned_builder'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()


def main() -> None:
    p = argparse.ArgumentParser(); p.add_argument('--build', action='store_true'); args = p.parse_args()
    if not args.build: p.error('use --build')
    build()

if __name__ == '__main__': main()
