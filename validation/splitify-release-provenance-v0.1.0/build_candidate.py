from pathlib import Path
import hashlib, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.24/out/bin'
OUT = ROOT / 'validation/splitify-release-provenance-v0.1.0/out/bin'
REPORT = ROOT / 'validation/splitify-release-provenance-v0.1.0/candidate-report.json'

BASE_MAIN_SIZE = 284312
BASE_MAIN_SHA = 'dc5d7ec17f18f7546786c81f3172c08f6fb1692842c2e6c0a69a86171e6b1151'
BASE_ADDON_SIZE = 275414
BASE_ADDON_SHA = '81343687c475f7f48f1311b09c98205a021776f26e8d55082e0ec47f8ebfb470'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
DISCOVERY_HEAD = '0656d3056d48b37e16e9fcf55e9bbb621137362d'
DISCOVERY_RUN = '40380481248'
DISCOVERY_ARTIFACT = '12677731951'
DISCOVERY_ARTIFACT_DIGEST = 'sha256:36e3b345d9bf6466410ba7f0043c762f94d3883eb9b98e280bed4b08240a2f1f'
SPLITIFY_V110_ASSET_SHA = '5de51a885815f78067b8d6f7f3ebe40c93b5a7c7e3c8c841fcd26147a13010ca'
SPLITIFY_V110_TREE_SHA = 'a138d868d219028d7498a6a4138aef4900da9583c04e572e5505e2ce971a4440'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


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


def prepare_base():
    subprocess.check_call([sys.executable, str(ROOT / 'validation/v0.6.24/build_v0624.py'), '--build'], cwd=ROOT)
    main = (BASE_OUT / 'spotify-control.ps1').read_bytes()
    addon = (BASE_OUT / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError(f'v0.6.24 main mismatch: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError(f'r13 addon mismatch: {len(addon)} {sha(addon)}')
    return main, addon


def build_main(base: bytes) -> bytes:
    if not base.startswith(b'\xef\xbb\xbf'):
        raise RuntimeError('v0.6.24 main BOM missing')
    body = base[3:]
    if b'\r\n' in body:
        raise RuntimeError('main must remain LF-only')
    text = body.decode('ascii')
    text = replace_once(text, '# Spotify Control v0.6.24 Archive Resource Hardening r13\n', '# Spotify Control v0.6.25 Splitify Release Provenance r14\n', 'main title')
    text = replace_once(text, '$ScriptVersion = "0.6.24"\n', '$ScriptVersion = "0.6.25"\n', 'main version')
    return b'\xef\xbb\xbf' + text.encode('ascii')


def build_addon(base: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    base_text = base[len(bom):].decode('utf-8')
    crlf = base_text.count('\r\n')
    lf = base_text.count('\n')
    newline = '\r\n' if crlf and crlf == lf else '\n'
    if newline == '\n' and '\r\n' in base_text:
        raise RuntimeError('mixed addon line endings')
    text = base_text
    text = replace_once(text, '$Version = "0.6.5-r13"', '$Version = "0.6.5-r14"', 'addon version')

    helpers = r'''function Get-SplitifyTreeFingerprint {
    param([string]$RootPath)
    if (-not (Test-PathSafe $RootPath "Container")) { throw "Splitify tree root is missing." }
    $root=[System.IO.Path]::GetFullPath($RootPath).TrimEnd([char]92,[char]47)
    $stack=New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($root)
    $files=New-Object System.Collections.Generic.List[object]
    [int]$entryCount=0
    [int64]$totalBytes=0
    while($stack.Count -gt 0){
        $current=$stack.Pop()
        foreach($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)){
            $entryCount++
            if($entryCount -gt 256){throw "Splitify local tree exceeds the accepted entry-count cap."}
            if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "Splitify local tree contains a reparse-point entry: $($item.FullName)"}
            if($item.PSIsContainer){
                $stack.Push($item.FullName)
                continue
            }
            if([int64]$item.Length -lt 0 -or [int64]$item.Length -gt 32MB){throw "Splitify local file exceeds the accepted per-file cap: $($item.FullName)"}
            $totalBytes += [int64]$item.Length
            if($totalBytes -gt 64MB){throw "Splitify local tree exceeds the accepted total-byte cap."}
            $rel=$item.FullName.Substring($root.Length).TrimStart([char]92,[char]47).Replace([char]92,[char]47)
            if([string]::IsNullOrWhiteSpace($rel)){throw "Splitify local tree produced an empty relative file path."}
            $files.Add([pscustomobject]@{Path=$rel;FullName=$item.FullName;Size=[int64]$item.Length})
        }
    }
    if($files.Count -lt 1){throw "Splitify local tree contains no files."}
    $ordered=@($files|Sort-Object @{Expression={$_.Path.ToLowerInvariant()}},@{Expression={$_.Path}})
    $rows=New-Object System.Collections.Generic.List[object]
    $lines=New-Object System.Collections.Generic.List[string]
    foreach($file in $ordered){
        $fileSha=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $rows.Add([pscustomobject]@{path=[string]$file.Path;size=[int64]$file.Size;sha256=$fileSha})
        $lines.Add("$($file.Path)|$([int64]$file.Size)|$fileSha")
    }
    $payload=($lines.ToArray() -join "`n")+"`n"
    $bytes=[System.Text.Encoding]::UTF8.GetBytes($payload)
    $hasher=[System.Security.Cryptography.SHA256]::Create()
    try{$treeSha=([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$hasher.Dispose()}
    return [pscustomobject]@{FileCount=$rows.Count;TotalBytes=$totalBytes;TreeSha256=$treeSha;Files=$rows.ToArray()}
}

function Test-SplitifyReleaseZipSafety {
    param([string]$ZipPath)
    if (-not (Test-PathSafe $ZipPath "Leaf")) { throw "Splitify release ZIP is missing." }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive=[System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try{
        [int]$count=0
        [int64]$expanded=0
        $seen=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        $top=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::Ordinal)
        foreach($entry in @($archive.Entries)){
            $count++
            if($count -gt 100){throw "Splitify release ZIP exceeds the accepted entry-count cap."}
            $raw=([string]$entry.FullName).Replace([char]92,[char]47)
            if([string]::IsNullOrWhiteSpace($raw)){throw "Splitify release ZIP contains an empty entry path."}
            if($raw.StartsWith('/') -or $raw -match '^[A-Za-z]:' -or $raw.Contains(':')){throw "Splitify release ZIP contains an unsafe absolute/device path: $raw"}
            $isDirectory=$raw.EndsWith('/')
            $path=$raw.TrimEnd('/')
            if([string]::IsNullOrWhiteSpace($path)){throw "Splitify release ZIP contains an unsafe empty path: $raw"}
            $parts=$path.Split('/')
            if(@($parts|Where-Object{$_ -eq '' -or $_ -eq '.' -or $_ -eq '..'}).Count -gt 0){throw "Splitify release ZIP contains an unsafe path component: $raw"}
            if(-not $seen.Add($path)){throw "Splitify release ZIP contains a duplicate/case-colliding path: $path"}
            [void]$top.Add($parts[0])
            $unixMode=(($entry.ExternalAttributes -shr 16) -band 0xF000)
            if($unixMode -eq 0xA000){throw "Splitify release ZIP contains a symlink entry: $raw"}
            if(-not $isDirectory){
                $entryLength=[int64]$entry.Length
                if($entryLength -lt 0 -or $entryLength -gt 16MB){throw "Splitify release ZIP entry exceeds the accepted per-entry cap: $raw"}
                $expanded += $entryLength
                if($expanded -gt 32MB){throw "Splitify release ZIP expanded-byte total exceeds the accepted cap."}
            }
        }
        if($count -lt 2){throw "Splitify release ZIP contains too few entries."}
        if($top.Count -ne 1 -or -not $top.Contains('splitify-dist')){throw "Splitify release ZIP top-level layout is not exactly splitify-dist/."}
        return [pscustomobject]@{EntryCount=$count;ExpandedBytes=$expanded;TopLevel='splitify-dist'}
    }finally{$archive.Dispose()}
}

function Get-SplitifyOfficialReleaseProof {
    param($Release)
    if(-not $Release){throw "Splitify release metadata is missing."}
    if([bool]$Release.draft -or [bool]$Release.prerelease){throw "Splitify latest release is not a stable published release."}
    $tag=[string]$Release.tag_name
    if($tag -notmatch '^v(?<version>\d+\.\d+\.\d+)$'){throw "Splitify latest release tag is not strict semver: $tag"}
    $assets=@($Release.assets|Where-Object{[string]$_.name -ceq 'splitify.zip'})
    if($assets.Count -ne 1){throw "Splitify latest release must expose exactly one splitify.zip asset."}
    $asset=$assets[0]
    $assetDigest=([string]$asset.digest).ToLowerInvariant()
    if($assetDigest -notmatch '^sha256:[0-9a-f]{64}$'){throw "Splitify release asset does not expose a GitHub SHA-256 digest."}
    $assetSize=[int64]$asset.size
    if($assetSize -lt 1 -or $assetSize -gt 16MB){throw "Splitify release asset size is outside the accepted monitor-only range."}
    $download=[string]$asset.browser_download_url
    if($download -notmatch '^https://github\.com/alexander-rebello/splitify/releases/download/'){throw "Splitify release asset URL is outside the official repository."}
    $temp=Join-Path $env:TEMP ("SpotifyControl-Splitify-Proof-"+[guid]::NewGuid().ToString('N'))
    $zip=Join-Path $temp 'splitify.zip'
    $extract=Join-Path $temp 'extract'
    New-Item -ItemType Directory -Force -Path $temp,$extract|Out-Null
    try{
        Invoke-WebRequest -Uri $download -Headers @{'User-Agent'="SpotifyControl-AddonManager/$Version"} -UseBasicParsing -OutFile $zip
        $actualSize=[int64](Get-Item -LiteralPath $zip).Length
        if($actualSize -ne $assetSize){throw "Splitify downloaded archive size mismatch. expected=$assetSize actual=$actualSize"}
        $actualDigest='sha256:'+((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant())
        if($actualDigest -cne $assetDigest){throw "Splitify GitHub-published digest mismatch. expected=$assetDigest actual=$actualDigest"}
        $zipSafety=Test-SplitifyReleaseZipSafety -ZipPath $zip
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $root=Join-Path $extract 'splitify-dist'
        if(-not(Test-PathSafe $root "Container")){throw "Splitify authenticated release root is missing after extraction."}
        $tree=Get-SplitifyTreeFingerprint -RootPath $root
        $manifest=Join-Path $root 'manifest.json'
        if(-not(Test-PathSafe $manifest "Leaf")){throw "Splitify authenticated release manifest is missing."}
        $manifestJson=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
        if([string]$manifestJson.name -cne 'Splitify'){throw "Splitify authenticated release manifest identity mismatch."}
        $manifestHasVersion=$null -ne $manifestJson.PSObject.Properties['version']
        return [pscustomobject]@{
            Version=$Matches['version'];Revision=$tag;TreeSha256=[string]$tree.TreeSha256;FileCount=[int]$tree.FileCount;TotalBytes=[int64]$tree.TotalBytes;Files=@($tree.Files)
            AssetDigest=$assetDigest;AssetSize=$assetSize;Download=$download;ZipEntryCount=[int]$zipSafety.EntryCount;ZipExpandedBytes=[int64]$zipSafety.ExpandedBytes
            ManifestHasVersion=$manifestHasVersion;ManifestVersion=$(if($manifestHasVersion){[string]$manifestJson.version}else{$null})
        }
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}

function Test-SplitifyInstalledReleaseProof {
    param([string]$InstalledPath,$OfficialProof)
    if(-not $OfficialProof){throw "Splitify official release proof is missing."}
    $local=Get-SplitifyTreeFingerprint -RootPath $InstalledPath
    $valid=([int]$local.FileCount -eq [int]$OfficialProof.FileCount -and [string]$local.TreeSha256 -ceq [string]$OfficialProof.TreeSha256)
    if($valid){
        $expected=@{};foreach($row in @($OfficialProof.Files)){$expected[[string]$row.path]=$row}
        foreach($row in @($local.Files)){
            if(-not $expected.ContainsKey([string]$row.path)){$valid=$false;break}
            $e=$expected[[string]$row.path]
            if([int64]$row.size -ne [int64]$e.size -or [string]$row.sha256 -cne [string]$e.sha256){$valid=$false;break}
        }
    }
    return [pscustomobject]@{Valid=$valid;InstalledTreeSha256=[string]$local.TreeSha256;InstalledFileCount=[int]$local.FileCount;OfficialTreeSha256=[string]$OfficialProof.TreeSha256;OfficialFileCount=[int]$OfficialProof.FileCount}
}

'''.replace('\n', newline)
    marker = 'function Get-AddonInventory {'
    if text.count(marker) != 1:
        raise RuntimeError('Get-AddonInventory marker drifted')
    text = text.replace(marker, helpers + marker, 1)

    old_inventory = """    # Splitify - source identified, but still strictly monitor-only.\n    # Upstream release metadata is observed read-only; installed release provenance is not inferred from manifest.json\n    # because upstream v1.1.0 still declares manifest version 1.0.0. No Splitify mutation/install path exists here.\n    try {\n        $splitifyResolution = Resolve-SpicetifyAsset -Name \"splitify\" -Kind \"CustomApp\" -Roots $customAppRoots\n        if ($splitifyResolution.status -ne \"absent\") {\n            $splitifyRelease = Invoke-GitHubJson \"https://api.github.com/repos/alexander-rebello/splitify/releases/latest\"\n            $splitifyAssets = @($splitifyRelease.assets | Where-Object { [string]$_.name -ceq \"splitify.zip\" })\n            if ($splitifyAssets.Count -ne 1) { throw \"Splitify latest release must expose exactly one splitify.zip asset.\" }\n            $splitifyAsset = $splitifyAssets[0]\n            if ([string]$splitifyAsset.digest -notmatch '^sha256:[0-9a-f]{64}$') { throw \"Splitify release asset does not expose a GitHub SHA-256 digest.\" }\n            $splitifyRemote = ([string]$splitifyRelease.tag_name).TrimStart(\"v\")\n            $splitifyStatus = if ($splitifyResolution.status -eq \"ambiguous\") { \"monitor-ambiguous-installation\" } else { \"monitor-local-release-unproven\" }\n            $items.Add([pscustomobject]@{\n                name=\"splitify\"; kind=\"custom-app\"; policy=\"monitor-only\"\n                installed=$(if($splitifyResolution.status -eq \"resolved\"){$true}else{$null})\n                local=$null; remote=$splitifyRemote; revision=[string]$splitifyRelease.tag_name; status=$splitifyStatus\n                source=\"alexander-rebello/splitify\"; download=[string]$splitifyAsset.browser_download_url; digest=[string]$splitifyAsset.digest; asset_size=[int64]$splitifyAsset.size\n                note=\"Official source/release is identified and monitored, but the installed release provenance is not yet proven; automatic update/install remains denied.\"\n                resolution_status=$splitifyResolution.status; install_path=$splitifyResolution.selected_path; locations=@($splitifyResolution.locations)\n            })\n        }\n    } catch {\n        $items.Add([pscustomobject]@{\n            name=\"splitify\"; kind=\"custom-app\"; policy=\"monitor-only\"; installed=$null\n            local=$null; remote=$null; revision=$null; status=\"check-error\"\n            source=\"alexander-rebello/splitify\"; download=$null; digest=$null; asset_size=[int64]0; error=$_.Exception.Message\n            note=\"Splitify remains untouched because source monitoring failed closed.\"\n            resolution_status=$null; install_path=$null; locations=@()\n        })\n    }""".replace('\n', newline)

    new_inventory = """    # Splitify - official latest release is authenticated and compared read-only against the installed tree.\n    # Release provenance comes from GitHub's published asset digest + exact file-tree fingerprint, never manifest.version.\n    # Mutation/install authority remains denied regardless of proof outcome.\n    try {\n        $splitifyResolution = Resolve-SpicetifyAsset -Name \"splitify\" -Kind \"CustomApp\" -Roots $customAppRoots\n        if ($splitifyResolution.status -ne \"absent\") {\n            $splitifyRelease = Invoke-GitHubJson \"https://api.github.com/repos/alexander-rebello/splitify/releases/latest\"\n            if([bool]$splitifyRelease.draft -or [bool]$splitifyRelease.prerelease){throw \"Splitify latest release is not stable.\"}\n            $splitifyAssets = @($splitifyRelease.assets | Where-Object { [string]$_.name -ceq \"splitify.zip\" })\n            if ($splitifyAssets.Count -ne 1) { throw \"Splitify latest release must expose exactly one splitify.zip asset.\" }\n            $splitifyAsset = $splitifyAssets[0]\n            if ([string]$splitifyAsset.digest -notmatch '^sha256:[0-9a-f]{64}$') { throw \"Splitify release asset does not expose a GitHub SHA-256 digest.\" }\n            $splitifyRemote = ([string]$splitifyRelease.tag_name).TrimStart(\"v\")\n            $splitifyLocal=$null\n            $splitifyStatus=if($splitifyResolution.status -eq \"ambiguous\"){\"monitor-ambiguous-installation\"}else{\"monitor-local-release-unproven\"}\n            $splitifyProofKind=$null;$splitifyOfficialTree=$null;$splitifyInstalledTree=$null;$splitifyManifestHasVersion=$null\n            if($splitifyResolution.status -eq \"resolved\"){\n                $officialProof=Get-SplitifyOfficialReleaseProof -Release $splitifyRelease\n                $installedProof=Test-SplitifyInstalledReleaseProof -InstalledPath ([string]$splitifyResolution.selected_path) -OfficialProof $officialProof\n                $splitifyOfficialTree=[string]$officialProof.TreeSha256;$splitifyInstalledTree=[string]$installedProof.InstalledTreeSha256;$splitifyManifestHasVersion=[bool]$officialProof.ManifestHasVersion\n                if($installedProof.Valid){\n                    $splitifyLocal=[string]$officialProof.Version\n                    $splitifyStatus=\"current-proven-latest-release\"\n                    $splitifyProofKind=\"github-release-asset-tree\"\n                }else{\n                    $splitifyProofKind=\"github-release-asset-tree-mismatch\"\n                }\n            }\n            $items.Add([pscustomobject]@{\n                name=\"splitify\"; kind=\"custom-app\"; policy=\"monitor-only\"\n                installed=$(if($splitifyResolution.status -eq \"resolved\"){$true}else{$null})\n                local=$splitifyLocal; remote=$splitifyRemote; revision=[string]$splitifyRelease.tag_name; status=$splitifyStatus\n                source=\"alexander-rebello/splitify\"; download=[string]$splitifyAsset.browser_download_url; digest=[string]$splitifyAsset.digest; asset_size=[int64]$splitifyAsset.size\n                proof_kind=$splitifyProofKind; official_tree_sha256=$splitifyOfficialTree; installed_tree_sha256=$splitifyInstalledTree; release_manifest_has_version=$splitifyManifestHasVersion\n                note=$(if($splitifyStatus -ceq \"current-proven-latest-release\"){\"Installed Splitify exactly matches the authenticated latest official release tree. Automatic update/install remains denied.\"}else{\"Splitify remains monitor-only; installed release is not inferred unless its exact tree matches the authenticated latest official release. Automatic update/install remains denied.\"})\n                resolution_status=$splitifyResolution.status; install_path=$splitifyResolution.selected_path; locations=@($splitifyResolution.locations)\n            })\n        }\n    } catch {\n        $items.Add([pscustomobject]@{\n            name=\"splitify\"; kind=\"custom-app\"; policy=\"monitor-only\"; installed=$null\n            local=$null; remote=$null; revision=$null; status=\"check-error\"\n            source=\"alexander-rebello/splitify\"; download=$null; digest=$null; asset_size=[int64]0; proof_kind=$null; official_tree_sha256=$null; installed_tree_sha256=$null; release_manifest_has_version=$null; error=$_.Exception.Message\n            note=\"Splitify remains untouched because read-only provenance monitoring failed closed.\"\n            resolution_status=$null; install_path=$null; locations=@()\n        })\n    }""".replace('\n', newline)
    text = replace_once(text, old_inventory, new_inventory, 'Splitify exact release-tree provenance inventory')

    for protected_fn in ('Get-AddonPolicyRegistry', 'Get-AddonSourceAdapterCatalog'):
        if function_block(base_text, protected_fn) != function_block(text, protected_fn):
            raise RuntimeError(f'{protected_fn} changed unexpectedly')

    base_registry = function_block(base_text, 'Get-AddonPolicyRegistry')
    candidate_registry = function_block(text, 'Get-AddonPolicyRegistry')
    auto_pat = re.compile(r"name='([^']+)'.*?mutation_mode='auto'", re.I)
    base_auto = sorted(auto_pat.findall(base_registry), key=str.lower)
    candidate_auto = sorted(auto_pat.findall(candidate_registry), key=str.lower)
    if base_auto != candidate_auto or sorted(x.lower() for x in candidate_auto) != sorted(x.lower() for x in AUTHORIZED_NAMES):
        raise RuntimeError(f'automatic mutation authority changed: {candidate_auto}')
    for required in (
        "name='splitify'; kind='custom-app'; source='alexander-rebello/splitify'; inventory_policy='monitor-only'; mutation_mode='deny'",
        "data_policy='preserve-installed-content'",
        "name='tagify'",
        "data_policy='protect-ratings-tags-notes'",
        "name='star-ratings'",
        "data_policy='playlist-backed-ratings-preserve'",
        "name='sc-cover-ambience.js'",
        "data_policy='never-disable-or-optimize'",
    ):
        if required.lower() not in candidate_registry.lower():
            raise RuntimeError(f'protected registry policy missing: {required}')

    inventory = function_block(text, 'Get-AddonInventory')
    split_start = inventory.find('# Splitify - official latest release')
    if split_start < 0:
        raise RuntimeError('new Splitify inventory block missing')
    split_end = inventory.find('\n    #', split_start + 5)
    if split_end < 0:
        split_end = len(inventory)
    split_block = inventory[split_start:split_end]
    for forbidden in ('Copy-Item','Move-Item','Start-Process','spicetify apply','spicetify backup','spicetify restore'):
        if forbidden.lower() in split_block.lower():
            raise RuntimeError(f'Splitify monitor gained forbidden mutation verb: {forbidden}')
    for required in ('Get-SplitifyOfficialReleaseProof','Test-SplitifyInstalledReleaseProof','current-proven-latest-release','github-release-asset-tree-mismatch'):
        if required not in split_block:
            raise RuntimeError(f'Splitify provenance inventory contract missing: {required}')

    return bom + text.encode('utf-8')


def build():
    base_main, base_addon = prepare_base()
    candidate_main = build_main(base_main)
    candidate_addon = build_addon(base_addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(candidate_main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate_addon)
    report = {
        'schema': 1,
        'base_version': '0.6.24',
        'candidate_version': '0.6.25',
        'addon_version': '0.6.5-r14',
        'base_main': {'size': len(base_main), 'sha256': sha(base_main)},
        'candidate_main': {'size': len(candidate_main), 'sha256': sha(candidate_main)},
        'base_addon': {'size': len(base_addon), 'sha256': sha(base_addon)},
        'candidate_addon': {'size': len(candidate_addon), 'sha256': sha(candidate_addon)},
        'registry_sha256_expected_unchanged': REGISTRY_SHA,
        'source_adapter_sha256_expected_unchanged': ADAPTER_SHA,
        'authority_expanded': False,
        'auto_authority': AUTHORIZED_NAMES,
        'splitify': {
            'mutation_mode': 'deny',
            'inventory_policy': 'monitor-only',
            'proof_kind': 'github-release-asset-tree',
            'latest_known_validation_release': 'v1.1.0',
            'v1_1_0_asset_sha256': SPLITIFY_V110_ASSET_SHA,
            'v1_1_0_tree_sha256': SPLITIFY_V110_TREE_SHA,
            'manifest_version_trusted': False,
        },
        'discovery': {
            'head': DISCOVERY_HEAD,
            'run': DISCOVERY_RUN,
            'artifact_id': DISCOVERY_ARTIFACT,
            'artifact_digest': DISCOVERY_ARTIFACT_DIGEST,
        },
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('SPLITIFY_PROVENANCE_CANDIDATE_PASS', len(candidate_main), sha(candidate_main), len(candidate_addon), sha(candidate_addon))


if __name__ == '__main__':
    build()
