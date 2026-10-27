from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
REPORT = HERE / 'candidate-validation.json'
OUT = HERE / 'out' / 'bin'

BASE_INTEGRATED_HEAD = '2889081f740dc41b514e9abab0d914f8848fb5b0'
BASE_INTEGRATED_PATH = 'validation/marketplace-integrated-engine-v0.2.0/build_candidate.py'
BASE_INTEGRATED_BLOB = 'd3427e1aafb45acdc2d6752dd23fe05bd7685aef'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git', 'rev-parse', f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label} anchor count drift: {count}')
    return text.replace(old, new, 1)


def load_validated_v020_namespace() -> dict:
    actual = git_blob(BASE_INTEGRATED_HEAD, BASE_INTEGRATED_PATH)
    if actual != BASE_INTEGRATED_BLOB:
        raise RuntimeError(f'validated integrated v0.2.0 builder drift: {actual} != {BASE_INTEGRATED_BLOB}')
    source = git_bytes(BASE_INTEGRATED_HEAD, BASE_INTEGRATED_PATH)
    fake = HERE / '_validated_integrated_v020_builder.py'
    ns = {'__file__': str(fake), '__name__': 'validated_integrated_v020_builder'}
    exec(compile(source, str(fake), 'exec'), ns)
    return ns


def harden_integrated_candidate(candidate: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if candidate.startswith(b'\xef\xbb\xbf') else b''
    text = candidate[len(bom):].decode('utf-8')

    old_schedule = '''        if ($source -ceq "alexk218/tagify" -and $safety -in @("trusted-baseline","release-proof-required")) {
            $plan = Get-AddonSourceAdapterPlan -Item $item
            if ([bool]$plan.allowed -and [bool]$plan.mutation_authorized) { $count++ }
            continue
        }'''
    new_schedule = '''        if ($source -ceq "alexk218/tagify" -and $safety -in @("trusted-baseline","release-proof-required")) {
            # A malformed/stale report must never bypass the Marketplace user-intent gate.
            if (-not $item.PSObject.Properties['marketplace_identity_required'] -or -not [bool]$item.marketplace_identity_required) { continue }
            $plan = Get-AddonSourceAdapterPlan -Item $item
            if ([bool]$plan.allowed -and [bool]$plan.mutation_authorized) { $count++ }
            continue
        }'''
    text = replace_once(text, old_schedule, new_schedule, 'Tagify schedule-bypass current-evidence requirement')

    old_pending = "        $tagifyPending = [pscustomobject]@{ name='tagify'; policy='auto'; installed=$true; status='update-available'; source='alexk218/tagify'; local_safety='trusted-baseline' }"
    new_pending = "        $tagifyPending = [pscustomobject]@{ name='tagify'; kind='custom-app'; policy='auto'; installed=$true; status='update-available'; source='alexk218/tagify'; local_safety='trusted-baseline'; marketplace_identity_required=$true; marketplace_identity_evidence_conclusive=$false; marketplace_identity_fingerprint=$null }"
    text = replace_once(text, old_pending, new_pending, 'pending Tagify SelfTest inventory shape')

    old_current = "        $tagifyCurrent = [pscustomobject]@{ name='tagify'; policy='auto'; installed=$true; status='current'; source='alexk218/tagify'; local_safety='trusted-baseline' }"
    new_current = "        $tagifyCurrent = [pscustomobject]@{ name='tagify'; kind='custom-app'; policy='auto'; installed=$true; status='current'; source='alexk218/tagify'; local_safety='trusted-baseline'; marketplace_identity_required=$true; marketplace_identity_evidence_conclusive=$false; marketplace_identity_fingerprint=$null }"
    text = replace_once(text, old_current, new_current, 'current Tagify SelfTest inventory shape')

    old_pending_assert = "        if ((Get-DiscoveredActionableAutoUpdateCount -Report (& $makeReport @($tagifyPending))) -ne 1) { throw 'Trusted pending Tagify app was not schedule-bypass actionable.' }"
    new_pending_assert = "        if ((Get-DiscoveredActionableAutoUpdateCount -Report (& $makeReport @($tagifyPending))) -ne 0) { throw 'Tagify without current conclusive Marketplace evidence escaped schedule-bypass fail-closed behavior.' }"
    text = replace_once(text, old_pending_assert, new_pending_assert, 'pending Tagify SelfTest fail-closed assertion')

    old_mixed_assert = "        if ((Get-DiscoveredActionableAutoUpdateCount -Report (& $makeReport @($ivPending,$pithayaPending,$tagifyPending,$pithayaCurrent,$tagifyCurrent,$monitorOnly))) -ne 3) { throw 'Mixed pending schedule-bypass fixture count was incorrect.' }"
    new_mixed_assert = "        if ((Get-DiscoveredActionableAutoUpdateCount -Report (& $makeReport @($ivPending,$pithayaPending,$tagifyPending,$pithayaCurrent,$tagifyCurrent,$monitorOnly))) -ne 2) { throw 'Mixed pending schedule-bypass fixture did not fail closed for Tagify without current Marketplace evidence.' }"
    text = replace_once(text, old_mixed_assert, new_mixed_assert, 'mixed pending SelfTest fail-closed assertion')

    return bom + text.encode('utf-8')


def build() -> None:
    ns = load_validated_v020_namespace()
    base_integrate = ns['integrate_marketplace_engine']

    def hardened_integrate(addon: bytes) -> bytes:
        return harden_integrated_candidate(base_integrate(addon))

    ns['integrate_marketplace_engine'] = hardened_integrate
    ns['build']()

    addon_path = OUT / 'addon-manager.ps1'
    addon = addon_path.read_bytes()
    text = addon.decode('utf-8-sig')
    required = (
        "if (-not $item.PSObject.Properties['marketplace_identity_required'] -or -not [bool]$item.marketplace_identity_required) { continue }",
        "marketplace_identity_evidence_conclusive=$false",
        "Tagify without current conclusive Marketplace evidence escaped schedule-bypass fail-closed behavior.",
        "Mixed pending schedule-bypass fixture did not fail closed for Tagify without current Marketplace evidence.",
    )
    for marker in required:
        if marker not in text:
            raise RuntimeError(f'v0.2.1 hardening marker missing: {marker}')

    report = json.loads(REPORT.read_text(encoding='utf-8'))
    report['candidate_version'] = '0.6.29-validation-integrated-marketplace-v0.2.1'
    report['candidate_addon'] = {'size': len(addon), 'sha256': sha(addon)}
    report['validated_integrated_base'] = {
        'head': BASE_INTEGRATED_HEAD,
        'path': BASE_INTEGRATED_PATH,
        'blob': BASE_INTEGRATED_BLOB,
    }
    report['schedule_bypass_missing_marketplace_evidence_fails_closed'] = True
    report['selftest_fixture_matches_marketplace_required_shape'] = True
    report.setdefault('features', []).append('schedule-bypass-requires-marketplace-identity-required-marker')
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('MARKETPLACE_INTEGRATED_ENGINE_V021_BUILD_PASS', len(addon), sha(addon), BASE_INTEGRATED_BLOB)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    if not args.build:
        parser.error('use --build')
    build()


if __name__ == '__main__':
    main()
