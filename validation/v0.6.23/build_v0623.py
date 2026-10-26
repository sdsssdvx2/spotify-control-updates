from pathlib import Path
import argparse, hashlib, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.22/out/bin'
OUT = ROOT / 'validation/v0.6.23/out/bin'
REPORT = ROOT / 'validation/v0.6.23/candidate-validation.json'

BASE_MAIN_SHA = 'b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe'
BASE_MAIN_SIZE = 281586
BASE_ADDON_SHA = '0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc'
BASE_ADDON_SIZE = 268670
TARGET_MAIN_SHA = 'bc9861bdd64ff8af94f68f0f065739f82b235271dcd18ad6325b819205528a08'
TARGET_MAIN_SIZE = 281588
TARGET_ADDON_SHA = '23ad2210aea4352f535d1cf0b3ebb827a82200dcba2b70bf1ebae96499d82687'
TARGET_ADDON_SIZE = 272494
PRIOR_R11_REGISTRY_SHA = '05c40a5339fe59b001ca0f4c4929643fd59e33a3002bae7067425845c85e2f6e'
TARGET_REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
VALIDATION_HEAD = '0f4f374bf491c0460ff3d51d06676a808117cc2d'
VALIDATION_PUSH_RUN = '40368420078'
VALIDATION_PR_RUN = '40368586584'
VALIDATION_PR = 71
VALIDATION_PR_ARTIFACT_ID = '12670949500'
VALIDATION_PR_ARTIFACT_DIGEST = 'sha256:b105a33b9070419378949a2f4011a543c84aa91c76da1186e214ed7551831f74'
SPLITIFY_REPOSITORY = 'alexander-rebello/splitify'
SPLITIFY_RELEASE = 'v1.1.0'
SPLITIFY_ASSET_SIZE = 7822
SPLITIFY_ASSET_DIGEST = 'sha256:5de51a885815f78067b8d6f7f3ebe40c93b5a7c7e3c8c841fcd26147a13010ca'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']


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
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError(f'v0.6.22 main base mismatch: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError(f'r11 addon base mismatch: {len(addon)} {sha(addon)}')
    return main, addon


def build_main(base: bytes) -> bytes:
    if not base.startswith(b'\xef\xbb\xbf'):
        raise RuntimeError('v0.6.22 main BOM missing')
    body = base[3:]
    if b'\r\n' in body:
        raise RuntimeError('unexpected CRLF in main')
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
    if newline == '\n' and '\r\n' in text:
        raise RuntimeError('mixed addon line endings')

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
    for required in ('source="alexander-rebello/splitify"', 'policy="monitor-only"', 'monitor-local-release-unproven', 'releases/latest', 'splitify.zip'):
        if required not in split_block:
            raise RuntimeError(f'Splitify monitor contract missing: {required}')
    for forbidden in ('Expand-Archive', 'Remove-Item', 'Copy-Item', 'Move-Item', 'Start-Process', 'spicetify apply', 'spicetify backup', 'spicetify restore'):
        if forbidden.lower() in split_block.lower():
            raise RuntimeError(f'Splitify monitor gained forbidden side effect: {forbidden}')
    policy = function_block(decoded, 'Get-AddonPolicyRegistry')
    if "name='splitify'; kind='custom-app'; source='alexander-rebello/splitify'; inventory_policy='monitor-only'; mutation_mode='deny'" not in policy:
        raise RuntimeError('Splitify registry policy mismatch')
    if "name='sc-cover-ambience.js'" not in policy or "data_policy='never-disable-or-optimize'" not in policy:
        raise RuntimeError('SC Cover Ambience protection drift')
    update = function_block(decoded, 'Update-AutoApps')
    if 'splitify' in update.lower():
        raise RuntimeError('Splitify gained a direct Update-AutoApps route')
    rollback = function_block(decoded, 'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback:
        raise RuntimeError('RollbackLast became source-adapter dependent')
    return candidate


def build():
    base_main, base_addon = prepare_base()
    candidate_main = build_main(base_main)
    candidate_addon = build_addon(base_addon)
    if (len(candidate_main), sha(candidate_main)) != (TARGET_MAIN_SIZE, TARGET_MAIN_SHA):
        raise RuntimeError(f'validated v0.6.23 main identity mismatch: {len(candidate_main)} {sha(candidate_main)}')
    if (len(candidate_addon), sha(candidate_addon)) != (TARGET_ADDON_SIZE, TARGET_ADDON_SHA):
        raise RuntimeError(f'validated r12 addon identity mismatch: {len(candidate_addon)} {sha(candidate_addon)}')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(candidate_main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate_addon)
    report = {
        'schema': 1,
        'base_version': '0.6.22',
        'version': '0.6.23',
        'addon_version': '0.6.5-r12',
        'base_main': {'size': len(base_main), 'sha256': sha(base_main)},
        'base_addon': {'size': len(base_addon), 'sha256': sha(base_addon)},
        'candidate_main': {'size': len(candidate_main), 'sha256': sha(candidate_main)},
        'candidate_addon': {'size': len(candidate_addon), 'sha256': sha(candidate_addon)},
        'authority_expanded': False,
        'new_auto_install_authority': False,
        'auto_authority': AUTHORIZED_NAMES,
        'adapter_fingerprint': ADAPTER_SHA,
        'registry_fingerprint': TARGET_REGISTRY_SHA,
        'prior_registry_compatibility': PRIOR_R11_REGISTRY_SHA,
        'splitify': {
            'repository': SPLITIFY_REPOSITORY,
            'release': SPLITIFY_RELEASE,
            'asset_size': SPLITIFY_ASSET_SIZE,
            'asset_digest': SPLITIFY_ASSET_DIGEST,
            'policy': 'monitor-only',
            'mutation_mode': 'deny',
            'install_mode': 'never-auto-install',
            'local_release_provenance': 'unproven',
        },
        'validation': {
            'head': VALIDATION_HEAD,
            'push_run': VALIDATION_PUSH_RUN,
            'pr_run': VALIDATION_PR_RUN,
            'pr': VALIDATION_PR,
            'pr_closed_unmerged': True,
            'pr_artifact_id': VALIDATION_PR_ARTIFACT_ID,
            'pr_artifact_digest': VALIDATION_PR_ARTIFACT_DIGEST,
        },
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('V0623_R12_BUILD_PASS', len(candidate_main), sha(candidate_main), len(candidate_addon), sha(candidate_addon), TARGET_REGISTRY_SHA, ADAPTER_SHA)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    if not args.build:
        parser.error('use --build')
    build()


if __name__ == '__main__':
    main()
