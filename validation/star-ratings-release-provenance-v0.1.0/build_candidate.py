from pathlib import Path
import argparse, hashlib, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.26/out/bin'
OUT = ROOT / 'validation/star-ratings-release-provenance-v0.1.0/out/bin'
REPORT = ROOT / 'validation/star-ratings-release-provenance-v0.1.0/candidate-report.json'

BASE_MAIN_SIZE = 284311
BASE_MAIN_SHA = 'd7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1'
BASE_ADDON_SIZE = 291294
BASE_ADDON_SHA = '4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']

AUDIT_HEAD = '52a9c0f633c87a0f4ce70077aaec22e72f9b9d8f'
AUDIT_RUN = 40460929873
AUDIT_ARTIFACT = 12714720971
AUDIT_ARTIFACT_DIGEST = 'sha256:161a1619ffea938eec444add714f4cbb330d3fc05c2aa88c7dc3190d3d63d05a'
AUDIT_CATALOG_JSON_SHA = '2592f43a26c3c49b9d58b8244654d27448d801995465c7c8e4ba8d3159b9aa27'

TRANSFORMED_SHA = '6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3'
PERF_ID = 'star-ratings-observer-debounce-v1'

RELEASES = [
    {'version':'2.0.0','tag':'2.0.0','commit':'81f4f388224c69c7b6abb22da2c5237d1147f073','size':36186,'sha256':'da28f23d88e083cfac2e720e9bdb9c6eac1a13f271fe4a2558e4d5695ac8b980'},
    {'version':'2.0.1','tag':'2.0.1','commit':'ffc9ba678731aabe2f36bf4d5b83a9ff485a0730','size':36223,'sha256':'013c62556b3be601e431b4c19d3a3d1fd4a8244883dca99fb40d21cd4ec476fd'},
    {'version':'2.0.2','tag':'2.0.2','commit':'57cb632da888c06accc1914b845095f8c232dae8','size':36240,'sha256':'a517351335f4276b789a820973a5047ed5ef654aa777ee9d9a7d6d5bfe37c7b8'},
    {'version':'2.0.3','tag':'2.0.3','commit':'565ec483a60775f4d3a66ec48f50768d38ba61f3','size':37151,'sha256':'f00a8bdf49a64868de5b039c1fd454fe25afda4e9ac68cfc72e57005913eb012'},
    {'version':'2.0.4','tag':'2.0.4','commit':'83d339f9bde3bf5d6536a7781eb31dc66e0eb4ae','size':41589,'sha256':'34f92bf6674d4904487db29ff0dfa2630623b807ca329657e9537a912ab376b4'},
    {'version':'2.0.5','tag':'2.0.5','commit':'196b95a12a84366fd3590da4c1a9f365c1c27b6c','size':41591,'sha256':'2433a84ae126643d517038974d57c875911cee36d4773f7a99d3a37292b878d3'},
    {'version':'2.0.6','tag':'2.0.6','commit':'644c0fc9e8b57af556e6107c08e43e1ed05b1498','size':41547,'sha256':'7d72ab5bff513fe7fce41a4083c30897a20a47bf9a31e1eaa6b49b51cd37014f'},
    {'version':'2.0.7','tag':'2.0.7','commit':'3a8cbd7faac9b13bc59c51046f32c27e1e5c493a','size':41353,'sha256':'a40857ba4ea137008ede75a0845e131973b1d6cfc0c823572a614e0267355324'},
    {'version':'2.0.8','tag':'2.0.8','commit':'6807876930f946b10f9ee21d31e09d16ebe209aa','size':41709,'sha256':'e8f57bec17c239516d3f6ffc744a4163cbc3f64dc01e3d96617a8fd90e29d555'},
    {'version':'2.1.0','tag':'2.1.0','commit':'a514c3d9e06f95b4e178834f7e05cb9dc7642ccf','size':42916,'sha256':'8dfb700c18f6f59e51760ea055833981e6ff9f08eb09f5d2a9342c24cb39735a'},
    {'version':'2.1.1','tag':'2.1.1','commit':'a48ffda3a02ded9a03a22958fa74df6ab862be61','size':43289,'sha256':'f014aaab876fabfce4e5e2eda7bc9ac9b7875d30ceae63c55817a1c43b7dc142'},
    {'version':'2.1.2','tag':'2.1.2','commit':'1a4e435dfaf1ed0f33cb08cea0e4a29db7c0db96','size':43372,'sha256':'08bf683c18685d45d2b418beb1315d0b5c512668c114dfba181eb549c82b34bd'},
    {'version':'2.1.3','tag':'2.1.3','commit':'0698684b95a984b6726618e1b4541e0f830b93f2','size':43396,'sha256':'198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1'},
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
    subprocess.check_call([sys.executable, str(ROOT/'validation/v0.6.26/build_v0626.py'), '--build'], cwd=ROOT)
    main = (BASE_OUT/'spotify-control.ps1').read_bytes()
    addon = (BASE_OUT/'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError(f'v0.6.26 main base drift: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError(f'r15 addon base drift: {len(addon)} {sha(addon)}')
    return main, addon


def patch_main(base: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text = base[len(bom):].decode('utf-8')
    old_title = '# Spotify Control v0.6.26 Tagify Release Provenance r15'
    if text.count(old_title) != 1 or text.count('$ScriptVersion = "0.6.26"') != 1:
        raise RuntimeError('main version/title anchors drifted')
    text = text.replace(old_title, '# Spotify Control v0.6.27 Star Ratings Release Provenance r16', 1)
    text = text.replace('$ScriptVersion = "0.6.26"', '$ScriptVersion = "0.6.27"', 1)
    return bom + text.encode('utf-8')


def patch_addon(base: bytes) -> bytes:
    bom = b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text = base[len(bom):].decode('utf-8')
    if '\r\n' in text:
        raise RuntimeError('unexpected CRLF in r15 addon base')
    if text.count('$Version = "0.6.5-r15"') != 1:
        raise RuntimeError('addon version anchor drifted')
    text = text.replace('$Version = "0.6.5-r15"', '$Version = "0.6.5-r16"', 1)

    inventory_marker = '\nfunction Get-AddonInventory {'
    insert = text.find(inventory_marker)
    if insert < 0:
        raise RuntimeError('Get-AddonInventory insertion point drifted')

    catalog_rows = ',\n'.join(
        "        [pscustomobject]@{Version='%s';Tag='%s';TagCommit='%s';Size=[int64]%d;Sha256='%s'}" %
        (r['version'], r['tag'], r['commit'], r['size'], r['sha256'])
        for r in RELEASES
    )
    helpers = r'''
function Get-StarRatingsReleaseCatalog {
    return @(
__CATALOG__
    )
}

function Get-StarRatingsReleaseFileProvenance {
    param([string]$Path,$Catalog=$(Get-StarRatingsReleaseCatalog))
    if([string]::IsNullOrWhiteSpace($Path) -or -not (Test-PathSafe $Path 'Leaf')){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;Size=[int64]0;Sha256=$null;MatchCount=0;Reason='source-file-missing'}
    }
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;Size=[int64]$item.Length;Sha256=$null;MatchCount=0;Reason='source-file-reparse-point'}
    }
    $size=[int64]$item.Length
    if($size -lt 1 -or $size -gt 8MB){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;Size=$size;Sha256=$null;MatchCount=0;Reason='source-file-size-out-of-range'}
    }
    $fileSha=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $matches=@($Catalog|Where-Object{[int64]$_.Size -eq $size -and [string]$_.Sha256 -ceq $fileSha})
    if($matches.Count -gt 1){
        return [pscustomobject]@{Proven=$false;Ambiguous=$true;Version=$null;Tag=$null;TagCommit=$null;Size=$size;Sha256=$fileSha;MatchCount=$matches.Count;Reason='catalog-ambiguous'}
    }
    if($matches.Count -eq 1){
        $m=$matches[0]
        return [pscustomobject]@{Proven=$true;Ambiguous=$false;Version=[string]$m.Version;Tag=[string]$m.Tag;TagCommit=[string]$m.TagCommit;Size=$size;Sha256=$fileSha;MatchCount=1;Reason='exact-release-dist-match'}
    }
    return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;Size=$size;Sha256=$fileSha;MatchCount=0;Reason='catalog-mismatch'}
}

function Resolve-StarRatingsInstalledReleaseProvenance {
    param(
        [string]$AppDataRoot=$env:APPDATA,
        [string]$LocalAppDataRoot=$env:LOCALAPPDATA,
        $Catalog=$(Get-StarRatingsReleaseCatalog)
    )
    $transformedSha='6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3'
    $perfId='star-ratings-observer-debounce-v1'
    if([string]::IsNullOrWhiteSpace($AppDataRoot)){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;ProofKind=$null;SourcePath=$null;SourceSha256=$null;ActivePath=$null;ActiveSha256=$null;ActiveMode='unavailable';Reason='appdata-unavailable'}
    }
    $active=Join-Path $AppDataRoot 'Spotify\Apps\xpui\extensions\sc-star-ratings.js'
    $activeProof=Get-StarRatingsReleaseFileProvenance -Path $active -Catalog $Catalog
    if([bool]$activeProof.Proven){
        return [pscustomobject]@{Proven=$true;Ambiguous=$false;Version=[string]$activeProof.Version;Tag=[string]$activeProof.Tag;TagCommit=[string]$activeProof.TagCommit;ProofKind='active-exact-upstream-dist-v1';SourcePath=$active;SourceSha256=[string]$activeProof.Sha256;ActivePath=$active;ActiveSha256=[string]$activeProof.Sha256;ActiveMode='original';Reason='exact-active-upstream-dist'}
    }
    if([bool]$activeProof.Ambiguous){
        return [pscustomobject]@{Proven=$false;Ambiguous=$true;Version=$null;Tag=$null;TagCommit=$null;ProofKind='active-catalog-ambiguous';SourcePath=$active;SourceSha256=[string]$activeProof.Sha256;ActivePath=$active;ActiveSha256=[string]$activeProof.Sha256;ActiveMode='unknown';Reason='active-catalog-ambiguous'}
    }
    if(-not (Test-PathSafe $active 'Leaf')){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;ProofKind=$null;SourcePath=$null;SourceSha256=$null;ActivePath=$active;ActiveSha256=$null;ActiveMode='absent';Reason='active-file-missing'}
    }
    $activeSha=(Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash.ToLowerInvariant()
    if($activeSha -cne $transformedSha){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;ProofKind='active-unrecognized';SourcePath=$active;SourceSha256=$activeSha;ActivePath=$active;ActiveSha256=$activeSha;ActiveMode='unknown';Reason='active-bytes-not-catalog-or-known-transform'}
    }
    if([string]::IsNullOrWhiteSpace($LocalAppDataRoot)){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;ProofKind='known-transform-without-state';SourcePath=$null;SourceSha256=$null;ActivePath=$active;ActiveSha256=$activeSha;ActiveMode='transformed';Reason='localappdata-unavailable'}
    }
    $stateRoot=Join-Path $LocalAppDataRoot 'SpotifyControl\star-ratings-performance\runtime-v1'
    $statePath=Join-Path $stateRoot 'active-state.json'
    $expectedBackup=Join-Path (Join-Path $stateRoot $perfId) 'original.bin'
    if(-not (Test-PathSafe $statePath 'Leaf')){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;ProofKind='known-transform-without-state';SourcePath=$null;SourceSha256=$null;ActivePath=$active;ActiveSha256=$activeSha;ActiveMode='transformed';Reason='performance-state-missing'}
    }
    try{$state=Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop|ConvertFrom-Json}catch{
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;ProofKind='known-transform-invalid-state';SourcePath=$null;SourceSha256=$null;ActivePath=$active;ActiveSha256=$activeSha;ActiveMode='transformed';Reason='performance-state-invalid-json'}
    }
    $activeFull=[System.IO.Path]::GetFullPath($active)
    $stateActive=if([string]::IsNullOrWhiteSpace([string]$state.path)){$null}else{[System.IO.Path]::GetFullPath([string]$state.path)}
    $backupFull=[System.IO.Path]::GetFullPath($expectedBackup)
    $stateBackup=if([string]::IsNullOrWhiteSpace([string]$state.backup_path)){$null}else{[System.IO.Path]::GetFullPath([string]$state.backup_path)}
    $stateValid=([int]$state.schema -eq 1 -and [string]$state.id -ceq $perfId -and [string]$state.source_repository -ceq 'brimell/spicetify-star-ratings' -and [string]$state.transformed_sha256 -ceq $transformedSha -and $stateActive -and $stateActive.Equals($activeFull,[System.StringComparison]::OrdinalIgnoreCase) -and $stateBackup -and $stateBackup.Equals($backupFull,[System.StringComparison]::OrdinalIgnoreCase))
    if(-not $stateValid){
        return [pscustomobject]@{Proven=$false;Ambiguous=$false;Version=$null;Tag=$null;TagCommit=$null;ProofKind='known-transform-invalid-state';SourcePath=$null;SourceSha256=$null;ActivePath=$active;ActiveSha256=$activeSha;ActiveMode='transformed';Reason='performance-state-contract-mismatch'}
    }
    $backupProof=Get-StarRatingsReleaseFileProvenance -Path $expectedBackup -Catalog $Catalog
    if(-not [bool]$backupProof.Proven -or [string]$state.original_sha256 -cne [string]$backupProof.Sha256){
        return [pscustomobject]@{Proven=$false;Ambiguous=[bool]$backupProof.Ambiguous;Version=$null;Tag=$null;TagCommit=$null;ProofKind='known-transform-backup-unproven';SourcePath=$expectedBackup;SourceSha256=[string]$backupProof.Sha256;ActivePath=$active;ActiveSha256=$activeSha;ActiveMode='transformed';Reason='performance-original-backup-unproven'}
    }
    return [pscustomobject]@{Proven=$true;Ambiguous=$false;Version=[string]$backupProof.Version;Tag=[string]$backupProof.Tag;TagCommit=[string]$backupProof.TagCommit;ProofKind='performance-original-backup-v1';SourcePath=$expectedBackup;SourceSha256=[string]$backupProof.Sha256;ActivePath=$active;ActiveSha256=$activeSha;ActiveMode='transformed';Reason='exact-performance-original-backup'}
}

'''.replace('__CATALOG__', catalog_rows)
    text = text[:insert] + '\n' + helpers + text[insert:]

    old_start = text.find('    # Star Ratings is Marketplace-managed and not a filesystem CustomApp.')
    old_end = text.find('    # Direct extensions are ownership-classified separately.', old_start)
    if old_start < 0 or old_end < 0:
        raise RuntimeError('Star Ratings inventory block anchors drifted')
    new_block = r'''    # Star Ratings - Marketplace ownership stays mutation-denied. Local release provenance is read-only and never uses the rescue copy.
    # Ratings themselves remain Spotify playlists. An exact version is inferred only from an official release dist hash, either active-original
    # or the exact original.bin bound by the existing performance active-state when the active xpui copy is the known transformed hash.
    try {
        $starProof=Resolve-StarRatingsInstalledReleaseProvenance
        $starRelease=Invoke-GitHubJson 'https://api.github.com/repos/brimell/spicetify-star-ratings/releases/latest'
        if([bool]$starRelease.draft -or [bool]$starRelease.prerelease){throw 'Star Ratings latest release is not stable.'}
        $starRemote=[string]$starRelease.tag_name
        if($starRemote -notmatch '^\d+\.\d+\.\d+$'){throw "Star Ratings latest release tag is not strict semver: $starRemote"}
        $starCatalog=@(Get-StarRatingsReleaseCatalog)
        $remoteKnown=@($starCatalog|Where-Object{[string]$_.Version -ceq $starRemote})
        $starRemoteCommit=if($remoteKnown.Count -eq 1){[string]$remoteKnown[0].TagCommit}else{$null}
        $starLocal=if([bool]$starProof.Proven){[string]$starProof.Version}else{$null}
        $starStatus=if([bool]$starProof.Ambiguous){'watched-local-release-ambiguous-catalog'}elseif(-not [bool]$starProof.Proven){'watched-local-release-unproven'}else{
            $localSem=[version]$starLocal;$remoteSem=[version]$starRemote
            if($localSem -eq $remoteSem){'watched-current-proven'}elseif($localSem -lt $remoteSem){'watched-update-available-proven-local'}else{'watched-local-newer-than-remote-proven'}
        }
        $items.Add([pscustomobject]@{
            name='star-ratings';kind='marketplace-extension';policy='source-watch-only';installed=$(if([bool]$starProof.Proven){$true}else{$null})
            local=$starLocal;remote=$starRemote;revision=$starRemoteCommit;status=$starStatus
            source='brimell/spicetify-star-ratings';download=$null;digest=$null
            proof_kind=[string]$starProof.ProofKind;local_release_tag=$(if($starLocal){$starLocal}else{$null});local_tag_commit=[string]$starProof.TagCommit
            source_sha256=[string]$starProof.SourceSha256;active_sha256=[string]$starProof.ActiveSha256;active_mode=[string]$starProof.ActiveMode
            provenance_catalog_sha256='2592f43a26c3c49b9d58b8244654d27448d801995465c7c8e4ba8d3159b9aa27'
            note='Ratings remain Spotify playlists. Provenance reads only exact official dist bytes or the existing performance original backup; rescue copies and transformed active bytes are never treated as release source.'
        })
    } catch {
        $items.Add([pscustomobject]@{
            name='star-ratings';kind='marketplace-extension';policy='source-watch-only';installed=$null
            local=$null;remote=$null;revision=$null;status='check-error'
            source='brimell/spicetify-star-ratings';download=$null;digest=$null;error=$_.Exception.Message
            proof_kind=$null;local_release_tag=$null;local_tag_commit=$null;source_sha256=$null;active_sha256=$null;active_mode=$null
            provenance_catalog_sha256='2592f43a26c3c49b9d58b8244654d27448d801995465c7c8e4ba8d3159b9aa27'
            note='Star Ratings remains untouched because read-only provenance monitoring failed closed.'
        })
    }

'''
    text = text[:old_start] + new_block + text[old_end:]
    return bom + text.encode('utf-8')


def validate_candidate(base_addon: bytes, candidate_addon: bytes):
    base = base_addon.decode('utf-8-sig').replace('\r\n','\n')
    cand = candidate_addon.decode('utf-8-sig').replace('\r\n','\n')
    base_funcs=function_map(base);cand_funcs=function_map(cand)
    allowed_changed={'Get-AddonInventory'}
    new_helpers={'Get-StarRatingsReleaseCatalog','Get-StarRatingsReleaseFileProvenance','Resolve-StarRatingsInstalledReleaseProvenance'}
    for name, block in base_funcs.items():
        if name in allowed_changed: continue
        if cand_funcs.get(name)!=block: raise RuntimeError(f'existing function changed unexpectedly: {name}')
    if not new_helpers.issubset(cand_funcs): raise RuntimeError('Star Ratings helper set incomplete')
    for name in new_helpers:
        block=cand_funcs[name]
        for forbidden in ('Invoke-WebRequest','Invoke-RestMethod','Remove-Item','Copy-Item','Move-Item','Start-Process','spicetify apply','spicetify backup','spicetify restore','Test-SpotifyStorageMarker'):
            if forbidden.lower() in block.lower(): raise RuntimeError(f'{name} gained forbidden side effect/data scan: {forbidden}')
    registry=function_block(cand,'Get-AddonPolicyRegistry')
    auto=re.findall(r"name='([^']+)'.*?mutation_mode='auto'",registry,re.I)
    if sorted(x.lower() for x in auto)!=sorted(x.lower() for x in AUTHORIZED_NAMES): raise RuntimeError(f'auto authority drift: {auto}')
    for required in ("name='star-ratings'","inventory_policy='source-watch-only'","mutation_mode='deny'","playlist-backed-ratings-preserve'","protect-ratings-tags-notes","never-disable-or-optimize"):
        if required.lower() not in registry.lower(): raise RuntimeError(f'protected policy missing: {required}')
    update=function_block(cand,'Update-AutoApps')
    if 'star-ratings' in update.lower(): raise RuntimeError('Star Ratings gained an automatic update route')
    rollback=function_block(cand,'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback: raise RuntimeError('RollbackLast became source-adapter-dependent')
    resolver=function_block(cand,'Resolve-StarRatingsInstalledReleaseProvenance')
    for required in ('runtime-v1','active-state.json','original.bin',TRANSFORMED_SHA,'performance-original-backup-v1','active-exact-upstream-dist-v1'):
        if required not in resolver: raise RuntimeError(f'Star Ratings provenance resolver missing contract: {required}')
    for forbidden in ('sc-star-ratings.js" -Kind "Extension"','Get-SpicetifyAssetRoots','Resolve-SpicetifyAsset','IndexedDB','Local Storage','Browser','Default'):
        if forbidden.lower() in resolver.lower(): raise RuntimeError(f'Star Ratings provenance resolver reads forbidden rescue/user-data surface: {forbidden}')
    inv=function_block(cand,'Get-AddonInventory')
    for required in ('Resolve-StarRatingsInstalledReleaseProvenance','watched-current-proven','watched-update-available-proven-local',AUDIT_CATALOG_JSON_SHA,'Ratings remain Spotify playlists'):
        if required not in inv: raise RuntimeError(f'Star Ratings inventory provenance contract missing: {required}')


def build():
    main_base, addon_base = build_base()
    main = patch_main(main_base)
    addon = patch_addon(addon_base)
    validate_candidate(addon_base, addon)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(main)
    (OUT/'addon-manager.ps1').write_bytes(addon)
    report={
        'schema':1,'base_version':'0.6.26','version':'0.6.27','addon_version':'0.6.5-r16',
        'base_main':{'size':BASE_MAIN_SIZE,'sha256':BASE_MAIN_SHA},'base_addon':{'size':BASE_ADDON_SIZE,'sha256':BASE_ADDON_SHA},
        'candidate_main':{'size':len(main),'sha256':sha(main)},'candidate_addon':{'size':len(addon),'sha256':sha(addon)},
        'audit':{'head':AUDIT_HEAD,'run':AUDIT_RUN,'artifact_id':AUDIT_ARTIFACT,'artifact_digest':AUDIT_ARTIFACT_DIGEST,'catalog_json_sha256':AUDIT_CATALOG_JSON_SHA},
        'release_catalog':RELEASES,'duplicate_release_dist_identities':[],
        'historical_performance_anchor':{'version':'2.1.3','size':43396,'sha256':'198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1','transformed_sha256':TRANSFORMED_SHA},
        'provenance_inputs':['active-xpui-exact-official-dist','performance-active-state-bound-original-backup'],
        'excluded_inputs':['spicetify-rescue-copy','known-transformed-active-bytes-without-valid-state','spotify-playlist-data','browser-indexeddb-localstorage'],
        'authority_expanded':False,'new_auto_install_authority':False,'auto_authority':AUTHORIZED_NAMES,
        'registry_fingerprint':REGISTRY_SHA,'source_adapter_fingerprint':ADAPTER_SHA,
        'star_ratings_policy':{'inventory_policy':'source-watch-only','mutation_mode':'deny','install_mode':'marketplace-owned','data_policy':'playlist-backed-ratings-preserve'},
    }
    REPORT.parent.mkdir(parents=True,exist_ok=True)
    REPORT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('STAR_RATINGS_V010_BUILD_PASS',len(main),sha(main),len(addon),sha(addon),AUDIT_CATALOG_JSON_SHA)


def main():
    p=argparse.ArgumentParser();p.add_argument('--build',action='store_true');args=p.parse_args()
    if not args.build:p.error('use --build')
    build()

if __name__=='__main__':main()
