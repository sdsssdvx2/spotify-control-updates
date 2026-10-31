from __future__ import annotations
from pathlib import Path
import hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_MAIN = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
PARENT_HEAD = '92a3e8ac83c8bbbe9e5d4b6f3f00469701250acc'
PARENT_BUILDER = 'validation/custom-app-production-bounded-recovery-stack-hard-disabled-integration-v0.1.0/build_candidate.py'
PARENT_BUILDER_BLOB = '1440d16fd55b268efbf1fdd4efe714cd80c35e39'
PARENT_ADDON = (1307828, 'd0bce3c8c4684838cd19cb2bd8bf70a44f8cbba323a853893e5497a854e96afc')
PARENT_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
ROUTER_HEAD = '2f2f596bb8a86c0b074543992f7634be858821a4'
ROUTER_PATH = 'validation/custom-app-production-recovery-routing-admission-v0.1.0/custom-app-production-recovery-routing-admission.ps1'
ROUTER_BLOB = '4225bb042aa8d240706e1f383e54f12894e74512'
PIPELINE_TRUE_RE = r'(?im)^[ \t]*\$script:CustomAppProductionPipelineEnabled[ \t]*=[ \t]*\$true[ \t]*$'

REQUIRED_ROUTER = [
    'Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010',
    'Test-CustomAppProductionRecoveryRoutingAdmissionSha256V010',
    'Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010',
    'New-CustomAppProductionRecoveryRoutingAdmissionDeniedV010',
    'Get-CustomAppProductionRecoveryRoutingExpectedV010',
    'Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010',
    'Resolve-CustomAppProductionRecoveryRoutingAdmissionV010',
]

SELFTEST = r'''function Invoke-CustomAppProductionRecoveryRoutingHardDisabledSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'Recovery routing integration observed enabled production pipeline.'}
    foreach($name in @(
        'Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010',
        'Test-CustomAppProductionRecoveryRoutingAdmissionSha256V010',
        'Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010',
        'New-CustomAppProductionRecoveryRoutingAdmissionDeniedV010',
        'Get-CustomAppProductionRecoveryRoutingExpectedV010',
        'Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010',
        'Resolve-CustomAppProductionRecoveryRoutingAdmissionV010'
    )){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('Integrated recovery routing function missing: '+$name)}
    }
    if([string]$CustomAppProductionRecoveryRoutingAdmissionManagedBy -cne 'custom-app-production-recovery-routing-admission-v1'){throw 'Recovery routing owner drift.'}
    if([string]$CustomAppProductionRecoveryRoutingAdmissionQualifiedJournalHead -cne '7e26187e2360089024e9d72d0701be6f1577a1ef'){throw 'Recovery routing journal parent drift.'}
    if([string]$CustomAppProductionRecoveryRoutingAdmissionQualifiedBoundedExecutorHead -cne '5a2840d824f1e28e2920657d0e3a8e139d7e8b71'){throw 'Recovery routing bounded executor parent drift.'}
    if([string]$CustomAppProductionRecoveryRoutingAdmissionQualifiedIntegratedCandidateHead -cne '92a3e8ac83c8bbbe9e5d4b6f3f00469701250acc'){throw 'Recovery routing integrated candidate parent drift.'}
    Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_ROUTING_HARD_DISABLED_SELFTEST_V010_PASS loaded-but-unreachable'
}
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git', 'rev-parse', f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def git_object_bytes(blob: str) -> bytes:
    return subprocess.check_output(['git', 'cat-file', 'blob', blob], cwd=ROOT)


def functions(text: str) -> list[str]:
    return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{', text)


def function_bounds(text: str, name: str) -> tuple[int, int]:
    m = re.search(rf'(?im)^[ \t]*function\s+{re.escape(name)}\s*\{{', text)
    if not m:
        raise RuntimeError(f'missing function {name}')
    nxt = re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{', text[m.end():])
    return m.start(), (m.end() + nxt.start() if nxt else len(text))


def function_block(text: str, name: str) -> str:
    a, b = function_bounds(text, name)
    return text[a:b]


def replace_function(text: str, name: str, replacement: str) -> str:
    a, b = function_bounds(text, name)
    return text[:a] + replacement.rstrip() + '\n\n' + text[b:].lstrip('\n')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label} anchor count drift: {count}')
    return text.replace(old, new, 1)


def build_parent() -> tuple[bytes, bytes, bytes, bytes, dict]:
    if git_blob(PARENT_HEAD, PARENT_BUILDER) != PARENT_BUILDER_BLOB:
        raise RuntimeError('parent bounded hard-disabled builder pin drift')
    subprocess.check_call(['python', str(ROOT / PARENT_BUILDER)], cwd=ROOT)
    d = ROOT / 'validation/custom-app-production-bounded-recovery-stack-hard-disabled-integration-v0.1.0/out/bin'
    main = (d / 'spotify-control.ps1').read_bytes()
    addon = (d / 'addon-manager.ps1').read_bytes()
    collector = (d / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (d / 'LevelDbReadOnly.cs').read_bytes()
    report = json.loads((ROOT / 'validation/custom-app-production-bounded-recovery-stack-hard-disabled-integration-v0.1.0/candidate-validation.json').read_text(encoding='utf-8'))
    if (len(main), sha(main)) != PARENT_MAIN:
        raise RuntimeError(f'parent main drift {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != PARENT_ADDON:
        raise RuntimeError(f'parent addon drift {len(addon)} {sha(addon)}')
    for flag in ('pipeline_enabled','pipeline_enablement_implemented','recovery_normal_path_wiring_added','bounded_recovery_normal_path_wiring_added','generic_auto_authority_expanded','production_main_changed'):
        if bool(report.get(flag)):
            raise RuntimeError(f'parent unexpectedly authoritative: {flag}')
    return main, addon, collector, reader, report


def integrate(addon: bytes) -> tuple[bytes, dict]:
    bom = b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    parent = addon[len(bom):].decode('utf-8').replace('\r\n', '\n')
    parent_funcs = functions(parent)
    parent_set = set(parent_funcs)
    if '$script:CustomAppProductionPipelineEnabled = $false' not in parent:
        raise RuntimeError('parent production pipeline hard-disable missing')
    if 'CUSTOM_APP_PRODUCTION_BOUNDED_RECOVERY_STACK_HARD_DISABLED_SELFTEST_V010_PASS loaded-but-unreachable' not in parent:
        raise RuntimeError('parent bounded recovery selftest marker missing')
    parent_true_count = len(re.findall(PIPELINE_TRUE_RE, parent))
    if parent_true_count != 1:
        raise RuntimeError(f'parent forced-enable assignment count drift: {parent_true_count}')

    actual_blob = git_blob(ROUTER_HEAD, ROUTER_PATH)
    if actual_blob != ROUTER_BLOB:
        raise RuntimeError(f'router core blob pin drift {actual_blob} != {ROUTER_BLOB}')
    router = git_object_bytes(actual_blob).decode('utf-8-sig').replace('\r\n', '\n').strip()
    router_funcs = functions(router)
    if not router_funcs:
        raise RuntimeError('router core contains no functions')
    collisions = sorted(parent_set & set(router_funcs))
    if collisions:
        raise RuntimeError(f'router function collision(s): {collisions}')
    missing = [name for name in REQUIRED_ROUTER if name not in router_funcs]
    if missing:
        raise RuntimeError(f'router required export(s) missing: {missing}')

    first = re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{', parent)
    if not first:
        raise RuntimeError('parent first function not found')
    payload = router + '\n\n' + SELFTEST.rstrip() + '\n\n'
    text = parent[:first.start()] + payload + parent[first.start():]

    addon_selftest = function_block(text, 'Invoke-AddonSelfTest')
    old_hook = '    try { Invoke-CustomAppProductionBoundedRecoveryStackHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production bounded recovery stack hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    new_hook = old_hook + '\n    try { Invoke-CustomAppProductionRecoveryRoutingHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production recovery routing hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    addon_selftest = replace_once(addon_selftest, old_hook, new_hook, 'recovery routing SelfTest hook')
    text = replace_function(text, 'Invoke-AddonSelfTest', addon_selftest)

    candidate_funcs = set(functions(text))
    missing_after = [name for name in REQUIRED_ROUTER if name not in candidate_funcs]
    if missing_after:
        raise RuntimeError(f'candidate router exports missing: {missing_after}')

    changed = []
    for name in parent_funcs:
        if name == 'Invoke-AddonSelfTest':
            continue
        if function_block(parent, name) != function_block(text, name):
            changed.append(name)
    if changed:
        raise RuntimeError(f'pre-existing parent function changed: {changed}')
    if function_block(parent, 'Invoke-CustomAppProductionFullChainV010') != function_block(text, 'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('full-chain execution function changed')

    if len(re.findall(PIPELINE_TRUE_RE, text)) != parent_true_count:
        raise RuntimeError('pipeline forced-enable assignment count changed')
    if '$script:CustomAppProductionPipelineEnabled = $false' not in text:
        raise RuntimeError('pipeline hard-disable lost')

    # The router is loaded only. No pre-existing production/normal-path function may reference it.
    router_call = 'Resolve-CustomAppProductionRecoveryRoutingAdmissionV010'
    unexpected_callers = []
    for name in parent_funcs:
        if name == 'Invoke-AddonSelfTest':
            continue
        if router_call in function_block(text, name):
            unexpected_callers.append(name)
    if unexpected_callers:
        raise RuntimeError(f'router became reachable from pre-existing function(s): {unexpected_callers}')

    reduced = text
    reduced = replace_once(reduced, payload, '', 'inserted recovery routing payload')
    reduced = replace_once(reduced, new_hook, old_hook, 'inserted recovery routing SelfTest hook')
    if reduced != parent:
        raise RuntimeError('candidate contains changes outside router module + SelfTest hook')

    encoded = bom + text.replace('\n', '\r\n').encode('utf-8')
    report = {
        'schema': 1,
        'production_main': PRODUCTION_MAIN,
        'parent_head': PARENT_HEAD,
        'parent_addon_size': len(addon),
        'parent_addon_sha256': sha(addon),
        'router_head': ROUTER_HEAD,
        'router_blob': ROUTER_BLOB,
        'router_function_count': len(router_funcs),
        'preexisting_parent_functions_changed': changed,
        'router_preexisting_callers': unexpected_callers,
        'full_chain_function_unchanged': True,
        'candidate_reduces_exactly_to_parent': True,
        'pipeline_true_assignment_count': parent_true_count,
        'pipeline_true_assignment_inherited_selftest_only': True,
        'pipeline_enabled': False,
        'pipeline_enablement_implemented': False,
        'recovery_normal_path_wiring_added': False,
        'bounded_recovery_normal_path_wiring_added': False,
        'routing_normal_path_wiring_added': False,
        'router_execution_added': False,
        'generic_auto_authority_expanded': False,
        'production_main_changed': False,
        'candidate_addon_size': len(encoded),
        'candidate_addon_sha256': sha(encoded),
    }
    return encoded, report


def main() -> None:
    main_bytes, addon_bytes, collector, reader, _ = build_parent()
    candidate, report = integrate(addon_bytes)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main_bytes)
    (OUT / 'addon-manager.ps1').write_bytes(candidate)
    (OUT / 'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT / 'LevelDbReadOnly.cs').write_bytes(reader)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(f"RECOVERY_ROUTING_HARD_DISABLED_CANDIDATE addon_size={len(candidate)} addon_sha256={sha(candidate)}")


if __name__ == '__main__':
    main()
