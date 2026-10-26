from pathlib import Path
import hashlib, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.22/out/bin'
OUT = ROOT / 'validation/splitify-source-monitor-v0.2.0/out/bin'
REPORT = ROOT / 'validation/splitify-source-monitor-v0.2.0/candidate-report.json'

BASE_MAIN_SHA = 'b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe'
BASE_MAIN_SIZE = 281586
BASE_ADDON_SHA = '0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc'
BASE_ADDON_SIZE = 268670
PRIOR_R11_REGISTRY_SHA = '05c40a5339fe59b001ca0f4c4929643fd59e33a3002bae7067425845c85e2f6e'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


def function_block(text: str, name: str) -> str:
    marker = f'function {name} {{'
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f'missing function {name}')
    nxt = text.find('\nfunction ', start + len(marker))
    if nxt < 0:
        nxt = len(text)
    return text[start:nxt]


def prepare_base():
    subprocess.check_call([sys.executable, str(ROOT / 'validation/v0.6.22/build_v0622.py'), '--build'], cwd=ROOT)
    main = (BASE_OUT / 'spotify-control.ps1').read_bytes()
    addon = (BASE_OUT / 'addon-manager.ps1').read_bytes()
    assert (len(main), sha(main)) == (BASE_MAIN_SIZE, BASE_MAIN_SHA), (len(main), sha(main))
    assert (len(addon), sha(addon)) == (BASE_ADDON_SIZE, BASE_ADDON_SHA), (len(addon), sha(addon))
    return main, addon


def build_main(base: bytes) -> bytes:
    assert base.startswith(b'\xef\xbb\xbf')
    body = base[3:]
    assert b'\r\n' not in body
    text = body.decode('ascii')
    text = replace_once(text, '# Spotify Control v0.6.22 Addon Source Registry r11\n', '# Spotify Control v0.6.23 Splitify Source Monitor r12\n', 'main title')
    text = replace_once(text, '$ScriptVersion = "0.6.22"\n', '$ScriptVersion = "0.6.23"\n', 'main version')
    return b'\xef\xbb\xbf' + text.encode('ascii')


def build_addon(base: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text = base[len(bom):].decode('utf-8')
    crlf = text.count('\r\n')
    lf = text.count('\n')
    newline = '\r\n' if crlf and crlf == lf else '\n'
    if newline == '\n':
        assert '\r\n' not in text

    text = replace_once(text, '$Version = "0.6.5-r11"', '$Version = "0.6.5-r12"', 'addon version')

    old_registry = "[pscustomobject]@{ name='splitify'; kind='custom-app'; source=$null; inventory_policy='unknown-source'; mutation_mode='deny'; handler='none'; install_mode='never-auto-install'; version_strategy='unresolved-source'; rollback_strategy='none'; data_policy='preserve-unknown-source' }"
    new_registry = "[pscustomobject]@{ name='splitify'; kind='custom-app'; source='alexander-rebello/splitify'; inventory_policy='monitor-only'; mutation_mode='deny'; handler='none'; install_mode='never-auto-install'; version_strategy='semver-release-monitor'; rollback_strategy='none'; data_policy='preserve-installed-content' }"
    text = replace_once(text, old_registry, new_registry, 'Splitify registry source identification')

    text = replace_once(
        text,
        "[pscustomobject]@{name='splitify';kind='custom-app';policy='unknown-source';source=$null;installed=$true}",
        "[pscustomobject]@{name='splitify';kind='custom-app';policy='monitor-only';source='alexander-rebello/splitify';installed=$true}",
        'Splitify denied fixture',
    )
    text = replace_once(
        text,
        "if([string]$split.source -ne '' -or [string]$split.mutation_mode -cne 'deny'){throw 'Splitify unknown-source fail-closed policy changed.'}",
        "if([string]$split.source -cne 'alexander-rebello/splitify' -or [string]$split.inventory_policy -cne 'monitor-only' -or [string]$split.mutation_mode -cne 'deny' -or [string]$split.data_policy -cne 'preserve-installed-content'){throw 'Splitify monitor-only preservation policy changed.'}",
        'Splitify policy self-test',
    )

    old_contract = """        'github-release-monitor-v1' {\n            if([string]$Entry.source -cne 'alexk218/tagify' -or [string]$Entry.mutation_mode -cne 'deny' -or [string]$Entry.inventory_policy -cne 'monitor-only'){ throw \"Release-monitor adapter contract mismatch for $name.\" }\n        }""".replace('\n', newline)
    new_contract = """        'github-release-monitor-v1' {\n            $allowedReleaseMonitorSources=@('alexk218/tagify','alexander-rebello/splitify')\n            if($allowedReleaseMonitorSources -cnotcontains [string]$Entry.source -or [string]$Entry.mutation_mode -cne 'deny' -or [string]$Entry.inventory_policy -cne 'monitor-only'){ throw \"Release-monitor adapter contract mismatch for $name.\" }\n        }""".replace('\n', newline)
    text = replace_once(text, old_contract, new_contract, 'release-monitor source allowlist')

    old_inventory = """    # Unknown local app remains untouched. Resolve both roots only to report safely.\n    $splitifyResolution = Resolve-SpicetifyAsset -Name \"splitify\" -Kind \"CustomApp\" -Roots $customAppRoots\n    if ($splitifyResolution.status -ne \"absent\") {\n        $items.Add([pscustomobject]@{\n            name=\"splitify\"; kind=\"custom-app\"; policy=\"unknown-source\"\n            installed=$(if($splitifyResolution.status -eq \"resolved\"){$true}else{$null})\n            local=$null; remote=$null; revision=$null\n            status=$(if($splitifyResolution.status -eq \"ambiguous\"){\"manual-source-identification-required-ambiguous\"}else{\"manual-source-identification-required\"})\n            source=$null; download=$null; digest=$null\n            resolution_status=$splitifyResolution.status; install_path=$splitifyResolution.selected_path; locations=@($splitifyResolution.locations)\n        })\n    }""".replace('\n', newline)
    new_inventory = """    # Splitify - source identified, but still strictly monitor-only.\n    # Upstream release metadata is observed read-only; installed release provenance is not inferred from manifest.json\n    # because upstream v1.1.0 still declares manifest version 1.0.0. No Splitify mutation/install path exists here.\n    try {\n        $splitifyResolution = Resolve-SpicetifyAsset -Name \"splitify\" -Kind \"CustomApp\" -Roots $customAppRoots\n        if ($splitifyResolution.status -ne \"absent\") {\n            $splitifyRelease = Invoke-GitHubJson \"https://api.github.com/repos/alexander-rebello/splitify/releases/latest\"\n            $splitifyAssets = @($splitifyRelease.assets | Where-Object { [string]$_.name -ceq \"splitify.zip\" })\n            if ($splitifyAssets.Count -ne 1) { throw \"Splitify latest release must expose exactly one splitify.zip asset.\" }\n            $splitifyAsset = $splitifyAssets[0]\n            if ([string]$splitifyAsset.digest -notmatch '^sha256:[0-9a-f]{64}$') { throw \"Splitify release asset does not expose a GitHub SHA-256 digest.\" }\n            $splitifyRemote = ([string]$splitifyRelease.tag_name).TrimStart(\"v\")\n            $splitifyStatus = if ($splitifyResolution.status -eq \"ambiguous\") { \"monitor-ambiguous-installation\" } else { \"monitor-local-release-unproven\" }\n            $items.Add([pscustomobject]@{\n                name=\"splitify\"; kind=\"custom-app\"; policy=\"monitor-only\"\n                installed=$(if($splitifyResolution.status -eq \"resolved\"){$true}else{$null})\n                local=$null; remote=$splitifyRemote; revision=[string]$splitifyRelease.tag_name; status=$splitifyStatus\n                source=\"alexander-rebello/splitify\"; download=[string]$splitifyAsset.browser_download_url; digest=[string]$splitifyAsset.digest; asset_size=[int64]$splitifyAsset.size\n                note=\"Official source/release is identified and monitored, but the installed release provenance is not yet proven; automatic update/install remains denied.\"\n                resolution_status=$splitifyResolution.status; install_path=$splitifyResolution.selected_path; locations=@($splitifyResolution.locations)\n            })\n        }\n    } catch {\n        $items.Add([pscustomobject]@{\n            name=\"splitify\"; kind=\"custom-app\"; policy=\"monitor-only\"; installed=$null\n            local=$null; remote=$null; revision=$null; status=\"check-error\"\n            source=\"alexander-rebello/splitify\"; download=$null; digest=$null; asset_size=[int64]0; error=$_.Exception.Message\n            note=\"Splitify remains untouched because source monitoring failed closed.\"\n            resolution_status=$null; install_path=$null; locations=@()\n        })\n    }""".replace('\n', newline)
    text = replace_once(text, old_inventory, new_inventory, 'Splitify monitor-only inventory')

    old_guard = """    $currentRegistrySha = Get-AddonPolicyRegistryFingerprint\n    if ($registrySha -cne $currentRegistrySha) { throw \"Addon policy registry changed since transaction preparation; refusing commit. transaction=$registrySha current=$currentRegistrySha\" }""".replace('\n', newline)
    new_guard = f"""    $currentRegistrySha = Get-AddonPolicyRegistryFingerprint\n    $compatiblePriorRegistryShas=@('{PRIOR_R11_REGISTRY_SHA}')\n    $registryMode='registry-v1-authorized'\n    if ($registrySha -cne $currentRegistrySha) {{\n        if ($compatiblePriorRegistryShas -cnotcontains $registrySha) {{ throw \"Addon policy registry changed since transaction preparation; refusing commit. transaction=$registrySha current=$currentRegistrySha\" }}\n        $registryMode='registry-v1-compatible-prior'\n    }}""".replace('\n', newline)
    text = replace_once(text, old_guard, new_guard, 'prior registry compatibility gate')
    text = replace_once(text, "    return 'registry-v1-authorized'", "    return $registryMode", 'registry authorization mode')

    current_fixture = """    if((Assert-AddonTransactionRegistryAuthorization -Tx $current) -cne 'registry-v1-authorized'){throw 'Current registry transaction fixture failed.'}\n\n    $badSha=""".replace('\n', newline)
    compatibility_fixture = f"""    if((Assert-AddonTransactionRegistryAuthorization -Tx $current) -cne 'registry-v1-authorized'){{throw 'Current registry transaction fixture failed.'}}\n    if($sha -ceq '{PRIOR_R11_REGISTRY_SHA}'){{throw 'Splitify source identification did not change the policy registry fingerprint.'}}\n    $prior=[pscustomobject]@{{schema=2;registry_schema=1;registry_sha256='{PRIOR_R11_REGISTRY_SHA}';changes=$current.changes}}\n    if((Assert-AddonTransactionRegistryAuthorization -Tx $prior) -cne 'registry-v1-compatible-prior'){{throw 'r11 registry transaction compatibility fixture failed.'}}\n\n    $badSha=""".replace('\n', newline)
    text = replace_once(text, current_fixture, compatibility_fixture, 'registry compatibility self-test')

    old_source_guard = """    $currentSha=Get-AddonSourceAdapterFingerprint\n    if([string]$Tx.source_adapter_sha256 -cne $currentSha){ throw 'Source-adapter catalog drifted since transaction creation.' }\n    foreach($change in @($Tx.changes)){""".replace('\n', newline)
    new_source_guard = f"""    $currentSha=Get-AddonSourceAdapterFingerprint\n    if([string]$Tx.source_adapter_sha256 -cne $currentSha){{ throw 'Source-adapter catalog drifted since transaction creation.' }}\n    $currentRegistrySha=Get-AddonPolicyRegistryFingerprint\n    $txRegistrySha=[string]$Tx.registry_sha256\n    $compatiblePriorRegistryShas=@('{PRIOR_R11_REGISTRY_SHA}')\n    $priorRegistryCompatible=($txRegistrySha -cne $currentRegistrySha -and $compatiblePriorRegistryShas -ccontains $txRegistrySha)\n    if($txRegistrySha -cne $currentRegistrySha -and -not $priorRegistryCompatible){{ throw 'Source-adapter transaction registry fingerprint is neither current nor an explicitly compatible prior registry.' }}\n    foreach($change in @($Tx.changes)){{""".replace('\n', newline)
    text = replace_once(text, old_source_guard, new_source_guard, 'source adapter prior-registry compatibility')
    text = replace_once(
        text,
        "registry_sha256=[string]$Tx.registry_sha256; mutation_handler=[string]$change.registry_handler",
        "registry_sha256=$(if($priorRegistryCompatible){$currentRegistrySha}else{[string]$Tx.registry_sha256}); mutation_handler=[string]$change.registry_handler",
        'source adapter provenance compatible registry',
    )
    text = replace_once(
        text,
        "    return 'current-source-adapter'",
        "    return $(if($priorRegistryCompatible){'current-source-adapter-compatible-prior-registry'}else{'current-source-adapter'})",
        'source adapter authorization mode',
    )

    source_selftest_anchor = """    $authorized=@($plans|Where-Object{$_.mutation_authorized}|ForEach-Object{[string]$_.entry.name}|Sort-Object)\n    if(($authorized -join ',') -cne 'better-local-files,eternal-jukebox,ivLyrics,playlist-maker'){ throw \"Source adapter authority drift: $($authorized -join ',')\" }\n    foreach($name in @('tagify','splitify','star-ratings','sc-cover-ambience.js','sc-star-ratings.js')){ if([bool](@($plans|Where-Object{$_.entry.name -ceq $name})[0].mutation_authorized)){ throw \"$name unexpectedly gained mutation authority.\" } }""".replace('\n', newline)
    source_selftest_new = source_selftest_anchor + newline + "    $splitifyPlan=@($plans|Where-Object{$_.entry.name -ceq 'splitify'})[0]; if([string]$splitifyPlan.adapter.id -cne 'github-release-monitor-v1' -or [bool]$splitifyPlan.mutation_authorized){ throw 'Splitify did not resolve to the non-mutating release monitor adapter.' }"
    text = replace_once(text, source_selftest_anchor, source_selftest_new, 'Splitify source adapter self-test')

    candidate = bom + text.encode('utf-8')

    decoded = candidate.decode('utf-8-sig')
    split_block = function_block(decoded, 'Get-AddonInventory')
    assert 'source="alexander-rebello/splitify"' in split_block
    assert 'policy="monitor-only"' in split_block
    assert 'monitor-local-release-unproven' in split_block
    assert 'manual-source-identification-required' not in split_block
    assert 'Invoke-GitHubJson "https://api.github.com/repos/alexander-rebello/splitify/releases/latest"' in split_block
    assert 'Expand-Archive' not in split_block and 'Remove-Item' not in split_block and 'Copy-Item' not in split_block and 'Move-Item' not in split_block

    policy = function_block(decoded, 'Get-AddonPolicyRegistry')
    assert "name='splitify'; kind='custom-app'; source='alexander-rebello/splitify'; inventory_policy='monitor-only'; mutation_mode='deny'" in policy
    assert "name='sc-cover-ambience.js'" in policy and "data_policy='never-disable-or-optimize'" in policy
    assert "name='ivLyrics'" in policy and "mutation_mode='auto'" in policy

    update = function_block(decoded, 'Update-AutoApps')
    assert 'splitify' not in update.lower()
    assert 'Get-AddonSourceAdapterPlan' in update

    rollback = function_block(decoded, 'Rollback-LastTransaction')
    assert 'Assert-AddonSourceAdapterTransactionAuthorization' not in rollback

    return candidate


def build():
    base_main, base_addon = prepare_base()
    candidate_main = build_main(base_main)
    candidate_addon = build_addon(base_addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(candidate_main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate_addon)
    report = {
        'schema': 1,
        'base': {
            'main': {'size': len(base_main), 'sha256': sha(base_main)},
            'addon': {'size': len(base_addon), 'sha256': sha(base_addon)},
        },
        'candidate': {
            'main_version': '0.6.23',
            'addon_version': '0.6.5-r12',
            'main': {'size': len(candidate_main), 'sha256': sha(candidate_main)},
            'addon': {'size': len(candidate_addon), 'sha256': sha(candidate_addon)},
        },
        'splitify': {
            'repository': 'alexander-rebello/splitify',
            'policy': 'monitor-only',
            'mutation_mode': 'deny',
            'install_mode': 'never-auto-install',
            'local_release_provenance': 'unproven',
        },
        'prior_registry_compatibility': PRIOR_R11_REGISTRY_SHA,
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('SPLITIFY_R12_BUILD_PASS', len(candidate_main), sha(candidate_main), len(candidate_addon), sha(candidate_addon))


if __name__ == '__main__':
    build()
