from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_BASE = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
V03_HEAD = '27aa2f2089e99d6354d5e724577cdd7687d36525'
V03_PATH = 'validation/custom-app-provenance-integrated-observer-v0.3.0/build_candidate.py'
V03_BLOB = 'ef94a51510de3f922659e633c86dbd44f3083a3d'
REMOTE_CONTRACT_HEAD = 'b53bcf39f715f1c35c7d1f99e157cdecb0a2a572'
REMOTE_CONTRACT_PATH = 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1'
REMOTE_CONTRACT_BLOB = 'f8c91f5a566b24c82257742942bdc6fecfe68eb2'
REMOTE_CONT_HEAD = '19109205bd2e61e862c3b9acd61946568397ecb5'
REMOTE_CONT_PATH = 'validation/custom-app-remote-source-contract-v0.1.1/release-continuity-v011.ps1'
REMOTE_CONT_BLOB = 'dbec4f817f4f4eab92d89d1f8dc623b1da435ac3'
REMOTE_OBSERVER_HEAD = 'dba3bb40d720192813a1df9f6cbff3b00c60844f'
REMOTE_OBSERVER_PATH = 'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1'
REMOTE_OBSERVER_BLOB = '3a49ceebd13fa993b086eb2643130fb02c746bd1'
REMOTE_FIX_HEAD = '7d22b55c58c6e85a8a3ec9396800e65d81b0e7d2'
REMOTE_FIX_PATH = 'validation/custom-app-remote-observation-collector-v0.1.1/release-id-fix-v011.ps1'
REMOTE_FIX_BLOB = 'e0ae3c494959c6b738bfd1be56183931119542cf'
LOCAL_BASELINE_HEAD = '7402ea5c77e58cd072f0166411d40e7726093f3c'
LOCAL_BASELINE_PATH = 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1'
LOCAL_BASELINE_BLOB = '83156d9c14e40061a0728d28b582c1e65684a4a2'
BINDING_STATE_PATH = 'validation/custom-app-remote-binding-observer-v0.4.0/custom-app-remote-binding-state.ps1'
BINDING_STATE_BLOB = '7d1a14227cb357bbe34d8846d5ddb295b17990c1'
EXPECTED_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
EXPECTED_V03_ADDON = (428643, '8de197a78e40faad6e934c0eef4bb123f6652fc6e35cf440733c813c6df86e52')
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


def load_ps1(commit: str, path: str, blob: str, label: str) -> str:
    require_blob(commit, path, blob, label)
    return git_bytes(commit, path).decode('utf-8-sig').replace('\r\n', '\n').rstrip()


def build_v03() -> tuple[bytes, bytes, bytes, bytes]:
    require_blob(V03_HEAD, V03_PATH, V03_BLOB, 'v0.3 builder')
    source = git_bytes(V03_HEAD, V03_PATH)
    fake = ROOT / 'validation/custom-app-provenance-integrated-observer-v0.3.0/_v040_pinned_builder.py'
    ns = {'__file__': str(fake), '__name__': 'pinned_v03_builder'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()
    base = ROOT / 'validation/custom-app-provenance-integrated-observer-v0.3.0/out/bin'
    main = (base / 'spotify-control.ps1').read_bytes()
    addon = (base / 'addon-manager.ps1').read_bytes()
    collector = (base / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (base / 'LevelDbReadOnly.cs').read_bytes()
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError(f'v0.3 main drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != EXPECTED_V03_ADDON:
        raise RuntimeError(f'v0.3 addon drift: {len(addon)} {sha(addon)}')
    return main, addon, collector, reader


CYCLE_HELPERS = r'''function Invoke-CustomAppRemoteBindingObserverCycleV040 {
    param(
        [Parameter(Mandatory=$true)]$State,
        [string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')),
        [int]$MinimumIntervalHours=24,
        [int]$MaxNetworkObservationsPerCycle=2
    )
    if($MaxNetworkObservationsPerCycle -lt 1 -or $MaxNetworkObservationsPerCycle -gt 10){throw 'Remote binding observer network cap must be between 1 and 10.'}
    $State=Ensure-CustomAppRemoteBindingState $State
    $now=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse($ObservedAt,[ref]$now)){throw 'Remote binding observer timestamp is invalid.'}
    $attempted=0;$skippedDue=0;$eligible=0;$blocked=0;$failures=0

    # Reconcile historical rows first. Missing/deleted/source-changed local identity deactivates
    # remote trust without any network request and without erasing historical binding evidence.
    foreach($remoteProp in @($State.custom_app_remote_sources.PSObject.Properties)){
        $key=[string]$remoteProp.Name
        if(-not $key.StartsWith('custom-app:',[StringComparison]::OrdinalIgnoreCase)){continue}
        $name=$key.Substring('custom-app:'.Length)
        $life=$(if($State.lifecycle.PSObject.Properties[$key]){$State.lifecycle.PSObject.Properties[$key].Value}else{$null})
        $prov=$(if($State.PSObject.Properties['custom_app_provenance'] -and $State.custom_app_provenance.PSObject.Properties[$key]){$State.custom_app_provenance.PSObject.Properties[$key].Value}else{$null})
        $elig=Test-CustomAppRemoteBindingEligibilityV040 -LifecycleRow $life -ProvenanceRow $prov
        if(-not [bool]$elig.ok){[void](Update-CustomAppRemoteBindingEligibilityOnlyV040 -State $State -Name $name -LifecycleRow $life -ProvenanceRow $prov -ObservedAt $ObservedAt);$blocked++}
    }

    foreach($lifeProp in @($State.lifecycle.PSObject.Properties|Sort-Object -Property Name)){
        $key=[string]$lifeProp.Name;$life=$lifeProp.Value
        if($null -eq $life -or [string]$life.managed_by -cne 'dynamic-spicetify-v1' -or [string]$life.kind -cne 'custom-app'){continue}
        $name=[string]$life.name;if([string]::IsNullOrWhiteSpace($name)){$name=$key.Substring('custom-app:'.Length)}
        $prov=$(if($State.PSObject.Properties['custom_app_provenance'] -and $State.custom_app_provenance.PSObject.Properties[$key]){$State.custom_app_provenance.PSObject.Properties[$key].Value}else{$null})
        $elig=Test-CustomAppRemoteBindingEligibilityV040 -LifecycleRow $life -ProvenanceRow $prov
        if(-not [bool]$elig.ok){[void](Update-CustomAppRemoteBindingEligibilityOnlyV040 -State $State -Name $name -LifecycleRow $life -ProvenanceRow $prov -ObservedAt $ObservedAt);continue}
        $eligible++
        $row=Ensure-CustomAppRemoteBindingRowV040 -State $State -Name $name
        if(-not (Test-CustomAppRemoteObservationDueV040 -Row $row -Now $now -MinimumIntervalHours $MinimumIntervalHours)){$skippedDue++;continue}
        if($attempted -ge $MaxNetworkObservationsPerCycle){continue}
        $attempted++

        $baseline=$null
        try{$baseline=Get-CustomAppLocalRuntimeBaseline -Name $name -AppPath ([string]$elig.path)}
        catch{
            [void](Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status 'local-baseline-error' -Reason ([string]$_.Exception.Message) -RequiresReenrollment:$true -ObservedAt $ObservedAt);$blocked++;continue
        }
        if($null -eq $baseline -or -not [bool]$baseline.safe -or -not [bool]$baseline.installable){
            [void](Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status 'local-baseline-denied' -Reason $(if($null -ne $baseline){[string]$baseline.reason}else{'local-baseline-null'}) -RequiresReenrollment:$true -ObservedAt $ObservedAt);$blocked++;continue
        }

        $bound=$(if([bool]$row.active -and $null -ne $row.binding){$row.binding}else{$null})
        $set=$null
        try{$set=Get-CustomAppRemoteObservationSet -Source ([string]$elig.source) -Binding $bound}
        catch{[void](Set-CustomAppRemoteBindingObservationFailureV040 -Row $row -ErrorText ([string]$_.Exception.Message) -ObservedAt $ObservedAt);$failures++;continue}
        try{
            $updated=Update-CustomAppRemoteBindingFromObservationSetV040 -State $State -Name $name -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $baseline -ObservationSet $set -ObservedAt $ObservedAt
            if([string]$updated.last_status -ceq 'remote-observation-failed'){$failures++}
            elseif(-not [bool]$updated.active){$blocked++}
        } catch {
            [void](Set-CustomAppRemoteBindingObservationFailureV040 -Row $row -ErrorText ('state-contract-failure:'+[string]$_.Exception.Message) -ObservedAt $ObservedAt);$failures++
        }
    }
    [void](Assert-CustomAppRemoteBindingStateDeniedV040 $State)
    $rows=@($State.custom_app_remote_sources.PSObject.Properties|ForEach-Object{$_.Value})
    return [pscustomobject]@{schema=1;observed_at=$ObservedAt;minimum_interval_hours=$MinimumIntervalHours;network_cap=$MaxNetworkObservationsPerCycle;eligible_count=$eligible;network_attempt_count=$attempted;due_skipped_count=$skippedDue;blocked_count=$blocked;failure_count=$failures;row_count=$rows.Count;active_count=@($rows|Where-Object{[bool]$_.active}).Count;update_observed_count=@($rows|Where-Object{[bool]$_.update_observed}).Count;mutation_authority_count=@($rows|Where-Object{Test-CustomAppRemoteBindingMutationAuthorityV040 $_}).Count;rows=$rows}
}

function Invoke-CustomAppRemoteBindingIntegratedSelfTestV040 {
    $state=[pscustomobject]@{}
    $state=Ensure-CustomAppRemoteBindingState $state
    $row=Ensure-CustomAppRemoteBindingRowV040 -State $state -Name 'fixture-app'
    $row.source_identity='example/app';$row.active=$true
    $row.binding=[pscustomobject]@{schema=1;managed_by='custom-app-remote-source-v1';source_identity='example/app';github_repo_id=[int64]123;surface_kind='release-asset';asset_name='fixture.zip';release_asset_selector='unique-zip-asset';layout_root='.';manifest_name='Fixture App';last_verified_local_tree_sha256=('a'*64);last_verified_remote_tree_sha256=('a'*64);last_verified_commit_sha=('1'*40);mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    if(Test-CustomAppRemoteBindingMutationAuthorityV040 $row){throw 'Remote binding integrated self-test: fixture row gained authority.'}
    $normalized=Normalize-AddonStateObject $state
    if(-not $normalized.PSObject.Properties['custom_app_remote_sources'] -or -not $normalized.custom_app_remote_sources.PSObject.Properties['custom-app:fixture-app']){throw 'Remote binding integrated self-test: Normalize-AddonStateObject dropped remote state root.'}

    $oldStatePath=$script:StatePath
    $temp=Join-Path $env:TEMP ('spotify-control-remote-binding-state-'+[guid]::NewGuid().ToString('N'))
    try{
        New-Item -ItemType Directory -Force -Path $temp|Out-Null
        $script:StatePath=Join-Path $temp 'addons-state.json'
        Save-AddonState $state
        $loaded=Load-AddonState
        if(-not $loaded.PSObject.Properties['custom_app_remote_sources'] -or -not $loaded.custom_app_remote_sources.PSObject.Properties['custom-app:fixture-app']){throw 'Remote binding integrated self-test: Save/Load dropped remote state root.'}
        $loadedRow=$loaded.custom_app_remote_sources.PSObject.Properties['custom-app:fixture-app'].Value
        if([string]$loadedRow.binding.source_identity -cne 'example/app' -or (Test-CustomAppRemoteBindingMutationAuthorityV040 $loadedRow)){throw 'Remote binding integrated self-test: Save/Load changed binding identity or authority.'}
    } finally {
        $script:StatePath=$oldStatePath
        if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
    }
    Write-Host 'CUSTOM_APP_REMOTE_BINDING_INTEGRATED_SELFTEST_V040_PASS normalize save-load authority-deny'
}'''


def integrate(addon: bytes) -> bytes:
    contract = load_ps1(REMOTE_CONTRACT_HEAD, REMOTE_CONTRACT_PATH, REMOTE_CONTRACT_BLOB, 'remote source contract')
    continuity = load_ps1(REMOTE_CONT_HEAD, REMOTE_CONT_PATH, REMOTE_CONT_BLOB, 'remote release continuity')
    observer = load_ps1(REMOTE_OBSERVER_HEAD, REMOTE_OBSERVER_PATH, REMOTE_OBSERVER_BLOB, 'remote observer')
    observer_fix = load_ps1(REMOTE_FIX_HEAD, REMOTE_FIX_PATH, REMOTE_FIX_BLOB, 'remote observer v0.1.1 fix')
    baseline = load_ps1(LOCAL_BASELINE_HEAD, LOCAL_BASELINE_PATH, LOCAL_BASELINE_BLOB, 'local runtime baseline')
    binding = load_ps1('HEAD', BINDING_STATE_PATH, BINDING_STATE_BLOB, 'remote binding state core')
    insertion = '\n\n'.join((contract, continuity, observer, observer_fix, baseline, binding, CYCLE_HELPERS))

    bom = b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    text = addon[len(bom):].decode('utf-8')
    anchor = 'function Test-Due {'
    text = replace_once(text, anchor, insertion + '\n\n' + anchor, 'v0.4 observer insertion')

    inventory = function_block(text, 'Get-AddonInventory')
    state_anchor = '''    Save-AddonState $state

    $marketplaceReport = Invoke-MarketplaceRecordDiscovery'''
    state_replacement = '''    Save-AddonState $state

    # Generic remote-source observation is state-only and deliberately rate-limited.
    # It never changes the existing five mutation-authorized registry entries.
    $customAppRemoteBindingSummary=Invoke-CustomAppRemoteBindingObserverCycleV040 -State $state -ObservedAt $now -MinimumIntervalHours 24 -MaxNetworkObservationsPerCycle 2
    Save-AddonState $state

    $marketplaceReport = Invoke-MarketplaceRecordDiscovery'''
    inventory = replace_once(inventory, state_anchor, state_replacement, 'v0.4 remote observer inventory hook')
    report_anchor = '''        custom_app_provenance = [pscustomobject]@{ schema=1; row_count=$customAppProvenanceRows.Count; mutation_authority_count=@($customAppProvenanceRows.ToArray()|Where-Object{Test-CustomAppProvenanceMutationAuthority -Row $_}).Count; rows=$customAppProvenanceRows.ToArray() }
'''
    report_replacement = report_anchor + '''        custom_app_remote_sources = $customAppRemoteBindingSummary
'''
    inventory = replace_once(inventory, report_anchor, report_replacement, 'v0.4 remote observer report publication')
    text = replace_function(text, 'Get-AddonInventory', inventory)

    selftest = function_block(text, 'Invoke-AddonSelfTest')
    hook_anchor = '    try { Invoke-MarketplaceNativeRefreshContractSelfTest } catch { $errors.Add("Marketplace native refresh contract self-test failed: $($_.Exception.Message)") }'
    hook_replacement = hook_anchor + '\n    try { Invoke-CustomAppRemoteBindingIntegratedSelfTestV040 } catch { $errors.Add("Custom App remote binding integrated self-test failed: $($_.Exception.Message)") }'
    selftest = replace_once(selftest, hook_anchor, hook_replacement, 'v0.4 selftest hook')
    text = replace_function(text, 'Invoke-AddonSelfTest', selftest)
    return bom + text.encode('utf-8')


def validate(main: bytes, addon: bytes, collector: bytes, reader: bytes) -> dict:
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError('v0.4 changed validated Spotify Control bytes')
    text = addon.decode('utf-8-sig').replace('\r\n', '\n')
    registry = function_block(text, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED):
        raise RuntimeError(f'v0.4 auto authority drift: {auto}')
    for marker in (
        'function Invoke-CustomAppRemoteBindingObserverCycleV040',
        'function Get-CustomAppLocalRuntimeBaseline',
        'function Get-CustomAppRemoteObservationSet',
        'function Resolve-CustomAppRemoteSourceContractV011',
        'function Ensure-CustomAppRemoteBindingState',
        "managed_by='custom-app-remote-binding-observer-v1'",
        "managed_by='custom-app-remote-source-v1'",
        'MinimumIntervalHours 24',
        'MaxNetworkObservationsPerCycle 2',
        'custom_app_remote_sources = $customAppRemoteBindingSummary',
        'New-RequiredSpotifyPersistenceBackup','Restore-SpotifyPersistenceBackup',
        'preserve-ratings-tags-notes-and-browser-storage','playlist-backed-ratings-preserve','never-disable-or-optimize',
        "source='alexk218/tagify'",
    ):
        if marker.lower() not in text.lower():
            raise RuntimeError(f'missing v0.4 safety marker: {marker}')
    inventory = function_block(text, 'Get-AddonInventory')
    if inventory.index('Update-CustomAppProvenanceEnrollment') > inventory.index('Invoke-CustomAppRemoteBindingObserverCycleV040'):
        raise RuntimeError('remote observer runs before current provenance refresh')
    if inventory.count('Save-AddonState $state') < 2:
        raise RuntimeError('remote observer state is not persisted after observation cycle')
    for forbidden in ('mutation_mode=\'auto\'', 'auto_update_authorized=$true', 'auto_install_authorized=$true'):
        state_block = function_block(text, 'Ensure-CustomAppRemoteBindingRowV040') + '\n' + function_block(text, 'Update-CustomAppRemoteBindingFromObservationSetV040')
        if forbidden.lower() in state_block.lower():
            raise RuntimeError(f'generic remote binding state gained forbidden authority: {forbidden}')
    return {
        'auto_authority': AUTHORIZED,
        'remote_binding_state_root': 'custom_app_remote_sources',
        'remote_binding_observer_integrated': True,
        'generic_remote_mutation_authority_expanded': False,
        'remote_observation_minimum_interval_hours': 24,
        'remote_observation_network_cap_per_inventory': 2,
        'network_failure_preserves_binding': True,
        'user_deletion_never_triggers_reinstall': True,
        'source_change_requires_reenrollment': True,
        'production_surface_changed': False,
        'collector_sha256': sha(collector),
        'reader_sha256': sha(reader),
    }


def build() -> None:
    main, v03_addon, collector, reader = build_v03()
    candidate = integrate(v03_addon)
    result = validate(main, candidate, collector, reader)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate)
    (OUT / 'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT / 'LevelDbReadOnly.cs').write_bytes(reader)
    report = {
        'schema': 1,
        'production_base': PRODUCTION_BASE,
        'candidate_version': '0.6.29-validation-remote-binding-observer-v0.4.0',
        'validated_v03': {'head': V03_HEAD, 'path': V03_PATH, 'blob': V03_BLOB},
        'validated_remote_contract': {'head': REMOTE_CONTRACT_HEAD, 'blob': REMOTE_CONTRACT_BLOB},
        'validated_release_continuity': {'head': REMOTE_CONT_HEAD, 'blob': REMOTE_CONT_BLOB},
        'validated_remote_observer': {'head': REMOTE_FIX_HEAD, 'base_blob': REMOTE_OBSERVER_BLOB, 'fix_blob': REMOTE_FIX_BLOB},
        'validated_local_baseline': {'head': LOCAL_BASELINE_HEAD, 'blob': LOCAL_BASELINE_BLOB},
        'candidate_main': {'size': len(main), 'sha256': sha(main)},
        'candidate_addon': {'size': len(candidate), 'sha256': sha(candidate)},
        'features': [
            'remote-binding-distinct-state-root',
            'current-lifecycle-and-provenance-required-before-network',
            'local-runtime-baseline-required-before-remote-binding',
            'initial-binding-requires-exact-local-remote-tree-and-manifest-match',
            'multiple-safe-surfaces-fail-closed-as-ambiguous',
            'network-failure-preserves-existing-binding',
            'user-deletion-deactivates-without-network-or-reinstall',
            'source-change-deactivates-and-requires-reenrollment',
            'remote-change-observer-only-no-mutation-authority',
            '24-hour-due-gate-and-two-network-attempt-cap-per-inventory',
            'remote-state-save-load-selftest',
        ],
        **result,
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('CUSTOM_APP_REMOTE_BINDING_OBSERVER_V040_BUILD_PASS', len(main), sha(main), len(candidate), sha(candidate))


def main() -> None:
    p = argparse.ArgumentParser();p.add_argument('--build', action='store_true');args=p.parse_args()
    if not args.build:p.error('use --build')
    build()

if __name__ == '__main__':main()
