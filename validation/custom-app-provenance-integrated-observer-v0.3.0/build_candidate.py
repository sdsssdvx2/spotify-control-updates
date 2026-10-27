from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_BASE = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
SOURCE_TOPOLOGY_HEAD = '4b7ef73fe416afdfb501173f145994b3ed817e42'
SOURCE_TOPOLOGY_PATH = 'validation/marketplace-source-topology-v0.1.0/build_candidate.py'
SOURCE_TOPOLOGY_BLOB = '1e32dd57c95f718f2aeaae6149da36762ca7f6fd'
PROVENANCE_HEAD = 'b339f2b79a267c13cf3c5974aea2fff3786d3093'
PROVENANCE_PATH = 'validation/custom-app-provenance-enrollment-v0.1.0/custom-app-provenance.ps1'
PROVENANCE_BLOB = '4f0831fa2e5dc23c9a4ec98b6c7a9afbb3c9af55'
NATIVE_REFRESH_HEAD = '62cc0803411ccd132e3bad3b6338b2ef783e0f4c'
NATIVE_REFRESH_PATH = 'validation/marketplace-native-refresh-contract-v0.1.0/marketplace-native-refresh-contract.ps1'
NATIVE_REFRESH_BLOB = 'bd895ebcc11d9fb2f1c7857ee861e5b9e2c2cc3c'
EXPECTED_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
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
    a, b = function_bounds(text, name)
    return text[a:b].rstrip()


def replace_function(text: str, name: str, replacement: str) -> str:
    a, b = function_bounds(text, name)
    return text[:a] + replacement.rstrip() + '\n\n' + text[b:].lstrip('\n')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label} anchor count drift: {count}')
    return text.replace(old, new, 1)


def build_source_topology() -> tuple[bytes, bytes, bytes, bytes]:
    require_blob(SOURCE_TOPOLOGY_HEAD, SOURCE_TOPOLOGY_PATH, SOURCE_TOPOLOGY_BLOB, 'source-topology builder')
    source = git_bytes(SOURCE_TOPOLOGY_HEAD, SOURCE_TOPOLOGY_PATH)
    fake = HERE / '_pinned_source_topology_builder.py'
    ns = {'__file__': str(fake), '__name__': 'pinned_source_topology_builder'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()
    main = (OUT / 'spotify-control.ps1').read_bytes()
    addon = (OUT / 'addon-manager.ps1').read_bytes()
    collector = (OUT / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (OUT / 'LevelDbReadOnly.cs').read_bytes()
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError(f'source-topology main drift: {len(main)} {sha(main)}')
    return main, addon, collector, reader


INTEGRATION_SELFTEST = r'''function Invoke-CustomAppProvenanceIntegratedSelfTest {
    $state=[pscustomobject]@{}
    $obs=[pscustomobject]@{kind='custom-app';name='future-app';ownership='local-spicetify-observed';source_identity=$null;locations=@('C:\\fixture\\CustomApps\\future-app');ambiguous=$false;safe_local_identity=$true}
    [void](Update-AddonLifecycleObservations -State $state -Observations @($obs) -ObservedAt '2026-10-28T02:00:00+00:00')
    $proven=[pscustomobject]@{schema=1;name='future-app';path='C:\\fixture\\CustomApps\\future-app';status='proven-local-git-origin';source_candidate='example/future-app';source_proven=$true;requires_reenrollment=$false;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint='fixture-a';git=$null;package=$null}
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $proven -ObservedAt '2026-10-28T02:00:00+00:00'
    if([string]$row.source_identity -cne 'example/future-app' -or [string]$row.last_proven_source -cne 'example/future-app'){throw 'Integrated provenance self-test: strong source was not enrolled.'}
    if(Test-CustomAppProvenanceMutationAuthority -Row $row){throw 'Integrated provenance self-test: enrollment unexpectedly granted mutation authority.'}

    [void](Update-AddonLifecycleObservations -State $state -Observations @() -ObservedAt '2026-10-28T02:01:00+00:00')
    $absent=[pscustomobject]@{schema=1;name='future-app';path=$null;status='lifecycle-absent';source_candidate=$null;source_proven=$false;requires_reenrollment=$false;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint='fixture-b';git=$null;package=$null}
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $absent -ObservedAt '2026-10-28T02:01:00+00:00'
    if($null -ne $row.source_identity -or [string]$row.source_status -cne 'user-removed' -or [string]$row.last_proven_source -cne 'example/future-app'){throw 'Integrated provenance self-test: deletion did not clear active source while preserving history.'}

    [void](Update-AddonLifecycleObservations -State $state -Observations @($obs) -ObservedAt '2026-10-28T02:02:00+00:00')
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $proven -ObservedAt '2026-10-28T02:02:00+00:00'
    if([string]$row.source_identity -cne 'example/future-app' -or [bool]$row.requires_reenrollment){throw 'Integrated provenance self-test: same-source reinstall was not restored safely.'}

    $swap=[pscustomobject]@{schema=1;name='future-app';path='C:\\fixture\\CustomApps\\future-app';status='proven-local-git-origin';source_candidate='example/other-app';source_proven=$true;requires_reenrollment=$false;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint='fixture-c';git=$null;package=$null}
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $swap -ObservedAt '2026-10-28T02:03:00+00:00'
    if($null -ne $row.source_identity -or -not [bool]$row.source_changed -or -not [bool]$row.requires_reenrollment -or [string]$row.source_status -cne 'source-change-blocked'){throw 'Integrated provenance self-test: source swap did not fail closed.'}
    if(Test-CustomAppProvenanceMutationAuthority -Row $row){throw 'Integrated provenance self-test: source swap granted mutation authority.'}
    Write-Host 'CUSTOM_APP_PROVENANCE_INTEGRATED_SELFTEST_PASS'
}'''


def integrate_observers(addon: bytes) -> bytes:
    require_blob(PROVENANCE_HEAD, PROVENANCE_PATH, PROVENANCE_BLOB, 'custom-app provenance core')
    require_blob(NATIVE_REFRESH_HEAD, NATIVE_REFRESH_PATH, NATIVE_REFRESH_BLOB, 'Marketplace native-refresh core')
    provenance = git_bytes(PROVENANCE_HEAD, PROVENANCE_PATH).decode('utf-8-sig').strip()
    native = git_bytes(NATIVE_REFRESH_HEAD, NATIVE_REFRESH_PATH).decode('utf-8-sig').strip()

    bom = b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    text = addon[len(bom):].decode('utf-8')
    anchor = 'function Test-Due {'
    if text.count(anchor) != 1:
        raise RuntimeError('observer insertion anchor drift')
    text = text.replace(anchor, provenance + '\n\n' + native + '\n\n' + INTEGRATION_SELFTEST + '\n\n' + anchor, 1)

    inventory = function_block(text, 'Get-AddonInventory')
    lifecycle_anchor = '''    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now
    Save-AddonState $state'''
    lifecycle_replacement = '''    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now

    # Provenance is observer-only. Process every tracked custom-app lifecycle row so a user
    # deletion clears active source trust in the same inventory cycle instead of waiting for
    # the app to reappear. Strong source evidence still never grants mutation authority.
    $customAppProvenanceRows=New-Object System.Collections.Generic.List[object]
    foreach($lifecycleProp in @($state.lifecycle.PSObject.Properties)) {
        $lifecycleRow=$lifecycleProp.Value
        if($null -eq $lifecycleRow -or [string]$lifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or [string]$lifecycleRow.kind -cne 'custom-app') { continue }
        $evidence=$null
        if([bool]$lifecycleRow.present -and -not [bool]$lifecycleRow.user_removed -and -not [bool]$lifecycleRow.ambiguous -and [bool]$lifecycleRow.safe_local_identity -and @($lifecycleRow.locations).Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$lifecycleRow.locations[0])) {
            try { $evidence=Get-CustomAppLocalProvenanceEvidence -Name ([string]$lifecycleRow.name) -AppPath ([string]$lifecycleRow.locations[0]) }
            catch {
                $evidence=[pscustomobject]@{schema=1;name=[string]$lifecycleRow.name;path=[string]$lifecycleRow.locations[0];status='provenance-read-error';source_candidate=$null;source_proven=$false;requires_reenrollment=$true;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=(Get-ProvenanceStringSha256Lower ('read-error|'+[string]$lifecycleRow.name));git=$null;package=$null}
            }
        } else {
            $status=$(if(-not [bool]$lifecycleRow.present -or [bool]$lifecycleRow.user_removed){'lifecycle-absent'}else{'unsafe-local-lifecycle'})
            $evidence=[pscustomobject]@{schema=1;name=[string]$lifecycleRow.name;path=$null;status=$status;source_candidate=$null;source_proven=$false;requires_reenrollment=($status -ceq 'unsafe-local-lifecycle');mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=(Get-ProvenanceStringSha256Lower ($status+'|'+([string]$lifecycleRow.name).ToLowerInvariant()));git=$null;package=$null}
        }
        $provRow=Update-CustomAppProvenanceEnrollment -State $state -Evidence $evidence -ObservedAt $now
        if(Test-CustomAppProvenanceMutationAuthority -Row $provRow){throw "Custom App provenance authority drift: $([string]$provRow.key)"}
        $customAppProvenanceRows.Add($provRow)
    }
    Save-AddonState $state'''
    inventory = replace_once(inventory, lifecycle_anchor, lifecycle_replacement, 'custom-app provenance inventory cycle')

    marketplace_anchor = '''    $marketplaceReport = Invoke-MarketplaceRecordDiscovery
    $marketplaceLifecycle = Update-MarketplaceIdentityLifecycleFromReport -State $state -MarketplaceReport $marketplaceReport -ObservedAt $now
    if ([bool]$marketplaceLifecycle.conclusive) { Save-AddonState $state }'''
    marketplace_replacement = marketplace_anchor + '''
    $marketplaceNativeRefresh=New-Object System.Collections.Generic.List[object]
    $marketplaceRecords=@()
    if($null -ne $marketplaceReport -and $marketplaceReport.PSObject.Properties['records']){$marketplaceRecords=@($marketplaceReport.records)}
    foreach($record in $marketplaceRecords){
        $decision=Resolve-MarketplaceNativeRefreshContract -Record $record
        if([bool]$decision.addon_manager_direct_mutation_allowed){throw "Marketplace native-refresh authority drift: $([string]$decision.kind)"}
        $marketplaceNativeRefresh.Add($decision)
    }'''
    inventory = replace_once(inventory, marketplace_anchor, marketplace_replacement, 'Marketplace native-refresh observer')

    report_anchor = '        marketplace_lifecycle = $marketplaceLifecycle\n'
    report_replacement = report_anchor + '''        marketplace_native_refresh = @($marketplaceNativeRefresh.ToArray())
        custom_app_provenance = [pscustomobject]@{ schema=1; row_count=$customAppProvenanceRows.Count; mutation_authority_count=@($customAppProvenanceRows.ToArray()|Where-Object{Test-CustomAppProvenanceMutationAuthority -Row $_}).Count; rows=$customAppProvenanceRows.ToArray() }
'''
    inventory = replace_once(inventory, report_anchor, report_replacement, 'observer report publication')
    text = replace_function(text, 'Get-AddonInventory', inventory)

    selftest = function_block(text, 'Invoke-AddonSelfTest')
    topology_hook = '    try { Invoke-SourceTopologySelfTest } catch { $errors.Add("Source topology self-test failed: $($_.Exception.Message)") }'
    observer_hooks = topology_hook + '\n    try { Invoke-CustomAppProvenanceIntegratedSelfTest } catch { $errors.Add("Custom App provenance integrated self-test failed: $($_.Exception.Message)") }\n    try { Invoke-MarketplaceNativeRefreshContractSelfTest } catch { $errors.Add("Marketplace native refresh contract self-test failed: $($_.Exception.Message)") }'
    selftest = replace_once(selftest, topology_hook, observer_hooks, 'observer self-test hooks')
    text = replace_function(text, 'Invoke-AddonSelfTest', selftest)

    return bom + text.encode('utf-8')


def validate(main: bytes, addon: bytes, collector: bytes, reader: bytes) -> dict:
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError('observer candidate changed validated Spotify Control bytes')
    text = addon.decode('utf-8-sig').replace('\r\n', '\n')
    registry = function_block(text, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED):
        raise RuntimeError(f'auto authority drift: {auto}')

    required = (
        'function Get-CustomAppLocalProvenanceEvidence',
        'function Update-CustomAppProvenanceEnrollment',
        'function Test-CustomAppProvenanceMutationAuthority',
        'function Resolve-MarketplaceNativeRefreshContract',
        'function Invoke-CustomAppProvenanceIntegratedSelfTest',
        'function Invoke-MarketplaceNativeRefreshContractSelfTest',
        '$customAppProvenanceRows=New-Object System.Collections.Generic.List[object]',
        'foreach($lifecycleProp in @($state.lifecycle.PSObject.Properties))',
        "status='provenance-read-error'",
        'Test-CustomAppProvenanceMutationAuthority -Row $provRow',
        '$marketplaceNativeRefresh=New-Object System.Collections.Generic.List[object]',
        'Resolve-MarketplaceNativeRefreshContract -Record $record',
        'marketplace_native_refresh = @($marketplaceNativeRefresh.ToArray())',
        'custom_app_provenance = [pscustomobject]@{',
        "managed_by='custom-app-provenance-v1'",
        "mutation_mode='deny'",
        'auto_update_authorized=$false',
        'auto_install_authorized=$false',
        'New-RequiredSpotifyPersistenceBackup',
        'Restore-SpotifyPersistenceBackup',
        "protected_state_policy='must-remain-byte-identical-through-apply'",
    )
    for marker in required:
        if marker not in text:
            raise RuntimeError(f'missing observer safety marker: {marker}')

    inventory = function_block(text, 'Get-AddonInventory')
    if inventory.find('Update-AddonLifecycleObservations') > inventory.find('Update-CustomAppProvenanceEnrollment'):
        raise RuntimeError('provenance enrollment occurs before lifecycle refresh')
    if 'Save-AddonState $state' not in inventory:
        raise RuntimeError('observer candidate does not persist lifecycle/provenance state')
    if 'addon_manager_direct_mutation_allowed' not in inventory:
        raise RuntimeError('native-refresh direct-mutation guard missing from inventory')

    for marker in (
        "name='splitify'", "name='star-ratings'", 'playlist-backed-ratings-preserve',
        "name='sc-cover-ambience.js'", 'never-disable-or-optimize', "name='tagify'",
        "source='alexk218/tagify'", "install_mode='installed-only'", 'preserve-ratings-tags-notes-and-browser-storage'
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected registry policy missing: {marker}')

    return {
        'auto_authority': AUTHORIZED,
        'custom_app_provenance_integrated': True,
        'custom_app_provenance_mutation_authority_expanded': False,
        'marketplace_native_refresh_contract_integrated': True,
        'marketplace_direct_mutation_authority_expanded': False,
        'deletion_tombstone_same_cycle_provenance_clear': True,
        'source_change_requires_reenrollment': True,
        'production_surface_changed': False,
        'collector_sha256': sha(collector),
        'reader_sha256': sha(reader),
    }


def build() -> None:
    main, source_topology_addon, collector, reader = build_source_topology()
    candidate = integrate_observers(source_topology_addon)
    result = validate(main, candidate, collector, reader)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate)
    (OUT / 'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT / 'LevelDbReadOnly.cs').write_bytes(reader)
    report = {
        'schema': 1,
        'production_base': PRODUCTION_BASE,
        'candidate_version': '0.6.29-validation-provenance-observer-v0.3.0',
        'validated_source_topology': {'head': SOURCE_TOPOLOGY_HEAD, 'path': SOURCE_TOPOLOGY_PATH, 'blob': SOURCE_TOPOLOGY_BLOB},
        'validated_custom_app_provenance': {'head': PROVENANCE_HEAD, 'path': PROVENANCE_PATH, 'blob': PROVENANCE_BLOB},
        'validated_marketplace_native_refresh': {'head': NATIVE_REFRESH_HEAD, 'path': NATIVE_REFRESH_PATH, 'blob': NATIVE_REFRESH_BLOB},
        'candidate_main': {'size': len(main), 'sha256': sha(main)},
        'candidate_addon': {'size': len(candidate), 'sha256': sha(candidate)},
        'features': [
            'custom-app-provenance-enrollment-runs-after-current-local-lifecycle-refresh',
            'tracked-custom-app-deletion-clears-active-provenance-in-same-inventory-cycle',
            'source-swap-remains-blocked-and-requires-reenrollment',
            'provenance-never-grants-generic-update-or-install-authority',
            'marketplace-native-refresh-contract-published-as-observer-only-report-data',
            'marketplace-extension-theme-partial-native-runtime-refresh-boundary-retained',
            'marketplace-snippet-no-remote-auto-refresh-boundary-retained',
            'existing-settings-persistence-and-protected-addon-policies-retained',
        ],
        **result,
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('CUSTOM_APP_PROVENANCE_OBSERVER_BUILD_PASS', len(main), sha(main), len(candidate), sha(candidate))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--build', action='store_true')
    args = p.parse_args()
    if not args.build:
        p.error('use --build')
    build()


if __name__ == '__main__':
    main()
