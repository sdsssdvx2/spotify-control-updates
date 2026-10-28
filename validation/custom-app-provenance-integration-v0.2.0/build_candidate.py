from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_BASE = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
SOURCE_TOPOLOGY_HEAD = '4b7ef73fe416afdfb501173f145994b3ed817e42'
SOURCE_TOPOLOGY_BUILDER = 'validation/marketplace-source-topology-v0.1.0/build_candidate.py'
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


def bounds(text: str, name: str) -> tuple[int, int]:
    marker = f'function {name} {{'
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f'missing function {name}')
    end = text.find('\nfunction ', start + len(marker))
    if end < 0:
        end = len(text)
    return start, end


def block(text: str, name: str) -> str:
    a, b = bounds(text, name)
    return text[a:b].rstrip()


def replace_func(text: str, name: str, replacement: str) -> str:
    a, b = bounds(text, name)
    return text[:a] + replacement.rstrip() + '\n\n' + text[b:].lstrip('\n')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label} anchor count drift: {count}')
    return text.replace(old, new, 1)


def build_parent() -> tuple[bytes, bytes, bytes, bytes]:
    actual = git_blob(SOURCE_TOPOLOGY_HEAD, SOURCE_TOPOLOGY_BUILDER)
    if actual != SOURCE_TOPOLOGY_BLOB:
        raise RuntimeError(f'source-topology builder drift: {actual} != {SOURCE_TOPOLOGY_BLOB}')
    source = git_bytes(SOURCE_TOPOLOGY_HEAD, SOURCE_TOPOLOGY_BUILDER)
    fake = ROOT / 'validation/marketplace-source-topology-v0.1.0/_provenance_integration_pinned_builder.py'
    namespace = {'__file__': str(fake), '__name__': 'pinned_source_topology_builder'}
    exec(compile(source, str(fake), 'exec'), namespace)
    namespace['build']()
    parent_out = ROOT / 'validation/marketplace-source-topology-v0.1.0/out/bin'
    main = (parent_out / 'spotify-control.ps1').read_bytes()
    addon = (parent_out / 'addon-manager.ps1').read_bytes()
    collector = (parent_out / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (parent_out / 'LevelDbReadOnly.cs').read_bytes()
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError(f'parent main drift: {len(main)} {sha(main)}')
    return main, addon, collector, reader


def load_pinned_ps1(commit: str, path: str, blob: str, label: str) -> str:
    actual = git_blob(commit, path)
    if actual != blob:
        raise RuntimeError(f'{label} blob drift: {actual} != {blob}')
    raw = git_bytes(commit, path)
    return raw.decode('utf-8-sig').replace('\r\n', '\n').rstrip()


INTEGRATION_HELPERS = r'''function New-CustomAppProvenanceSyntheticEvidence {
    param([string]$Name,[string]$Status,[bool]$RequiresReenrollment=$true,[AllowNull()][string]$SourceCandidate=$null)
    if([string]::IsNullOrWhiteSpace($Name)){throw 'Synthetic provenance evidence name cannot be empty.'}
    if([string]::IsNullOrWhiteSpace($Status)){$Status='synthetic-inconclusive'}
    $canon=('synthetic|'+$Name.Trim().ToLowerInvariant()+'|'+$Status+'|'+$(if($SourceCandidate){$SourceCandidate}else{''}))
    return [pscustomobject]@{
        schema=$CustomAppProvenanceSchema;name=$Name;path=$null;status=$Status;source_candidate=$SourceCandidate;
        source_proven=$false;requires_reenrollment=$RequiresReenrollment;mutation_authorized=$false;
        auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=(Get-ProvenanceStringSha256Lower $canon);
        git=$null;package=$null
    }
}

function Get-CustomAppProvenanceEvidenceForLifecycleRow {
    param([string]$Name,$LifecycleRow)
    if($null -eq $LifecycleRow){return New-CustomAppProvenanceSyntheticEvidence -Name $Name -Status 'lifecycle-row-null'}
    if([string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1'){
        return New-CustomAppProvenanceSyntheticEvidence -Name $Name -Status 'lifecycle-owner-mismatch'
    }
    $locations=@($LifecycleRow.locations)
    if($locations.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$locations[0])){
        return New-CustomAppProvenanceSyntheticEvidence -Name $Name -Status 'lifecycle-location-inconclusive'
    }
    try {
        return Get-CustomAppLocalProvenanceEvidence -Name $Name -AppPath ([string]$locations[0])
    } catch {
        return New-CustomAppProvenanceSyntheticEvidence -Name $Name -Status 'provenance-evidence-collection-failed'
    }
}

function Update-CustomAppProvenanceFromCurrentLifecycle {
    param($State,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    if($null -eq $State){throw 'Provenance integration state cannot be null.'}
    $root=Ensure-CustomAppProvenanceLedgerRoot -State $State
    $seen=@{};$observed=0;$updated=0;$sourceChanged=0;$reenrollmentRequired=0

    if($State.PSObject.Properties['lifecycle'] -and $null -ne $State.lifecycle){
        foreach($prop in @($State.lifecycle.PSObject.Properties)){
            $key=[string]$prop.Name
            if(-not $key.StartsWith('custom-app:',[StringComparison]::OrdinalIgnoreCase)){continue}
            $row=$prop.Value
            $name=$(if($null -ne $row -and $row.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$row.name)){[string]$row.name}else{$key.Substring('custom-app:'.Length)})
            $seen[$key.ToLowerInvariant()]=$true
            $evidence=Get-CustomAppProvenanceEvidenceForLifecycleRow -Name $name -LifecycleRow $row
            if($null -ne $evidence){$observed++}
            $result=Update-CustomAppProvenanceEnrollment -State $State -Evidence $evidence -ObservedAt $ObservedAt
            if($null -eq $result){throw "Provenance ledger update returned null: $key"}
            if(Test-CustomAppProvenanceMutationAuthority -Row $result){throw "Provenance ledger authority drift: $key"}
            if([bool]$result.source_changed){$sourceChanged++}
            if([bool]$result.requires_reenrollment){$reenrollmentRequired++}
            $updated++
        }
    }

    # Reconcile any historical provenance row whose lifecycle row disappeared/corrupted.
    foreach($prop in @($root.PSObject.Properties)){
        $key=[string]$prop.Name
        if(-not $key.StartsWith('custom-app:',[StringComparison]::OrdinalIgnoreCase) -or $seen.ContainsKey($key.ToLowerInvariant())){continue}
        $existing=$prop.Value
        $name=$(if($null -ne $existing -and $existing.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$existing.name)){[string]$existing.name}else{$key.Substring('custom-app:'.Length)})
        $evidence=New-CustomAppProvenanceSyntheticEvidence -Name $name -Status 'lifecycle-missing'
        $result=Update-CustomAppProvenanceEnrollment -State $State -Evidence $evidence -ObservedAt $ObservedAt
        if(Test-CustomAppProvenanceMutationAuthority -Row $result){throw "Orphan provenance ledger authority drift: $key"}
        $updated++;$reenrollmentRequired++
    }

    foreach($prop in @($root.PSObject.Properties)){
        if(Test-CustomAppProvenanceMutationAuthority -Row $prop.Value){throw "Provenance ledger contains mutation authority: $($prop.Name)"}
    }
    return [pscustomobject]@{schema=1;observed_at=$ObservedAt;observed=$observed;updated=$updated;source_changed=$sourceChanged;reenrollment_required=$reenrollmentRequired;entries=@($root.PSObject.Properties).Count;mutation_authority_granted=$false}
}

function Invoke-ProvenanceIntegrationSelfTest {
    $state=Normalize-AddonStateObject ([pscustomobject]@{})
    $missing=Join-Path $env:TEMP ('spotify-control-provenance-selftest-'+[guid]::NewGuid().ToString('N'))
    $obs=[pscustomobject]@{kind='custom-app';name='fixture-app';ownership='local-spicetify-observed';source_identity=$null;locations=@($missing);ambiguous=$false;safe_local_identity=$true}
    [void](Update-AddonLifecycleObservations -State $state -Observations @($obs) -ObservedAt '2026-10-28T02:00:00+00:00')
    $summary=Update-CustomAppProvenanceFromCurrentLifecycle -State $state -ObservedAt '2026-10-28T02:00:00+00:00'
    if([bool]$summary.mutation_authority_granted -or [int]$summary.entries -ne 1){throw 'Provenance integration self-test: observer summary drift.'}
    $row=$state.custom_app_provenance.PSObject.Properties['custom-app:fixture-app'].Value
    if($null -eq $row -or [string]$row.source_status -cne 'absent' -or (Test-CustomAppProvenanceMutationAuthority -Row $row)){throw 'Provenance integration self-test: absent local app did not remain deny-by-default.'}

    $strong=[pscustomobject]@{schema=1;name='fixture-app';path=$missing;status='proven-local-git-origin';source_candidate='example/app';source_proven=$true;requires_reenrollment=$false;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=(Get-ProvenanceStringSha256Lower 'fixture-strong');git=$null;package=$null}
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $strong -ObservedAt '2026-10-28T02:01:00+00:00'
    if([string]$row.source_identity -cne 'example/app' -or (Test-CustomAppProvenanceMutationAuthority -Row $row)){throw 'Provenance integration self-test: strong identity enrollment drift.'}
    $life=$state.lifecycle.PSObject.Properties['custom-app:fixture-app'].Value;$life.present=$false;$life.user_removed=$true
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $strong -ObservedAt '2026-10-28T02:02:00+00:00'
    if($null -ne $row.source_identity -or [string]$row.last_proven_source -cne 'example/app' -or [string]$row.source_status -cne 'user-removed'){throw 'Provenance integration self-test: user deletion did not clear active trust while preserving history.'}
    $life.present=$true;$life.user_removed=$false
    [void](Update-CustomAppProvenanceEnrollment -State $state -Evidence $strong -ObservedAt '2026-10-28T02:03:00+00:00')
    $swapped=[pscustomobject]@{schema=1;name='fixture-app';path=$missing;status='proven-local-git-origin';source_candidate='other/fork';source_proven=$true;requires_reenrollment=$false;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=(Get-ProvenanceStringSha256Lower 'fixture-swap');git=$null;package=$null}
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $swapped -ObservedAt '2026-10-28T02:04:00+00:00'
    if([string]$row.source_status -cne 'source-change-blocked' -or $null -ne $row.source_identity -or -not [bool]$row.requires_reenrollment -or (Test-CustomAppProvenanceMutationAuthority -Row $row)){throw 'Provenance integration self-test: source change did not fail closed.'}

    $normalized=Normalize-AddonStateObject $state
    if(-not $normalized.PSObject.Properties['custom_app_provenance'] -or -not $normalized.custom_app_provenance.PSObject.Properties['custom-app:fixture-app']){throw 'Provenance integration self-test: state normalization dropped provenance ledger.'}

    $extension=Resolve-MarketplaceNativeRefreshContract ([pscustomobject]@{kind='extension';source_kind='github-repository-key';ambiguous=$false;mutation_authorized=$false})
    if(-not $extension.conclusive -or -not $extension.automatic_runtime_content_refresh -or $extension.full_installed_record_refresh_guaranteed -or $extension.addon_manager_direct_mutation_allowed){throw 'Provenance integration self-test: extension native-refresh boundary drift.'}
    $snippet=Resolve-MarketplaceNativeRefreshContract ([pscustomobject]@{kind='snippet';source_kind='snippet-key';ambiguous=$false;mutation_authorized=$false})
    if(-not $snippet.conclusive -or $snippet.automatic_runtime_content_refresh -or $snippet.full_installed_record_refresh_guaranteed -or $snippet.addon_manager_direct_mutation_allowed){throw 'Provenance integration self-test: snippet native-refresh boundary drift.'}
    Write-AddonLog 'Provenance integration self-test passed: lifecycle enrollment, deletion, source-swap, state retention, and native-refresh boundaries remain fail closed.'
}'''


def patch(addon: bytes, provenance: str, native_refresh: str) -> bytes:
    bom = b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    text = addon[len(bom):].decode('utf-8')
    insertion = provenance + '\n\n' + native_refresh + '\n\n' + INTEGRATION_HELPERS
    anchor = 'function Get-AddonInventory {'
    text = replace_once(text, anchor, insertion + '\n\n' + anchor, 'integration helper insertion')

    inv = block(text, 'Get-AddonInventory')
    lifecycle = '    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now\n    Save-AddonState $state'
    replacement = "    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now\n    $provenanceSummary=Update-CustomAppProvenanceFromCurrentLifecycle -State $state -ObservedAt $now\n    Save-AddonState $state"
    inv = replace_once(inv, lifecycle, replacement, 'inventory provenance cycle hook')
    text = replace_func(text, 'Get-AddonInventory', inv)

    selftest = block(text, 'Invoke-AddonSelfTest')
    marker = '    try { Invoke-SourceTopologySelfTest } catch { $errors.Add("Source topology self-test failed: $($_.Exception.Message)") }'
    hook = marker + '\n    try { Invoke-MarketplaceNativeRefreshContractSelfTest } catch { $errors.Add("Marketplace native refresh self-test failed: $($_.Exception.Message)") }\n    try { Invoke-ProvenanceIntegrationSelfTest } catch { $errors.Add("Provenance integration self-test failed: $($_.Exception.Message)") }'
    selftest = replace_once(selftest, marker, hook, 'selftest integration hook')
    text = replace_func(text, 'Invoke-AddonSelfTest', selftest)
    return bom + text.encode('utf-8')


def validate(main: bytes, addon: bytes, collector: bytes, reader: bytes, provenance: str, native_refresh: str) -> dict:
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError('integration changed validated Spotify Control bytes')
    text = addon.decode('utf-8-sig').replace('\r\n', '\n')
    required = (
        '$CustomAppProvenanceSchema = 1',
        'function Get-CustomAppLocalProvenanceEvidence',
        'function Update-CustomAppProvenanceEnrollment',
        'function Test-CustomAppProvenanceMutationAuthority',
        'function Update-CustomAppProvenanceFromCurrentLifecycle',
        'function Resolve-MarketplaceNativeRefreshContract',
        'function Invoke-ProvenanceIntegrationSelfTest',
        'custom_app_provenance',
        "managed_by='custom-app-provenance-v1'",
        "mutation_mode='deny'",
        'auto_update_authorized=$false',
        'auto_install_authorized=$false',
        'New-RequiredSpotifyPersistenceBackup',
        'Restore-SpotifyPersistenceBackup',
        "protected_state_policy='must-remain-byte-identical-through-apply'",
    )
    for marker in required:
        if marker.lower() not in text.lower():
            raise RuntimeError(f'missing integration safety marker: {marker}')

    registry = block(text, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED):
        raise RuntimeError(f'integrated auto authority drift: {auto}')
    for marker in (
        "name='splitify'", "name='star-ratings'", 'playlist-backed-ratings-preserve',
        "name='sc-cover-ambience.js'", 'never-disable-or-optimize', "name='tagify'",
        "source='alexk218/tagify'", "install_mode='installed-only'", 'preserve-ratings-tags-notes-and-browser-storage'
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected registry policy missing: {marker}')

    inventory = block(text, 'Get-AddonInventory')
    if 'Update-CustomAppProvenanceFromCurrentLifecycle -State $state -ObservedAt $now' not in inventory:
        raise RuntimeError('inventory cycle does not update provenance from current lifecycle')
    if inventory.index('Update-CustomAppProvenanceFromCurrentLifecycle') > inventory.index('Save-AddonState $state'):
        raise RuntimeError('provenance is not updated before state persistence')

    if 'auto_update_authorized=$true' in provenance.lower() or 'auto_install_authorized=$true' in provenance.lower():
        raise RuntimeError('pinned provenance core unexpectedly grants update/install authority')
    if 'addon_manager_direct_mutation_allowed = $true' in native_refresh.lower():
        raise RuntimeError('pinned native-refresh contract unexpectedly grants direct mutation')

    return {
        'auto_authority': auto,
        'generic_custom_app_mutation_authority_expanded': False,
        'generic_marketplace_mutation_authority_expanded': False,
        'custom_app_provenance_state_root': 'custom_app_provenance',
        'marketplace_native_refresh_direct_mutation_allowed': False,
        'provenance_persisted_in_inventory_cycle': True,
        'production_surface_changed': False,
        'collector_sha256': sha(collector),
        'reader_sha256': sha(reader),
    }


def build() -> None:
    main, parent_addon, collector, reader = build_parent()
    provenance = load_pinned_ps1(PROVENANCE_HEAD, PROVENANCE_PATH, PROVENANCE_BLOB, 'custom-app provenance core')
    native_refresh = load_pinned_ps1(NATIVE_REFRESH_HEAD, NATIVE_REFRESH_PATH, NATIVE_REFRESH_BLOB, 'Marketplace native-refresh contract')
    candidate = patch(parent_addon, provenance, native_refresh)
    result = validate(main, candidate, collector, reader, provenance, native_refresh)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate)
    (OUT / 'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT / 'LevelDbReadOnly.cs').write_bytes(reader)
    report = {
        'schema': 1,
        'candidate_version': '0.6.29-validation-custom-app-provenance-integration-v0.2.0',
        'production_base': PRODUCTION_BASE,
        'source_topology_parent': SOURCE_TOPOLOGY_HEAD,
        'provenance_head': PROVENANCE_HEAD,
        'native_refresh_head': NATIVE_REFRESH_HEAD,
        'candidate_main': {'size': len(main), 'sha256': sha(main)},
        'candidate_addon': {'size': len(candidate), 'sha256': sha(candidate)},
        'features': [
            'custom-app-provenance-observer-integrated-into-inventory-cycle',
            'custom-app-provenance-distinct-state-root',
            'historical-provenance-reconciled-when-lifecycle-missing',
            'source-change-and-weak-evidence-remain-fail-closed',
            'marketplace-native-refresh-boundary-integrated-as-informational-contract',
            'generic-mutation-authority-remains-denied',
            'protected-persistence-transaction-preserved',
        ],
        **result,
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('CUSTOM_APP_PROVENANCE_INTEGRATION_BUILD_PASS', len(main), sha(main), len(candidate), sha(candidate))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--build', action='store_true')
    args = p.parse_args()
    if not args.build:
        p.error('use --build')
    build()


if __name__ == '__main__':
    main()
