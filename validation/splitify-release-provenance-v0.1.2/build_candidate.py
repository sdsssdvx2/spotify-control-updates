from pathlib import Path
import hashlib, json, subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'validation/splitify-release-provenance-v0.1.2/out/bin'
REPORT = ROOT / 'validation/splitify-release-provenance-v0.1.2/candidate-report.json'

BASE_MAIN_SIZE = 284312
BASE_MAIN_SHA = 'dc5d7ec17f18f7546786c81f3172c08f6fb1692842c2e6c0a69a86171e6b1151'
BASE_ADDON_SIZE = 275414
BASE_ADDON_SHA = '81343687c475f7f48f1311b09c98205a021776f26e8d55082e0ec47f8ebfb470'
V011_MAIN_SIZE = 284313
V011_MAIN_SHA = '896bb74e71385b5b6ada118af41cbe9d398dc662ce3719234104028e6eed197f'
V011_ADDON_SIZE = 287290
V011_ADDON_SHA = '40bbfde7557df25110398a0f4972c6c156fba86d3fe12ce203b1fbb0ef9c229f'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']

V011_COMMIT = '8c32c9e98038893dd117af1636a4774c2f39630f'
V011_PATH = 'validation/splitify-release-provenance-v0.1.1/build_candidate.py'
V011_BUILDER_SIZE = 25426
V011_BUILDER_SHA = 'f280c4d88231cf17014844d6ccff713d03d16592e28e51a976f90b820e37dd81'

CATALOG_HEAD = '4af252f0d60b371db1cf7456d8f22ea0c200221a'
CATALOG_RUN = '40384980123'
CATALOG_ARTIFACT = '12681395038'
CATALOG_ARTIFACT_DIGEST = 'sha256:a275c0e4274b98394d057efd49a2ba45d44ace71d47ed71b9383b44e18993918'
CATALOG_JSON_SHA = '60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454'

RELEASES = [
    {'version': '1.0.5', 'tag': 'v1.0.5', 'asset_size': 7301, 'asset_sha256': 'c2ecc5e9330035b5c1855f537ea42f85a49705519ccc57e10d121e8b4595fab2', 'tree_sha256': '8c4525b41511fb5a32ad4921fbdbda5c59e0fb613ff0b2f223d0ee295030936a', 'file_count': 5},
    {'version': '1.0.8', 'tag': 'v1.0.8', 'asset_size': 8801, 'asset_sha256': '03158572d234c1aba14d7b9c53578886c885ffc568f5004dc03346eaa5dc4508', 'tree_sha256': '571722765760ccb98697a50742cfc8e66fae5411f91716794359e483b4383c76', 'file_count': 6},
    {'version': '1.1.0', 'tag': 'v1.1.0', 'asset_size': 7822, 'asset_sha256': '5de51a885815f78067b8d6f7f3ebe40c93b5a7c7e3c8c841fcd26147a13010ca', 'tree_sha256': '48bace1b6cef325dd1757bf4428e01fd42759a74da20a93fc16ab1ce49132777', 'file_count': 6},
]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def function_bounds(text: str, name: str):
    marker = f'function {name} {{'
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f'missing function {name}')
    nxt = text.find('\nfunction ', start + len(marker))
    if nxt < 0:
        nxt = len(text)
    return start, nxt


def function_block(text: str, name: str) -> str:
    a, b = function_bounds(text, name)
    return text[a:b]


def run_validated_v011_builder():
    source = subprocess.check_output(['git', 'show', f'{V011_COMMIT}:{V011_PATH}'], cwd=ROOT)
    if len(source) != V011_BUILDER_SIZE or sha(source) != V011_BUILDER_SHA:
        raise RuntimeError(f'validated v0.1.1 builder source drift: {len(source)} {sha(source)}')
    fake_file = ROOT / V011_PATH
    ns = {'__file__': str(fake_file), '__name__': 'validated_splitify_v011'}
    exec(compile(source, str(fake_file), 'exec'), ns)
    ns['build']()
    old_out = ROOT / 'validation/splitify-release-provenance-v0.1.1/out/bin'
    main = (old_out / 'spotify-control.ps1').read_bytes()
    addon = (old_out / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (V011_MAIN_SIZE, V011_MAIN_SHA):
        raise RuntimeError(f'validated v0.1.1 main drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (V011_ADDON_SIZE, V011_ADDON_SHA):
        raise RuntimeError(f'validated v0.1.1 addon drift: {len(addon)} {sha(addon)}')
    return main, addon


def patch_addon(v011_addon: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if v011_addon.startswith(b'\xef\xbb\xbf') else b''
    text = v011_addon[len(bom):].decode('utf-8')
    crlf = text.count('\r\n')
    lf = text.count('\n')
    newline = '\r\n' if crlf and crlf == lf else '\n'
    if newline == '\n' and '\r\n' in text:
        raise RuntimeError('mixed addon line endings')

    helper_start = text.find('function Get-SplitifyTreeFingerprint {')
    inventory_start = text.find('function Get-AddonInventory {', helper_start)
    if helper_start < 0 or inventory_start < 0:
        raise RuntimeError('validated v0.1.1 Splitify helper range drifted')

    helpers = r'''function Get-SplitifyReleaseCatalog {
    return @(
        [pscustomobject]@{Version='1.0.5';Tag='v1.0.5';TreeSha256='8c4525b41511fb5a32ad4921fbdbda5c59e0fb613ff0b2f223d0ee295030936a';FileCount=5;AssetSize=[int64]7301;AssetDigest='sha256:c2ecc5e9330035b5c1855f537ea42f85a49705519ccc57e10d121e8b4595fab2'},
        [pscustomobject]@{Version='1.0.8';Tag='v1.0.8';TreeSha256='571722765760ccb98697a50742cfc8e66fae5411f91716794359e483b4383c76';FileCount=6;AssetSize=[int64]8801;AssetDigest='sha256:03158572d234c1aba14d7b9c53578886c885ffc568f5004dc03346eaa5dc4508'},
        [pscustomobject]@{Version='1.1.0';Tag='v1.1.0';TreeSha256='48bace1b6cef325dd1757bf4428e01fd42759a74da20a93fc16ab1ce49132777';FileCount=6;AssetSize=[int64]7822;AssetDigest='sha256:5de51a885815f78067b8d6f7f3ebe40c93b5a7c7e3c8c841fcd26147a13010ca'}
    )
}

function Get-SplitifyTreeFingerprint {
    param([string]$RootPath)
    if (-not (Test-PathSafe $RootPath "Container")) { throw "Splitify tree root is missing." }
    $root=[System.IO.Path]::GetFullPath($RootPath).TrimEnd([char]92,[char]47)
    $stack=New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($root)
    $paths=New-Object 'System.Collections.Generic.List[string]'
    $files=New-Object -TypeName 'System.Collections.Generic.Dictionary[string,object]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    [int]$entryCount=0
    [int64]$totalBytes=0
    while($stack.Count -gt 0){
        $current=$stack.Pop()
        foreach($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)){
            $entryCount++
            if($entryCount -gt 256){throw "Splitify local tree exceeds the accepted entry-count cap."}
            if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "Splitify local tree contains a reparse-point entry: $($item.FullName)"}
            if($item.PSIsContainer){$stack.Push($item.FullName);continue}
            if([int64]$item.Length -lt 0 -or [int64]$item.Length -gt 32MB){throw "Splitify local file exceeds the accepted per-file cap: $($item.FullName)"}
            $totalBytes += [int64]$item.Length
            if($totalBytes -gt 64MB){throw "Splitify local tree exceeds the accepted total-byte cap."}
            $rel=$item.FullName.Substring($root.Length).TrimStart([char]92,[char]47).Replace([char]92,[char]47)
            if([string]::IsNullOrWhiteSpace($rel)){throw "Splitify local tree produced an empty relative file path."}
            if($files.ContainsKey($rel)){throw "Splitify local tree contains a duplicate/case-colliding relative path: $rel"}
            $row=[pscustomobject]@{Path=$rel;FullName=$item.FullName;Size=[int64]$item.Length}
            $files.Add($rel,$row);$paths.Add($rel)
        }
    }
    if($paths.Count -lt 1){throw "Splitify local tree contains no files."}
    $paths.Sort([System.StringComparer]::OrdinalIgnoreCase)
    $rows=New-Object System.Collections.Generic.List[object]
    $lines=New-Object System.Collections.Generic.List[string]
    foreach($path in $paths){
        $file=$files[$path]
        $fileSha=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $rows.Add([pscustomobject]@{path=[string]$file.Path;size=[int64]$file.Size;sha256=$fileSha})
        $lines.Add("$($file.Path)|$([int64]$file.Size)|$fileSha")
    }
    $payload=($lines.ToArray() -join "`n")+"`n"
    $bytes=[System.Text.Encoding]::UTF8.GetBytes($payload)
    $hasher=[System.Security.Cryptography.SHA256]::Create()
    try{$treeSha=([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$hasher.Dispose()}
    return [pscustomobject]@{FileCount=$rows.Count;TotalBytes=$totalBytes;TreeSha256=$treeSha;Files=$rows.ToArray();CanonicalOrder='OrdinalIgnoreCase'}
}

function Resolve-SplitifyInstalledReleaseProvenance {
    param([string]$InstalledPath,$Catalog=$(Get-SplitifyReleaseCatalog))
    $local=Get-SplitifyTreeFingerprint -RootPath $InstalledPath
    $matches=@($Catalog|Where-Object{[int]$_.FileCount -eq [int]$local.FileCount -and [string]$_.TreeSha256 -ceq [string]$local.TreeSha256})
    if($matches.Count -gt 1){
        return [pscustomobject]@{Proven=$false;Ambiguous=$true;Version=$null;Tag=$null;TreeSha256=[string]$local.TreeSha256;FileCount=[int]$local.FileCount;MatchCount=$matches.Count}
    }
    if($matches.Count -eq 1){
        $match=$matches[0]
        return [pscustomobject]@{Proven=$true;Ambiguous=$false;Version=[string]$match.Version;Tag=[string]$match.Tag;TreeSha256=[string]$local.TreeSha256;FileCount=[int]$local.FileCount;MatchCount=1}
    }
    return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TreeSha256=[string]$local.TreeSha256;FileCount=[int]$local.FileCount;MatchCount=0}
}

'''.replace('\n', newline)
    text = text[:helper_start] + helpers + text[inventory_start:]

    inv_a, inv_b = function_bounds(text.replace('\r\n', '\n'), 'Get-AddonInventory')
    # Recompute bounds against native line endings by locating the function and the next function directly.
    inv_start = text.find('function Get-AddonInventory {')
    inv_end = text.find(newline + 'function ', inv_start + len('function Get-AddonInventory {'))
    if inv_start < 0 or inv_end < 0:
        raise RuntimeError('Get-AddonInventory bounds drifted')
    inventory = text[inv_start:inv_end]
    split_start = inventory.find('    # Splitify - official latest release is authenticated and compared read-only against the installed tree.')
    if split_start < 0:
        raise RuntimeError('validated v0.1.1 Splitify inventory marker drifted')
    try_pos = inventory.find('    try {', split_start)
    next_section = inventory.find(newline + '    # ', try_pos)
    if next_section < 0:
        raise RuntimeError('could not locate section following Splitify inventory')

    new_inventory = r'''    # Splitify - monitor latest metadata, but prove the installed release only against the frozen authenticated release catalog.
    # manifest.version is never trusted; local provenance is an exact file-tree fingerprint match only. Mutation/install authority remains denied.
    try {
        $splitifyResolution = Resolve-SpicetifyAsset -Name "splitify" -Kind "CustomApp" -Roots $customAppRoots
        if ($splitifyResolution.status -ne "absent") {
            $splitifyRelease = Invoke-GitHubJson "https://api.github.com/repos/alexander-rebello/splitify/releases/latest"
            if([bool]$splitifyRelease.draft -or [bool]$splitifyRelease.prerelease){throw "Splitify latest release is not stable."}
            $splitifyTag=[string]$splitifyRelease.tag_name
            if($splitifyTag -notmatch '^v(?<version>\d+\.\d+\.\d+)$'){throw "Splitify latest release tag is not strict semver: $splitifyTag"}
            $splitifyRemote=[string]$Matches['version']
            $splitifyAssets=@($splitifyRelease.assets|Where-Object{[string]$_.name -ceq "splitify.zip"})
            if($splitifyAssets.Count -ne 1){throw "Splitify latest release must expose exactly one splitify.zip asset."}
            $splitifyAsset=$splitifyAssets[0]
            $splitifyDigest=([string]$splitifyAsset.digest).ToLowerInvariant()
            if($splitifyDigest -notmatch '^sha256:[0-9a-f]{64}$'){throw "Splitify release asset does not expose a GitHub SHA-256 digest."}
            $splitifyAssetSize=[int64]$splitifyAsset.size
            if($splitifyAssetSize -lt 1 -or $splitifyAssetSize -gt 16MB){throw "Splitify release asset size is outside the accepted monitor-only range."}
            $splitifyDownload=[string]$splitifyAsset.browser_download_url
            if($splitifyDownload -notmatch '^https://github\.com/alexander-rebello/splitify/releases/download/'){throw "Splitify release asset URL is outside the official repository."}
            $splitifyLocal=$null;$splitifyLocalTag=$null;$splitifyInstalledTree=$null;$splitifyProofKind=$null
            $splitifyStatus=if($splitifyResolution.status -eq "ambiguous"){"monitor-ambiguous-installation"}else{"monitor-local-release-unproven"}
            if($splitifyResolution.status -eq "resolved"){
                $localProof=Resolve-SplitifyInstalledReleaseProvenance -InstalledPath ([string]$splitifyResolution.selected_path)
                $splitifyInstalledTree=[string]$localProof.TreeSha256
                if([bool]$localProof.Ambiguous){
                    $splitifyStatus="monitor-local-release-ambiguous-catalog";$splitifyProofKind="authenticated-release-catalog-ambiguous"
                }elseif([bool]$localProof.Proven){
                    $splitifyLocal=[string]$localProof.Version;$splitifyLocalTag=[string]$localProof.Tag;$splitifyProofKind="authenticated-release-catalog-tree-v1"
                    $localSem=[version]$splitifyLocal;$remoteSem=[version]$splitifyRemote
                    if($localSem -eq $remoteSem){$splitifyStatus="monitor-current-proven"}
                    elseif($localSem -lt $remoteSem){$splitifyStatus="monitor-update-available-proven-local"}
                    else{$splitifyStatus="monitor-local-newer-than-remote-proven"}
                }else{$splitifyProofKind="authenticated-release-catalog-tree-mismatch"}
            }
            $items.Add([pscustomobject]@{
                name="splitify";kind="custom-app";policy="monitor-only"
                installed=$(if($splitifyResolution.status -eq "resolved"){$true}else{$null})
                local=$splitifyLocal;remote=$splitifyRemote;revision=$splitifyTag;status=$splitifyStatus
                source="alexander-rebello/splitify";download=$splitifyDownload;digest=$splitifyDigest;asset_size=$splitifyAssetSize
                proof_kind=$splitifyProofKind;local_release_tag=$splitifyLocalTag;installed_tree_sha256=$splitifyInstalledTree;provenance_catalog_sha256="60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454"
                note=$(if($splitifyLocal){"Installed Splitify exactly matches an authenticated official release tree. Automatic update/install remains denied."}else{"Splitify remains monitor-only; no local release version is inferred without an exact authenticated release-tree match. Automatic update/install remains denied."})
                resolution_status=$splitifyResolution.status;install_path=$splitifyResolution.selected_path;locations=@($splitifyResolution.locations)
            })
        }
    } catch {
        $items.Add([pscustomobject]@{
            name="splitify";kind="custom-app";policy="monitor-only";installed=$null
            local=$null;remote=$null;revision=$null;status="check-error"
            source="alexander-rebello/splitify";download=$null;digest=$null;asset_size=[int64]0;proof_kind=$null;local_release_tag=$null;installed_tree_sha256=$null;provenance_catalog_sha256="60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454";error=$_.Exception.Message
            note="Splitify remains untouched because read-only provenance monitoring failed closed."
            resolution_status=$null;install_path=$null;locations=@()
        })
    }'''.replace('\n', newline)
    inventory = inventory[:split_start] + new_inventory + inventory[next_section:]
    text = text[:inv_start] + inventory + text[inv_end:]

    decoded = text.replace('\r\n', '\n')
    for protected_fn in ('Get-AddonPolicyRegistry', 'Get-AddonSourceAdapterCatalog'):
        current = function_block(decoded, protected_fn)
        v011_decoded = v011_addon.decode('utf-8-sig').replace('\r\n', '\n')
        if current != function_block(v011_decoded, protected_fn):
            raise RuntimeError(f'{protected_fn} changed unexpectedly')
    reg = function_block(decoded, 'Get-AddonPolicyRegistry')
    import re
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", reg, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED_NAMES):
        raise RuntimeError(f'automatic mutation authority changed: {auto}')
    for marker in (
        "name='splitify'", "source='alexander-rebello/splitify'", "inventory_policy='monitor-only'", "mutation_mode='deny'", "data_policy='preserve-installed-content'",
        'protect-ratings-tags-notes', 'playlist-backed-ratings-preserve', 'never-disable-or-optimize',
    ):
        if marker.lower() not in reg.lower():
            raise RuntimeError(f'protected policy missing: {marker}')
    update = function_block(decoded, 'Update-AutoApps')
    if 'splitify' in update.lower():
        raise RuntimeError('Splitify gained a direct Update-AutoApps route')
    rollback = function_block(decoded, 'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback:
        raise RuntimeError('RollbackLast became source-adapter dependent')
    for name in ('Get-SplitifyReleaseCatalog', 'Get-SplitifyTreeFingerprint', 'Resolve-SplitifyInstalledReleaseProvenance'):
        block = function_block(decoded, name)
        for forbidden in ('Invoke-WebRequest', 'Invoke-RestMethod', 'Remove-Item', 'Copy-Item', 'Move-Item', 'Start-Process', 'Expand-Archive', 'spicetify apply', 'spicetify backup', 'spicetify restore'):
            if forbidden.lower() in block.lower():
                raise RuntimeError(f'{name} gained forbidden side effect: {forbidden}')
    if 'Sort-Object' in function_block(decoded, 'Get-SplitifyTreeFingerprint'):
        raise RuntimeError('Splitify fingerprint remains culture-dependent via Sort-Object')
    if '.Sort([System.StringComparer]::OrdinalIgnoreCase)' not in function_block(decoded, 'Get-SplitifyTreeFingerprint'):
        raise RuntimeError('Splitify fingerprint is missing explicit OrdinalIgnoreCase sort')
    return bom + text.encode('utf-8')


def build():
    candidate_main, v011_addon = run_validated_v011_builder()
    candidate_addon = patch_addon(v011_addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(candidate_main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate_addon)
    report = {
        'schema': 2,
        'base_version': '0.6.24',
        'candidate_version': '0.6.25',
        'addon_version': '0.6.5-r14',
        'base_main': {'size': BASE_MAIN_SIZE, 'sha256': BASE_MAIN_SHA},
        'base_addon': {'size': BASE_ADDON_SIZE, 'sha256': BASE_ADDON_SHA},
        'candidate_main': {'size': len(candidate_main), 'sha256': sha(candidate_main)},
        'candidate_addon': {'size': len(candidate_addon), 'sha256': sha(candidate_addon)},
        'validated_v011_builder': {'commit': V011_COMMIT, 'path': V011_PATH, 'size': V011_BUILDER_SIZE, 'sha256': V011_BUILDER_SHA},
        'catalog_evidence': {'head': CATALOG_HEAD, 'run': CATALOG_RUN, 'artifact_id': CATALOG_ARTIFACT, 'artifact_digest': CATALOG_ARTIFACT_DIGEST, 'catalog_json_sha256': CATALOG_JSON_SHA},
        'release_catalog': RELEASES,
        'unsupported_stable_releases': [{'version': '1.0.1', 'reason': 'no-splitify-zip'}, {'version': '1.0.4', 'reason': 'authenticated-asset-missing-manifest'}],
        'canonical_order': 'StringComparer.OrdinalIgnoreCase',
        'manifest_version_trusted': False,
        'authority_expanded': False,
        'auto_authority': AUTHORIZED_NAMES,
        'registry_sha256_expected_unchanged': REGISTRY_SHA,
        'source_adapter_sha256_expected_unchanged': ADAPTER_SHA,
        'splitify_policy': {'inventory_policy': 'monitor-only', 'mutation_mode': 'deny', 'install_mode': 'never-auto-install'},
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('SPLITIFY_PROVENANCE_V012_CANDIDATE_PASS', len(candidate_main), sha(candidate_main), len(candidate_addon), sha(candidate_addon))


if __name__ == '__main__':
    build()
