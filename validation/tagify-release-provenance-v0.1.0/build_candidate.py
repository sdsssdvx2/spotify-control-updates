from pathlib import Path
import argparse, hashlib, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.25/out/bin'
OUT = ROOT / 'validation/tagify-release-provenance-v0.1.0/out/bin'
REPORT = ROOT / 'validation/tagify-release-provenance-v0.1.0/candidate-report.json'

BASE_MAIN_SIZE = 284313
BASE_MAIN_SHA = '896bb74e71385b5b6ada118af41cbe9d398dc662ce3719234104028e6eed197f'
BASE_ADDON_SIZE = 282718
BASE_ADDON_SHA = '25ebd0a5d5158f7d3cb4b4ce2ecf89f05f4dad3ef6bc799599e7204ce103c29c'
TARGET_MAIN_SIZE = 284311
TARGET_MAIN_SHA = 'd7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1'
TARGET_ADDON_SIZE = 291294
TARGET_ADDON_SHA = '4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']

AUDIT_HEAD = '4263a53f145fc602fbe81e0c243f8d7a70f46fc5'
AUDIT_RUN = 40388895760
AUDIT_ARTIFACT = 12682440808
AUDIT_ARTIFACT_DIGEST = 'sha256:9ed6837dccbf5229a9546a16ef4a35fc933289a28cc4929e45138625bd499f50'
AUDIT_CATALOG_JSON_SHA = '75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a'

RELEASES = [
    {'version':'2.5.0','tag':'v2.5.0','asset_size':494087,'asset_sha256':'5a47106d50b08aa377a3402258dee94db63797360e21dccf59f81f0827fcaccc','tree_sha256':'3b5ba1c33e4415fe530a029fd93af8f0fc84748eb2ac432422f31747a40c28dc','file_count':13},
    {'version':'3.0.0','tag':'v3.0.0','asset_size':909371,'asset_sha256':'ee04ec7eeb45054b798337ccd9e08f66a2cc881348f74b7a4d2adfbc93ef07b1','tree_sha256':'ac6d7f7567d78cbfbb37df40dc3d76273df3dde80f0962efaea3a217dcba99d0','file_count':18},
    {'version':'3.1.0','tag':'v3.1.0','asset_size':1355380,'asset_sha256':'a84b9c2aefd43035b16edf537b91652b934c09f1ef5037ed17b3738f1e4ecc91','tree_sha256':'f896dc5f83acd8272315aa171ea7893d744dc029422b15574da9c60190750c4e','file_count':21},
    {'version':'3.2.0','tag':'v3.2.0','asset_size':1436949,'asset_sha256':'346f0e746abf3e29aca754240da2e9d2c87e75d7e35fd27109575fed66629c31','tree_sha256':'516f364e8519983ae1bd64158b552a3bb68ed54414402e4ab9523f3e6abe1559','file_count':22},
    {'version':'3.3.0','tag':'v3.3.0','asset_size':1470208,'asset_sha256':'12f2efc0221014464eff2d5884a83bd05882138e87bcd0c208e734538c71604c','tree_sha256':'108e8afba7bcab8cfe8657431041a0118140a774ba4996e60ce91cfa8a4cf2d9','file_count':22},
    {'version':'3.3.1','tag':'v3.3.1','asset_size':1471676,'asset_sha256':'b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957','tree_sha256':'8f8abd6f80f88321d6517c1496c985da146e313a949e80f4e4b41c34ad27178a','file_count':22},
    {'version':'3.3.2','tag':'v3.3.2','asset_size':1554948,'asset_sha256':'5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b','tree_sha256':'e751c2692d0edb5d63ac359df0b81c024ddca4f02e9de46cd5e4d8f3266bbf71','file_count':22},
]

EXCLUDED = [
    {'versions':['1.0.0','1.0.1','1.0.2','2.0.0','2.1.0','2.1.1'],'reason':'no-exact-release-zip'},
    {'versions':['2.1.2','2.2.0','2.3.0','2.4.0'],'reason':'authenticated-zip-without-Tagify-identity-marker'},
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


def function_map(text: str):
    found = {}
    matches = list(re.finditer(r'(?m)^function ([A-Za-z0-9_-]+) \{', text))
    for idx, match in enumerate(matches):
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        found[match.group(1)] = text[match.start():end]
    return found


def build_base():
    subprocess.check_call([sys.executable, str(ROOT/'validation/v0.6.25/build_v0625.py'), '--build'], cwd=ROOT)
    main = (BASE_OUT/'spotify-control.ps1').read_bytes()
    addon = (BASE_OUT/'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError(f'v0.6.25 main base drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError(f'r14 addon base drift: {len(addon)} {sha(addon)}')
    return main, addon


def patch_main(base: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text = base[len(bom):].decode('utf-8')
    old_title = '# Spotify Control v0.6.25 Splitify Release Provenance r14'
    if text.count(old_title) != 1 or text.count('$ScriptVersion = "0.6.25"') != 1:
        raise RuntimeError('main version/title anchors drifted')
    text = text.replace(old_title, '# Spotify Control v0.6.26 Tagify Release Provenance r15', 1)
    text = text.replace('$ScriptVersion = "0.6.25"', '$ScriptVersion = "0.6.26"', 1)
    return bom + text.encode('utf-8')


def patch_addon(base: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text = base[len(bom):].decode('utf-8')
    if '\r\n' in text:
        raise RuntimeError('unexpected CRLF in r14 addon base')
    if text.count('$Version = "0.6.5-r14"') != 1:
        raise RuntimeError('addon version anchor drifted')
    text = text.replace('$Version = "0.6.5-r14"', '$Version = "0.6.5-r15"', 1)

    insert = text.find('\nfunction Get-IvLyricsReleaseInfo {', text.find('function Get-TagifyLocalVersion {'))
    if insert < 0:
        raise RuntimeError('Tagify helper insertion point drifted')
    helpers = r'''
function Get-TagifyReleaseCatalog {
    return @(
        [pscustomobject]@{Version='2.5.0';Tag='v2.5.0';TreeSha256='3b5ba1c33e4415fe530a029fd93af8f0fc84748eb2ac432422f31747a40c28dc';FileCount=13;AssetSize=[int64]494087;AssetDigest='sha256:5a47106d50b08aa377a3402258dee94db63797360e21dccf59f81f0827fcaccc'},
        [pscustomobject]@{Version='3.0.0';Tag='v3.0.0';TreeSha256='ac6d7f7567d78cbfbb37df40dc3d76273df3dde80f0962efaea3a217dcba99d0';FileCount=18;AssetSize=[int64]909371;AssetDigest='sha256:ee04ec7eeb45054b798337ccd9e08f66a2cc881348f74b7a4d2adfbc93ef07b1'},
        [pscustomobject]@{Version='3.1.0';Tag='v3.1.0';TreeSha256='f896dc5f83acd8272315aa171ea7893d744dc029422b15574da9c60190750c4e';FileCount=21;AssetSize=[int64]1355380;AssetDigest='sha256:a84b9c2aefd43035b16edf537b91652b934c09f1ef5037ed17b3738f1e4ecc91'},
        [pscustomobject]@{Version='3.2.0';Tag='v3.2.0';TreeSha256='516f364e8519983ae1bd64158b552a3bb68ed54414402e4ab9523f3e6abe1559';FileCount=22;AssetSize=[int64]1436949;AssetDigest='sha256:346f0e746abf3e29aca754240da2e9d2c87e75d7e35fd27109575fed66629c31'},
        [pscustomobject]@{Version='3.3.0';Tag='v3.3.0';TreeSha256='108e8afba7bcab8cfe8657431041a0118140a774ba4996e60ce91cfa8a4cf2d9';FileCount=22;AssetSize=[int64]1470208;AssetDigest='sha256:12f2efc0221014464eff2d5884a83bd05882138e87bcd0c208e734538c71604c'},
        [pscustomobject]@{Version='3.3.1';Tag='v3.3.1';TreeSha256='8f8abd6f80f88321d6517c1496c985da146e313a949e80f4e4b41c34ad27178a';FileCount=22;AssetSize=[int64]1471676;AssetDigest='sha256:b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957'},
        [pscustomobject]@{Version='3.3.2';Tag='v3.3.2';TreeSha256='e751c2692d0edb5d63ac359df0b81c024ddca4f02e9de46cd5e4d8f3266bbf71';FileCount=22;AssetSize=[int64]1554948;AssetDigest='sha256:5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b'}
    )
}

function Get-TagifyTreeFingerprint {
    param([string]$RootPath)
    if (-not (Test-PathSafe $RootPath "Container")) { throw "Tagify tree root is missing." }
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
            if($entryCount -gt 512){throw "Tagify local tree exceeds the accepted entry-count cap."}
            if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "Tagify local tree contains a reparse-point entry: $($item.FullName)"}
            if($item.PSIsContainer){$stack.Push($item.FullName);continue}
            if([int64]$item.Length -lt 0 -or [int64]$item.Length -gt 64MB){throw "Tagify local file exceeds the accepted per-file cap: $($item.FullName)"}
            $totalBytes += [int64]$item.Length
            if($totalBytes -gt 256MB){throw "Tagify local tree exceeds the accepted total-byte cap."}
            $rel=$item.FullName.Substring($root.Length).TrimStart([char]92,[char]47).Replace([char]92,[char]47)
            if([string]::IsNullOrWhiteSpace($rel)){throw "Tagify local tree produced an empty relative file path."}
            if($files.ContainsKey($rel)){throw "Tagify local tree contains a duplicate/case-colliding relative path: $rel"}
            $row=[pscustomobject]@{Path=$rel;FullName=$item.FullName;Size=[int64]$item.Length}
            $files.Add($rel,$row);$paths.Add($rel)
        }
    }
    if($paths.Count -lt 1){throw "Tagify local tree contains no files."}
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

function Resolve-TagifyInstalledReleaseProvenance {
    param([string]$InstalledPath,$Catalog=$(Get-TagifyReleaseCatalog))
    $local=Get-TagifyTreeFingerprint -RootPath $InstalledPath
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

'''
    text = text[:insert] + helpers + text[insert:]

    inv = text.find('function Get-AddonInventory {')
    start = text.find('    # Tagify -', inv)
    end = text.find('    # Splitify -', start)
    if start < 0 or end < 0:
        raise RuntimeError('Tagify inventory section drifted')
    new_inventory = r'''    # Tagify - monitor latest metadata, but prove the installed release only against a frozen authenticated release catalog.
    # Ratings/tags/notes remain outside this read-only install-tree fingerprint path; mutation/install authority remains denied.
    try {
        $tagifyResolution = Resolve-SpicetifyAsset -Name "tagify" -Kind "CustomApp" -Roots $customAppRoots
        $tagifyInstalled = if ($tagifyResolution.status -eq "resolved") { $true } elseif ($tagifyResolution.status -eq "absent") { $false } else { $null }
        $tagifyLocal=$null;$tagifyLocalTag=$null;$tagifyInstalledTree=$null;$tagifyProofKind=$null
        $tagifyStatus=if($tagifyResolution.status -eq "ambiguous"){"monitor-ambiguous-installation"}elseif($tagifyResolution.status -eq "absent"){"not-installed"}else{"monitor-local-release-unproven"}
        if($tagifyResolution.status -eq "resolved"){
            $tagifyProof=Resolve-TagifyInstalledReleaseProvenance -InstalledPath ([string]$tagifyResolution.selected_path)
            $tagifyInstalledTree=[string]$tagifyProof.TreeSha256
            if([bool]$tagifyProof.Ambiguous){
                $tagifyStatus="monitor-local-release-ambiguous-catalog";$tagifyProofKind="authenticated-release-catalog-ambiguous"
            }elseif([bool]$tagifyProof.Proven){
                $tagifyLocal=[string]$tagifyProof.Version;$tagifyLocalTag=[string]$tagifyProof.Tag;$tagifyProofKind="authenticated-release-catalog-tree-v1"
            }else{$tagifyProofKind="authenticated-release-catalog-tree-mismatch"}
        }
        $tagifyRelease = Invoke-GitHubJson "https://api.github.com/repos/alexk218/tagify/releases/latest"
        if([bool]$tagifyRelease.draft -or [bool]$tagifyRelease.prerelease){throw "Tagify latest release is not stable."}
        $tagifyTag=[string]$tagifyRelease.tag_name
        if($tagifyTag -notmatch '^v(?<version>\d+\.\d+\.\d+)$'){throw "Tagify latest release tag is not strict semver: $tagifyTag"}
        $tagifyRemote=[string]$Matches['version']
        $tagifyAssetName="tagify-$tagifyTag.zip"
        $tagifyAssets=@($tagifyRelease.assets|Where-Object{[string]$_.name -ceq $tagifyAssetName})
        if($tagifyAssets.Count -ne 1){throw "Tagify latest release must expose exactly one $tagifyAssetName asset."}
        $tagifyAsset=$tagifyAssets[0]
        $tagifyDigest=([string]$tagifyAsset.digest).ToLowerInvariant()
        if($tagifyDigest -notmatch '^sha256:[0-9a-f]{64}$'){throw "Tagify release asset does not expose a GitHub SHA-256 digest."}
        $tagifyAssetSize=[int64]$tagifyAsset.size
        if($tagifyAssetSize -lt 1 -or $tagifyAssetSize -gt 64MB){throw "Tagify release asset size is outside the accepted monitor-only range."}
        $tagifyDownload=[string]$tagifyAsset.browser_download_url
        $expectedTagifyDownload="https://github.com/alexk218/tagify/releases/download/$tagifyTag/$tagifyAssetName"
        if($tagifyDownload -cne $expectedTagifyDownload){throw "Tagify release asset URL is not the exact official release URL."}
        if($tagifyLocal){
            $localSem=[version]$tagifyLocal;$remoteSem=[version]$tagifyRemote
            if($localSem -eq $remoteSem){$tagifyStatus="monitor-current-proven"}
            elseif($localSem -lt $remoteSem){$tagifyStatus="monitor-update-available-proven-local"}
            else{$tagifyStatus="monitor-local-newer-than-remote-proven"}
        }
        $items.Add([pscustomobject]@{
            name="tagify";kind="custom-app";policy="monitor-only";installed=$tagifyInstalled
            local=$tagifyLocal;remote=$tagifyRemote;revision=$tagifyTag;status=$tagifyStatus
            source="alexk218/tagify";download=$tagifyDownload;digest=$tagifyDigest;asset_size=$tagifyAssetSize
            proof_kind=$tagifyProofKind;local_release_tag=$tagifyLocalTag;installed_tree_sha256=$tagifyInstalledTree;provenance_catalog_sha256="75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a"
            note="Monitor-only exact install-tree provenance; ratings/tags/notes remain protected and no Tagify mutation route exists."
            resolution_status=$tagifyResolution.status;install_path=$tagifyResolution.selected_path;locations=@($tagifyResolution.locations)
        })
    } catch {
        $items.Add([pscustomobject]@{
            name="tagify";kind="custom-app";policy="monitor-only";installed=$null
            local=$null;remote=$null;revision=$null;status="check-error"
            source="alexk218/tagify";download=$null;digest=$null;error=$_.Exception.Message
            proof_kind=$null;local_release_tag=$null;installed_tree_sha256=$null;provenance_catalog_sha256="75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a"
            resolution_status=$null;install_path=$null;locations=@()
        })
    }

'''
    text = text[:start] + new_inventory + text[end:]
    return bom + text.encode('utf-8')


def validate_candidate(base_main: bytes, base_addon: bytes, main: bytes, addon: bytes):
    if (len(main), sha(main)) != (TARGET_MAIN_SIZE, TARGET_MAIN_SHA):
        raise RuntimeError(f'prospective v0.6.26 main identity drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (TARGET_ADDON_SIZE, TARGET_ADDON_SHA):
        raise RuntimeError(f'prospective r15 addon identity drift: {len(addon)} {sha(addon)}')

    base = base_addon.decode('utf-8-sig')
    cand = addon.decode('utf-8-sig')
    base_functions = function_map(base)
    cand_functions = function_map(cand)
    added = sorted(set(cand_functions)-set(base_functions))
    removed = sorted(set(base_functions)-set(cand_functions))
    changed = sorted(k for k in base_functions if k in cand_functions and base_functions[k] != cand_functions[k])
    expected_added = ['Get-TagifyReleaseCatalog','Get-TagifyTreeFingerprint','Resolve-TagifyInstalledReleaseProvenance']
    if added != sorted(expected_added) or removed or changed != ['Get-AddonInventory']:
        raise RuntimeError(f'unexpected function surface delta: added={added} removed={removed} changed={changed}')

    registry = function_block(cand, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED_NAMES):
        raise RuntimeError(f'auto authority drift: {auto}')
    for marker in (
        "name='tagify'", "source='alexk218/tagify'", "inventory_policy='monitor-only'", "mutation_mode='deny'",
        "install_mode='never-auto-install'", "data_policy='protect-ratings-tags-notes'",
        "name='splitify'", "source='alexander-rebello/splitify'", "playlist-backed-ratings-preserve", "never-disable-or-optimize"
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected policy missing: {marker}')

    update = function_block(cand, 'Update-AutoApps')
    if 'tagify' in update.lower() or 'splitify' in update.lower():
        raise RuntimeError('protected monitor-only app gained an automatic update route')
    rollback = function_block(cand, 'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback:
        raise RuntimeError('RollbackLast became source-adapter-dependent')

    for helper in expected_added:
        block = function_block(cand, helper)
        for forbidden in ('Invoke-WebRequest','Invoke-RestMethod','Remove-Item','Copy-Item','Move-Item','Start-Process','Expand-Archive','spicetify apply','spicetify backup','spicetify restore'):
            if forbidden.lower() in block.lower():
                raise RuntimeError(f'{helper} gained forbidden side effect: {forbidden}')
    fp = function_block(cand, 'Get-TagifyTreeFingerprint')
    if 'Sort-Object' in fp or '.Sort([System.StringComparer]::OrdinalIgnoreCase)' not in fp:
        raise RuntimeError('Tagify fingerprint ordering contract drifted')

    inventory = function_block(cand, 'Get-AddonInventory')
    for required in (
        'Resolve-TagifyInstalledReleaseProvenance','monitor-current-proven','monitor-update-available-proven-local',
        'authenticated-release-catalog-tree-v1',AUDIT_CATALOG_JSON_SHA,
        'Resolve-SplitifyInstalledReleaseProvenance','60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454'
    ):
        if required not in inventory:
            raise RuntimeError(f'provenance inventory contract missing: {required}')
    if 'Get-TagifyLocalVersion $dir' in inventory:
        raise RuntimeError('Tagify inventory still trusts local version metadata for provenance')

    main_text = main.decode('utf-8-sig')
    if '$ScriptVersion = "0.6.26"' not in main_text or 'Tagify Release Provenance r15' not in main_text:
        raise RuntimeError('prospective main version/title contract missing')
    if '$Version = "0.6.5-r15"' not in cand:
        raise RuntimeError('prospective addon version contract missing')


def build():
    base_main, base_addon = build_base()
    main = patch_main(base_main)
    addon = patch_addon(base_addon)
    validate_candidate(base_main, base_addon, main, addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(main)
    (OUT/'addon-manager.ps1').write_bytes(addon)
    report = {
        'schema':1,
        'base':{'version':'0.6.25','main':{'size':BASE_MAIN_SIZE,'sha256':BASE_MAIN_SHA},'addon_version':'0.6.5-r14','addon':{'size':BASE_ADDON_SIZE,'sha256':BASE_ADDON_SHA}},
        'candidate':{'version':'0.6.26','main':{'size':TARGET_MAIN_SIZE,'sha256':TARGET_MAIN_SHA},'addon_version':'0.6.5-r15','addon':{'size':TARGET_ADDON_SIZE,'sha256':TARGET_ADDON_SHA}},
        'audit_evidence':{'head':AUDIT_HEAD,'run':AUDIT_RUN,'artifact_id':AUDIT_ARTIFACT,'artifact_digest':AUDIT_ARTIFACT_DIGEST,'catalog_json_sha256':AUDIT_CATALOG_JSON_SHA},
        'release_catalog':RELEASES,
        'excluded_releases':EXCLUDED,
        'canonical_order':'StringComparer.OrdinalIgnoreCase',
        'local_provenance_source':'exact-install-tree-only',
        'manifest_or_package_version_trusted_for_provenance':False,
        'authority_expanded':False,
        'new_auto_install_authority':False,
        'auto_authority':AUTHORIZED_NAMES,
        'registry_fingerprint':REGISTRY_SHA,
        'source_adapter_fingerprint':ADAPTER_SHA,
        'tagify_policy':{'inventory_policy':'monitor-only','mutation_mode':'deny','install_mode':'never-auto-install','data_policy':'protect-ratings-tags-notes'},
        'splitify_policy_preserved':True,
        'rollback_last_source_adapter_independent':True,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n', encoding='utf-8', newline='\n')
    print('TAGIFY_PROVENANCE_CANDIDATE_BUILD_PASS', len(main), sha(main), len(addon), sha(addon), AUDIT_CATALOG_JSON_SHA)


def main():
    p = argparse.ArgumentParser(); p.add_argument('--build', action='store_true'); args = p.parse_args()
    if not args.build: p.error('use --build')
    build()

if __name__ == '__main__':
    main()
