from __future__ import annotations

from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.27/out/bin'
OUT = ROOT / 'validation/sc-cover-ambience-commit-provenance-v0.1.0/out/bin'
REPORT = ROOT / 'validation/sc-cover-ambience-commit-provenance-v0.1.0/candidate-report.json'

BASE_MAIN_SIZE = 284317
BASE_MAIN_SHA = '9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787'
BASE_ADDON_SIZE = 303745
BASE_ADDON_SHA = 'c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']

CATALOG_COMMIT = '008daeb5c57992b79fabc2ad9ca54192f1d78463'
CATALOG_PATH = 'validation/sc-cover-ambience-runtime-topology-collector-v0.1.0/official-snapshots.json'
CATALOG_BLOB = '244f3e7616b0b6d0eecc2017ec7d5febcf10bece'
CATALOG_FINGERPRINT = 'c12391e57a393d37d70ffd7a984bdbb6af9f4a83cf3c2b0a8c9bf040247c731f'
CURRENT_COMMIT = '9454b55e454fb354ecedcf3f72c5a4f0a9671651'
CURRENT_SIZE = 10267
CURRENT_SHA = '0aea69246e14156b22a10261af07b84f3abc58bed4368e03f740ed76db329738'

AUDIT_PR = 91
AUDIT_HEAD = 'cc304a1b1c4b3178c7269884a0d24332a5525ec6'
AUDIT_RUN = 40498778865
AUDIT_ARTIFACT = 12731962049
AUDIT_ARTIFACT_DIGEST = 'sha256:157291e1d54b68e8ad5a90662f301f6cb8f48a9e67ab3b0d01f88e0e0d47991b'
COLLECTOR_PR = 92
COLLECTOR_HEAD = '008daeb5c57992b79fabc2ad9ca54192f1d78463'
COLLECTOR_RUN = 40499795044
COLLECTOR_ARTIFACT = 12732098347
COLLECTOR_ARTIFACT_DIGEST = 'sha256:77c0c4a9976fcbb699608d41e3f10d64c82420b6e3ffed85d7f390d7c86d395b'
REAL_PC_REPORT_SIZE = 16730
REAL_PC_REPORT_SHA = '7349326c6567806f6c45bacb741d32649a6afc424b797d7249358cd9b8f5b38b'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def function_bounds(text: str, name: str) -> tuple[int, int]:
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


def function_map(text: str) -> dict[str, str]:
    found: dict[str, str] = {}
    matches = list(re.finditer(r'(?m)^function ([A-Za-z0-9_-]+) \{', text))
    for idx, match in enumerate(matches):
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        found[match.group(1)] = text[match.start():end].rstrip()
    return found


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git', 'rev-parse', f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def load_catalog() -> dict:
    blob = git_blob(CATALOG_COMMIT, CATALOG_PATH)
    if blob != CATALOG_BLOB:
        raise RuntimeError(f'pinned SC Cover Ambience snapshot catalog blob drifted: {blob}')
    doc = json.loads(git_bytes(CATALOG_COMMIT, CATALOG_PATH).decode('utf-8'))
    if doc.get('schema') != 1:
        raise RuntimeError('snapshot catalog schema drifted')
    if doc.get('source_repository') != 'Theblockbuster1/spicetify-extensions':
        raise RuntimeError('snapshot catalog repository drifted')
    if doc.get('source_path') != 'CoverAmbience/CoverAmbience.js':
        raise RuntimeError('snapshot catalog source path drifted')
    if doc.get('audit_catalog_payload_sha256') != CATALOG_FINGERPRINT:
        raise RuntimeError('snapshot catalog audit fingerprint drifted')
    snapshots = list(doc.get('snapshots') or [])
    if len(snapshots) != 35:
        raise RuntimeError(f'expected 35 snapshots, got {len(snapshots)}')
    keys = set()
    for row in snapshots:
        key = (int(row['size']), str(row['sha256']))
        if key in keys:
            raise RuntimeError(f'duplicate snapshot identity: {key}')
        keys.add(key)
    current = [row for row in snapshots if bool(row.get('current'))]
    if len(current) != 1:
        raise RuntimeError(f'current snapshot cardinality drifted: {len(current)}')
    row = current[0]
    if (row['commit'], int(row['size']), row['sha256']) != (CURRENT_COMMIT, CURRENT_SIZE, CURRENT_SHA):
        raise RuntimeError('current snapshot identity drifted')
    return doc


def build_base() -> tuple[bytes, bytes]:
    subprocess.check_call([sys.executable, str(ROOT / 'validation/v0.6.27/build_v0627.py'), '--build'], cwd=ROOT)
    main = (BASE_OUT / 'spotify-control.ps1').read_bytes()
    addon = (BASE_OUT / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError(f'v0.6.27 main base drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError(f'r16 addon base drift: {len(addon)} {sha(addon)}')
    return main, addon


def patch_main(base: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text = base[len(bom):].decode('utf-8')
    old_title = '# Spotify Control v0.6.27 Star Ratings Release Provenance r16'
    if text.count(old_title) != 1:
        raise RuntimeError('main title anchor drifted')
    if text.count('$ScriptVersion = "0.6.27"') != 1:
        raise RuntimeError('main version anchor drifted')
    text = text.replace(old_title, '# Spotify Control v0.6.28 SC Cover Ambience Commit Provenance r17', 1)
    text = text.replace('$ScriptVersion = "0.6.27"', '$ScriptVersion = "0.6.28"', 1)
    return bom + text.encode('utf-8')


def patch_addon(base: bytes, catalog: dict) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text = base[len(bom):].decode('utf-8')
    if '\r\n' in text:
        raise RuntimeError('unexpected CRLF in r16 addon base')
    if text.count('$Version = "0.6.5-r16"') != 1:
        raise RuntimeError('addon version anchor drifted')
    text = text.replace('$Version = "0.6.5-r16"', '$Version = "0.6.5-r17"', 1)

    insert = text.find('\nfunction Get-AddonInventory {')
    if insert < 0:
        raise RuntimeError('Get-AddonInventory helper insertion point drifted')

    rows = []
    for row in catalog['snapshots']:
        current = '$true' if bool(row.get('current')) else '$false'
        rows.append(
            "        [pscustomobject]@{Commit='%s';Date='%s';Size=[int64]%d;Sha256='%s';Current=%s}" %
            (row['commit'], row['date'], int(row['size']), row['sha256'], current)
        )
    catalog_rows = ',\n'.join(rows)

    helpers = r'''
function Get-SCCoverAmbienceSnapshotCatalog {
    return @(
__CATALOG__
    )
}

function Get-SCCoverAmbienceFileSnapshotProvenance {
    param([string]$Path,[string]$Role='unknown',$Catalog=$(Get-SCCoverAmbienceSnapshotCatalog))
    if([string]::IsNullOrWhiteSpace($Path) -or -not (Test-PathSafe $Path 'Leaf')){
        return [pscustomobject]@{Exists=$false;Proven=$false;Ambiguous=$false;Role=$Role;Path=$Path;Commit=$null;Date=$null;Current=$false;Size=[int64]0;Sha256=$null;MatchCount=0;Reason='file-missing'}
    }
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){
        return [pscustomobject]@{Exists=$true;Proven=$false;Ambiguous=$false;Role=$Role;Path=$Path;Commit=$null;Date=$null;Current=$false;Size=[int64]$item.Length;Sha256=$null;MatchCount=0;Reason='file-reparse-point'}
    }
    $size=[int64]$item.Length
    if($size -lt 1 -or $size -gt 8MB){
        return [pscustomobject]@{Exists=$true;Proven=$false;Ambiguous=$false;Role=$Role;Path=$Path;Commit=$null;Date=$null;Current=$false;Size=$size;Sha256=$null;MatchCount=0;Reason='file-size-out-of-range'}
    }
    $fileSha=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $matches=@($Catalog|Where-Object{[int64]$_.Size -eq $size -and [string]$_.Sha256 -ceq $fileSha})
    if($matches.Count -gt 1){
        return [pscustomobject]@{Exists=$true;Proven=$false;Ambiguous=$true;Role=$Role;Path=$Path;Commit=$null;Date=$null;Current=$false;Size=$size;Sha256=$fileSha;MatchCount=$matches.Count;Reason='catalog-ambiguous'}
    }
    if($matches.Count -eq 1){
        $m=$matches[0]
        return [pscustomobject]@{Exists=$true;Proven=$true;Ambiguous=$false;Role=$Role;Path=$Path;Commit=[string]$m.Commit;Date=[string]$m.Date;Current=[bool]$m.Current;Size=$size;Sha256=$fileSha;MatchCount=1;Reason='exact-official-commit-snapshot'}
    }
    return [pscustomobject]@{Exists=$true;Proven=$false;Ambiguous=$false;Role=$Role;Path=$Path;Commit=$null;Date=$null;Current=$false;Size=$size;Sha256=$fileSha;MatchCount=0;Reason='catalog-mismatch'}
}

function Resolve-SCCoverAmbienceInstalledSnapshotProvenance {
    param(
        [string]$AppDataRoot=$env:APPDATA,
        [string]$LocalAppDataRoot=$env:LOCALAPPDATA,
        $Catalog=$(Get-SCCoverAmbienceSnapshotCatalog)
    )
    $candidates=New-Object System.Collections.Generic.List[object]
    if(-not [string]::IsNullOrWhiteSpace($AppDataRoot)){
        $candidates.Add([pscustomobject]@{Role='source';Label='roaming-sc';Path=(Join-Path $AppDataRoot 'spicetify\Extensions\sc-cover-ambience.js')})
        $candidates.Add([pscustomobject]@{Role='source';Label='roaming-plain';Path=(Join-Path $AppDataRoot 'spicetify\Extensions\CoverAmbience.js')})
        $candidates.Add([pscustomobject]@{Role='active';Label='roaming-sc';Path=(Join-Path $AppDataRoot 'Spotify\Apps\xpui\extensions\sc-cover-ambience.js')})
        $candidates.Add([pscustomobject]@{Role='active';Label='roaming-plain';Path=(Join-Path $AppDataRoot 'Spotify\Apps\xpui\extensions\CoverAmbience.js')})
    }
    if(-not [string]::IsNullOrWhiteSpace($LocalAppDataRoot)){
        $candidates.Add([pscustomobject]@{Role='source';Label='local-sc';Path=(Join-Path $LocalAppDataRoot 'spicetify\Extensions\sc-cover-ambience.js')})
        $candidates.Add([pscustomobject]@{Role='source';Label='local-plain';Path=(Join-Path $LocalAppDataRoot 'spicetify\Extensions\CoverAmbience.js')})
        $candidates.Add([pscustomobject]@{Role='active';Label='local-sc';Path=(Join-Path $LocalAppDataRoot 'Spotify\Apps\xpui\extensions\sc-cover-ambience.js')})
        $candidates.Add([pscustomobject]@{Role='active';Label='local-plain';Path=(Join-Path $LocalAppDataRoot 'Spotify\Apps\xpui\extensions\CoverAmbience.js')})
    }
    $seen=@{}
    $proofs=New-Object System.Collections.Generic.List[object]
    foreach($candidate in $candidates){
        $full=[System.IO.Path]::GetFullPath([string]$candidate.Path)
        if($seen.ContainsKey($full)){continue}
        $seen[$full]=$true
        $p=Get-SCCoverAmbienceFileSnapshotProvenance -Path $full -Role ([string]$candidate.Role) -Catalog $Catalog
        Set-ObjectNoteProperty -Object $p -Name 'Label' -Value ([string]$candidate.Label)
        $proofs.Add($p)
    }
    $existing=@($proofs|Where-Object{$_.Exists})
    if($existing.Count -eq 0){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Commit=$null;Date=$null;Current=$false;ProofKind=$null;SourceSha256=$null;ActiveSha256=$null;SourceCount=0;ActiveCount=0;Reason='no-local-cover-ambience-files';Files=$proofs.ToArray()}
    }
    $unproven=@($existing|Where-Object{-not [bool]$_.Proven})
    if($unproven.Count -gt 0){
        return [pscustomobject]@{Proven=$false;Ambiguous=(@($unproven|Where-Object{$_.Ambiguous}).Count -gt 0);Commit=$null;Date=$null;Current=$false;ProofKind='unrecognized-local-file-present';SourceSha256=$null;ActiveSha256=$null;SourceCount=@($existing|Where-Object{$_.Role -ceq 'source'}).Count;ActiveCount=@($existing|Where-Object{$_.Role -ceq 'active'}).Count;Reason='one-or-more-local-files-unproven';Files=$proofs.ToArray()}
    }
    $commits=@($existing|ForEach-Object{[string]$_.Commit}|Sort-Object -Unique)
    if($commits.Count -ne 1){
        return [pscustomobject]@{Proven=$false;Ambiguous=$true;Commit=$null;Date=$null;Current=$false;ProofKind='official-snapshot-divergence';SourceSha256=$null;ActiveSha256=$null;SourceCount=@($existing|Where-Object{$_.Role -ceq 'source'}).Count;ActiveCount=@($existing|Where-Object{$_.Role -ceq 'active'}).Count;Reason='multiple-official-snapshot-commits-present';Files=$proofs.ToArray()}
    }
    $commit=$commits[0]
    $matching=@($existing|Where-Object{[string]$_.Commit -ceq $commit})
    $source=@($matching|Where-Object{$_.Role -ceq 'source'})
    $active=@($matching|Where-Object{$_.Role -ceq 'active'})
    $sourceSha=if($source.Count -gt 0){[string]$source[0].Sha256}else{$null}
    $activeSha=if($active.Count -gt 0){[string]$active[0].Sha256}else{$null}
    $kind=if($source.Count -gt 0 -and $active.Count -gt 0){'source-active-exact-official-snapshot-v1'}elseif($source.Count -gt 0){'source-exact-official-snapshot-v1'}else{'active-exact-official-snapshot-v1'}
    return [pscustomobject]@{Proven=$true;Ambiguous=$false;Commit=$commit;Date=[string]$matching[0].Date;Current=[bool]$matching[0].Current;ProofKind=$kind;SourceSha256=$sourceSha;ActiveSha256=$activeSha;SourceCount=$source.Count;ActiveCount=$active.Count;Reason='all-present-files-match-one-official-snapshot';Files=$proofs.ToArray()}
}

function Get-SCCoverAmbienceRemoteHead {
    param($Catalog=$(Get-SCCoverAmbienceSnapshotCatalog))
    $rows=@(Invoke-GitHubJson 'https://api.github.com/repos/Theblockbuster1/spicetify-extensions/commits?path=CoverAmbience%2FCoverAmbience.js&per_page=1')
    if($rows.Count -lt 1){throw 'SC Cover Ambience upstream path history returned no commits.'}
    $commit=[string]$rows[0].sha
    if($commit -notmatch '^[0-9a-f]{40}$'){throw "SC Cover Ambience upstream head commit is invalid: $commit"}
    $matches=@($Catalog|Where-Object{[string]$_.Commit -ceq $commit})
    if($matches.Count -gt 1){throw 'SC Cover Ambience upstream head matched multiple frozen snapshots.'}
    return [pscustomobject]@{Commit=$commit;CatalogKnown=($matches.Count -eq 1);CatalogCurrent=($matches.Count -eq 1 -and [bool]$matches[0].Current);Date=$(if($matches.Count -eq 1){[string]$matches[0].Date}else{$null});Sha256=$(if($matches.Count -eq 1){[string]$matches[0].Sha256}else{$null})}
}

'''.replace('__CATALOG__', catalog_rows)
    text = text[:insert] + '\n' + helpers + text[insert:]

    inventory = function_block(text, 'Get-AddonInventory')
    anchor = '    $registrySummary = Add-AddonPolicyRegistryMetadata -Items $items.ToArray()'
    if inventory.count(anchor) != 1:
        raise RuntimeError(f'Cover Ambience enrichment anchor drifted: {inventory.count(anchor)}')
    enrichment = r'''    # SC Cover Ambience remains recovery/Marketplace-owned and mutation denied. This is read-only provenance only.
    $coverItems=@($items|Where-Object{[string]$_.name -ceq 'sc-cover-ambience.js' -and [string]$_.kind -ceq 'extension'})
    if($coverItems.Count -eq 1){
        $coverItem=$coverItems[0]
        try{
            $coverCatalog=@(Get-SCCoverAmbienceSnapshotCatalog)
            $coverProof=Resolve-SCCoverAmbienceInstalledSnapshotProvenance -Catalog $coverCatalog
            $coverRemote=Get-SCCoverAmbienceRemoteHead -Catalog $coverCatalog
            $coverStatus=if([bool]$coverProof.Ambiguous){'watched-local-snapshot-ambiguous'}elseif(-not [bool]$coverProof.Proven){'watched-local-snapshot-unproven'}elseif(-not [bool]$coverRemote.CatalogKnown){'watched-upstream-head-unproven-new-snapshot'}elseif([string]$coverProof.Commit -ceq [string]$coverRemote.Commit){'watched-current-proven'}elseif([bool]$coverRemote.CatalogCurrent){'watched-update-available-proven-local'}else{'watched-remote-head-historical-divergence'}
            Set-ObjectNoteProperty -Object $coverItem -Name 'provenance_status' -Value $coverStatus
            Set-ObjectNoteProperty -Object $coverItem -Name 'proof_kind' -Value ([string]$coverProof.ProofKind)
            Set-ObjectNoteProperty -Object $coverItem -Name 'local_snapshot_commit' -Value ([string]$coverProof.Commit)
            Set-ObjectNoteProperty -Object $coverItem -Name 'local_snapshot_date' -Value ([string]$coverProof.Date)
            Set-ObjectNoteProperty -Object $coverItem -Name 'local_snapshot_current' -Value ([bool]$coverProof.Current)
            Set-ObjectNoteProperty -Object $coverItem -Name 'source_sha256' -Value ([string]$coverProof.SourceSha256)
            Set-ObjectNoteProperty -Object $coverItem -Name 'active_sha256' -Value ([string]$coverProof.ActiveSha256)
            Set-ObjectNoteProperty -Object $coverItem -Name 'source_copy_count' -Value ([int]$coverProof.SourceCount)
            Set-ObjectNoteProperty -Object $coverItem -Name 'active_copy_count' -Value ([int]$coverProof.ActiveCount)
            Set-ObjectNoteProperty -Object $coverItem -Name 'remote_snapshot_commit' -Value ([string]$coverRemote.Commit)
            Set-ObjectNoteProperty -Object $coverItem -Name 'remote_snapshot_catalog_known' -Value ([bool]$coverRemote.CatalogKnown)
            Set-ObjectNoteProperty -Object $coverItem -Name 'provenance_catalog_sha256' -Value 'c12391e57a393d37d70ffd7a984bdbb6af9f4a83cf3c2b0a8c9bf040247c731f'
            Set-ObjectNoteProperty -Object $coverItem -Name 'ownership_migration_authorized' -Value $false
            Set-ObjectNoteProperty -Object $coverItem -Name 'disable_or_optimize_authorized' -Value $false
            Set-ObjectNoteProperty -Object $coverItem -Name 'provenance_note' -Value 'Read-only exact official commit-snapshot provenance. Dual ownership is observed but cleanup/update/disable/optimization remain unauthorized.'
        }catch{
            Set-ObjectNoteProperty -Object $coverItem -Name 'provenance_status' -Value 'check-error'
            Set-ObjectNoteProperty -Object $coverItem -Name 'proof_kind' -Value $null
            Set-ObjectNoteProperty -Object $coverItem -Name 'local_snapshot_commit' -Value $null
            Set-ObjectNoteProperty -Object $coverItem -Name 'local_snapshot_date' -Value $null
            Set-ObjectNoteProperty -Object $coverItem -Name 'local_snapshot_current' -Value $false
            Set-ObjectNoteProperty -Object $coverItem -Name 'source_sha256' -Value $null
            Set-ObjectNoteProperty -Object $coverItem -Name 'active_sha256' -Value $null
            Set-ObjectNoteProperty -Object $coverItem -Name 'source_copy_count' -Value 0
            Set-ObjectNoteProperty -Object $coverItem -Name 'active_copy_count' -Value 0
            Set-ObjectNoteProperty -Object $coverItem -Name 'remote_snapshot_commit' -Value $null
            Set-ObjectNoteProperty -Object $coverItem -Name 'remote_snapshot_catalog_known' -Value $false
            Set-ObjectNoteProperty -Object $coverItem -Name 'provenance_catalog_sha256' -Value 'c12391e57a393d37d70ffd7a984bdbb6af9f4a83cf3c2b0a8c9bf040247c731f'
            Set-ObjectNoteProperty -Object $coverItem -Name 'ownership_migration_authorized' -Value $false
            Set-ObjectNoteProperty -Object $coverItem -Name 'disable_or_optimize_authorized' -Value $false
            Set-ObjectNoteProperty -Object $coverItem -Name 'provenance_error' -Value $_.Exception.Message
            Set-ObjectNoteProperty -Object $coverItem -Name 'provenance_note' -Value 'SC Cover Ambience remains untouched because read-only provenance monitoring failed closed.'
        }
    }

'''
    inventory = inventory.replace(anchor, enrichment + anchor, 1)
    old_inventory = function_block(text, 'Get-AddonInventory')
    if text.count(old_inventory) != 1:
        raise RuntimeError('Get-AddonInventory replacement cardinality drifted')
    text = text.replace(old_inventory, inventory, 1)
    return bom + text.encode('utf-8')


def validate_candidate(base_addon: bytes, candidate_addon: bytes) -> None:
    base = base_addon.decode('utf-8-sig').replace('\r\n', '\n')
    cand = candidate_addon.decode('utf-8-sig').replace('\r\n', '\n')
    base_funcs = function_map(base)
    cand_funcs = function_map(cand)
    allowed_changed = {'Get-AddonInventory'}
    new_helpers = {
        'Get-SCCoverAmbienceSnapshotCatalog',
        'Get-SCCoverAmbienceFileSnapshotProvenance',
        'Resolve-SCCoverAmbienceInstalledSnapshotProvenance',
        'Get-SCCoverAmbienceRemoteHead',
    }
    for name, block in base_funcs.items():
        if name in allowed_changed:
            continue
        if cand_funcs.get(name) != block:
            raise RuntimeError(f'existing function changed unexpectedly: {name}')
    if not new_helpers.issubset(cand_funcs):
        raise RuntimeError(f'SC Cover Ambience helper set incomplete: {sorted(new_helpers - set(cand_funcs))}')

    for name in ('Get-SCCoverAmbienceSnapshotCatalog','Get-SCCoverAmbienceFileSnapshotProvenance','Resolve-SCCoverAmbienceInstalledSnapshotProvenance'):
        block = cand_funcs[name]
        for forbidden in ('Invoke-WebRequest','Invoke-RestMethod','Remove-Item','Copy-Item','Move-Item','Set-Content','Add-Content','Start-Process','Stop-Process','spicetify apply','spicetify backup','spicetify restore','IndexedDB','localStorage','Local Storage','\\Browser\\','\\Default\\'):
            if forbidden.lower() in block.lower():
                raise RuntimeError(f'{name} gained forbidden side effect/data access: {forbidden}')
    remote = cand_funcs['Get-SCCoverAmbienceRemoteHead']
    if 'Invoke-GitHubJson' not in remote or 'CoverAmbience%2FCoverAmbience.js' not in remote:
        raise RuntimeError('SC Cover Ambience remote head helper contract missing')
    for forbidden in ('Remove-Item','Copy-Item','Move-Item','Set-Content','Start-Process','spicetify apply'):
        if forbidden.lower() in remote.lower():
            raise RuntimeError(f'remote head helper gained mutation surface: {forbidden}')

    registry = function_block(cand, 'Get-AddonPolicyRegistry')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED_NAMES):
        raise RuntimeError(f'auto authority drift: {auto}')
    for marker in (
        "name='sc-cover-ambience.js'", "source='Theblockbuster1/spicetify-extensions'",
        "inventory_policy='rescue-copy-cleanup-only'", "mutation_mode='deny'",
        "install_mode='recovery-owned'", "version_strategy='owner-cleanup-only'",
        "rollback_strategy='external-owner'", "data_policy='never-disable-or-optimize'",
        "name='star-ratings'", "playlist-backed-ratings-preserve", "protect-ratings-tags-notes"
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f'protected policy missing: {marker}')

    update = function_block(cand, 'Update-AutoApps')
    if 'sc-cover-ambience' in update.lower():
        raise RuntimeError('SC Cover Ambience gained an automatic mutation route')
    rollback = function_block(cand, 'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback:
        raise RuntimeError('RollbackLast became source-adapter-dependent')

    resolver = cand_funcs['Resolve-SCCoverAmbienceInstalledSnapshotProvenance']
    for required in ('source-active-exact-official-snapshot-v1','official-snapshot-divergence','one-or-more-local-files-unproven','sc-cover-ambience.js','CoverAmbience.js'):
        if required not in resolver:
            raise RuntimeError(f'SC Cover Ambience resolver contract missing: {required}')
    inventory = cand_funcs['Get-AddonInventory']
    for required in (
        'Resolve-SCCoverAmbienceInstalledSnapshotProvenance', 'Get-SCCoverAmbienceRemoteHead',
        'watched-current-proven', 'watched-update-available-proven-local',
        'watched-upstream-head-unproven-new-snapshot', CATALOG_FINGERPRINT,
        'ownership_migration_authorized', 'disable_or_optimize_authorized',
        'cleanup/update/disable/optimization remain unauthorized'
    ):
        if required not in inventory:
            raise RuntimeError(f'SC Cover Ambience inventory provenance contract missing: {required}')


def build() -> None:
    catalog = load_catalog()
    base_main, base_addon = build_base()
    main = patch_main(base_main)
    addon = patch_addon(base_addon, catalog)
    validate_candidate(base_addon, addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'spotify-control.ps1').write_bytes(main)
    (OUT / 'addon-manager.ps1').write_bytes(addon)
    report = {
        'schema': 1,
        'base_version': '0.6.27',
        'version': '0.6.28-candidate',
        'addon_version': '0.6.5-r17-candidate',
        'base_main': {'size': BASE_MAIN_SIZE, 'sha256': BASE_MAIN_SHA},
        'base_addon': {'size': BASE_ADDON_SIZE, 'sha256': BASE_ADDON_SHA},
        'candidate_main': {'size': len(main), 'sha256': sha(main)},
        'candidate_addon': {'size': len(addon), 'sha256': sha(addon)},
        'snapshot_catalog': {
            'source_commit': CATALOG_COMMIT,
            'source_path': CATALOG_PATH,
            'source_blob': CATALOG_BLOB,
            'audit_catalog_payload_sha256': CATALOG_FINGERPRINT,
            'snapshot_count': len(catalog['snapshots']),
            'current_commit': CURRENT_COMMIT,
            'current_size': CURRENT_SIZE,
            'current_sha256': CURRENT_SHA,
        },
        'audit_evidence': {
            'pr': AUDIT_PR, 'head': AUDIT_HEAD, 'run': AUDIT_RUN,
            'artifact_id': AUDIT_ARTIFACT, 'artifact_digest': AUDIT_ARTIFACT_DIGEST,
            'pr_closed_unmerged': True,
        },
        'collector_evidence': {
            'pr': COLLECTOR_PR, 'head': COLLECTOR_HEAD, 'run': COLLECTOR_RUN,
            'artifact_id': COLLECTOR_ARTIFACT, 'artifact_digest': COLLECTOR_ARTIFACT_DIGEST,
            'pr_closed_unmerged': True,
        },
        'real_pc_evidence': {
            'report_size': REAL_PC_REPORT_SIZE,
            'report_sha256': REAL_PC_REPORT_SHA,
            'topology': 'dual-owned-risk',
            'marketplace_installed': True,
            'persistent_configured': True,
            'source_exact_current_snapshot': True,
            'active_exact_current_snapshot': True,
            'safe_to_expand_mutation_authority': False,
            'safe_to_auto_remove_direct_copy': False,
            'disable_or_optimize': False,
            'raw_report_committed': False,
        },
        'authority_expanded': False,
        'new_auto_install_authority': False,
        'ownership_migration_authorized': False,
        'disable_or_optimize_authorized': False,
        'auto_authority': AUTHORIZED_NAMES,
        'registry_fingerprint': REGISTRY_SHA,
        'source_adapter_fingerprint': ADAPTER_SHA,
        'cover_ambience_policy': {
            'inventory_policy': 'rescue-copy-cleanup-only',
            'mutation_mode': 'deny',
            'install_mode': 'recovery-owned',
            'version_strategy': 'owner-cleanup-only',
            'rollback_strategy': 'external-owner',
            'data_policy': 'never-disable-or-optimize',
        },
        'provenance_inputs': ['local-source-files-exact-official-snapshot','active-xpui-files-exact-official-snapshot','github-path-head-read-only'],
        'excluded_inputs': ['marketplace-indexeddb-localstorage','spotify-user-data','ownership-migration','direct-copy-cleanup','performance-transform'],
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('SC_COVER_AMBIENCE_PROVENANCE_CANDIDATE_BUILD_PASS', len(main), sha(main), len(addon), sha(addon), CATALOG_FINGERPRINT)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    if not args.build:
        parser.error('use --build')
    build()


if __name__ == '__main__':
    main()
