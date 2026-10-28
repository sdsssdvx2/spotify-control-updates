from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, subprocess

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


INTEGRATION_HELPERS = r'''function Get-CustomAppProvenanceObservationFromLifecycle {
    param($State,$LifecycleRow)
    if($null -eq $LifecycleRow){return $null}
    if([string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1'){return $null}
    if(-not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed -or [bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity){return $null}
    if(@($LifecycleRow.locations).Count -ne 1){return $null}
    $path=[string]$LifecycleRow.locations[0]
    if([string]::IsNullOrWhiteSpace($path)){return $null}
    $name=''
    if($LifecycleRow.PSObject.Properties['name']){$name=[string]$LifecycleRow.name}
    if([string]::IsNullOrWhiteSpace($name) -and $LifecycleRow.PSObject.Properties['key']){$name=([string]$LifecycleRow.key -replace '^custom-app:','')}
    if([string]::IsNullOrWhiteSpace($name)){return $null}
    return Get-CustomAppLocalProvenanceObservation -Name $name -RootPath $path
}

function Update-CustomAppProvenanceFromCurrentLifecycle {
    param($State,[string]$ObservedAt)
    $State=Normalize-CustomAppProvenanceStateObject $State
    if(-not $State.PSObject.Properties['lifecycle']){return [pscustomobject]@{observed=0;updated=0;blocked=0}}
    $updated=0;$blocked=0;$observed=0
    foreach($prop in @($State.lifecycle.PSObject.Properties)){
        $key=[string]$prop.Name
        if(-not $key.StartsWith('custom-app:',[StringComparison]::OrdinalIgnoreCase)){continue}
        $row=$prop.Value
        $name=$key.Substring('custom-app:'.Length)
        $obs=Get-CustomAppProvenanceObservationFromLifecycle -State $State -LifecycleRow $row
        if($null -ne $obs){$observed++}
        $before=$null
        if($State.custom_app_provenance.PSObject.Properties[$key]){$before=$State.custom_app_provenance.PSObject.Properties[$key].Value}
        $result=Update-CustomAppProvenanceLedger -State $State -Name $name -Observation $obs -LifecycleRow $row -ObservedAt $ObservedAt
        if($null -ne $result){
            if([bool]$result.PSObject.Properties['source_changed'] -and [bool]$result.source_changed){$blocked++}
            $updated++
        }
    }
    return [pscustomobject]@{observed=$observed;updated=$updated;blocked=$blocked}
}

function Invoke-ProvenanceIntegrationSelfTest {
    $state=[pscustomobject]@{}
    $safe=[pscustomobject]@{key='custom-app:fixture-app';name='fixture-app';managed_by='dynamic-spicetify-v1';mutation_mode='deny';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@('C:\\fixture\\CustomApps\\fixture-app');last_seen='2026-10-28T02:00:00+00:00'}
    $state | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject]@{}) -Force
    $state.lifecycle | Add-Member -NotePropertyName 'custom-app:fixture-app' -NotePropertyValue $safe -Force
    $state=Normalize-CustomAppProvenanceStateObject $state
    if($state.custom_app_provenance.PSObject.Properties.Count -ne 0){throw 'Provenance integration self-test: initial provenance root not empty.'}
    $decision=Resolve-MarketplaceNativeRefreshContract ([pscustomobject]@{kind='extension';source_kind='github-repository-key';ambiguous=$false;mutation_authorized=$false})
    if(-not $decision.conclusive -or -not $decision.automatic_runtime_content_refresh -or $decision.addon_manager_direct_mutation_allowed){throw 'Provenance integration self-test: native refresh extension contract drift.'}
    $snippet=Resolve-MarketplaceNativeRefreshContract ([pscustomobject]@{kind='snippet';source_kind='snippet-key';ambiguous=$false;mutation_authorized=$false})
    if(-not $snippet.conclusive -or $snippet.automatic_runtime_content_refresh -or $snippet.addon_manager_direct_mutation_allowed){throw 'Provenance integration self-test: snippet authority drift.'}
    Write-AddonLog 'Provenance integration self-test passed: distinct state root and Marketplace native-refresh authority remain deny-by-default.'
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
    marker = "    try { Invoke-SourceTopologySelfTest } catch { $errors.Add(\"Source topology self-test failed: $($_.Exception.Message)\") }"
    hook = marker + "\n    try { Invoke-CustomAppProvenanceSelfTest } catch { $errors.Add(\"Custom App provenance self-test failed: $($_.Exception.Message)\") }\n    try { Invoke-MarketplaceNativeRefreshContractSelfTest } catch { $errors.Add(\"Marketplace native refresh self-test failed: $($_.Exception.Message)\") }\n    try { Invoke-ProvenanceIntegrationSelfTest } catch { $errors.Add(\"Provenance integration self-test failed: $($_.Exception.Message)\") }"
    selftest = replace_once(selftest, marker, hook, 'selftest integration hook')
    text = replace_func(text, 'Invoke-AddonSelfTest', selftest)
    return bom + text.encode('utf-8')


def validate(main: bytes, addon: bytes, collector: bytes, reader: bytes) -> dict:
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError('integration changed validated Spotify Control bytes')
    text = addon.decode('utf-8-sig')
    required = [
        '$CustomAppProvenanceSchema = 1',
        'function Update-CustomAppProvenanceFromCurrentLifecycle',
        'function Resolve-MarketplaceNativeRefreshContract',
        'function Invoke-ProvenanceIntegrationSelfTest',
        'custom_app_provenance',
        "mutation_mode='deny'",
        'auto_update_authorized',
        'auto_install_authorized',
        'New-RequiredSpotifyPersistenceBackup',
        'Restore-SpotifyPersistenceBackup',
        "name='tagify'",
        "source='alexk218/tagify'",
        "name='splitify'",
        "name='star-ratings'",
        "name='sc-cover-ambience.js'",
    ]
    for marker in required:
        if marker.lower() not in text.lower():
            raise RuntimeError(f'missing integration safety marker: {marker}')
    for forbidden in [
        "auto_update_authorized=$true",
        "auto_install_authorized=$true",
        "addon_manager_direct_mutation_allowed = $true",
    ]:
        if forbidden.lower() in text.lower():
            raise RuntimeError(f'generic authority unexpectedly expanded: {forbidden}')
    registry = block(text, 'Get-AddonPolicyRegistry')
    auto = []
    for name in AUTHORIZED:
        if name.lower() not in registry.lower():
            raise RuntimeError(f'authorized registry entry disappeared: {name}')
        auto.append(name)
    return {
        'auto_authority': auto,
        'generic_custom_app_mutation_authority_expanded': False,
        'generic_marketplace_mutation_authority_expanded': False,
        'custom_app_provenance_state_root': 'custom_app_provenance',
        'marketplace_native_refresh_direct_mutation_allowed': False,
        'production_surface_changed': False,
        'collector_sha256': sha(collector),
        'reader_sha256': sha(reader),
    }


def build() -> None:
    main, parent_addon, collector, reader = build_parent()
    provenance = load_pinned_ps1(PROVENANCE_HEAD, PROVENANCE_PATH, PROVENANCE_BLOB, 'custom-app provenance core')
    native_refresh = load_pinned_ps1(NATIVE_REFRESH_HEAD, NATIVE_REFRESH_PATH, NATIVE_REFRESH_BLOB, 'Marketplace native-refresh contract')
    candidate = patch(parent_addon, provenance, native_refresh)
    result = validate(main, candidate, collector, reader)
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
