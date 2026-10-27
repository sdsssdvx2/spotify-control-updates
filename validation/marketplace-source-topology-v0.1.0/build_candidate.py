from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_BASE = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
INTEGRATED_HEAD = '71ebf04ec6744383161bc16376a6a292dd3a5e33'
INTEGRATED_PATH = 'validation/marketplace-integrated-engine-v0.2.0/build_candidate.py'
INTEGRATED_BLOB = 'a3c10668d5630d1e1a40dc425fffe4e859652e37'
INTEGRATED_FAKE = ROOT / 'validation/marketplace-integrated-engine-v0.2.0/_source_topology_pinned_builder.py'
INTEGRATED_OUT = ROOT / 'validation/marketplace-integrated-engine-v0.2.0/out/bin'
EXPECTED_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MARKETPLACE_UPSTREAM_COMMIT = '7f357885a3514a55d426fd43edfd705d583a5cdd'
TAGIFY_UPSTREAM_COMMIT = '759b3c106620bddbd9a59e517af7bdbbfa629905'
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


def build_integrated_v021() -> tuple[bytes, bytes, bytes, bytes]:
    actual = git_blob(INTEGRATED_HEAD, INTEGRATED_PATH)
    if actual != INTEGRATED_BLOB:
        raise RuntimeError(f'integrated v0.2.1 builder drift: {actual} != {INTEGRATED_BLOB}')
    source = git_bytes(INTEGRATED_HEAD, INTEGRATED_PATH)
    namespace = {'__file__': str(INTEGRATED_FAKE), '__name__': 'pinned_integrated_marketplace_v021'}
    exec(compile(source, str(INTEGRATED_FAKE), 'exec'), namespace)
    namespace['build']()
    main = (INTEGRATED_OUT / 'spotify-control.ps1').read_bytes()
    addon = (INTEGRATED_OUT / 'addon-manager.ps1').read_bytes()
    collector = (INTEGRATED_OUT / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (INTEGRATED_OUT / 'LevelDbReadOnly.cs').read_bytes()
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError(f'integrated main drift: {len(main)} {sha(main)}')
    return main, addon, collector, reader


LOCAL_GATE = r'''function Test-LocalSpicetifyUserIntentAllowsMutation {
    param($State,$Item)
    if ($null -eq $Item) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-item-null'; LifecycleKey=$null }
    }
    if (-not $Item.PSObject.Properties['local_lifecycle_identity_required'] -or -not [bool]$Item.local_lifecycle_identity_required) {
        return [pscustomobject]@{ Applicable=$false; Allowed=$true; Reason='not-required'; LifecycleKey=$null }
    }
    $observedAt = if ($Item.PSObject.Properties['local_lifecycle_observed_at']) { ([string]$Item.local_lifecycle_observed_at).Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($observedAt)) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-current-evidence-missing'; LifecycleKey=$null }
    }
    try { $key = Get-AddonLifecycleKey -Kind ([string]$Item.kind) -Name ([string]$Item.name) }
    catch { return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-key-invalid'; LifecycleKey=$null } }
    $State = Normalize-AddonStateObject $State
    if (-not $State.lifecycle.PSObject.Properties[$key]) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-missing'; LifecycleKey=$key }
    }
    $row = $State.lifecycle.PSObject.Properties[$key].Value
    if ($null -eq $row -or [string]$row.managed_by -cne 'dynamic-spicetify-v1') {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-owner-mismatch'; LifecycleKey=$key }
    }
    if ([string]$row.mutation_mode -cne 'deny') {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-authority-drift'; LifecycleKey=$key }
    }
    if (-not [bool]$row.present) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-not-present'; LifecycleKey=$key }
    }
    if ([bool]$row.user_removed) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-user-removed'; LifecycleKey=$key }
    }
    if ([bool]$row.ambiguous -or -not [bool]$row.safe_local_identity) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-ambiguous-or-unsafe'; LifecycleKey=$key }
    }
    if (@($row.locations).Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$row.locations[0])) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-location-invalid'; LifecycleKey=$key }
    }
    if ([string]$row.last_seen -cne $observedAt) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='local-lifecycle-evidence-stale'; LifecycleKey=$key }
    }
    return [pscustomobject]@{ Applicable=$true; Allowed=$true; Reason='current-local-user-intent-confirmed'; LifecycleKey=$key }
}

function Invoke-SourceTopologySelfTest {
    $state=[pscustomobject]@{}
    $obs=[pscustomobject]@{kind='custom-app';name='tagify';ownership='local-spicetify-observed';source_identity=$null;locations=@('C:\\fixture\\CustomApps\\tagify');ambiguous=$false;safe_local_identity=$true}
    [void](Update-AddonLifecycleObservations -State $state -Observations @($obs) -ObservedAt '2026-10-28T01:00:00+00:00')
    $item=[pscustomobject]@{name='tagify';kind='custom-app';policy='auto';installed=$true;source='alexk218/tagify';local_lifecycle_identity_required=$true;local_lifecycle_observed_at='2026-10-28T01:00:00+00:00'}
    $g1=Test-LocalSpicetifyUserIntentAllowsMutation -State $state -Item $item
    if(-not [bool]$g1.Allowed -or [string]$g1.Reason -cne 'current-local-user-intent-confirmed'){throw 'Source topology self-test: current safe Tagify local lifecycle was not accepted.'}
    $stale=[pscustomobject]@{name='tagify';kind='custom-app';policy='auto';installed=$true;source='alexk218/tagify';local_lifecycle_identity_required=$true;local_lifecycle_observed_at='2026-10-28T00:59:00+00:00'}
    if((Test-LocalSpicetifyUserIntentAllowsMutation -State $state -Item $stale).Allowed){throw 'Source topology self-test: stale local lifecycle evidence was accepted.'}
    [void](Update-AddonLifecycleObservations -State $state -Observations @() -ObservedAt '2026-10-28T01:01:00+00:00')
    if((Test-LocalSpicetifyUserIntentAllowsMutation -State $state -Item $item).Allowed){throw 'Source topology self-test: deleted Tagify local lifecycle was accepted.'}
    [void](Update-AddonLifecycleObservations -State $state -Observations @($obs) -ObservedAt '2026-10-28T01:02:00+00:00')
    $reinstalled=[pscustomobject]@{name='tagify';kind='custom-app';policy='auto';installed=$true;source='alexk218/tagify';local_lifecycle_identity_required=$true;local_lifecycle_observed_at='2026-10-28T01:02:00+00:00'}
    if(-not (Test-LocalSpicetifyUserIntentAllowsMutation -State $state -Item $reinstalled).Allowed){throw 'Source topology self-test: explicit Tagify reinstall was not accepted.'}
    $unsafeState=[pscustomobject]@{}
    $unsafe=[pscustomobject]@{kind='custom-app';name='tagify';ownership='local-spicetify-observed';source_identity=$null;locations=@('C:\\a','C:\\b');ambiguous=$true;safe_local_identity=$false}
    [void](Update-AddonLifecycleObservations -State $unsafeState -Observations @($unsafe) -ObservedAt '2026-10-28T01:03:00+00:00')
    $unsafeItem=[pscustomobject]@{name='tagify';kind='custom-app';policy='auto';installed=$true;source='alexk218/tagify';local_lifecycle_identity_required=$true;local_lifecycle_observed_at='2026-10-28T01:03:00+00:00'}
    if((Test-LocalSpicetifyUserIntentAllowsMutation -State $unsafeState -Item $unsafeItem).Allowed){throw 'Source topology self-test: ambiguous local identity was accepted.'}
    $plain=[pscustomobject]@{name='playlist-maker';kind='custom-app';policy='auto';installed=$true;source='Pithaya/spicetify-apps-dist'}
    $plainGate=Test-LocalSpicetifyUserIntentAllowsMutation -State $unsafeState -Item $plain
    if(-not [bool]$plainGate.Allowed -or [bool]$plainGate.Applicable){throw 'Source topology self-test: unrelated managed app was unexpectedly gated.'}
    Write-AddonLog 'Source topology self-test passed: Tagify uses fresh local CustomApps lifecycle evidence; deletion, stale evidence, and ambiguity fail closed.'
}'''


def patch_source_topology(addon: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    text = addon[len(bom):].decode('utf-8')

    marker = 'function Invoke-MarketplaceIntegratedEngineSelfTest {'
    if text.count(marker) != 1:
        raise RuntimeError('source-topology helper insertion anchor drift')
    text = text.replace(marker, LOCAL_GATE + '\n\n' + marker, 1)

    inventory = block(text, 'Get-AddonInventory')
    lifecycle_line = '    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now'
    lifecycle_saved = lifecycle_line + '\n    Save-AddonState $state'
    inventory = replace_once(inventory, lifecycle_line, lifecycle_saved, 'persist current local lifecycle evidence')
    marketplace_fields = "marketplace_identity_required=$true;marketplace_identity_evidence_conclusive=[bool]$marketplaceLifecycle.conclusive;marketplace_identity_fingerprint=$(if([bool]$marketplaceLifecycle.conclusive){[string]$marketplaceLifecycle.report_fingerprint}else{$null});"
    if inventory.count(marketplace_fields) != 2:
        raise RuntimeError(f'Tagify Marketplace-coupling field count drift: {inventory.count(marketplace_fields)}')
    inventory = inventory.replace(marketplace_fields, "local_lifecycle_identity_required=$true;local_lifecycle_observed_at=$now;")
    text = replace_func(text, 'Get-AddonInventory', inventory)

    authorization = block(text, 'Get-AddonMutationAuthorization')
    marketplace_gate = "    if ($Item.PSObject.Properties['marketplace_identity_required'] -and [bool]$Item.marketplace_identity_required) {"
    local_gate = """    if ($Item.PSObject.Properties['local_lifecycle_identity_required'] -and [bool]$Item.local_lifecycle_identity_required) {
        $localGate = Test-LocalSpicetifyUserIntentAllowsMutation -State (Load-AddonState) -Item $Item
        if (-not [bool]$localGate.Allowed) {
            return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason=[string]$localGate.Reason; Entry=$entry; RegistrySha256=$fingerprint }
        }
    }
""" + marketplace_gate
    authorization = replace_once(authorization, marketplace_gate, local_gate, 'local lifecycle mutation gate')
    text = replace_func(text, 'Get-AddonMutationAuthorization', authorization)

    schedule = block(text, 'Get-DiscoveredActionableAutoUpdateCount')
    old_requirement = "if (-not $item.PSObject.Properties['marketplace_identity_required'] -or -not [bool]$item.marketplace_identity_required) { continue }"
    new_requirement = "if (-not $item.PSObject.Properties['local_lifecycle_identity_required'] -or -not [bool]$item.local_lifecycle_identity_required) { continue }"
    schedule = replace_once(schedule, old_requirement, new_requirement, 'Tagify schedule local lifecycle requirement')
    text = replace_func(text, 'Get-DiscoveredActionableAutoUpdateCount', schedule)

    selftest = block(text, 'Invoke-AddonSelfTest')
    old_fixture = "marketplace_identity_required=$true; marketplace_identity_evidence_conclusive=$false; marketplace_identity_fingerprint=$null"
    if selftest.count(old_fixture) != 2:
        raise RuntimeError(f'Tagify self-test Marketplace fixture count drift: {selftest.count(old_fixture)}')
    selftest = selftest.replace(old_fixture, "local_lifecycle_identity_required=$true; local_lifecycle_observed_at=$null")
    selftest = selftest.replace('Tagify without current conclusive Marketplace evidence escaped schedule-bypass fail-closed behavior.', 'Tagify without current local lifecycle evidence escaped schedule-bypass fail-closed behavior.')
    selftest = selftest.replace('Mixed pending schedule-bypass fixture did not fail closed for Tagify without current Marketplace evidence.', 'Mixed pending schedule-bypass fixture did not fail closed for Tagify without current local lifecycle evidence.')
    marketplace_test_line = '    try { Invoke-MarketplaceIntegratedEngineSelfTest } catch { $errors.Add("Marketplace integrated engine self-test failed: $($_.Exception.Message)") }'
    topology_test_line = marketplace_test_line + '\n    try { Invoke-SourceTopologySelfTest } catch { $errors.Add("Source topology self-test failed: $($_.Exception.Message)") }'
    selftest = replace_once(selftest, marketplace_test_line, topology_test_line, 'source topology self-test hook')
    text = replace_func(text, 'Invoke-AddonSelfTest', selftest)

    return bom + text.encode('utf-8')


def validate(main: bytes, addon: bytes, collector: bytes, reader: bytes) -> dict:
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError('source-topology candidate changed validated Spotify Control bytes')
    text = addon.decode('utf-8-sig').replace('\r\n', '\n')
    registry = block(text, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED):
        raise RuntimeError(f'auto authority drift: {auto}')
    inventory = block(text, 'Get-AddonInventory')
    auth = block(text, 'Get-AddonMutationAuthorization')
    schedule = block(text, 'Get-DiscoveredActionableAutoUpdateCount')
    if 'local_lifecycle_identity_required=$true' not in inventory or 'local_lifecycle_observed_at=$now' not in inventory:
        raise RuntimeError('Tagify inventory is not bound to current local lifecycle evidence')
    if 'marketplace_identity_required=$true' in inventory:
        raise RuntimeError('Tagify inventory remains incorrectly coupled to Marketplace record evidence')
    if 'Save-AddonState $state' not in inventory:
        raise RuntimeError('current local lifecycle evidence is not persisted before authorization')
    if 'Test-LocalSpicetifyUserIntentAllowsMutation' not in auth or 'Test-MarketplaceSourceUserIntentAllowsMutation' not in auth:
        raise RuntimeError('authorization does not preserve both local and Marketplace user-intent gates')
    if "local_lifecycle_identity_required']" not in schedule:
        raise RuntimeError('Tagify schedule path does not require local lifecycle identity')
    for marker in (
        'function Test-LocalSpicetifyUserIntentAllowsMutation', 'function Invoke-SourceTopologySelfTest',
        "Reason='local-lifecycle-evidence-stale'", "Reason='local-lifecycle-user-removed'",
        "Reason='local-lifecycle-ambiguous-or-unsafe'", "managed_by -cne 'dynamic-spicetify-v1'",
        'function Update-MarketplaceIdentityLifecycleLedger', "mutation_mode','deny'",
        'New-RequiredSpotifyPersistenceBackup', 'Restore-SpotifyPersistenceBackup',
        "protected_state_policy='must-remain-byte-identical-through-apply'"
    ):
        if marker not in text:
            raise RuntimeError(f'missing source-topology safety marker: {marker}')
    for marker in (
        "name='splitify'", "name='star-ratings'", 'playlist-backed-ratings-preserve',
        "name='sc-cover-ambience.js'", 'never-disable-or-optimize', "name='tagify'",
        "source='alexk218/tagify'", "install_mode='installed-only'", 'preserve-ratings-tags-notes-and-browser-storage'
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected registry policy missing: {marker}')
    return {
        'auto_authority': AUTHORIZED,
        'generic_marketplace_mutation_authority_expanded': False,
        'marketplace_record_kinds': ['extension', 'theme', 'snippet'],
        'custom_app_identity_surface': 'dynamic-spicetify-local-lifecycle',
        'tagify_identity_gate': 'fresh-safe-local-custom-app-lifecycle-plus-exact-registry-source',
        'production_surface_changed': False,
        'collector_sha256': sha(collector),
        'reader_sha256': sha(reader),
    }


def build() -> None:
    main, integrated_addon, collector, reader = build_integrated_v021()
    candidate = patch_source_topology(integrated_addon)
    result = validate(main, candidate, collector, reader)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate)
    (OUT / 'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT / 'LevelDbReadOnly.cs').write_bytes(reader)
    report = {
        'schema': 1,
        'production_base': PRODUCTION_BASE,
        'candidate_version': '0.6.29-validation-source-topology-v0.1.0',
        'validated_integrated_base': {'head': INTEGRATED_HEAD, 'path': INTEGRATED_PATH, 'blob': INTEGRATED_BLOB},
        'marketplace_upstream_commit': MARKETPLACE_UPSTREAM_COMMIT,
        'tagify_upstream_commit': TAGIFY_UPSTREAM_COMMIT,
        'candidate_main': {'size': len(main), 'sha256': sha(main)},
        'candidate_addon': {'size': len(candidate), 'sha256': sha(candidate)},
        'features': [
            'marketplace-extension-theme-snippet-identity-kept-separate-from-custom-app-identity',
            'tagify-current-local-customapp-lifecycle-user-intent-gate',
            'local-lifecycle-deletion-tombstone-and-reinstall-semantics',
            'local-lifecycle-stale-or-ambiguous-evidence-fails-closed',
            'generic-marketplace-ledger-remains-mutation-denied',
            'exact-protected-persistence-transaction-preserved',
        ],
        **result,
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('MARKETPLACE_SOURCE_TOPOLOGY_BUILD_PASS', len(main), sha(main), len(candidate), sha(candidate))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--build', action='store_true')
    args = p.parse_args()
    if not args.build:
        p.error('use --build')
    build()


if __name__ == '__main__':
    main()
