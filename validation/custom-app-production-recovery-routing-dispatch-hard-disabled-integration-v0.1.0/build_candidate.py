from __future__ import annotations
from pathlib import Path
import hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_MAIN = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
PARENT_HEAD = '165f820dff82a8c4e5edada443db595f545ddc03'
PARENT_BUILDER = 'validation/custom-app-production-recovery-routing-hard-disabled-integration-v0.1.0/build_candidate.py'
PARENT_BUILDER_BLOB = '977ee4a599952877a2eac316fa78ca406326b396'
PARENT_ADDON = (1325619, 'e7f3ba6bc03cc4ff118f098778fe5ac7f308f1a99ecdc4149131ed2a8156579a')
PARENT_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
DISPATCH_HEAD = '93d4bdb0dfde63e5a643e5ab44023a8b0e5652c1'
DISPATCH_PATH = 'validation/custom-app-production-recovery-routing-fixture-dispatch-v0.1.0/custom-app-production-recovery-routing-fixture-dispatch.ps1'
DISPATCH_BLOB = '0cfb42759a3284dd70b2a8395304f48588ccd1b8'
ROUTER_HEAD = '2f2f596bb8a86c0b074543992f7634be858821a4'
BOUNDED_EXECUTOR_HEAD = '5a2840d824f1e28e2920657d0e3a8e139d7e8b71'
PIPELINE_TRUE_RE = r'(?im)^[ \t]*\$script:CustomAppProductionPipelineEnabled[ \t]*=[ \t]*\$true[ \t]*$'

REQUIRED_DISPATCH = [
    'Get-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010',
    'Test-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010',
    'Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010',
    'Test-CustomAppProductionRecoveryRoutingFixtureDispatchPathWithinV010',
    'Test-CustomAppProductionRecoveryRoutingFixtureDispatchEnvironmentV010',
    'Get-CustomAppProductionRecoveryRoutingFixtureDispatchResultMaterialV010',
    'Test-CustomAppProductionRecoveryRoutingFixtureDispatchResultV010',
    'Invoke-CustomAppProductionRecoveryRoutingFixtureDispatchV010',
]

SELFTEST = r'''function Invoke-CustomAppProductionRecoveryRoutingDispatchHardDisabledSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'Recovery routing dispatch integration observed enabled production pipeline.'}
    foreach($name in @(
        'Get-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010',
        'Test-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010',
        'Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010',
        'Test-CustomAppProductionRecoveryRoutingFixtureDispatchPathWithinV010',
        'Test-CustomAppProductionRecoveryRoutingFixtureDispatchEnvironmentV010',
        'Get-CustomAppProductionRecoveryRoutingFixtureDispatchResultMaterialV010',
        'Test-CustomAppProductionRecoveryRoutingFixtureDispatchResultV010',
        'Invoke-CustomAppProductionRecoveryRoutingFixtureDispatchV010'
    )){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('Integrated recovery routing dispatch function missing: '+$name)}
    }
    if([string]$CustomAppProductionRecoveryRoutingFixtureDispatchManagedBy -cne 'custom-app-production-recovery-routing-fixture-dispatch-v1'){throw 'Recovery routing dispatch owner drift.'}
    if([string]$CustomAppProductionRecoveryRoutingFixtureDispatchQualifiedRouterHead -cne '2f2f596bb8a86c0b074543992f7634be858821a4'){throw 'Recovery routing dispatch router parent drift.'}
    if([string]$CustomAppProductionRecoveryRoutingFixtureDispatchQualifiedBoundedExecutorHead -cne '5a2840d824f1e28e2920657d0e3a8e139d7e8b71'){throw 'Recovery routing dispatch bounded executor parent drift.'}
    Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_ROUTING_DISPATCH_HARD_DISABLED_SELFTEST_V010_PASS loaded-but-unreachable'
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
        raise RuntimeError('parent routing hard-disabled builder pin drift')
    subprocess.check_call(['python', str(ROOT / PARENT_BUILDER)], cwd=ROOT)
    d = ROOT / 'validation/custom-app-production-recovery-routing-hard-disabled-integration-v0.1.0/out/bin'
    main = (d / 'spotify-control.ps1').read_bytes()
    addon = (d / 'addon-manager.ps1').read_bytes()
    collector = (d / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (d / 'LevelDbReadOnly.cs').read_bytes()
    report = json.loads((ROOT / 'validation/custom-app-production-recovery-routing-hard-disabled-integration-v0.1.0/candidate-validation.json').read_text(encoding='utf-8'))
    if (len(main), sha(main)) != PARENT_MAIN:
        raise RuntimeError(f'parent main drift {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != PARENT_ADDON:
        raise RuntimeError(f'parent addon drift {len(addon)} {sha(addon)}')
    for flag in ('pipeline_enabled','pipeline_enablement_implemented','recovery_normal_path_wiring_added','bounded_recovery_normal_path_wiring_added','routing_normal_path_wiring_added','router_execution_added','generic_auto_authority_expanded','production_main_changed'):
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
    if 'CUSTOM_APP_PRODUCTION_RECOVERY_ROUTING_HARD_DISABLED_SELFTEST_V010_PASS loaded-but-unreachable' not in parent:
        raise RuntimeError('parent recovery routing selftest marker missing')
    parent_true_count = len(re.findall(PIPELINE_TRUE_RE, parent))
    if parent_true_count != 1:
        raise RuntimeError(f'parent forced-enable assignment count drift: {parent_true_count}')

    actual_blob = git_blob(DISPATCH_HEAD, DISPATCH_PATH)
    if actual_blob != DISPATCH_BLOB:
        raise RuntimeError(f'dispatch core blob pin drift {actual_blob} != {DISPATCH_BLOB}')
    dispatch = git_object_bytes(actual_blob).decode('utf-8-sig').replace('\r\n', '\n').strip()
    dispatch_funcs = functions(dispatch)
    if not dispatch_funcs:
        raise RuntimeError('dispatch core contains no functions')
    collisions = sorted(parent_set & set(dispatch_funcs))
    if collisions:
        raise RuntimeError(f'dispatch function collision(s): {collisions}')
    missing = [name for name in REQUIRED_DISPATCH if name not in dispatch_funcs]
    if missing:
        raise RuntimeError(f'dispatch required export(s) missing: {missing}')

    first = re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{', parent)
    if not first:
        raise RuntimeError('parent first function not found')
    payload = dispatch + '\n\n' + SELFTEST.rstrip() + '\n\n'
    text = parent[:first.start()] + payload + parent[first.start():]

    addon_selftest = function_block(text, 'Invoke-AddonSelfTest')
    old_hook = '    try { Invoke-CustomAppProductionRecoveryRoutingHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production recovery routing hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    new_hook = old_hook + '\n    try { Invoke-CustomAppProductionRecoveryRoutingDispatchHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production recovery routing dispatch hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    addon_selftest = replace_once(addon_selftest, old_hook, new_hook, 'recovery routing dispatch SelfTest hook')
    text = replace_function(text, 'Invoke-AddonSelfTest', addon_selftest)

    candidate_funcs = set(functions(text))
    missing_after = [name for name in REQUIRED_DISPATCH if name not in candidate_funcs]
    if missing_after:
        raise RuntimeError(f'candidate dispatch exports missing: {missing_after}')

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

    # Dispatch is loaded only. No pre-existing production/normal-path function may reference it.
    dispatch_call = 'Invoke-CustomAppProductionRecoveryRoutingFixtureDispatchV010'
    unexpected_callers = []
    for name in parent_funcs:
        if name == 'Invoke-AddonSelfTest':
            continue
        if dispatch_call in function_block(text, name):
            unexpected_callers.append(name)
    if unexpected_callers:
        raise RuntimeError(f'dispatch became reachable from pre-existing function(s): {unexpected_callers}')

    # SelfTest may prove symbols/owner/pins only; it must never invoke dispatch.
    selftest_block = function_block(text, 'Invoke-CustomAppProductionRecoveryRoutingDispatchHardDisabledSelfTestV010')
    if re.search(r'(?im)^[ \t]*Invoke-CustomAppProductionRecoveryRoutingFixtureDispatchV010\b', selftest_block):
        raise RuntimeError('dispatch SelfTest invokes dispatch executor')

    reduced = text
    reduced = replace_once(reduced, payload, '', 'inserted recovery routing dispatch payload')
    reduced = replace_once(reduced, new_hook, old_hook, 'inserted recovery routing dispatch SelfTest hook')
    if reduced != parent:
        raise RuntimeError('candidate contains changes outside dispatch module + SelfTest hook')

    encoded = bom + text.replace('\n', '\r\n').encode('utf-8')
    report = {
        'schema': 1,
        'production_main': PRODUCTION_MAIN,
        'parent_head': PARENT_HEAD,
        'parent_addon_size': len(addon),
        'parent_addon_sha256': sha(addon),
        'dispatch_head': DISPATCH_HEAD,
        'dispatch_blob': DISPATCH_BLOB,
        'dispatch_router_head': ROUTER_HEAD,
        'dispatch_bounded_executor_head': BOUNDED_EXECUTOR_HEAD,
        'dispatch_function_count': len(dispatch_funcs),
        'preexisting_parent_functions_changed': changed,
        'dispatch_preexisting_callers': unexpected_callers,
        'dispatch_selftest_executes_dispatch': False,
        'full_chain_function_unchanged': True,
        'candidate_reduces_exactly_to_parent': True,
        'pipeline_true_assignment_count': parent_true_count,
        'pipeline_true_assignment_inherited_selftest_only': True,
        'pipeline_enabled': False,
        'pipeline_enablement_implemented': False,
        'recovery_normal_path_wiring_added': False,
        'bounded_recovery_normal_path_wiring_added': False,
        'routing_normal_path_wiring_added': False,
        'dispatch_normal_path_wiring_added': False,
        'dispatch_execution_added': False,
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
    print(f"RECOVERY_ROUTING_DISPATCH_HARD_DISABLED_CANDIDATE addon_size={len(candidate)} addon_sha256={sha(candidate)}")


if __name__ == '__main__':
    main()
