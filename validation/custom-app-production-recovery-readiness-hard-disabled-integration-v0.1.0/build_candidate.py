from __future__ import annotations
from pathlib import Path
import hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_MAIN = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
PARENT_HEAD = '1ae80173bc70cce71dd8fb77595b64ca4463d7ad'
PARENT_BUILDER = 'validation/custom-app-production-recovery-routing-dispatch-hard-disabled-integration-v0.1.0/build_candidate.py'
PARENT_BUILDER_BLOB = 'c21290958ad5e9ddeebb08b2edfe9a53081a49e1'
PARENT_ADDON = (1344160, '8ca2b97ec9460d5d95d695d8205b1186e654ebcd5c8de6e3085b15b78b734644')
PARENT_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
READINESS_HEAD = '19bfe20681bc497ac45ee8face01d74436c38d1b'
READINESS_PATH = 'validation/custom-app-production-recovery-aware-new-permit-readiness-v0.1.0/custom-app-production-recovery-aware-new-permit-readiness.ps1'
READINESS_BLOB = '0c73b5352c7b9bd29472d3a145a4fc4333d0574b'
PROMOTION_HEAD = '6bc69d2c8b12d074fa68f3d2ed7688e0846cd23c'
RECOVERY_RESUME_HEAD = '2ad528b8a969fd45e88168d22ea787984f5e2714'
TERMINAL_BRIDGE_HEAD = '894c5013df0a2f1c17483425a31f49d0f9eaa99d'
PIPELINE_TRUE_RE = r'(?im)^[ \t]*\$script:CustomAppProductionPipelineEnabled[ \t]*=[ \t]*\$true[ \t]*$'

REQUIRED_READINESS = [
    'Get-CustomAppProductionRecoveryAwarePermitReadinessSha256V010',
    'Test-CustomAppProductionRecoveryAwarePermitReadinessSha256V010',
    'Get-CustomAppProductionRecoveryAwarePermitReadinessMaterialV010',
    'New-CustomAppProductionRecoveryAwarePermitReadinessDeniedV010',
    'Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010',
    'Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010',
]
REQUIRED_PARENT_DEPS = [
    'Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010',
    'Resolve-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationV010',
    'Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationReceiptV010',
    'Resolve-CustomAppProductionPromotionEligibilityV010',
]
FORBIDDEN_READINESS_PRIMITIVES = [
    '[IO.Directory]::Delete', '[IO.Directory]::Move', '[IO.File]::Copy', '[IO.File]::Write',
    'Remove-Item', 'Move-Item', 'Copy-Item', 'Set-Content', 'Add-Content', 'Out-File',
    'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-Process', 'ProcessStartInfo',
    'New-CustomAppProductionPermitV010', 'Reserve-CustomAppProductionPermitV010',
    'Consume-CustomAppProductionPermitV010',
]

SELFTEST = r'''function Invoke-CustomAppProductionRecoveryReadinessHardDisabledSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'Recovery readiness integration observed enabled production pipeline.'}
    foreach($name in @(
        'Get-CustomAppProductionRecoveryAwarePermitReadinessSha256V010',
        'Test-CustomAppProductionRecoveryAwarePermitReadinessSha256V010',
        'Get-CustomAppProductionRecoveryAwarePermitReadinessMaterialV010',
        'New-CustomAppProductionRecoveryAwarePermitReadinessDeniedV010',
        'Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010',
        'Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010'
    )){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('Integrated recovery readiness function missing: '+$name)}
    }
    if([string]$CustomAppProductionRecoveryAwarePermitReadinessManagedBy -cne 'custom-app-production-recovery-aware-new-permit-readiness-v1'){throw 'Recovery readiness owner drift.'}
    if([string]$CustomAppProductionRecoveryAwarePermitReadinessQualifiedPromotionHead -cne '6bc69d2c8b12d074fa68f3d2ed7688e0846cd23c'){throw 'Recovery readiness promotion parent drift.'}
    if([string]$CustomAppProductionRecoveryAwarePermitReadinessQualifiedRecoveryResumeHead -cne '2ad528b8a969fd45e88168d22ea787984f5e2714'){throw 'Recovery readiness resume parent drift.'}
    if([string]$CustomAppProductionRecoveryAwarePermitReadinessQualifiedTerminalBridgeHead -cne '894c5013df0a2f1c17483425a31f49d0f9eaa99d'){throw 'Recovery readiness terminal bridge parent drift.'}
    Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_READINESS_HARD_DISABLED_SELFTEST_V010_PASS loaded-but-unreachable zero-authority'
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
        raise RuntimeError('parent routing-dispatch builder pin drift')
    subprocess.check_call(['python', str(ROOT / PARENT_BUILDER)], cwd=ROOT)
    d = ROOT / 'validation/custom-app-production-recovery-routing-dispatch-hard-disabled-integration-v0.1.0/out/bin'
    main = (d / 'spotify-control.ps1').read_bytes()
    addon = (d / 'addon-manager.ps1').read_bytes()
    collector = (d / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (d / 'LevelDbReadOnly.cs').read_bytes()
    report = json.loads((ROOT / 'validation/custom-app-production-recovery-routing-dispatch-hard-disabled-integration-v0.1.0/candidate-validation.json').read_text(encoding='utf-8'))
    if (len(main), sha(main)) != PARENT_MAIN:
        raise RuntimeError(f'parent main drift {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != PARENT_ADDON:
        raise RuntimeError(f'parent addon drift {len(addon)} {sha(addon)}')
    for flag in ('pipeline_enabled','pipeline_enablement_implemented','recovery_normal_path_wiring_added','bounded_recovery_normal_path_wiring_added','routing_normal_path_wiring_added','dispatch_normal_path_wiring_added','dispatch_execution_added','generic_auto_authority_expanded','production_main_changed'):
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
    if 'CUSTOM_APP_PRODUCTION_RECOVERY_ROUTING_DISPATCH_HARD_DISABLED_SELFTEST_V010_PASS loaded-but-unreachable' not in parent:
        raise RuntimeError('parent routing-dispatch selftest marker missing')
    parent_true_count = len(re.findall(PIPELINE_TRUE_RE, parent))
    if parent_true_count != 1:
        raise RuntimeError(f'parent forced-enable assignment count drift: {parent_true_count}')
    missing_parent_deps = [name for name in REQUIRED_PARENT_DEPS if name not in parent_set]
    if missing_parent_deps:
        raise RuntimeError(f'parent readiness dependency export(s) missing: {missing_parent_deps}')

    actual_blob = git_blob(READINESS_HEAD, READINESS_PATH)
    if actual_blob != READINESS_BLOB:
        raise RuntimeError(f'readiness core blob pin drift {actual_blob} != {READINESS_BLOB}')
    readiness = git_object_bytes(actual_blob).decode('utf-8-sig').replace('\r\n', '\n').strip()
    readiness_funcs = functions(readiness)
    if not readiness_funcs:
        raise RuntimeError('readiness core contains no functions')
    collisions = sorted(parent_set & set(readiness_funcs))
    if collisions:
        raise RuntimeError(f'readiness function collision(s): {collisions}')
    missing = [name for name in REQUIRED_READINESS if name not in readiness_funcs]
    if missing:
        raise RuntimeError(f'readiness required export(s) missing: {missing}')
    extra = sorted(set(readiness_funcs) - set(REQUIRED_READINESS))
    if extra:
        raise RuntimeError(f'unexpected readiness export(s): {extra}')
    for primitive in FORBIDDEN_READINESS_PRIMITIVES:
        if primitive.lower() in readiness.lower():
            raise RuntimeError(f'readiness core gained forbidden primitive: {primitive}')
    for escaped in ('readiness_is_authority=$true','promotion_token_issued=$true','permit_issued=$true','execution_authorized=$true','restore_authorized=$true','apply_authorized=$true','cleanup_authorized=$true','production_mutation_authorized=$true'):
        if re.search(re.escape(escaped).replace(r'\=', r'\s*=\s*'), readiness, re.IGNORECASE):
            raise RuntimeError(f'readiness authority escaped in source: {escaped}')

    first = re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{', parent)
    if not first:
        raise RuntimeError('parent first function not found')
    payload = readiness + '\n\n' + SELFTEST.rstrip() + '\n\n'
    text = parent[:first.start()] + payload + parent[first.start():]

    addon_selftest = function_block(text, 'Invoke-AddonSelfTest')
    old_hook = '    try { Invoke-CustomAppProductionRecoveryRoutingDispatchHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production recovery routing dispatch hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    new_hook = old_hook + '\n    try { Invoke-CustomAppProductionRecoveryReadinessHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production recovery readiness hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    addon_selftest = replace_once(addon_selftest, old_hook, new_hook, 'recovery readiness SelfTest hook')
    text = replace_function(text, 'Invoke-AddonSelfTest', addon_selftest)

    candidate_funcs = set(functions(text))
    missing_after = [name for name in REQUIRED_READINESS if name not in candidate_funcs]
    if missing_after:
        raise RuntimeError(f'candidate readiness exports missing: {missing_after}')

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

    readiness_call = 'Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010'
    unexpected_callers = []
    for name in parent_funcs:
        if name == 'Invoke-AddonSelfTest':
            continue
        if readiness_call in function_block(text, name):
            unexpected_callers.append(name)
    if unexpected_callers:
        raise RuntimeError(f'readiness became reachable from pre-existing function(s): {unexpected_callers}')

    selftest_block = function_block(text, 'Invoke-CustomAppProductionRecoveryReadinessHardDisabledSelfTestV010')
    if re.search(r'(?im)^[ \t]*Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010\b', selftest_block):
        raise RuntimeError('readiness SelfTest invokes readiness resolver')

    reduced = text
    reduced = replace_once(reduced, payload, '', 'inserted recovery readiness payload')
    reduced = replace_once(reduced, new_hook, old_hook, 'inserted recovery readiness SelfTest hook')
    if reduced != parent:
        raise RuntimeError('candidate contains changes outside readiness module + SelfTest hook')

    encoded = bom + text.replace('\n', '\r\n').encode('utf-8')
    report = {
        'schema': 1,
        'production_main': PRODUCTION_MAIN,
        'parent_head': PARENT_HEAD,
        'parent_addon_size': len(addon),
        'parent_addon_sha256': sha(addon),
        'readiness_head': READINESS_HEAD,
        'readiness_blob': READINESS_BLOB,
        'readiness_promotion_head': PROMOTION_HEAD,
        'readiness_recovery_resume_head': RECOVERY_RESUME_HEAD,
        'readiness_terminal_bridge_head': TERMINAL_BRIDGE_HEAD,
        'readiness_function_count': len(readiness_funcs),
        'preexisting_parent_functions_changed': changed,
        'readiness_preexisting_callers': unexpected_callers,
        'readiness_selftest_executes_readiness': False,
        'readiness_source_forbidden_primitive_count': 0,
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
        'readiness_normal_path_wiring_added': False,
        'readiness_execution_added': False,
        'permit_issuance_added': False,
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
    print(f"RECOVERY_READINESS_HARD_DISABLED_CANDIDATE addon_size={len(candidate)} addon_sha256={sha(candidate)} report_sha256={sha(REPORT.read_bytes())}")


if __name__ == '__main__':
    main()
