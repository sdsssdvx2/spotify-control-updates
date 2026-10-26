from pathlib import Path
import hashlib, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.23/out/bin'
OUT = ROOT / 'validation/archive-resource-hardening-v0.1.0/out/bin'
REPORT = ROOT / 'validation/archive-resource-hardening-v0.1.0/candidate-report.json'

BASE_MAIN_SIZE = 281588
BASE_MAIN_SHA = 'bc9861bdd64ff8af94f68f0f065739f82b235271dcd18ad6325b819205528a08'
BASE_ADDON_SIZE = 272494
BASE_ADDON_SHA = '23ad2210aea4352f535d1cf0b3ebb827a82200dcba2b70bf1ebae96499d82687'


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


def replace_in_function(text: str, name: str, old: str, new: str, label: str) -> str:
    a, b = function_bounds(text, name)
    block = text[a:b]
    count = block.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one match in {name}, got {count}')
    block = block.replace(old, new, 1)
    return text[:a] + block + text[b:]


def prepare_base():
    subprocess.check_call([sys.executable, str(ROOT / 'validation/v0.6.23/build_v0623.py'), '--build'], cwd=ROOT)
    main = (BASE_OUT / 'spotify-control.ps1').read_bytes()
    addon = (BASE_OUT / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError(f'v0.6.23 main mismatch: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError(f'v0.6.23 addon mismatch: {len(addon)} {sha(addon)}')
    return main, addon


def build_main(base: bytes) -> bytes:
    if not base.startswith(b'\xef\xbb\xbf'):
        raise RuntimeError('main BOM missing')
    body = base[3:]
    if b'\r\n' in body:
        raise RuntimeError('main must remain LF-only')
    base_text = body.decode('ascii')
    text = base_text
    text = replace_once(text, '# Spotify Control v0.6.23 Splitify Source Monitor r12\n', '# Spotify Control v0.6.24 Archive Resource Hardening r13\n', 'main title')
    text = replace_once(text, '$ScriptVersion = "0.6.23"\n', '$ScriptVersion = "0.6.24"\n', 'main version')

    helper = r'''function Test-SpotifyControlZipArchiveSafety {
    param(
        [string]$ZipPath,
        [string]$Label='Archive',
        [int]$MaxEntries=16384,
        [int64]$MaxEntryBytes=134217728,
        [int64]$MaxExpandedBytes=536870912
    )
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw "$Label ZIP is missing." }
    if ($MaxEntries -lt 1 -or $MaxEntryBytes -lt 1 -or $MaxExpandedBytes -lt 1) { throw "$Label ZIP safety limits are invalid." }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive=[System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        [int]$count=0
        [int64]$expanded=0
        $seen=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        foreach($entry in @($archive.Entries)) {
            $count++
            if($count -gt $MaxEntries){throw "$Label ZIP entry count exceeds the safety limit."}
            $raw=([string]$entry.FullName).Replace('\','/')
            if([string]::IsNullOrWhiteSpace($raw)){throw "$Label ZIP contains an empty entry path."}
            if($raw.StartsWith('/') -or $raw -match '^[A-Za-z]:' -or $raw.Contains(':')){throw "$Label ZIP contains an unsafe absolute/device path: $raw"}
            $isDirectory=$raw.EndsWith('/')
            $name=$raw.TrimEnd('/')
            if([string]::IsNullOrWhiteSpace($name)){throw "$Label ZIP contains an unsafe empty path: $raw"}
            $parts=$name.Split('/')
            if(@($parts | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0){throw "$Label ZIP contains an unsafe path component: $raw"}
            if(-not $seen.Add($name)){throw "$Label ZIP contains a duplicate/case-colliding path: $name"}
            $unixMode=(($entry.ExternalAttributes -shr 16) -band 0xF000)
            if($unixMode -eq 0xA000){throw "$Label ZIP contains a symlink entry: $raw"}
            if(-not $isDirectory){
                $entryLength=[int64]$entry.Length
                if($entryLength -lt 0 -or $entryLength -gt $MaxEntryBytes){throw "$Label ZIP entry exceeds the per-entry safety limit: $raw"}
                $expanded += $entryLength
                if($expanded -gt $MaxExpandedBytes){throw "$Label ZIP expanded-byte total exceeds the safety limit."}
            }
        }
        if($count -lt 1){throw "$Label ZIP contains no entries."}
        return [pscustomobject]@{EntryCount=$count;ExpandedBytes=$expanded}
    } finally {
        $archive.Dispose()
    }
}

'''
    marker = 'function Expand-AndValidateMarketplaceAsset {'
    if text.count(marker) != 1:
        raise RuntimeError('Marketplace extraction function marker drifted')
    text = text.replace(marker, helper + marker, 1)
    text = replace_in_function(
        text,
        'Expand-AndValidateMarketplaceAsset',
        '    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force\n',
        "    $archiveSafety = Test-SpotifyControlZipArchiveSafety -ZipPath $zip -Label 'Marketplace' -MaxEntries 16384 -MaxEntryBytes 134217728 -MaxExpandedBytes 536870912\n    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force\n",
        'Marketplace pre-extraction safety gate',
    )

    candidate = b'\xef\xbb\xbf' + text.encode('ascii')
    if function_block(base_text, 'Expand-AndValidateSpicetifyAsset') != function_block(text, 'Expand-AndValidateSpicetifyAsset'):
        raise RuntimeError('Spicetify hardened extraction path changed unexpectedly')
    return candidate


def build_addon(base: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    base_text = base[len(bom):].decode('utf-8')
    crlf = base_text.count('\r\n')
    lf = base_text.count('\n')
    newline = '\r\n' if crlf and crlf == lf else '\n'
    if newline == '\n' and '\r\n' in base_text:
        raise RuntimeError('mixed Addon Manager line endings')
    text = base_text
    text = replace_once(text, '$Version = "0.6.5-r12"', '$Version = "0.6.5-r13"', 'addon version')

    old_iv_file_block = '''            if (-not $name.EndsWith('/')) {
                $expanded += [int64]$entry.Length
                if ($expanded -gt 512MB) { throw "ivLyrics ZIP expanded-byte total exceeds the accepted cap." }
            }'''.replace('\n', newline)
    new_iv_file_block = '''            $unixMode=(($entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($unixMode -eq 0xA000) { throw "ivLyrics ZIP contains a symlink entry: $name" }
            if (-not $name.EndsWith('/')) {
                $entryLength=[int64]$entry.Length
                if ($entryLength -lt 0 -or $entryLength -gt 128MB) { throw "ivLyrics ZIP entry exceeds the accepted per-entry cap: $name" }
                $expanded += $entryLength
                if ($expanded -gt 512MB) { throw "ivLyrics ZIP expanded-byte total exceeds the accepted cap." }
            }'''.replace('\n', newline)
    text = replace_in_function(text, 'Test-IvLyricsZipArchiveSafety', old_iv_file_block, new_iv_file_block, 'ivLyrics symlink/per-entry hardening')

    pithaya_helper = '''function Test-PithayaZipArchiveSafety {
    param([string]$ZipPath,[string]$Name)
    if (-not (Test-PathSafe $ZipPath "Leaf")) { throw "Pinned Pithaya ZIP for $Name is missing." }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive=[System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        [int]$count=0
        [int64]$expanded=0
        $seen=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        foreach($entry in @($archive.Entries)) {
            $count++
            if($count -gt 8192){throw "Pinned Pithaya ZIP for $Name exceeds the accepted entry-count cap."}
            $raw=([string]$entry.FullName).Replace([char]92,[char]47)
            if([string]::IsNullOrWhiteSpace($raw)){throw "Pinned Pithaya ZIP for $Name contains an empty entry path."}
            if($raw.StartsWith('/') -or $raw -match '^[A-Za-z]:' -or $raw.Contains(':')){throw "Pinned Pithaya ZIP for $Name contains an unsafe absolute/device path: $raw"}
            $isDirectory=$raw.EndsWith('/')
            $path=$raw.TrimEnd('/')
            if([string]::IsNullOrWhiteSpace($path)){throw "Pinned Pithaya ZIP for $Name contains an unsafe empty path: $raw"}
            $parts=$path.Split('/')
            if(@($parts | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0){throw "Pinned Pithaya ZIP for $Name contains an unsafe path component: $raw"}
            if(-not $seen.Add($path)){throw "Pinned Pithaya ZIP for $Name contains a duplicate/case-colliding path: $path"}
            $unixMode=(($entry.ExternalAttributes -shr 16) -band 0xF000)
            if($unixMode -eq 0xA000){throw "Pinned Pithaya ZIP for $Name contains a symlink entry: $raw"}
            if(-not $isDirectory){
                $entryLength=[int64]$entry.Length
                if($entryLength -lt 0 -or $entryLength -gt 128MB){throw "Pinned Pithaya ZIP for $Name entry exceeds the accepted per-entry cap: $raw"}
                $expanded += $entryLength
                if($expanded -gt 512MB){throw "Pinned Pithaya ZIP for $Name expanded-byte total exceeds the accepted cap."}
            }
        }
        if($count -lt 1){throw "Pinned Pithaya ZIP for $Name contains no entries."}
        return [pscustomobject]@{EntryCount=$count;ExpandedBytes=$expanded}
    } finally {
        $archive.Dispose()
    }
}

'''.replace('\n', newline)
    marker = 'function Download-PithayaPinnedStage {'
    if text.count(marker) != 1:
        raise RuntimeError('Pithaya stage marker drifted')
    text = text.replace(marker, pithaya_helper + marker, 1)

    text = replace_in_function(
        text,
        'Download-PithayaPinnedStage',
        '        $archiveSha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()' + newline + '        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force',
        '        $archiveSha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()' + newline + '        $zipSafety=Test-PithayaZipArchiveSafety -ZipPath $zip -Name $Name' + newline + '        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force',
        'Pithaya pre-extraction safety gate',
    )
    text = replace_in_function(
        text,
        'Invoke-IvLyricsOfficialTagProofOnlineSelfTest',
        '        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force',
        '        $zipSafety=Test-IvLyricsZipArchiveSafety -ZipPath $zip' + newline + '        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force',
        'ivLyrics historical zipball pre-extraction safety gate',
    )

    for protected_fn in ('Get-AddonPolicyRegistry', 'Get-AddonSourceAdapterCatalog'):
        if function_block(base_text, protected_fn) != function_block(text, protected_fn):
            raise RuntimeError(f'{protected_fn} changed unexpectedly')

    base_registry = function_block(base_text, 'Get-AddonPolicyRegistry')
    candidate_registry = function_block(text, 'Get-AddonPolicyRegistry')
    auto_pat = re.compile(r"name='([^']+)'.*?mutation_mode='auto'", re.I)
    if sorted(auto_pat.findall(base_registry)) != sorted(auto_pat.findall(candidate_registry)):
        raise RuntimeError('automatic mutation authority changed')
    for required in ('ivLyrics', 'better-local-files', 'eternal-jukebox', 'playlist-maker'):
        if required not in auto_pat.findall(candidate_registry):
            raise RuntimeError(f'missing existing auto authority: {required}')
    if "name='sc-cover-ambience'" not in candidate_registry.lower() or "mutation_mode='deny'" not in candidate_registry.lower():
        raise RuntimeError('SC Cover Ambience deny policy missing')

    return bom + text.encode('utf-8')


def main():
    base_main, base_addon = prepare_base()
    candidate_main = build_main(base_main)
    candidate_addon = build_addon(base_addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(candidate_main)
    (OUT / 'addon-manager.ps1').write_bytes(candidate_addon)
    report = {
        'schema': 1,
        'base_version': '0.6.23',
        'candidate_version': '0.6.24',
        'addon_version': '0.6.5-r13',
        'base_main': {'size': len(base_main), 'sha256': sha(base_main)},
        'candidate_main': {'size': len(candidate_main), 'sha256': sha(candidate_main)},
        'base_addon': {'size': len(base_addon), 'sha256': sha(base_addon)},
        'candidate_addon': {'size': len(candidate_addon), 'sha256': sha(candidate_addon)},
        'authority_expanded': False,
        'spicetify_extractor_unchanged': True,
        'protected_registry_unchanged': True,
        'source_adapter_catalog_unchanged': True,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('ARCHIVE_HARDENING_CANDIDATE_PASS', len(candidate_main), sha(candidate_main), len(candidate_addon), sha(candidate_addon))


if __name__ == '__main__':
    main()
