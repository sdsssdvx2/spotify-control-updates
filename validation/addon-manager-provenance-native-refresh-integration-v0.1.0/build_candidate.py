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
SOURCE_TOPOLOGY_OUT = ROOT / 'validation/marketplace-source-topology-v0.1.0/out/bin'
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


def build_source_topology() -> tuple[bytes, bytes, bytes, bytes]:
    require_blob(SOURCE_TOPOLOGY_HEAD, SOURCE_TOPOLOGY_PATH, SOURCE_TOPOLOGY_BLOB, 'source-topology builder')
    source = git_bytes(SOURCE_TOPOLOGY_HEAD, SOURCE_TOPOLOGY_PATH)
    fake = ROOT / 'validation/marketplace-source-topology-v0.1.0/_pinned_provenance_native_refresh_builder.py'
    ns = {'__file__': str(fake), '__name__': 'pinned_source_topology_builder'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()
    main = (SOURCE_TOPOLOGY_OUT / 'spotify-control.ps1').read_bytes()
    addon = (SOURCE_TOPOLOGY_OUT / 'addon-manager.ps1').read_bytes()
    collector = (SOURCE_TOPOLOGY_OUT / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (SOURCE_TOPOLOGY_OUT / 'LevelDbReadOnly.cs').read_bytes()
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError(f'source-topology main drift: {len(main)} {sha(main)}')
    return main, addon, collector, reader


INTEGRATION_HELPER = r'''function New-CustomAppObserverSyntheticEvidence {
    param([string]$Name,[AllowNull()][string]$Path,[string]$Status,[bool]$RequiresReenrollment)
    $canon = ('synthetic|{0}|{1}|{2}' -f $Name.ToLowerInvariant(),$Status,$Path)
    return [pscustomobject]@{
        schema=$CustomAppProvenanceSchema;name=$Name;path=$Path;status=$Status;source_candidate=$null;source_proven=$false
        requires_reenrollment=$RequiresReenrollment;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false
        evidence_fingerprint=(Get-ProvenanceStringSha256Lower $canon);git=$null;package=$null
    }
}

function Update-CustomAppProvenanceObserverFromLifecycle {
    param($State,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    $seen=0;$proven=0;$blocked=0;$removed=0;$weak=0
    if($null -eq $State -or -not $State.PSObject.Properties['lifecycle'] -or $null -eq $State.lifecycle){
        return [pscustomobject]@{schema=1;managed_by='custom-app-provenance-observer-v1';observed_at=$ObservedAt;entries=0;proven_count=0;blocked_count=0;removed_count=0;weak_count=0;mutation_authority_expanded=$false}
    }
    foreach($prop in @($State.lifecycle.PSObject.Properties)){
        $life=$prop.Value
        if($null -eq $life -or [string]$life.managed_by -cne 'dynamic-spicetify-v1' -or [string]$life.kind -cne 'custom-app'){continue}
        $name=[string]$life.name
        if([string]::IsNullOrWhiteSpace($name) -and ([string]$prop.Name).StartsWith('custom-app:',[StringComparison]::OrdinalIgnoreCase)){$name=([string]$prop.Name).Substring(11)}
        if([string]::IsNullOrWhiteSpace($name)){continue}
        $seen++
        $locations=@($life.locations)
        $evidence=$null
        if([bool]$life.present -and -not [bool]$life.user_removed -and -not [bool]$life.ambiguous -and [bool]$life.safe_local_identity -and $locations.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$locations[0])){
            try{$evidence=Get-CustomAppLocalProvenanceEvidence -Name $name -AppPath ([string]$locations[0])}
            catch{$evidence=New-CustomAppObserverSyntheticEvidence -Name $name -Path ([string]$locations[0]) -Status 'provenance-evidence-read-failed' -RequiresReenrollment $true}
        }elseif(-not [bool]$life.present -or [bool]$life.user_removed){
            $evidence=New-CustomAppObserverSyntheticEvidence -Name $name -Path $null -Status $(if([bool]$life.user_removed){'user-removed'}else{'lifecycle-absent'}) -RequiresReenrollment $false
        }else{
            $evidence=New-CustomAppObserverSyntheticEvidence -Name $name -Path $(if($locations.Count -eq 1){[string]$locations[0]}else{$null}) -Status 'unsafe-local-lifecycle' -RequiresReenrollment $true
        }
        $row=Update-CustomAppProvenanceEnrollment -State $State -Evidence $evidence -ObservedAt $ObservedAt
        if(Test-CustomAppProvenanceMutationAuthority -Row $row){throw "Custom App provenance observer unexpectedly expanded mutation authority: $name"}
        if([string]$row.source_status -ceq 'user-removed' -or [string]$row.source_status -ceq 'lifecycle-absent'){$removed++}
        elseif([bool]$row.source_changed -or [bool]$row.requires_reenrollment){$blocked++}
        elseif(-not [string]::IsNullOrWhiteSpace([string]$row.source_identity)){$proven++}
        else{$weak++}
    }
    return [pscustomobject]@{schema=1;managed_by='custom-app-provenance-observer-v1';observed_at=$ObservedAt;entries=$seen;proven_count=$proven;blocked_count=$blocked;removed_count=$removed;weak_count=$weak;mutation_authority_expanded=$false}
}

function Update-MarketplaceNativeRefreshObserverState {
    param($State,$MarketplaceReport,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    $decisions=New-Object System.Collections.Generic.List[object]
    $safeReport=($null -ne $MarketplaceReport -and $MarketplaceReport.PSObject.Properties['read_only'] -and [bool]$MarketplaceReport.read_only -and $MarketplaceReport.PSObject.Properties['mutation_performed'] -and -not [bool]$MarketplaceReport.mutation_performed -and [string]$MarketplaceReport.status -ceq 'ok')
    $records=if($safeReport){@($MarketplaceReport.records)}else{@()}
    $countMatches=($safeReport -and [int]$MarketplaceReport.record_count -eq $records.Count)
    $conclusive=($safeReport -and $countMatches)
    $runtimeRefresh=0;$noRuntimeRefresh=0;$inconclusive=0
    if($conclusive){
        foreach($record in $records){
            $decision=Resolve-MarketplaceNativeRefreshContract -Record $record
            if([bool]$decision.addon_manager_direct_mutation_allowed){throw 'Marketplace native-refresh observer unexpectedly granted direct mutation authority.'}
            if(-not [bool]$decision.conclusive){$conclusive=$false;$inconclusive++}
            elseif([bool]$decision.automatic_runtime_content_refresh){$runtimeRefresh++}else{$noRuntimeRefresh++}
            $decisions.Add([pscustomobject]@{
                key=$(if($record.PSObject.Properties['key']){[string]$record.key}else{$null});kind=[string]$record.kind
                source_kind=[string]$record.source_kind;conclusive=[bool]$decision.conclusive;owner=[string]$decision.owner
                automatic_runtime_content_refresh=[bool]$decision.automatic_runtime_content_refresh
                full_installed_record_refresh_guaranteed=[bool]$decision.full_installed_record_refresh_guaranteed
                addon_manager_direct_mutation_allowed=$false;reason=[string]$decision.reason
            })
        }
    }
    $summary=[pscustomobject]@{
        schema=1;managed_by='marketplace-native-refresh-observer-v1';observed_at=$ObservedAt
        report_status=$(if($null -eq $MarketplaceReport){'null'}else{[string]$MarketplaceReport.status})
        report_fingerprint=$(if($null -ne $MarketplaceReport -and $MarketplaceReport.PSObject.Properties['identity_fingerprint']){[string]$MarketplaceReport.identity_fingerprint}else{$null})
        report_safe=[bool]$safeReport;record_count=$records.Count;record_count_matches=[bool]$countMatches;conclusive=[bool]$conclusive
        automatic_runtime_content_refresh_count=$runtimeRefresh;no_automatic_runtime_content_refresh_count=$noRuntimeRefresh
        inconclusive_count=$inconclusive;addon_manager_direct_mutation_allowed=$false;decisions=$decisions.ToArray()
    }
    if(-not $State.PSObject.Properties['marketplace_native_refresh']){$State|Add-Member -NotePropertyName marketplace_native_refresh -NotePropertyValue $summary}
    else{$State.marketplace_native_refresh=$summary}
    return $summary
}

function Invoke-ProvenanceNativeRefreshIntegrationSelfTest {
    $root=Join-Path $env:TEMP ('spotify-control-provenance-native-refresh-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $root|Out-Null
    try{
        $app=Join-Path $root 'future-app';New-Item -ItemType Directory -Force -Path $app|Out-Null
        $git=Join-Path $app '.git';New-Item -ItemType Directory -Force -Path $git|Out-Null
        @('[core]','    repositoryformatversion = 0','[remote "origin"]','    url = https://github.com/Example/Future-App.git')|Set-Content -LiteralPath (Join-Path $git 'config') -Encoding UTF8
        $life=[pscustomobject]@{}
        $life|Add-Member -NotePropertyName 'custom-app:future-app' -NotePropertyValue ([pscustomobject]@{managed_by='dynamic-spicetify-v1';kind='custom-app';name='future-app';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($app)})
        $state=[pscustomobject]@{lifecycle=$life}
        $s1=Update-CustomAppProvenanceObserverFromLifecycle -State $state -ObservedAt '2026-10-28T09:00:00+00:00'
        $row=$state.custom_app_provenance.PSObject.Properties['custom-app:future-app'].Value
        if([string]$row.source_identity -cne 'example/future-app' -or [string]$row.mutation_mode -cne 'deny' -or [bool]$row.auto_update_authorized -or [bool]$row.auto_install_authorized){throw 'Integration self-test: strong provenance enrollment or deny authority drifted.'}
        if([int]$s1.proven_count -ne 1 -or [bool]$s1.mutation_authority_expanded){throw 'Integration self-test: provenance observer summary drifted.'}

        @('[core]','    repositoryformatversion = 0','[remote "origin"]','    url = https://github.com/Other/Fork.git')|Set-Content -LiteralPath (Join-Path $git 'config') -Encoding UTF8
        [void](Update-CustomAppProvenanceObserverFromLifecycle -State $state -ObservedAt '2026-10-28T09:01:00+00:00')
        $row=$state.custom_app_provenance.PSObject.Properties['custom-app:future-app'].Value
        if([string]$row.source_status -cne 'source-change-blocked' -or $null -ne $row.source_identity -or [string]$row.last_proven_source -cne 'example/future-app' -or -not [bool]$row.requires_reenrollment){throw 'Integration self-test: source swap was not blocked with historical provenance preserved.'}
        if(Test-CustomAppProvenanceMutationAuthority -Row $row){throw 'Integration self-test: source swap gained authority.'}

        $lr=$state.lifecycle.PSObject.Properties['custom-app:future-app'].Value;$lr.present=$false;$lr.user_removed=$true
        [void](Update-CustomAppProvenanceObserverFromLifecycle -State $state -ObservedAt '2026-10-28T09:02:00+00:00')
        $row=$state.custom_app_provenance.PSObject.Properties['custom-app:future-app'].Value
        if([string]$row.source_status -cne 'user-removed' -or $null -ne $row.source_identity -or [string]$row.last_proven_source -cne 'example/future-app'){throw 'Integration self-test: deletion tombstone semantics drifted.'}

        $records=@(
            [pscustomobject]@{key='marketplace:extension:a/b/a.js';kind='extension';source_kind='github-repository-key';ambiguous=$false;mutation_authorized=$false},
            [pscustomobject]@{key='marketplace:theme:c/d/theme';kind='theme';source_kind='github-repository-key';ambiguous=$false;mutation_authorized=$false},
            [pscustomobject]@{key='marketplace:snippet:x';kind='snippet';source_kind='snippet-key';ambiguous=$false;mutation_authorized=$false}
        )
        $report=[pscustomobject]@{status='ok';read_only=$true;mutation_performed=$false;record_count=3;identity_fingerprint=('a'*64);records=$records}
        $nr=Update-MarketplaceNativeRefreshObserverState -State $state -MarketplaceReport $report -ObservedAt '2026-10-28T09:03:00+00:00'
        if(-not [bool]$nr.conclusive -or [int]$nr.automatic_runtime_content_refresh_count -ne 2 -or [int]$nr.no_automatic_runtime_content_refresh_count -ne 1 -or [bool]$nr.addon_manager_direct_mutation_allowed){throw 'Integration self-test: Marketplace native-refresh summary drifted.'}
        foreach($d in @($nr.decisions)){if([bool]$d.addon_manager_direct_mutation_allowed){throw 'Integration self-test: native-refresh decision gained direct authority.'}}
        Invoke-MarketplaceNativeRefreshContractSelfTest
        Write-AddonLog 'Provenance/native-refresh integration self-test passed: enrollment, source swap, deletion tombstone, Marketplace refresh classification, and deny authority.'
    }finally{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}'''


def integrate(addon: bytes) -> bytes:
    require_blob(PROVENANCE_HEAD, PROVENANCE_PATH, PROVENANCE_BLOB, 'custom-app provenance core')
    require_blob(NATIVE_REFRESH_HEAD, NATIVE_REFRESH_PATH, NATIVE_REFRESH_BLOB, 'Marketplace native-refresh contract')
    provenance = git_bytes(PROVENANCE_HEAD, PROVENANCE_PATH).decode('utf-8-sig').strip()
    native = git_bytes(NATIVE_REFRESH_HEAD, NATIVE_REFRESH_PATH).decode('utf-8-sig').strip()
    bom = b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    text = addon[len(bom):].decode('utf-8')

    insert_anchor = 'function Test-Due {'
    if text.count(insert_anchor) != 1:
        raise RuntimeError('observer helper insertion anchor drift')
    text = text.replace(insert_anchor, provenance + '\n\n' + native + '\n\n' + INTEGRATION_HELPER + '\n\n' + insert_anchor, 1)

    inventory = block(text, 'Get-AddonInventory')
    lifecycle_anchor = '    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now\n    Save-AddonState $state'
    lifecycle_replacement = '''    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now
    $customAppProvenanceSummary=Update-CustomAppProvenanceObserverFromLifecycle -State $state -ObservedAt $now
    $marketplaceNativeRefreshSummary=Update-MarketplaceNativeRefreshObserverState -State $state -MarketplaceReport $marketplaceReport -ObservedAt $now
    Save-AddonState $state'''
    inventory = replace_once(inventory, lifecycle_anchor, lifecycle_replacement, 'inventory observer integration')
    report_anchor = '        marketplace_lifecycle = $marketplaceLifecycle\n'
    report_replacement = report_anchor + '        custom_app_provenance = $customAppProvenanceSummary\n        marketplace_native_refresh = $marketplaceNativeRefreshSummary\n'
    inventory = replace_once(inventory, report_anchor, report_replacement, 'inventory observer report fields')
    text = replace_func(text, 'Get-AddonInventory', inventory)

    selftest = block(text, 'Invoke-AddonSelfTest')
    topology_test = '    try { Invoke-SourceTopologySelfTest } catch { $errors.Add("Source topology self-test failed: $($_.Exception.Message)") }'
    integration_test = topology_test + '\n    try { Invoke-ProvenanceNativeRefreshIntegrationSelfTest } catch { $errors.Add("Provenance/native-refresh integration self-test failed: $($_.Exception.Message)") }'
    selftest = replace_once(selftest, topology_test, integration_test, 'integration self-test hook')
    text = replace_func(text, 'Invoke-AddonSelfTest', selftest)
    return bom + text.encode('utf-8')


def validate(main: bytes, parent_addon: bytes, addon: bytes, collector: bytes, reader: bytes) -> dict:
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError('integration candidate changed validated Spotify Control bytes')
    text = addon.decode('utf-8-sig').replace('\r\n', '\n')
    parent_text = parent_addon.decode('utf-8-sig').replace('\r\n', '\n')
    registry = block(text, 'Get-AddonPolicyRegistry')
    parent_registry = block(parent_text, 'Get-AddonPolicyRegistry')
    if registry != parent_registry:
        raise RuntimeError('policy registry changed during observer-only integration')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED):
        raise RuntimeError(f'auto authority drift: {auto}')

    inventory = block(text, 'Get-AddonInventory')
    for marker in (
        'Update-CustomAppProvenanceObserverFromLifecycle -State $state -ObservedAt $now',
        'Update-MarketplaceNativeRefreshObserverState -State $state -MarketplaceReport $marketplaceReport -ObservedAt $now',
        'custom_app_provenance = $customAppProvenanceSummary',
        'marketplace_native_refresh = $marketplaceNativeRefreshSummary',
        'Save-AddonState $state',
    ):
        if marker not in inventory:
            raise RuntimeError(f'inventory observer integration marker missing: {marker}')
    if inventory.index('Update-CustomAppProvenanceObserverFromLifecycle') > inventory.index('Save-AddonState $state'):
        raise RuntimeError('provenance observer is not persisted in the inventory cycle')
    if inventory.index('Update-MarketplaceNativeRefreshObserverState') > inventory.index('Save-AddonState $state'):
        raise RuntimeError('native-refresh observer is not persisted in the inventory cycle')

    auth = block(text, 'Get-AddonMutationAuthorization')
    parent_auth = block(parent_text, 'Get-AddonMutationAuthorization')
    if auth != parent_auth:
        raise RuntimeError('mutation authorization changed during observer-only integration')
    schedule = block(text, 'Get-DiscoveredActionableAutoUpdateCount')
    parent_schedule = block(parent_text, 'Get-DiscoveredActionableAutoUpdateCount')
    if schedule != parent_schedule:
        raise RuntimeError('schedule authority changed during observer-only integration')

    required = (
        'function Update-CustomAppProvenanceEnrollment', 'function Test-CustomAppProvenanceMutationAuthority',
        'function Update-CustomAppProvenanceObserverFromLifecycle', "managed_by='custom-app-provenance-v1'",
        "mutation_mode='deny'", 'auto_update_authorized=$false', 'auto_install_authorized=$false',
        "source_status='source-change-blocked'", 'last_proven_source',
        'function Resolve-MarketplaceNativeRefreshContract', 'function Update-MarketplaceNativeRefreshObserverState',
        'addon_manager_direct_mutation_allowed=$false', 'function Invoke-ProvenanceNativeRefreshIntegrationSelfTest',
        'New-RequiredSpotifyPersistenceBackup', 'Restore-SpotifyPersistenceBackup',
        "protected_state_policy='must-remain-byte-identical-through-apply'",
    )
    for marker in required:
        if marker not in text:
            raise RuntimeError(f'missing observer integration safety marker: {marker}')

    for marker in (
        "name='splitify'", "name='star-ratings'", 'playlist-backed-ratings-preserve',
        "name='sc-cover-ambience.js'", 'never-disable-or-optimize', "name='tagify'",
        "source='alexk218/tagify'", "install_mode='installed-only'", 'preserve-ratings-tags-notes-and-browser-storage'
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected registry policy missing: {marker}')

    for fn in ('Update-CustomAppProvenanceObserverFromLifecycle','Update-MarketplaceNativeRefreshObserverState'):
        body = block(text, fn).lower()
        for forbidden in ('invoke-webrequest','invoke-restmethod','start-process','copy-item','move-item','remove-item','spicetify apply','spicetify config'):
            if forbidden in body:
                raise RuntimeError(f'{fn} gained forbidden side effect/network primitive: {forbidden}')

    if sha(collector) != sha((SOURCE_TOPOLOGY_OUT / 'Collect-Marketplace-Records.ps1').read_bytes()):
        raise RuntimeError('Marketplace collector changed during observer integration')
    if sha(reader) != sha((SOURCE_TOPOLOGY_OUT / 'LevelDbReadOnly.cs').read_bytes()):
        raise RuntimeError('LevelDB reader changed during observer integration')
    return {
        'auto_authority': AUTHORIZED,
        'policy_registry_byte_identical_to_source_topology_parent': True,
        'mutation_authorization_byte_identical_to_source_topology_parent': True,
        'schedule_authority_byte_identical_to_source_topology_parent': True,
        'generic_custom_app_mutation_authority_expanded': False,
        'generic_marketplace_mutation_authority_expanded': False,
        'custom_app_provenance_runtime_observer_integrated': True,
        'marketplace_native_refresh_runtime_observer_integrated': True,
        'production_surface_changed': False,
        'parent_addon_sha256': sha(parent_addon),
        'collector_sha256': sha(collector),
        'reader_sha256': sha(reader),
    }


def build() -> None:
    main, parent_addon, collector, reader = build_source_topology()
    candidate = integrate(parent_addon)
    result = validate(main, parent_addon, candidate, collector, reader)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate)
    (OUT / 'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT / 'LevelDbReadOnly.cs').write_bytes(reader)
    report = {
        'schema': 1,
        'candidate_version': '0.6.29-validation-provenance-native-refresh-integration-v0.1.0',
        'production_base': PRODUCTION_BASE,
        'source_topology_parent': {'head': SOURCE_TOPOLOGY_HEAD, 'path': SOURCE_TOPOLOGY_PATH, 'blob': SOURCE_TOPOLOGY_BLOB},
        'provenance_source': {'head': PROVENANCE_HEAD, 'path': PROVENANCE_PATH, 'blob': PROVENANCE_BLOB},
        'native_refresh_source': {'head': NATIVE_REFRESH_HEAD, 'path': NATIVE_REFRESH_PATH, 'blob': NATIVE_REFRESH_BLOB},
        'candidate_main': {'size': len(main), 'sha256': sha(main)},
        'candidate_addon': {'size': len(candidate), 'sha256': sha(candidate)},
        'features': [
            'custom-app-provenance-updated-from-complete-lifecycle-ledger-each-inventory-cycle',
            'deleted-custom-app-provenance-tombstones-preserved',
            'source-change-requires-reenrollment-and-never-grants-authority',
            'marketplace-extension-theme-snippet-native-refresh-classified-observer-only',
            'marketplace-direct-addon-manager-mutation-remains-denied',
            'existing-policy-registry-mutation-authorization-and-schedule-authority-byte-identical',
            'protected-persistence-transaction-contract-preserved',
        ],
        **result,
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('PROVENANCE_NATIVE_REFRESH_INTEGRATION_BUILD_PASS', len(main), sha(main), len(candidate), sha(candidate))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--build', action='store_true')
    args = p.parse_args()
    if not args.build:
        p.error('use --build')
    build()


if __name__ == '__main__':
    main()
