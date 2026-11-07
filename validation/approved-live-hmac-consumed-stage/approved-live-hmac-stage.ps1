# V029 / real approved CustomApp source -> single-use authenticated stage.
# Requires true current GitHub snapshots and real complete ZIP bytes from
# V028, plus the existing V026 actual installed-only owner policy. Reuses
# the earlier V010 HMAC/SHA256/constant-time primitives unchanged.
# A successful consumption DOES NOT authorize any Spotify or app mutation.
function Assert-ApprovedLiveHmacHostedV029 {
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        throw 'V029_AUTHENTIC_STAGE_HOSTED_WINDOWS_ONLY'
    }
}
function Get-ApprovedLiveHmacMaterialV029 {
    param([Parameter(Mandatory=$true)]$Permit)
    return @(
      'approved-real-source-HMAC-stage-v029',
      [string]$Permit.name,[string]$Permit.source,
      [string]$Permit.registry_sha256,
      [string]$Permit.source_provenance_sha256,
      [string]$Permit.remote_snapshot_material_sha256,
      [string]$Permit.github_repo_id,[string]$Permit.commit_sha,
      [string]$Permit.archive_sha256,[string]$Permit.runtime_tree_sha256,
      [string]$Permit.manifest_name,[string]$Permit.file_count,[string]$Permit.total_bytes,
      [string]$Permit.workspace_path,[string]$Permit.archive_path,[string]$Permit.stage_path,
      [string]$Permit.issued_at,[string]$Permit.expires_at,[string]$Permit.nonce,
      'single-use','no-production-mutation'
    ) -join ([char]10)
}
function Assert-ApprovedLiveHmacStagePathsV029 {
    param([Parameter(Mandatory=$true)]$Acquired)
    Assert-ApprovedLiveHmacHostedV029
    $scope=Get-CustomAppStageWorkspaceRootV010
    $root=Assert-CustomAppStagePathV010 -Root $scope -Path ([string]$Acquired.workspace_path) -Label 'HMAC authenticated stage workspace'
    $archive=Assert-CustomAppStagePathV010 -Root $root -Path ([string]$Acquired.archive_path) -Label 'HMAC archived real source'
    $stage=Assert-CustomAppStagePathV010 -Root $root -Path ([string]$Acquired.stage_path) -Label 'HMAC extracted real source'
    if(-not(Test-Path -LiteralPath $archive -PathType Leaf) -or
       -not(Test-Path -LiteralPath $stage -PathType Container) -or
       [IO.Path]::GetFileName($archive) -cne 'pinned-upstream.zip' -or
       [IO.Path]::GetFileName($stage) -cne ('prepared-'+[string]$Acquired.name) -or
       [string]$root -ceq [string]$stage){
       throw 'V029_SOURCE_STAGE_ARTIFACTS_NOT_UNIQUELY_SCOPED'
    }
    return [pscustomobject]@{root=$root;archive=$archive;stage=$stage}
}
function Assert-ApprovedLiveHmacCurrentSourceV029 {
    param([Parameter(Mandatory=$true)]$Item,
          [Parameter(Mandatory=$true)]$Acquired)
    Assert-ApprovedLiveHmacHostedV029
    if(-not[bool]$Acquired.ok -or
       [int]$Acquired.schema -ne 1 -or
       [string]$Acquired.managed_by -cne 'approved-live-source-acquisition-v028' -or
       -not[bool]$Acquired.ready_for_separate_cryptographic_permit -or
       [bool]$Acquired.authenticated_hmac_permit -or
       [bool]$Acquired.production_mutation_authorized -or
       [bool]$Acquired.spicetify_executed){
       throw 'V029_NOT_A_REAL_V028_NONAUTHORITATIVE_ACQUISITION'
    }
    $policy=Get-ApprovedLiveSourcePolicyV028 -Item $Item
    if([string]$policy.name -cne [string]$Acquired.name -or
       [string]$policy.source -cne [string]$Acquired.source -or
       [string]$policy.registry_sha256 -cne [string]$Acquired.source_snapshot.registry_sha256 -or
       [string]$policy.manifest_name -cne [string]$Acquired.manifest_name){
       throw 'V029_INSTALLED_APP_REGISTRY_OR_MANIFEST_CHANGED'
    }
    $latest=Get-ApprovedLiveRemoteSnapshotV028 -Policy $policy
    if((Get-ApprovedLiveRemoteSnapshotMaterialV028 $latest) -cne
       (Get-ApprovedLiveRemoteSnapshotMaterialV028 $Acquired.source_snapshot)){
       throw 'V029_OFFICIAL_PUBLISHER_REF_CHANGED_SINCE_DOWNLOAD'
    }
    $stagePaths=Assert-ApprovedLiveHmacStagePathsV029 -Acquired $Acquired
    if((Get-FileHash -LiteralPath $stagePaths.archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        [string]$Acquired.archive_sha256){
       throw 'V029_AUTHENTIC_ARCHIVE_BYTES_CHANGED'
    }
    $ev=Get-CustomAppObserverZipEvidence -ZipPath ([string]$stagePaths.archive) -WrapperMode auto
    if(-not[bool]$ev.manifest_valid -or [bool]$ev.build_required -or
       [string]$ev.tree_sha256 -cne [string]$Acquired.runtime_tree_sha256 -or
       [string]$ev.manifest_name -cne [string]$policy.manifest_name -or
       [int]$ev.file_count -ne [int]$Acquired.file_count){
       throw 'V029_REAL_ZIP_TREE_OR_DISPLAY_MANIFEST_CHANGED'
    }
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name ([string]$policy.name) -AppPath $stagePaths.stage
    if(-not[bool]$baseline.safe -or -not[bool]$baseline.installable -or
       [string]$baseline.tree_sha256 -cne [string]$ev.tree_sha256 -or
       [string]$baseline.manifest_name -cne [string]$ev.manifest_name -or
       [int64]$baseline.total_bytes -ne [int64]$Acquired.total_bytes -or
       [int]$baseline.file_count -ne [int]$Acquired.file_count){
       throw 'V029_AUTHENTIC_EXTRACTED_FULL_TREE_CHANGED'
    }
    $evidenceMaterial=@('approved-real-remote-v028',
       (Get-ApprovedLiveRemoteSnapshotMaterialV028 $Acquired.source_snapshot),
       [string]$Acquired.archive_sha256,[string]$ev.tree_sha256,
       [string]$ev.file_count,[string]$ev.expanded_bytes) -join [Environment]::NewLine
    if((Get-CustomAppObserverStringSha256 $evidenceMaterial) -cne
       [string]$Acquired.source_provenance_sha256){
       throw 'V029_V028_LIVE_PROVENANCE_FINGERPRINT_CHANGED'
    }
    return [pscustomobject]@{
       ok=$true;policy=$policy;snapshot=$latest
       paths=$stagePaths;baseline=$baseline
       snapshot_material_sha256=(Get-CustomAppProductionPermitSha256V010 (
          Get-ApprovedLiveRemoteSnapshotMaterialV028 $latest))
    }
}
function New-ApprovedLiveHmacStagePermitV029 {
    param([Parameter(Mandatory=$true)]$Item,
          [Parameter(Mandatory=$true)]$Acquired,
          [Parameter(Mandatory=$true)][byte[]]$SessionKey,
          [Parameter(Mandatory=$true)][string]$Nonce,
          [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($SessionKey.Length -lt 32 -or $Nonce -cnotmatch '^[0-9a-f]{32}$'){
       throw 'V029_SESSION_KEY_OR_NONCE_INVALID'
    }
    $proof=Assert-ApprovedLiveHmacCurrentSourceV029 -Item $Item -Acquired $Acquired
    $issued=$Now.ToUniversalTime()
    $p=[pscustomobject]@{
       schema=1;managed_by='approved-live-hmac-stage-v029'
       name=[string]$Acquired.name;source=[string]$Acquired.source
       registry_sha256=[string]$proof.policy.registry_sha256
       source_provenance_sha256=[string]$Acquired.source_provenance_sha256
       remote_snapshot_material_sha256=[string]$proof.snapshot_material_sha256
       github_repo_id=[int64]$proof.snapshot.repository_id
       commit_sha=[string]$proof.snapshot.commit_sha
       archive_sha256=[string]$Acquired.archive_sha256
       runtime_tree_sha256=[string]$Acquired.runtime_tree_sha256
       manifest_name=[string]$Acquired.manifest_name
       file_count=[int]$Acquired.file_count;total_bytes=[int64]$Acquired.total_bytes
       workspace_path=[string]$proof.paths.root;archive_path=[string]$proof.paths.archive
       stage_path=[string]$proof.paths.stage
       issued_at=$issued.ToString('o');expires_at=$issued.AddMinutes(3).ToString('o')
       nonce=$Nonce
       token_id=$null;hmac_sha256=$null
       single_use=$true;requires_durable_consumption=$true
       production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $material=Get-ApprovedLiveHmacMaterialV029 -Permit $p
    $p.token_id=Get-CustomAppProductionPermitSha256V010 -Text $material
    $p.hmac_sha256=Get-CustomAppProductionPermitHmacV010 -Text $material -SessionKey $SessionKey
    return $p
}
function Test-ApprovedLiveHmacStagePermitV029 {
    param([Parameter(Mandatory=$true)]$Item,
          [Parameter(Mandatory=$true)]$Acquired,
          [Parameter(Mandatory=$true)]$Permit,
          [Parameter(Mandatory=$true)][byte[]]$SessionKey,
          [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $deny={param($why)[pscustomobject]@{
        ok=$false;reason=[string]$why;production_execution_authorized=$false
        production_mutation_authorized=$false;single_use_consumed=$false}}
    try{
       if([string]$Permit.managed_by -cne 'approved-live-hmac-stage-v029' -or
          [int]$Permit.schema -ne 1 -or
          -not[bool]$Permit.single_use -or
          -not[bool]$Permit.requires_durable_consumption -or
          [bool]$Permit.production_execution_authorized -or
          [bool]$Permit.production_mutation_authorized -or
          [string]$Permit.nonce -cnotmatch '^[a-f0-9]{32}$' -or
          [string]$Permit.token_id -cnotmatch '^[a-f0-9]{64}$' -or
          [string]$Permit.hmac_sha256 -cnotmatch '^[a-f0-9]{64}$'){
           throw 'V029_PERMIT_SCHEMA_NONCE_OR_AUTHORITY_CHANGED'
       }
       if($SessionKey.Length -lt 32){throw 'V029_KEY_TOO_SHORT'}
       $issued=[DateTimeOffset]::Parse([string]$Permit.issued_at)
       $expires=[DateTimeOffset]::Parse([string]$Permit.expires_at)
       if($expires -cne $issued.AddMinutes(3) -or
          $Now -ge $expires -or $Now -lt $issued.AddSeconds(-30)){
           throw 'V029_SIGNED_SINGLE_USE_PERMIT_NOT_CURRENT'
       }
       $material=Get-ApprovedLiveHmacMaterialV029 -Permit $Permit
       $expectedId=Get-CustomAppProductionPermitSha256V010 -Text $material
       $expectedMac=Get-CustomAppProductionPermitHmacV010 -Text $material -SessionKey $SessionKey
       if(-not(Test-CustomAppProductionPermitFixedTimeHexV010 $expectedId ([string]$Permit.token_id)) -or
          -not(Test-CustomAppProductionPermitFixedTimeHexV010 $expectedMac ([string]$Permit.hmac_sha256))){
           throw 'V029_HMAC_STAGE_AUTHENTICATION_FAILED'
       }
       $current=Assert-ApprovedLiveHmacCurrentSourceV029 -Item $Item -Acquired $Acquired
       $matches=@(
          @('name',[string]$Acquired.name),
          @('source',[string]$Acquired.source),
          @('registry_sha256',[string]$current.policy.registry_sha256),
          @('source_provenance_sha256',[string]$Acquired.source_provenance_sha256),
          @('remote_snapshot_material_sha256',[string]$current.snapshot_material_sha256),
          @('github_repo_id',[string]$current.snapshot.repository_id),
          @('commit_sha',[string]$current.snapshot.commit_sha),
          @('archive_sha256',[string]$Acquired.archive_sha256),
          @('runtime_tree_sha256',[string]$Acquired.runtime_tree_sha256),
          @('manifest_name',[string]$Acquired.manifest_name),
          @('file_count',[string]$Acquired.file_count),
          @('total_bytes',[string]$Acquired.total_bytes),
          @('workspace_path',[string]$current.paths.root),
          @('archive_path',[string]$current.paths.archive),
          @('stage_path',[string]$current.paths.stage)
       )
       foreach($row in $matches){
          if([string]$Permit.([string]$row[0]) -cne [string]$row[1]){
             throw ('V029_SIGNED_CURRENT_BYTE_BINDING_CHANGED_'+[string]$row[0])
          }
       }
       return [pscustomobject]@{
          ok=$true;reason='current-real-github-stage-and-installed-policy-HMAC-authenticated'
          token_id=[string]$Permit.token_id
          name=[string]$Permit.name;source=[string]$Permit.source
          runtime_tree_sha256=[string]$Permit.runtime_tree_sha256
          production_execution_authorized=$false;production_mutation_authorized=$false
          single_use_consumed=$false
       }
    }catch{return & $deny ('V029_HMAC_ADMISSION_DENIED:'+ [string]$_.Exception.Message)}
}
function Assert-ApprovedLiveHmacStoreV029 {
    param([Parameter(Mandatory=$true)][string]$Directory)
    Assert-ApprovedLiveHmacHostedV029
    $root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $store=[IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
    if($store.StartsWith('\\') -or $root.StartsWith('\\') -or
       -not $store.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       -not[IO.Directory]::Exists($store)){
        throw 'V029_CLAIM_STORE_OUTSIDE_HOSTED_RUNNER_OR_NOT_CREATED'
    }
    $probe=$store
    while(-not $probe.Equals($root,[StringComparison]::OrdinalIgnoreCase)){
        if(((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'V029_STORE_SYMLINK_OR_REPARSE_POINT'
        }
        $probe=[IO.Path]::GetDirectoryName($probe)
        if([string]::IsNullOrWhiteSpace($probe)){throw 'V029_STORE_PARENT_ESCAPE'}
    }
    return $store
}
function Get-ApprovedLiveHmacReceiptPathV029 {
    param([Parameter(Mandatory=$true)][string]$Store,
          [Parameter(Mandatory=$true)][string]$TokenId)
    if($TokenId -cnotmatch '^[0-9a-f]{64}$'){throw 'V029_CONSUMPTION_TOKEN_ID_INVALID'}
    $qualified=Assert-ApprovedLiveHmacStoreV029 -Directory $Store
    return Join-Path $qualified ('consumed-'+$TokenId+'.dpapi')
}
function Read-ApprovedLiveHmacConsumedReceiptV029 {
    param([Parameter(Mandatory=$true)][string]$Store,
          [Parameter(Mandatory=$true)][string]$TokenId)
    $deny={param($why)[pscustomobject]@{
       ok=$false;reason=[string]$why;single_use_consumed=$false
       production_execution_authorized=$false;production_mutation_authorized=$false}}
    try{
        $p=Get-ApprovedLiveHmacReceiptPathV029 -Store $Store -TokenId $TokenId
        $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
           $item.Length -lt 160 -or $item.Length -gt 32768){
           throw 'V029_RECEIPT_UNEXPECTED_FILE_TYPE_OR_LENGTH'
        }
        $data=[IO.File]::ReadAllBytes($p)
        $encrypted=New-Object byte[] ($data.Length-32)
        [Array]::Copy($data,32,$encrypted,0,$encrypted.Length)
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=$sha.ComputeHash($encrypted)}finally{$sha.Dispose()}
        for($i=0;$i -lt 32;$i++){
            if($data[$i] -ne $hash[$i]){throw 'V029_RECEIPT_WHOLE_DPAPI_ENVELOPE_CHANGED'}
        }
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $entropy=[Text.Encoding]::UTF8.GetBytes('ApprovedLiveHmacConsumedStage|v029|'+$TokenId)
        $plain=$null
        try{
            $plain=[Security.Cryptography.ProtectedData]::Unprotect(
                $encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
            $record=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop
        }finally{if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)}}
        if([int]$record.schema -ne 1 -or
           [string]$record.managed_by -cne 'approved-live-hmac-single-use-stage-v029' -or
           [string]$record.token_id -cne $TokenId -or
           [string]$record.source_provenance_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [string]$record.runtime_tree_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [string]$record.name -notin @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker') -or
           [string]$record.phase -cne 'consumed-awaiting-separate-central-journal' -or
           [bool]$record.production_mutation_authorized){
           throw 'V029_CONSUMPTION_RECORD_SCHEMA_OR_AUTHORITY_DRIFT'
        }
        return [pscustomobject]@{
           ok=$true;reason='DPAPI-sealed-once-only-authentic-source-consumed'
           token_id=$TokenId;name=[string]$record.name;source=[string]$record.source
           runtime_tree_sha256=[string]$record.runtime_tree_sha256
           source_provenance_sha256=[string]$record.source_provenance_sha256
           single_use_consumed=$true;separate_journal_required=$true
           production_execution_authorized=$false;production_mutation_authorized=$false
        }
    }catch{return & $deny ('V029_SEALED_CONSUMPTION_READ_DENIED:'+ [string]$_.Exception.Message)}
}
function Consume-ApprovedLiveHmacStageOnceV029 {
    param([Parameter(Mandatory=$true)]$Item,
          [Parameter(Mandatory=$true)]$Acquired,
          [Parameter(Mandatory=$true)]$Permit,
          [Parameter(Mandatory=$true)][byte[]]$SessionKey,
          [Parameter(Mandatory=$true)][string]$ReceiptStore,
          [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $proof=Test-ApprovedLiveHmacStagePermitV029 -Item $Item -Acquired $Acquired -Permit $Permit -SessionKey $SessionKey -Now $Now
    if(-not[bool]$proof.ok){
        throw ('V029_ONE_TIME_CONSUME_REFUSED:'+ [string]$proof.reason)
    }
    $path=Get-ApprovedLiveHmacReceiptPathV029 -Store $ReceiptStore -TokenId ([string]$Permit.token_id)
    $record=[ordered]@{
       schema=1;managed_by='approved-live-hmac-single-use-stage-v029'
       token_id=[string]$Permit.token_id
       name=[string]$Permit.name;source=[string]$Permit.source
       source_provenance_sha256=[string]$Permit.source_provenance_sha256
       runtime_tree_sha256=[string]$Permit.runtime_tree_sha256
       archive_sha256=[string]$Permit.archive_sha256
       commit_sha=[string]$Permit.commit_sha
       manifest_name=[string]$Permit.manifest_name
       consumed_at=$Now.ToUniversalTime().ToString('o')
       phase='consumed-awaiting-separate-central-journal'
       production_mutation_authorized=$false
    }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=[Text.Encoding]::UTF8.GetBytes(($record|ConvertTo-Json -Compress -Depth 5))
    $entropy=[Text.Encoding]::UTF8.GetBytes('ApprovedLiveHmacConsumedStage|v029|'+[string]$Permit.token_id)
    try{
       $encrypted=[Security.Cryptography.ProtectedData]::Protect(
           $plain,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    }finally{[Array]::Clear($plain,0,$plain.Length)}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=$sha.ComputeHash($encrypted)}finally{$sha.Dispose()}
    $out=New-Object byte[] ($encrypted.Length+32)
    [Array]::Copy($hash,0,$out,0,32)
    [Array]::Copy($encrypted,0,$out,32,$encrypted.Length)
    # O_EXCL: simultaneous consumers cannot both spend this signed permit.
    # Incomplete/torn records intentionally block automatic replay.
    $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($out,0,$out.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    $fresh=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $ReceiptStore -TokenId ([string]$Permit.token_id)
    if(-not[bool]$fresh.ok -or -not[bool]$fresh.single_use_consumed -or
       [string]$fresh.runtime_tree_sha256 -cne [string]$Permit.runtime_tree_sha256){
        throw 'V029_CONSUMPTION_WRITE_DURABLE_READBACK_FAILED'
    }
    return [pscustomobject]@{
       ok=$true;reason='HMAC-authenticated-real-source-spent-once'
       token_id=[string]$Permit.token_id
       source_provenance_sha256=[string]$Permit.source_provenance_sha256
       runtime_tree_sha256=[string]$Permit.runtime_tree_sha256
       receipt_path=$path;single_use_consumed=$true
       separate_central_journal_required=$true
       official_vendor_not_invoked=$true
       production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
