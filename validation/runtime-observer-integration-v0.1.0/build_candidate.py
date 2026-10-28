from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_BASE = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
PARENT_HEAD = '4b7ef73fe416afdfb501173f145994b3ed817e42'
PARENT_PATH = 'validation/marketplace-source-topology-v0.1.0/build_candidate.py'
PARENT_BLOB = '1e32dd57c95f718f2aeaae6149da36762ca7f6fd'
PARENT_OUT = ROOT / 'validation/marketplace-source-topology-v0.1.0/out/bin'
PROVENANCE_HEAD = 'b339f2b79a267c13cf3c5974aea2fff3786d3093'
PROVENANCE_PATH = 'validation/custom-app-provenance-enrollment-v0.1.0/custom-app-provenance.ps1'
PROVENANCE_BLOB = '4f0831fa2e5dc23c9a4ec98b6c7a9afbb3c9af55'
NATIVE_HEAD = '62cc0803411ccd132e3bad3b6338b2ef783e0f4c'
NATIVE_PATH = 'validation/marketplace-native-refresh-contract-v0.1.0/marketplace-native-refresh-contract.ps1'
NATIVE_BLOB = 'bd895ebcc11d9fb2f1c7857ee861e5b9e2c2cc3c'
LOCAL_NATIVE_PATH = 'validation/runtime-observer-integration-v0.1.0/marketplace-native-refresh-contract.ps1'
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


def verify_pins() -> None:
    pins = (
        (PARENT_HEAD, PARENT_PATH, PARENT_BLOB, 'source-topology parent builder'),
        (PROVENANCE_HEAD, PROVENANCE_PATH, PROVENANCE_BLOB, 'custom-app provenance core'),
        (NATIVE_HEAD, NATIVE_PATH, NATIVE_BLOB, 'Marketplace native-refresh contract'),
    )
    for head, path, expected, label in pins:
        actual = git_blob(head, path)
        if actual != expected:
            raise RuntimeError(f'{label} drift: {actual} != {expected}')
    local_native = git_blob('HEAD', LOCAL_NATIVE_PATH)
    if local_native != NATIVE_BLOB:
        raise RuntimeError(f'local native-refresh contract copy drift: {local_native} != {NATIVE_BLOB}')


def build_parent() -> tuple[bytes, bytes, bytes, bytes]:
    source = git_bytes(PARENT_HEAD, PARENT_PATH)
    fake = ROOT / PARENT_PATH
    ns = {'__file__': str(fake), '__name__': 'pinned_source_topology_parent'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()
    main = (PARENT_OUT / 'spotify-control.ps1').read_bytes()
    addon = (PARENT_OUT / 'addon-manager.ps1').read_bytes()
    collector = (PARENT_OUT / 'Collect-Marketplace-Records.ps1').read_bytes()
    reader = (PARENT_OUT / 'LevelDbReadOnly.cs').read_bytes()
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError(f'parent main drift: {len(main)} {sha(main)}')
    return main, addon, collector, reader


OBSERVER_GLUE = r'''function New-CustomAppProvenanceSyntheticEvidence {
    param([string]$Name,[string]$Status,[bool]$RequiresReenrollment=$false)
    $fingerprint=Get-ProvenanceStringSha256Lower (('synthetic|{0}|{1}' -f $Name.ToLowerInvariant(),$Status))
    return [pscustomobject]@{schema=1;name=$Name;path=$null;status=$Status;source_candidate=$null;source_proven=$false;requires_reenrollment=$RequiresReenrollment;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=$fingerprint;git=$null;package=$null}
}

function Update-CustomAppProvenanceFromLifecycleState {
    param($State,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    $State=Normalize-AddonStateObject $State
    [void](Ensure-CustomAppProvenanceLedgerRoot -State $State)
    $processed=0;$proven=0;$reenroll=0;$removed=0
    foreach($prop in @($State.lifecycle.PSObject.Properties)){
        $key=[string]$prop.Name;$row=$prop.Value
        if($null -eq $row -or [string]$row.managed_by -cne 'dynamic-spicetify-v1' -or -not $key.StartsWith('custom-app:',[StringComparison]::OrdinalIgnoreCase)){continue}
        $name=if($row.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$row.name)){[string]$row.name}else{$key.Substring('custom-app:'.Length)}
        $evidence=$null
        if(-not [bool]$row.present -or [bool]$row.user_removed){
            $status=if([bool]$row.user_removed){'user-removed'}else{'lifecycle-absent'}
            $evidence=New-CustomAppProvenanceSyntheticEvidence -Name $name -Status $status
            $removed++
        }elseif([bool]$row.ambiguous -or -not [bool]$row.safe_local_identity -or @($row.locations).Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$row.locations[0])){
            $evidence=New-CustomAppProvenanceSyntheticEvidence -Name $name -Status 'unsafe-local-lifecycle' -RequiresReenrollment $true
        }else{
            try{$evidence=Get-CustomAppLocalProvenanceEvidence -Name $name -AppPath ([string]$row.locations[0])}
            catch{$evidence=New-CustomAppProvenanceSyntheticEvidence -Name $name -Status ('provenance-read-failed:'+([string]$_.Exception.GetType().Name)) -RequiresReenrollment $true}
        }
        $ledgerRow=Update-CustomAppProvenanceEnrollment -State $State -Evidence $evidence -ObservedAt $ObservedAt
        if(Test-CustomAppProvenanceMutationAuthority -Row $ledgerRow){throw ('Custom App provenance authority drift: '+$key)}
        if(-not [string]::IsNullOrWhiteSpace([string]$ledgerRow.source_identity)){$proven++}
        if([bool]$ledgerRow.requires_reenrollment){$reenroll++}
        $processed++
    }
    return [pscustomobject]@{schema=1;observed_at=$ObservedAt;processed_count=$processed;active_proven_count=$proven;requires_reenrollment_count=$reenroll;removed_count=$removed;mutation_authority_granted=$false}
}

function Ensure-MarketplaceNativeRefreshLedgerRoot {
    param($State)
    if(-not $State.PSObject.Properties['marketplace_native_refresh']){$State|Add-Member -NotePropertyName marketplace_native_refresh -NotePropertyValue ([pscustomobject]@{})}
    if($null -eq $State.marketplace_native_refresh){$State.marketplace_native_refresh=[pscustomobject]@{}}
    return $State.marketplace_native_refresh
}

function Update-MarketplaceNativeRefreshStateFromReport {
    param($State,$MarketplaceReport,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    if($null -eq $MarketplaceReport -or [string]$MarketplaceReport.status -cne 'ok' -or $MarketplaceReport.read_only -ne $true -or $MarketplaceReport.mutation_performed -ne $false){
        return [pscustomobject]@{schema=1;conclusive=$false;state_changed=$false;observed_at=$ObservedAt;record_count=0;classified_count=0;inconclusive_count=0;mutation_authority_granted=$false;reason='marketplace-report-inconclusive'}
    }
    $prepared=New-Object System.Collections.Generic.List[object]
    foreach($record in @($MarketplaceReport.records)){
        if($null -eq $record -or -not $record.PSObject.Properties['key'] -or [string]::IsNullOrWhiteSpace([string]$record.key)){
            return [pscustomobject]@{schema=1;conclusive=$false;state_changed=$false;observed_at=$ObservedAt;record_count=@($MarketplaceReport.records).Count;classified_count=0;inconclusive_count=0;mutation_authority_granted=$false;reason='marketplace-record-key-invalid'}
        }
        $decision=Resolve-MarketplaceNativeRefreshContract -Record $record
        if([bool]$decision.addon_manager_direct_mutation_allowed){throw ('Marketplace native-refresh direct mutation authority drift: '+[string]$record.key)}
        $prepared.Add([pscustomobject]@{key=[string]$record.key;record=$record;decision=$decision})
    }
    $root=Ensure-MarketplaceNativeRefreshLedgerRoot -State $State
    $fingerprint=if($MarketplaceReport.PSObject.Properties['identity_fingerprint']){[string]$MarketplaceReport.identity_fingerprint}else{$null}
    foreach($prop in @($root.PSObject.Properties)){
        $old=$prop.Value
        if($null -eq $old -or [string]$old.managed_by -cne 'marketplace-native-refresh-v1'){continue}
        $old.present=$false;$old.last_absent=$ObservedAt;$old.last_report_fingerprint=$fingerprint;$old.mutation_mode='deny';$old.auto_update_authorized=$false;$old.auto_install_authorized=$false
    }
    $classified=0;$inconclusive=0
    foreach($entry in @($prepared.ToArray())){
        $key=[string]$entry.key;$record=$entry.record;$d=$entry.decision
        if(-not $root.PSObject.Properties[$key]){$root|Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{schema=1;key=$key;managed_by='marketplace-native-refresh-v1';first_seen=$ObservedAt})}
        $row=$root.PSObject.Properties[$key].Value
        foreach($pair in @(
            @('schema',1),@('key',$key),@('managed_by','marketplace-native-refresh-v1'),@('kind',[string]$d.kind),@('owner',[string]$d.owner),
            @('present',$true),@('last_seen',$ObservedAt),@('last_absent',$null),@('last_report_fingerprint',$fingerprint),@('conclusive',[bool]$d.conclusive),
            @('runtime_refresh',[string]$d.runtime_refresh),@('metadata_refresh',[string]$d.metadata_refresh),@('stored_state_refresh',[string]$d.stored_state_refresh),
            @('automatic_runtime_content_refresh',[bool]$d.automatic_runtime_content_refresh),@('full_installed_record_refresh_guaranteed',[bool]$d.full_installed_record_refresh_guaranteed),
            @('reason',[string]$d.reason),@('mutation_mode','deny'),@('auto_update_authorized',$false),@('auto_install_authorized',$false)
        )){
            $n=[string]$pair[0];$v=$pair[1]
            if($row.PSObject.Properties[$n]){$row.PSObject.Properties[$n].Value=$v}else{$row|Add-Member -NotePropertyName $n -NotePropertyValue $v}
        }
        if([bool]$d.conclusive){$classified++}else{$inconclusive++}
    }
    return [pscustomobject]@{schema=1;conclusive=$true;state_changed=$true;observed_at=$ObservedAt;record_count=$prepared.Count;classified_count=$classified;inconclusive_count=$inconclusive;mutation_authority_granted=$false;reason='observer-state-updated'}
}

function Invoke-RuntimeObserverIntegrationSelfTest {
    Invoke-MarketplaceNativeRefreshContractSelfTest
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('spotify-control-provenance-'+[guid]::NewGuid().ToString('N'))
    try{
        $app=Join-Path $temp 'future-app';New-Item -ItemType Directory -Force -Path (Join-Path $app '.git')|Out-Null
        @('[remote "origin"]','    url = https://github.com/Example/Future-App.git')|Set-Content -LiteralPath (Join-Path $app '.git\config') -Encoding UTF8
        '{"repository":"https://github.com/example/future-app"}'|Set-Content -LiteralPath (Join-Path $app 'package.json') -Encoding UTF8
        $state=[pscustomobject]@{}
        $obs=[pscustomobject]@{kind='custom-app';name='future-app';ownership='local-spicetify-observed';source_identity=$null;locations=@($app);ambiguous=$false;safe_local_identity=$true}
        [void](Update-AddonLifecycleObservations -State $state -Observations @($obs) -ObservedAt '2026-10-28T08:00:00+00:00')
        $s1=Update-CustomAppProvenanceFromLifecycleState -State $state -ObservedAt '2026-10-28T08:00:00+00:00'
        $p=$state.custom_app_provenance.PSObject.Properties['custom-app:future-app'].Value
        if([string]$p.source_identity -cne 'example/future-app' -or [string]$p.mutation_mode -cne 'deny' -or [bool]$p.auto_update_authorized -or [bool]$p.auto_install_authorized -or [int]$s1.active_proven_count -ne 1){throw 'Runtime observer self-test: strong Custom App provenance was not enrolled deny-only.'}
        @('[remote "origin"]','    url = https://github.com/Example/Other-App.git')|Set-Content -LiteralPath (Join-Path $app '.git\config') -Encoding UTF8
        $s2=Update-CustomAppProvenanceFromLifecycleState -State $state -ObservedAt '2026-10-28T08:01:00+00:00'
        if([string]$p.source_status -cne 'source-change-blocked' -or $null -ne $p.source_identity -or -not [bool]$p.requires_reenrollment -or [int]$s2.requires_reenrollment_count -lt 1){throw 'Runtime observer self-test: Custom App source swap was not blocked.'}
        [void](Update-AddonLifecycleObservations -State $state -Observations @() -ObservedAt '2026-10-28T08:02:00+00:00')
        [void](Update-CustomAppProvenanceFromLifecycleState -State $state -ObservedAt '2026-10-28T08:02:00+00:00')
        if([string]$p.source_status -cne 'user-removed' -or $null -ne $p.source_identity){throw 'Runtime observer self-test: deletion tombstone did not clear active provenance.'}

        $mstate=[pscustomobject]@{}
        $records=@(
            [pscustomobject]@{key='marketplace:extension:owner/repo/a.js';kind='extension';source_kind='github-repository-key';ambiguous=$false;mutation_authorized=$false},
            [pscustomobject]@{key='marketplace:theme:owner/theme/theme.css';kind='theme';source_kind='github-repository-key';ambiguous=$false;mutation_authorized=$false},
            [pscustomobject]@{key='marketplace:snippet:abc';kind='snippet';source_kind='snippet-key';ambiguous=$false;mutation_authorized=$false},
            [pscustomobject]@{key='marketplace:unlisted:x';kind='unlisted';source_kind='github-repository-key';ambiguous=$false;mutation_authorized=$false}
        )
        $report=[pscustomobject]@{status='ok';read_only=$true;mutation_performed=$false;identity_fingerprint=('a'*64);records=$records}
        $ms=Update-MarketplaceNativeRefreshStateFromReport -State $mstate -MarketplaceReport $report -ObservedAt '2026-10-28T08:03:00+00:00'
        if(-not [bool]$ms.conclusive -or [int]$ms.record_count -ne 4 -or [bool]$ms.mutation_authority_granted){throw 'Runtime observer self-test: Marketplace refresh observer summary drift.'}
        foreach($prop in @($mstate.marketplace_native_refresh.PSObject.Properties)){
            $r=$prop.Value
            if([string]$r.mutation_mode -cne 'deny' -or [bool]$r.auto_update_authorized -or [bool]$r.auto_install_authorized){throw 'Runtime observer self-test: Marketplace refresh ledger gained mutation authority.'}
        }
        $ext=$mstate.marketplace_native_refresh.PSObject.Properties['marketplace:extension:owner/repo/a.js'].Value
        $sn=$mstate.marketplace_native_refresh.PSObject.Properties['marketplace:snippet:abc'].Value
        if(-not [bool]$ext.automatic_runtime_content_refresh -or [bool]$ext.full_installed_record_refresh_guaranteed -or [bool]$sn.automatic_runtime_content_refresh){throw 'Runtime observer self-test: Marketplace native-refresh semantics drift.'}
    }finally{
        if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
    }
    Write-AddonLog 'Runtime observer integration self-test passed: provenance enrollment/source-change/deletion and Marketplace refresh ownership remain observer-only.'
}'''


def integrate(addon: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    text = addon[len(bom):].decode('utf-8')
    provenance = git_bytes(PROVENANCE_HEAD, PROVENANCE_PATH).decode('utf-8').strip()
    native = git_bytes(NATIVE_HEAD, NATIVE_PATH).decode('utf-8').strip()
    anchor = 'function Get-AddonInventory {'
    if text.count(anchor) != 1:
        raise RuntimeError('runtime observer insertion anchor drift')
    text = text.replace(anchor, provenance + '\n\n' + native + '\n\n' + OBSERVER_GLUE + '\n\n' + anchor, 1)

    inventory = block(text, 'Get-AddonInventory')
    old = '    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now\n    Save-AddonState $state'
    new = '''    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now
    $customAppProvenanceSummary=Update-CustomAppProvenanceFromLifecycleState -State $state -ObservedAt $now
    $marketplaceNativeRefreshSummary=Update-MarketplaceNativeRefreshStateFromReport -State $state -MarketplaceReport $marketplaceReport -ObservedAt $now
    Save-AddonState $state'''
    inventory = replace_once(inventory, old, new, 'inventory observer state update')
    report_anchor = '        marketplace_lifecycle = $marketplaceLifecycle\n'
    report_new = report_anchor + '        custom_app_provenance = $customAppProvenanceSummary\n        marketplace_native_refresh = $marketplaceNativeRefreshSummary\n'
    inventory = replace_once(inventory, report_anchor, report_new, 'inventory observer report fields')
    text = replace_func(text, 'Get-AddonInventory', inventory)

    selftest = block(text, 'Invoke-AddonSelfTest')
    parent_hook = '    try { Invoke-SourceTopologySelfTest } catch { $errors.Add("Source topology self-test failed: $($_.Exception.Message)") }'
    observer_hook = parent_hook + '\n    try { Invoke-RuntimeObserverIntegrationSelfTest } catch { $errors.Add("Runtime observer integration self-test failed: $($_.Exception.Message)") }'
    selftest = replace_once(selftest, parent_hook, observer_hook, 'runtime observer self-test hook')
    text = replace_func(text, 'Invoke-AddonSelfTest', selftest)
    return bom + text.encode('utf-8')


def validate(main: bytes, addon: bytes, collector: bytes, reader: bytes) -> dict:
    if (len(main), sha(main)) != EXPECTED_MAIN:
        raise RuntimeError('runtime observer candidate changed validated Spotify Control bytes')
    text = addon.decode('utf-8-sig').replace('\r\n','\n')
    registry = block(text, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED):
        raise RuntimeError(f'auto authority drift: {auto}')
    required = (
        'function Update-CustomAppProvenanceFromLifecycleState',
        'function Update-MarketplaceNativeRefreshStateFromReport',
        'function Invoke-RuntimeObserverIntegrationSelfTest',
        "managed_by='custom-app-provenance-v1'",
        "managed_by='marketplace-native-refresh-v1'",
        "mutation_mode='deny'",
        'auto_update_authorized=$false',
        'auto_install_authorized=$false',
        'source-change-blocked',
        'marketplace_native_refresh',
        'custom_app_provenance',
        'New-RequiredSpotifyPersistenceBackup',
        'Restore-SpotifyPersistenceBackup',
        "protected_state_policy='must-remain-byte-identical-through-apply'",
        "name='star-ratings'",
        'playlist-backed-ratings-preserve',
        "name='sc-cover-ambience.js'",
        'never-disable-or-optimize',
        "name='splitify'",
        "name='tagify'",
        "source='alexk218/tagify'",
    )
    for marker in required:
        if marker.lower() not in text.lower():
            raise RuntimeError(f'missing runtime observer safety marker: {marker}')
    if text.count('Invoke-RuntimeObserverIntegrationSelfTest') < 2:
        raise RuntimeError('runtime observer self-test is not hooked into Addon Manager SelfTest')
    return {
        'auto_authority': AUTHORIZED,
        'custom_app_provenance_authority_expanded': False,
        'marketplace_direct_mutation_authority_expanded': False,
        'production_surface_changed': False,
        'collector_sha256': sha(collector),
        'reader_sha256': sha(reader),
    }


def build() -> None:
    verify_pins()
    main, parent_addon, collector, reader = build_parent()
    candidate = integrate(parent_addon)
    result = validate(main, candidate, collector, reader)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate)
    (OUT / 'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT / 'LevelDbReadOnly.cs').write_bytes(reader)
    report = {
        'schema': 1,
        'production_base': PRODUCTION_BASE,
        'candidate_version': '0.6.29-validation-runtime-observers-v0.1.0',
        'validated_source_topology_parent': {'head': PARENT_HEAD, 'path': PARENT_PATH, 'blob': PARENT_BLOB},
        'validated_custom_app_provenance': {'head': PROVENANCE_HEAD, 'path': PROVENANCE_PATH, 'blob': PROVENANCE_BLOB},
        'validated_marketplace_native_refresh': {'head': NATIVE_HEAD, 'path': NATIVE_PATH, 'blob': NATIVE_BLOB},
        'candidate_main': {'size': len(main), 'sha256': sha(main)},
        'candidate_addon': {'size': len(candidate), 'sha256': sha(candidate)},
        'features': [
            'runtime-custom-app-provenance-ledger-observer-only',
            'runtime-marketplace-native-refresh-ledger-observer-only',
            'source-change-and-user-removal-fail-closed',
            'generic-unknown-custom-app-remains-mutation-denied',
            'marketplace-extension-theme-snippet-direct-mutation-remains-denied',
            'existing-settings-and-persistence-transaction-guards-preserved',
        ],
        **result,
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('RUNTIME_OBSERVER_INTEGRATION_BUILD_PASS', len(main), sha(main), len(candidate), sha(candidate))


def main() -> None:
    p=argparse.ArgumentParser();p.add_argument('--build',action='store_true');args=p.parse_args()
    if not args.build:p.error('use --build')
    build()


if __name__ == '__main__':
    main()
