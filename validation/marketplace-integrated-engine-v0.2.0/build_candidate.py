from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'
GLUE = HERE / 'integration-glue.ps1'

PRODUCTION_BASE = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'

TAGIFY_HEAD = '3178c335e82bdbf7ca5610f0fd618468b4e1c26a'
TAGIFY_PATH = 'validation/marketplace-lifecycle-tagify-state-preserving-v0.1.2/build_candidate.py'
TAGIFY_BLOB = '33261373ae8f178de305964dd1376b6babf84322'
TAGIFY_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
TAGIFY_ADDON = (341952, '2754b8d32f96bc8368436cced0b5969a9f1c97a61d61f1082bb070b6f2dd67a7')

SETTINGS_HEAD = '57be1dcd10e339e9da2b8f15b9910a2ae1b79c1b'
SETTINGS_BUILDER_PATH = 'validation/marketplace-lifecycle-settings-core-v0.1.0/build_candidate.py'
SETTINGS_BUILDER_BLOB = 'c31579cb95f3a8c7065afd462c377e19378d3cc6'
SETTINGS_CORE_PATH = 'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1'
SETTINGS_CORE_BLOB = '86c715370021cc1f09c46424172e2163ad56f236'

LEDGER_HEAD = '1e70069457ceeffb15bdc711b3b6c29cb2d3639e'
LEDGER_PATH = 'validation/marketplace-lifecycle-identity-ledger-v0.1.0/marketplace-identity-ledger.ps1'
LEDGER_BLOB = '7cea70935f84deb098c4db3c13fc6b901f121626'

COLLECTOR_HEAD = '957286ed0a9d06e469d09811286b93321af819a0'
COLLECTOR_PATH = 'validation/marketplace-record-discovery-v0.1.0/Collect-Marketplace-Records.ps1'
COLLECTOR_BLOB = '5f4cc7f78a5d1a17281771f2b2caf58aab09e008'
READER_HEAD = '14a2f9bfacc54e617aec024b44b7f367dec28bbe'
READER_PATH = 'validation/star-ratings-runtime-topology-collector-v0.1.0/LevelDbReadOnly.cs'
READER_BLOB = '66de32a1dafcb4fbca9ebe0509cf326fd8a65a5e'
MARKETPLACE_UPSTREAM_COMMIT = '7f357885a3514a55d426fd43edfd705d583a5cdd'

AUTHORIZED = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker', 'tagify']


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git', 'rev-parse', f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def require_blob(commit: str, path: str, expected: str, label: str) -> None:
    actual = git_blob(commit, path)
    if actual != expected:
        raise RuntimeError(f'{label} blob drift: {actual} != {expected}')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label} anchor count drift: {count}')
    return text.replace(old, new, 1)


def function_bounds(text: str, name: str) -> tuple[int, int]:
    marker = f'function {name} {{'
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f'missing function {name}')
    end = text.find('\nfunction ', start + len(marker))
    if end < 0:
        end = len(text)
    return start, end


def function_block(text: str, name: str) -> str:
    start, end = function_bounds(text, name)
    return text[start:end].rstrip()


def replace_function(text: str, name: str, replacement: str) -> str:
    start, end = function_bounds(text, name)
    return text[:start] + replacement.rstrip() + '\n\n' + text[end:].lstrip('\n')


def verify_pins() -> None:
    require_blob(TAGIFY_HEAD, TAGIFY_PATH, TAGIFY_BLOB, 'Tagify v0.1.2 wrapper')
    require_blob(SETTINGS_HEAD, SETTINGS_BUILDER_PATH, SETTINGS_BUILDER_BLOB, 'settings core builder')
    require_blob(SETTINGS_HEAD, SETTINGS_CORE_PATH, SETTINGS_CORE_BLOB, 'settings core')
    require_blob(LEDGER_HEAD, LEDGER_PATH, LEDGER_BLOB, 'Marketplace identity ledger')
    require_blob(COLLECTOR_HEAD, COLLECTOR_PATH, COLLECTOR_BLOB, 'Marketplace collector')
    require_blob(READER_HEAD, READER_PATH, READER_BLOB, 'LevelDB reader')


def reproduce_tagify_candidate() -> tuple[bytes, bytes]:
    wrapper = git_bytes(TAGIFY_HEAD, TAGIFY_PATH)
    temp = HERE / '_pinned_tagify_v012_builder.py'
    try:
        temp.write_bytes(wrapper)
        subprocess.check_call(['python', str(temp)], cwd=ROOT)
    finally:
        temp.unlink(missing_ok=True)
    main = (OUT / 'spotify-control.ps1').read_bytes()
    addon = (OUT / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != TAGIFY_MAIN:
        raise RuntimeError(f'Tagify candidate main drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != TAGIFY_ADDON:
        raise RuntimeError(f'Tagify candidate addon drift: {len(addon)} {sha(addon)}')
    return main, addon


def apply_validated_settings_core(addon: bytes) -> bytes:
    source = git_bytes(SETTINGS_HEAD, SETTINGS_BUILDER_PATH).decode('utf-8')
    source = replace_once(
        source,
        "HERE=ROOT/'validation/marketplace-lifecycle-settings-core-v0.1.0'",
        'HERE=Path(__file__).resolve().parent',
        'settings builder HERE relocation',
    )
    core_path = HERE / 'lifecycle-settings-core.ps1'
    core_path.write_bytes(git_bytes(SETTINGS_HEAD, SETTINGS_CORE_PATH))
    fake = HERE / '_pinned_settings_core_builder.py'
    namespace = {'__file__': str(fake), '__name__': 'marketplace_integrated_settings_core'}
    try:
        exec(compile(source, str(fake), 'exec'), namespace)
        patched = namespace['patch_addon'](addon)
    finally:
        core_path.unlink(missing_ok=True)
    return patched


def integrate_marketplace_engine(addon: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    text = addon[len(bom):].decode('utf-8')
    ledger = git_bytes(LEDGER_HEAD, LEDGER_PATH).decode('utf-8').strip()
    glue = GLUE.read_text(encoding='utf-8').strip()

    anchor = 'function Test-Due {'
    if text.count(anchor) != 1:
        raise RuntimeError('integration insertion anchor drift')
    text = text.replace(anchor, ledger + '\n\n' + glue + '\n\n' + anchor, 1)

    inventory = function_block(text, 'Get-AddonInventory')
    inventory_start = '    $hasUnresolvedTransaction = Test-PathSafe $TransactionPath "Leaf"'
    inventory_insert = inventory_start + '''

    # Current Marketplace evidence is collected every inventory cycle. A prior/stale ledger
    # can never authorize Marketplace-dependent mutation on its own.
    $marketplaceReport = Invoke-MarketplaceRecordDiscovery
    $marketplaceLifecycle = Update-MarketplaceIdentityLifecycleFromReport -State $state -MarketplaceReport $marketplaceReport -ObservedAt $now
    if ([bool]$marketplaceLifecycle.conclusive) { Save-AddonState $state }
'''
    inventory = replace_once(inventory, inventory_start, inventory_insert, 'inventory Marketplace discovery')

    success_anchor = "protected_state_policy='must-remain-byte-identical-through-apply';note='Installed-only exact release update; Browser/Default IndexedDB/localStorage/WebStorage are read-only protected state.'"
    success_replacement = "protected_state_policy='must-remain-byte-identical-through-apply';marketplace_identity_required=$true;marketplace_identity_evidence_conclusive=[bool]$marketplaceLifecycle.conclusive;marketplace_identity_fingerprint=$(if([bool]$marketplaceLifecycle.conclusive){[string]$marketplaceLifecycle.report_fingerprint}else{$null});note='Installed-only exact release update; Browser/Default IndexedDB/localStorage/WebStorage are read-only protected state.'"
    inventory = replace_once(inventory, success_anchor, success_replacement, 'Tagify current Marketplace evidence fields')

    catch_anchor = "protected_state_kind='tagify-browser-storage-v1';protected_state_policy='must-remain-byte-identical-through-apply';resolution_status=$null"
    catch_replacement = "protected_state_kind='tagify-browser-storage-v1';protected_state_policy='must-remain-byte-identical-through-apply';marketplace_identity_required=$true;marketplace_identity_evidence_conclusive=[bool]$marketplaceLifecycle.conclusive;marketplace_identity_fingerprint=$(if([bool]$marketplaceLifecycle.conclusive){[string]$marketplaceLifecycle.report_fingerprint}else{$null});resolution_status=$null"
    inventory = replace_once(inventory, catch_anchor, catch_replacement, 'Tagify error Marketplace evidence fields')

    report_anchor = '        policy_registry = $registrySummary\n'
    report_replacement = report_anchor + '''        marketplace_discovery = [pscustomobject]@{ status=[string]$marketplaceReport.status; record_count=[int]$marketplaceReport.record_count; identity_fingerprint=[string]$marketplaceReport.identity_fingerprint; read_only=[bool]$marketplaceReport.read_only; mutation_performed=[bool]$marketplaceReport.mutation_performed }
        marketplace_lifecycle = $marketplaceLifecycle
'''
    inventory = replace_once(inventory, report_anchor, report_replacement, 'inventory Marketplace report fields')
    text = replace_function(text, 'Get-AddonInventory', inventory)

    authorization = function_block(text, 'Get-AddonMutationAuthorization')
    final_allow = "    return [pscustomobject]@{ Allowed=$true; Handler=[string]$entry.handler; Reason='authorized'; Entry=$entry; RegistrySha256=$fingerprint }"
    gated_allow = '''    if ($Item.PSObject.Properties['marketplace_identity_required'] -and [bool]$Item.marketplace_identity_required) {
        $marketplaceGate = Test-MarketplaceSourceUserIntentAllowsMutation -State (Load-AddonState) -Item $Item
        if (-not [bool]$marketplaceGate.Allowed) {
            return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason=[string]$marketplaceGate.Reason; Entry=$entry; RegistrySha256=$fingerprint }
        }
    }
''' + final_allow
    authorization = replace_once(authorization, final_allow, gated_allow, 'mutation authorization Marketplace gate')
    text = replace_function(text, 'Get-AddonMutationAuthorization', authorization)

    actionable = function_block(text, 'Get-DiscoveredActionableAutoUpdateCount')
    tagify_count = '''        if ($source -ceq "alexk218/tagify" -and $safety -in @("trusted-baseline","release-proof-required")) {
            $count++
            continue
        }'''
    tagify_count_gated = '''        if ($source -ceq "alexk218/tagify" -and $safety -in @("trusted-baseline","release-proof-required")) {
            $plan = Get-AddonSourceAdapterPlan -Item $item
            if ([bool]$plan.allowed -and [bool]$plan.mutation_authorized) { $count++ }
            continue
        }'''
    actionable = replace_once(actionable, tagify_count, tagify_count_gated, 'schedule bypass Marketplace gate')
    text = replace_function(text, 'Get-DiscoveredActionableAutoUpdateCount', actionable)

    selftest = function_block(text, 'Invoke-AddonSelfTest')
    lifecycle_test = '    try { Invoke-LifecycleSettingsCoreSelfTest } catch { $errors.Add("Settings-preserving lifecycle core self-test failed: $($_.Exception.Message)") }'
    integration_test = lifecycle_test + '\n    try { Invoke-MarketplaceIntegratedEngineSelfTest } catch { $errors.Add("Marketplace integrated engine self-test failed: $($_.Exception.Message)") }'
    selftest = replace_once(selftest, lifecycle_test, integration_test, 'integrated self-test hook')
    text = replace_function(text, 'Invoke-AddonSelfTest', selftest)

    return bom + text.encode('utf-8')


def validate_candidate(main: bytes, addon: bytes, collector: bytes, reader: bytes) -> dict:
    if (len(main), sha(main)) != TAGIFY_MAIN:
        raise RuntimeError('integrated candidate changed validated Tagify Spotify Control bytes')
    text = addon.decode('utf-8-sig').replace('\r\n', '\n')
    registry = function_block(text, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED):
        raise RuntimeError(f'integrated auto authority drift: {auto}')

    required = (
        'function Update-MarketplaceIdentityLifecycleLedger',
        'function Invoke-MarketplaceRecordDiscovery',
        'function Test-MarketplaceSourceUserIntentAllowsMutation',
        'function Invoke-MarketplaceIntegratedEngineSelfTest',
        'marketplace_identity_required=$true',
        'marketplace_identity_evidence_conclusive',
        'marketplace_identity_fingerprint',
        "Reason='marketplace-evidence-inconclusive'",
        "Reason='marketplace-evidence-stale'",
        "Reason='marketplace-source-ambiguous'",
        "Reason='marketplace-ledger-authority-drift'",
        "managed_by','marketplace-record-v1'",
        "mutation_mode','deny'",
        'New-RequiredSpotifyPersistenceBackup',
        'Restore-SpotifyPersistenceBackup',
        'persistence_before_fingerprint',
        "protected_state_policy='must-remain-byte-identical-through-apply'",
    )
    for marker in required:
        if marker not in text:
            raise RuntimeError(f'missing integrated safety marker: {marker}')

    for marker in (
        "name='splitify'", "mutation_mode='deny'", "name='star-ratings'", 'playlist-backed-ratings-preserve',
        "name='sc-cover-ambience.js'", 'never-disable-or-optimize', "name='tagify'", "handler='tagify'",
        "install_mode='installed-only'", 'preserve-ratings-tags-notes-and-browser-storage'
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected registry policy missing: {marker}')

    auth = function_block(text, 'Get-AddonMutationAuthorization')
    if 'Test-MarketplaceSourceUserIntentAllowsMutation' not in auth:
        raise RuntimeError('Marketplace user-intent gate is not inside mutation authorization')
    schedule = function_block(text, 'Get-DiscoveredActionableAutoUpdateCount')
    if 'Get-AddonSourceAdapterPlan -Item $item' not in schedule:
        raise RuntimeError('schedule-bypass path is not gated by current mutation authorization')
    inventory = function_block(text, 'Get-AddonInventory')
    if 'Invoke-MarketplaceRecordDiscovery' not in inventory or 'marketplace_lifecycle = $marketplaceLifecycle' not in inventory:
        raise RuntimeError('inventory does not refresh and publish current Marketplace evidence')

    if git_blob(COLLECTOR_HEAD, COLLECTOR_PATH) != COLLECTOR_BLOB or sha(collector) != sha(git_bytes(COLLECTOR_HEAD, COLLECTOR_PATH)):
        raise RuntimeError('collector bytes drifted from validated source')
    if git_blob(READER_HEAD, READER_PATH) != READER_BLOB or sha(reader) != sha(git_bytes(READER_HEAD, READER_PATH)):
        raise RuntimeError('LevelDB reader bytes drifted from validated source')

    return {
        'auto_authority': AUTHORIZED,
        'generic_marketplace_mutation_authority_expanded': False,
        'marketplace_gate_is_user_intent_only': True,
        'tagify_requires_current_marketplace_evidence': True,
        'production_surface_changed': False,
    }


def build() -> None:
    verify_pins()
    main, tagify_addon = reproduce_tagify_candidate()
    settings_addon = apply_validated_settings_core(tagify_addon)
    integrated_addon = integrate_marketplace_engine(settings_addon)
    collector = git_bytes(COLLECTOR_HEAD, COLLECTOR_PATH)
    reader = git_bytes(READER_HEAD, READER_PATH)
    validation = validate_candidate(main, integrated_addon, collector, reader)

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(integrated_addon)
    (OUT / 'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT / 'LevelDbReadOnly.cs').write_bytes(reader)

    report = {
        'schema': 1,
        'production_base': PRODUCTION_BASE,
        'candidate_version': '0.6.29-validation-integrated-marketplace-v0.2.0',
        'candidate_main': {'size': len(main), 'sha256': sha(main)},
        'candidate_addon': {'size': len(integrated_addon), 'sha256': sha(integrated_addon)},
        'collector': {'size': len(collector), 'sha256': sha(collector), 'head': COLLECTOR_HEAD, 'path': COLLECTOR_PATH, 'blob': COLLECTOR_BLOB},
        'leveldb_reader': {'size': len(reader), 'sha256': sha(reader), 'head': READER_HEAD, 'path': READER_PATH, 'blob': READER_BLOB},
        'marketplace_upstream_commit': MARKETPLACE_UPSTREAM_COMMIT,
        'validated_inputs': {
            'tagify': {'head': TAGIFY_HEAD, 'path': TAGIFY_PATH, 'blob': TAGIFY_BLOB, 'main_sha256': TAGIFY_MAIN[1], 'addon_sha256': TAGIFY_ADDON[1]},
            'settings_lifecycle': {'head': SETTINGS_HEAD, 'builder_blob': SETTINGS_BUILDER_BLOB, 'core_blob': SETTINGS_CORE_BLOB},
            'identity_ledger': {'head': LEDGER_HEAD, 'path': LEDGER_PATH, 'blob': LEDGER_BLOB},
        },
        'features': [
            'current-read-only-marketplace-discovery-every-inventory-cycle',
            'marketplace-identity-user-removal-tombstone-and-reinstall-ledger',
            'current-report-fingerprint-bound-user-intent-gate',
            'tagify-installed-only-state-preserving-update-requires-current-marketplace-evidence',
            'generic-marketplace-records-remain-mutation-denied',
            'dynamic-local-spicetify-lifecycle-observation',
            'exact-protected-persistence-backup-before-managed-mutation',
            'commit-persistence-drift-fail-closed',
            'rollback-code-plus-persistence-exact-restore',
        ],
        **validation,
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('MARKETPLACE_INTEGRATED_ENGINE_BUILD_PASS', len(main), sha(main), len(integrated_addon), sha(integrated_addon), len(collector), sha(collector), len(reader), sha(reader))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    if not args.build:
        parser.error('use --build')
    build()


if __name__ == '__main__':
    main()
