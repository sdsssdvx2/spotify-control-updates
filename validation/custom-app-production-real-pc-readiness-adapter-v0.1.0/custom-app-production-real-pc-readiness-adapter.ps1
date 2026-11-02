$CustomAppProductionRealPcReadinessAdapterSchema = 1
$CustomAppProductionRealPcReadinessAdapterManagedBy = 'custom-app-production-real-pc-readiness-adapter-v1'
$CustomAppProductionRealPcReadinessAdapterQualifiedLiveAdmissionHead = 'c128595c3ac7eab338f5d23d7041ae56a6822948'
$CustomAppProductionRealPcReadinessAdapterQualifiedLiveAdmissionCoreBlob = '9bdcbf0a928539e5f3c4e28b7de1d68589e18525'
$CustomAppProductionRealPcReadinessAdapterQualifiedPromotionHead = '979e9d6362ead31016b9532f98629d6bcc2bbb56'
$CustomAppProductionRealPcReadinessAdapterQualifiedShadowHead = '22eb3561843fbe4016023d527186aa629512b67d'
$CustomAppProductionRealPcReadinessAdapterQualifiedProductionMain = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'

function Get-CustomAppProductionRealPcReadinessSha256V010 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRealPcReadinessSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not[string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRealPcReadinessCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'real-pc-readiness-path-empty'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}
function Test-CustomAppProductionRealPcReadinessDirectChildV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path)
    try{$r=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 $Root;$p=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 $Path}catch{return $false}
    $parent=[IO.Path]::GetDirectoryName($p)
    return (-not[string]::IsNullOrWhiteSpace($parent)-and(Get-CustomAppProductionRealPcReadinessCanonicalPathV010 $parent).Equals($r,[StringComparison]::OrdinalIgnoreCase))
}
function New-CustomAppProductionRealPcShadowProtocolQualificationV010 {
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-shadow-protocol-qualification-v1'
        validated_shadow_head=$CustomAppPromotionQualifiedShadowHead;validated_stage_parent=$CustomAppPromotionQualifiedStageHead
        production_main=$CustomAppPromotionQualifiedProductionMain;addon_manager_sha256=$CustomAppPromotionQualifiedAddonSha256;spotify_control_sha256=$CustomAppPromotionQualifiedSpotifySha256
        push_success=$true;pull_request_success=$true;offline_matrix_passed=$true;live_tagify_331_to_332_passed=$true;parent_selftest_passed=$true
        push_run_id=$CustomAppPromotionQualifiedPushRunId;pull_request_run_id=$CustomAppPromotionQualifiedPrRunId;push_artifact_id=$CustomAppPromotionQualifiedPushArtifactId;pull_request_artifact_id=$CustomAppPromotionQualifiedPrArtifactId
        push_artifact_digest=$CustomAppPromotionQualifiedPushArtifactDigest;pull_request_artifact_digest=$CustomAppPromotionQualifiedPrArtifactDigest
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function New-CustomAppProductionRealPcReadinessDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;production_environment_ready=$false;eligible_to_request_production_permit=$false;requires_fresh_admission_before_permit=$true
        current_user_roots_verified=$false;live_path_bound_to_spicetify_root=$false;fresh_provenance_revalidated=$false;persistence_snapshot_read_only=$false
        permit_issued=$false;result_is_authority=$false;admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-CustomAppProductionRealPcReadinessResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_live_admission_head,[string]$Result.qualified_live_admission_core_blob,[string]$Result.qualified_promotion_head,[string]$Result.qualified_shadow_head,[string]$Result.qualified_production_main,[string]$Result.status,[string]$Result.reason,
        [string]$Result.name,[string]$Result.source_identity,[string]$Result.live_path,[string]$Result.live_root,[string]$Result.custom_app_roots_fingerprint,[string]$Result.current_tree_sha256,[string]$Result.manifest_name,
        [string]$Result.stored_provenance_fingerprint,[string]$Result.fresh_provenance_fingerprint,[string]$Result.remote_tree_sha256,[string]$Result.remote_commit_sha,[string]$Result.binding_fingerprint,[string]$Result.admission_fingerprint,[string]$Result.current_eligibility_fingerprint,
        [string]$Result.persistence_fingerprint,[string]$Result.local_app_data_root,[string]$Result.app_data_root,[string]$Result.checked_at,
        [string]$Result.production_environment_ready,[string]$Result.eligible_to_request_production_permit,[string]$Result.pending_remote_change_verified,[string]$Result.current_user_roots_verified,[string]$Result.live_path_bound_to_spicetify_root,[string]$Result.fresh_provenance_revalidated,[string]$Result.persistence_snapshot_read_only,[string]$Result.requires_fresh_admission_before_permit,
        [string]$Result.permit_issued,[string]$Result.result_is_authority,[string]$Result.admission_is_authority,[string]$Result.execution_authorized,[string]$Result.restore_authorized,[string]$Result.apply_authorized,[string]$Result.cleanup_authorized,[string]$Result.mutation_mode,[string]$Result.mutation_authorized,[string]$Result.auto_update_authorized,[string]$Result.auto_install_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    )-join"`n"
}
function Test-CustomAppProductionRealPcReadinessResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-result-null'}}
    $required=@('schema','managed_by','qualified_live_admission_head','qualified_live_admission_core_blob','qualified_promotion_head','qualified_shadow_head','qualified_production_main','status','reason','name','source_identity','live_path','live_root','custom_app_roots_fingerprint','current_tree_sha256','manifest_name','stored_provenance_fingerprint','fresh_provenance_fingerprint','remote_tree_sha256','remote_commit_sha','binding_fingerprint','admission_fingerprint','current_eligibility_fingerprint','persistence_fingerprint','local_app_data_root','app_data_root','checked_at','production_environment_ready','eligible_to_request_production_permit','pending_remote_change_verified','current_user_roots_verified','live_path_bound_to_spicetify_root','fresh_provenance_revalidated','persistence_snapshot_read_only','requires_fresh_admission_before_permit','permit_issued','result_is_authority','admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','mutation_mode','mutation_authorized','auto_update_authorized','auto_install_authorized','production_execution_authorized','production_mutation_authorized','result_fingerprint')
    foreach($f in $required){if(-not$Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('real-pc-readiness-required-field-missing-'+$f)}}}
    if([int]$Result.schema-ne$CustomAppProductionRealPcReadinessAdapterSchema-or[string]$Result.managed_by-cne$CustomAppProductionRealPcReadinessAdapterManagedBy-or[string]$Result.qualified_live_admission_head-cne$CustomAppProductionRealPcReadinessAdapterQualifiedLiveAdmissionHead-or[string]$Result.qualified_live_admission_core_blob-cne$CustomAppProductionRealPcReadinessAdapterQualifiedLiveAdmissionCoreBlob-or[string]$Result.qualified_promotion_head-cne$CustomAppProductionRealPcReadinessAdapterQualifiedPromotionHead-or[string]$Result.qualified_shadow_head-cne$CustomAppProductionRealPcReadinessAdapterQualifiedShadowHead-or[string]$Result.qualified_production_main-cne$CustomAppProductionRealPcReadinessAdapterQualifiedProductionMain-or[string]$Result.status-cne'real-pc-readiness-verified-zero-authority'-or[string]$Result.reason-cne'fresh-live-admission-and-current-user-environment-reverified'){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-owner-lineage-status-invalid'}}
    foreach($f in @('custom_app_roots_fingerprint','current_tree_sha256','stored_provenance_fingerprint','fresh_provenance_fingerprint','remote_tree_sha256','binding_fingerprint','admission_fingerprint','current_eligibility_fingerprint','persistence_fingerprint','result_fingerprint')){if(-not(Test-CustomAppProductionRealPcReadinessSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('real-pc-readiness-invalid-'+$f)}}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-invalid-remote-commit'}}
    if([string]::IsNullOrWhiteSpace([string]$Result.name)-or([string]$Result.source_identity).Trim().ToLowerInvariant()-notmatch'^[a-z0-9_.-]+/[a-z0-9_.-]+$'-or[string]::IsNullOrWhiteSpace([string]$Result.manifest_name)){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-identity-invalid'}}
    try{$live=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 ([string]$Result.live_path);$root=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 ([string]$Result.live_root);$local=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 ([string]$Result.local_app_data_root);$app=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 ([string]$Result.app_data_root)}catch{return [pscustomobject]@{ok=$false;reason='real-pc-readiness-result-path-invalid'}}
    if(-not(Test-CustomAppProductionRealPcReadinessDirectChildV010 -Root $root -Path $live)-or$local.Equals($app,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-result-path-boundary-invalid'}}
    foreach($f in @('production_environment_ready','eligible_to_request_production_permit','pending_remote_change_verified','current_user_roots_verified','live_path_bound_to_spicetify_root','fresh_provenance_revalidated','persistence_snapshot_read_only','requires_fresh_admission_before_permit')){if(-not[bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('real-pc-readiness-required-flag-false-'+$f)}}}
    if([string]$Result.mutation_mode-cne'deny'){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-mutation-mode-not-deny'}}
    foreach($f in @('permit_issued','result_is_authority','admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','mutation_authorized','auto_update_authorized','auto_install_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('real-pc-readiness-authority-escaped-'+$f)}}}
    if(([string]$Result.stored_provenance_fingerprint).Trim().ToLowerInvariant()-cne([string]$Result.fresh_provenance_fingerprint).Trim().ToLowerInvariant()-or([string]$Result.current_tree_sha256).Trim().ToLowerInvariant()-ceq([string]$Result.remote_tree_sha256).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-evidence-continuity-invalid'}}
    $at=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Result.checked_at,[ref]$at)){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-time-invalid'}}
    $expected=Get-CustomAppProductionRealPcReadinessSha256V010 (Get-CustomAppProductionRealPcReadinessResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='real-pc-readiness-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='real-pc-readiness-result-valid-zero-authority';result_fingerprint=$expected;production_mutation_authorized=$false}
}
function Resolve-CustomAppProductionRealPcReadinessV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,
        [string]$LocalAppDataRoot=$env:LOCALAPPDATA,[string]$AppDataRoot=$env:APPDATA,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionRealPcReadinessDeniedV010 -Reason $Reason}
    if([string]::IsNullOrWhiteSpace($Name)){return & $deny 'real-pc-readiness-name-empty'}
    if([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)-or[string]::IsNullOrWhiteSpace($env:APPDATA)){return & $deny 'real-pc-readiness-current-user-roots-unavailable'}
    try{$local=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 $LocalAppDataRoot;$app=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 $AppDataRoot;$envLocal=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 $env:LOCALAPPDATA;$envApp=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 $env:APPDATA}catch{return & $deny 'real-pc-readiness-current-user-root-invalid'}
    if(-not$local.Equals($envLocal,[StringComparison]::OrdinalIgnoreCase)-or-not$app.Equals($envApp,[StringComparison]::OrdinalIgnoreCase)-or$local.Equals($app,[StringComparison]::OrdinalIgnoreCase)){return & $deny 'real-pc-readiness-current-user-root-mismatch'}
    foreach($spec in @(@('localappdata',$local),@('appdata',$app))){
        if(-not(Test-Path -LiteralPath ([string]$spec[1]) -PathType Container)){return & $deny ('real-pc-readiness-'+[string]$spec[0]+'-missing')}
        try{$item=Get-Item -LiteralPath ([string]$spec[1]) -Force -ErrorAction Stop}catch{return & $deny ('real-pc-readiness-'+[string]$spec[0]+'-read-failed')}
        if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){return & $deny ('real-pc-readiness-'+[string]$spec[0]+'-reparse-point')}
    }
    if($null-eq$LifecycleRow-or[string]$LifecycleRow.managed_by-cne'dynamic-spicetify-v1'-or[string]$LifecycleRow.kind-cne'custom-app'-or-not[bool]$LifecycleRow.present-or[bool]$LifecycleRow.user_removed-or[bool]$LifecycleRow.ambiguous-or-not[bool]$LifecycleRow.safe_local_identity-or@($LifecycleRow.locations).Count-ne1){return & $deny 'real-pc-readiness-lifecycle-not-current-safe-single-path'}
    if($LifecycleRow.PSObject.Properties['name']-and-not[string]::IsNullOrWhiteSpace([string]$LifecycleRow.name)-and([string]$LifecycleRow.name).Trim().ToLowerInvariant()-cne$Name.Trim().ToLowerInvariant()){return & $deny 'real-pc-readiness-lifecycle-name-mismatch'}
    try{$live=Get-CustomAppProductionRealPcReadinessCanonicalPathV010 ([string]$LifecycleRow.locations[0])}catch{return & $deny 'real-pc-readiness-live-path-invalid'}
    if(-not(Test-Path -LiteralPath $live -PathType Container)){return & $deny 'real-pc-readiness-live-path-missing'}
    try{$liveItem=Get-Item -LiteralPath $live -Force -ErrorAction Stop}catch{return & $deny 'real-pc-readiness-live-path-read-failed'}
    if(($liveItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){return & $deny 'real-pc-readiness-live-path-reparse-point'}
    try{$rawRoots=@(Get-SpicetifyAssetRoots -Kind 'CustomApp')}catch{return & $deny ('real-pc-readiness-spicetify-roots-read-failed:'+[string]$_.Exception.Message)}
    $roots=New-Object System.Collections.Generic.List[string];foreach($r in $rawRoots){if([string]::IsNullOrWhiteSpace([string]$r)){continue};try{$roots.Add((Get-CustomAppProductionRealPcReadinessCanonicalPathV010 ([string]$r)))}catch{}}
    if($roots.Count-lt1){return & $deny 'real-pc-readiness-spicetify-customapp-roots-empty'}
    $matched=@($roots.ToArray()|Where-Object{Test-CustomAppProductionRealPcReadinessDirectChildV010 -Root $_ -Path $live}|Select-Object -Unique)
    if($matched.Count-ne1){return & $deny 'real-pc-readiness-live-path-not-bound-to-single-spicetify-root'}
    $liveRoot=[string]$matched[0]
    if(-not(Test-Path -LiteralPath $liveRoot -PathType Container)){return & $deny 'real-pc-readiness-live-root-missing'}
    try{$rootItem=Get-Item -LiteralPath $liveRoot -Force -ErrorAction Stop}catch{return & $deny 'real-pc-readiness-live-root-read-failed'}
    if(($rootItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){return & $deny 'real-pc-readiness-live-root-reparse-point'}
    $rootLines=@($roots.ToArray()|ForEach-Object{$_.ToLowerInvariant()}|Sort-Object -Unique);$rootsFp=Get-CustomAppProductionRealPcReadinessSha256V010 ($rootLines-join"`n")
    try{$baseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $live}catch{return & $deny ('real-pc-readiness-baseline-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$baseline-or-not[bool]$baseline.safe-or-not[bool]$baseline.installable-or-not(Test-CustomAppProductionRealPcReadinessSha256V010 ([string]$baseline.tree_sha256))-or[string]::IsNullOrWhiteSpace([string]$baseline.manifest_name)){return & $deny 'real-pc-readiness-baseline-not-safe-installable'}
    if($baseline.PSObject.Properties['path']){try{if(-not(Get-CustomAppProductionRealPcReadinessCanonicalPathV010 ([string]$baseline.path)).Equals($live,[StringComparison]::OrdinalIgnoreCase)){return & $deny 'real-pc-readiness-baseline-path-drift'}}catch{return & $deny 'real-pc-readiness-baseline-path-invalid'}}
    if(Get-Command Test-CustomAppLocalRuntimeBaselineMutationAuthority -CommandType Function -ErrorAction SilentlyContinue){if(Test-CustomAppLocalRuntimeBaselineMutationAuthority $baseline){return & $deny 'real-pc-readiness-baseline-authority-drift'}}
    if($null-eq$ProvenanceRow-or[string]$ProvenanceRow.managed_by-cne'custom-app-provenance-v1'-or-not(Test-CustomAppProductionRealPcReadinessSha256V010 ([string]$ProvenanceRow.evidence_fingerprint))){return & $deny 'real-pc-readiness-stored-provenance-invalid'}
    try{$freshProv=Get-CustomAppLocalProvenanceEvidence -Name $Name -AppPath $live}catch{return & $deny ('real-pc-readiness-fresh-provenance-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$freshProv-or-not[bool]$freshProv.source_proven-or[bool]$freshProv.requires_reenrollment){return & $deny 'real-pc-readiness-fresh-provenance-not-strong'}
    $source=([string]$ProvenanceRow.source_identity).Trim().ToLowerInvariant();if([string]::IsNullOrWhiteSpace($source)-or([string]$freshProv.source_candidate).Trim().ToLowerInvariant()-cne$source){return & $deny 'real-pc-readiness-fresh-provenance-source-drift'}
    $storedProv=([string]$ProvenanceRow.evidence_fingerprint).Trim().ToLowerInvariant();$freshFp=([string]$freshProv.evidence_fingerprint).Trim().ToLowerInvariant();if(-not(Test-CustomAppProductionRealPcReadinessSha256V010 $freshFp)-or$freshFp-cne$storedProv){return & $deny 'real-pc-readiness-fresh-provenance-fingerprint-drift'}
    if($freshProv.PSObject.Properties['path']){try{if(-not(Get-CustomAppProductionRealPcReadinessCanonicalPathV010 ([string]$freshProv.path)).Equals($live,[StringComparison]::OrdinalIgnoreCase)){return & $deny 'real-pc-readiness-fresh-provenance-path-drift'}}catch{return & $deny 'real-pc-readiness-fresh-provenance-path-invalid'}}
    $shadow=New-CustomAppProductionRealPcShadowProtocolQualificationV010;$liveQualification=New-CustomAppLiveAttestedProtocolQualificationV010
    try{$admission=Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $baseline -ShadowProtocolQualification $shadow -LiveAttestedQualification $liveQualification -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours}catch{return & $deny ('real-pc-readiness-live-admission-failed:'+[string]$_.Exception.Message)}
    if($null-eq$admission-or-not[bool]$admission.production_admission_eligible){return & $deny ('real-pc-readiness-live-admission-denied:'+[string]$admission.reason)}
    foreach($f in @('admission_is_authority','production_permit_issued','mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){if($admission.PSObject.Properties[$f]-and[bool]$admission.$f){return & $deny ('real-pc-readiness-live-admission-authority-drift-'+$f)}}
    if(-not(Test-CustomAppProductionRealPcReadinessSha256V010 ([string]$admission.admission_fingerprint))-or-not(Test-CustomAppProductionRealPcReadinessSha256V010 ([string]$admission.current_eligibility_fingerprint))-or([string]$admission.current_tree_sha256).Trim().ToLowerInvariant()-cne([string]$baseline.tree_sha256).Trim().ToLowerInvariant()-or([string]$admission.remote_tree_sha256).Trim().ToLowerInvariant()-ceq([string]$baseline.tree_sha256).Trim().ToLowerInvariant()){return & $deny 'real-pc-readiness-live-admission-evidence-invalid'}
    $bindingFp=Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $BindingRow;if(-not(Test-CustomAppProductionRealPcReadinessSha256V010 $bindingFp)){return & $deny 'real-pc-readiness-binding-fingerprint-invalid'}
    try{$persistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $local -AppDataRoot $app}catch{return & $deny ('real-pc-readiness-persistence-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$persistence-or-not(Test-CustomAppProductionRealPcReadinessSha256V010 ([string]$persistence.fingerprint))){return & $deny 'real-pc-readiness-persistence-fingerprint-invalid'}
    $result=[pscustomobject]@{
        schema=$CustomAppProductionRealPcReadinessAdapterSchema;managed_by=$CustomAppProductionRealPcReadinessAdapterManagedBy;qualified_live_admission_head=$CustomAppProductionRealPcReadinessAdapterQualifiedLiveAdmissionHead;qualified_live_admission_core_blob=$CustomAppProductionRealPcReadinessAdapterQualifiedLiveAdmissionCoreBlob;qualified_promotion_head=$CustomAppProductionRealPcReadinessAdapterQualifiedPromotionHead;qualified_shadow_head=$CustomAppProductionRealPcReadinessAdapterQualifiedShadowHead;qualified_production_main=$CustomAppProductionRealPcReadinessAdapterQualifiedProductionMain
        status='real-pc-readiness-verified-zero-authority';reason='fresh-live-admission-and-current-user-environment-reverified';name=$Name;source_identity=$source;live_path=$live;live_root=$liveRoot;custom_app_roots_fingerprint=$rootsFp;current_tree_sha256=([string]$baseline.tree_sha256).Trim().ToLowerInvariant();manifest_name=[string]$baseline.manifest_name
        stored_provenance_fingerprint=$storedProv;fresh_provenance_fingerprint=$freshFp;remote_tree_sha256=([string]$admission.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$admission.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=$bindingFp;admission_fingerprint=([string]$admission.admission_fingerprint).Trim().ToLowerInvariant();current_eligibility_fingerprint=([string]$admission.current_eligibility_fingerprint).Trim().ToLowerInvariant();persistence_fingerprint=([string]$persistence.fingerprint).Trim().ToLowerInvariant();local_app_data_root=$local;app_data_root=$app;checked_at=$Now.ToUniversalTime().ToString('o')
        production_environment_ready=$true;eligible_to_request_production_permit=$true;pending_remote_change_verified=$true;current_user_roots_verified=$true;live_path_bound_to_spicetify_root=$true;fresh_provenance_revalidated=$true;persistence_snapshot_read_only=$true;requires_fresh_admission_before_permit=$true
        permit_issued=$false;result_is_authority=$false;admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $result.result_fingerprint=Get-CustomAppProductionRealPcReadinessSha256V010 (Get-CustomAppProductionRealPcReadinessResultMaterialV010 -Result $result)
    $check=Test-CustomAppProductionRealPcReadinessResultV010 -Result $result;if(-not[bool]$check.ok){return & $deny ('real-pc-readiness-self-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result;production_environment_ready=$true;eligible_to_request_production_permit=$true;permit_issued=$false;result_is_authority=$false;production_mutation_authorized=$false}
}
