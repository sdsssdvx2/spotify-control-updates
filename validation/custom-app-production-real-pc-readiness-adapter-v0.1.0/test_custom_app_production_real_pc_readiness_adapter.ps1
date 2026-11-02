$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-production-real-pc-readiness-adapter.ps1')

function Assert-RPTrue([bool]$v,[string]$m){if(-not $v){throw $m}}
function Assert-RPFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-RPEq($a,$e,[string]$m){if([string]$a-cne[string]$e){throw "$m actual=<$a> expected=<$e>"}}
function Copy-RP($o){return (($o|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}

$CustomAppPromotionQualifiedShadowHead='22eb3561843fbe4016023d527186aa629512b67d'
$CustomAppPromotionQualifiedStageHead='c420a1df6f306c7ba74772b91241cb14abd04738'
$CustomAppPromotionQualifiedProductionMain='d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
$CustomAppPromotionQualifiedAddonSha256='b2cec989ef399aed4a8763105121b21181ffb493ed9e3e884baa1d62a634f94b'
$CustomAppPromotionQualifiedSpotifySha256='69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99'
$CustomAppPromotionQualifiedPushRunId=[int64]40673331603
$CustomAppPromotionQualifiedPrRunId=[int64]40673541954
$CustomAppPromotionQualifiedPushArtifactId=[int64]12808363735
$CustomAppPromotionQualifiedPrArtifactId=[int64]12809940304
$CustomAppPromotionQualifiedPushArtifactDigest='sha256:ab1d0b651e89c19670d75fc07082cdadde81f5082a791554ed4861b02b8740dd'
$CustomAppPromotionQualifiedPrArtifactDigest='sha256:9ce022e987f6522b767aa330f2e1338210b13ceb5c34617377b548949dcc6c0c'

$script:RPMode='valid';$script:RPRoot=$null;$script:RPLive=$null;$script:RPOtherRoot=$null
$script:RPLocalTree=('1'*64);$script:RPRemoteTree=('2'*64);$script:RPProv=('3'*64);$script:RPBind=('4'*64);$script:RPPersist=('5'*64);$script:RPAdmission=('6'*64);$script:RPElig=('7'*64);$script:RPCommit=('a'*40)
function Get-SpicetifyAssetRoots {param([string]$Kind);if($Kind-cne'CustomApp'){return @()};if($script:RPMode-ceq'root-mismatch'){return @($script:RPOtherRoot)};return @($script:RPRoot)}
function Get-CustomAppLocalRuntimeBaseline {param([string]$Name,[string]$AppPath);return [pscustomobject]@{safe=($script:RPMode-cne'baseline-unsafe');installable=$true;tree_sha256=$script:RPLocalTree;manifest_name='Tagify';path=$AppPath}}
function Test-CustomAppLocalRuntimeBaselineMutationAuthority {param($Baseline);return ($script:RPMode-ceq'baseline-authority')}
function Get-CustomAppLocalProvenanceEvidence {param([string]$Name,[string]$AppPath);$source=$(if($script:RPMode-ceq'fresh-source-drift'){'owner/other'}else{'alexk218/tagify'});$fp=$(if($script:RPMode-ceq'fresh-fingerprint-drift'){('8'*64)}else{$script:RPProv});return [pscustomobject]@{source_proven=$true;requires_reenrollment=$false;source_candidate=$source;evidence_fingerprint=$fp;path=$AppPath}}
function New-CustomAppLiveAttestedProtocolQualificationV010 {return [pscustomobject]@{schema=1}}
function Resolve-CustomAppLiveAttestedProductionAdmissionV010 {
    param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,[DateTimeOffset]$Now,[int]$MaxRemoteObservationAgeHours)
    if($script:RPMode-ceq'admission-denied'){return [pscustomobject]@{production_admission_eligible=$false;reason='synthetic-denied'}}
    $remote=$(if($script:RPMode-ceq'admission-no-change'){$script:RPLocalTree}else{$script:RPRemoteTree})
    return [pscustomobject]@{production_admission_eligible=$true;reason='synthetic-live-admission';source_identity='alexk218/tagify';current_tree_sha256=$script:RPLocalTree;remote_tree_sha256=$remote;remote_commit_sha=$script:RPCommit;admission_fingerprint=$script:RPAdmission;current_eligibility_fingerprint=$script:RPElig;admission_is_authority=($script:RPMode-ceq'admission-authority');production_permit_issued=$false;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
}
function Get-CustomAppPromotionBindingFingerprintV010 {param($BindingRow);return $script:RPBind}
function Get-SpotifyPersistenceSnapshot {param([string]$LocalAppDataRoot,[string]$AppDataRoot);$fp=$(if($script:RPMode-ceq'persistence-invalid'){'bad'}else{$script:RPPersist});return [pscustomobject]@{schema=1;fingerprint=$fp;surface_count=1;surfaces=@()}}

function New-RPFixture([string]$Base){
    $local=Join-Path $Base 'Local';$app=Join-Path $Base 'Roaming';$root=Join-Path $app 'spicetify\CustomApps';$live=Join-Path $root 'tagify';$other=Join-Path $Base 'OtherCustomApps'
    foreach($p in @($local,$app,$root,$live,$other)){[IO.Directory]::CreateDirectory($p)|Out-Null}
    $script:RPRoot=$root;$script:RPLive=$live;$script:RPOtherRoot=$other;$env:LOCALAPPDATA=$local;$env:APPDATA=$app
    $l=[pscustomobject]@{schema=1;managed_by='dynamic-spicetify-v1';kind='custom-app';name='tagify';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($live);mutation_mode='deny'}
    $p=[pscustomobject]@{schema=1;managed_by='custom-app-provenance-v1';name='tagify';source_identity='alexk218/tagify';last_proven_source='alexk218/tagify';source_changed=$false;requires_reenrollment=$false;evidence_fingerprint=$script:RPProv;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $b=[pscustomobject]@{schema=1;managed_by='custom-app-remote-binding-observer-v1';name='tagify';active=$true;source_identity='alexk218/tagify';mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    return [pscustomobject]@{local=$local;app=$app;lifecycle=$l;provenance=$p;binding=$b}
}
function Invoke-RP($F,[string]$Mode='valid',[AllowNull()]$Lifecycle=$null,[AllowNull()][string]$LocalOverride=$null){
    $script:RPMode=$Mode;if($null-eq$Lifecycle){$Lifecycle=$F.lifecycle};if($null-eq$LocalOverride){$LocalOverride=$F.local}
    return Resolve-CustomAppProductionRealPcReadinessV010 -Name 'tagify' -LifecycleRow $Lifecycle -ProvenanceRow $F.provenance -BindingRow $F.binding -LocalAppDataRoot $LocalOverride -AppDataRoot $F.app -Now ([DateTimeOffset]'2026-11-02T00:00:00Z')
}
function Assert-RPNoAuthority($R,[string]$L){$x=if($R.PSObject.Properties['result']-and$null-ne$R.result){$R.result}else{$R};foreach($f in @('permit_issued','result_is_authority','admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','mutation_authorized','auto_update_authorized','auto_install_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RPFalse ([bool]$x.$f) "$L escaped $f"}}

$oldLocal=$env:LOCALAPPDATA;$oldApp=$env:APPDATA;$base=Join-Path $env:TEMP ('real-pc-readiness-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($base)|Out-Null
try{
    $f=New-RPFixture $base;$count=0
    $r=Invoke-RP $f;Assert-RPTrue ([bool]$r.ok) ('valid denied '+[string]$r.reason);Assert-RPTrue ([bool]$r.result.production_environment_ready) 'valid readiness false';Assert-RPTrue ([bool]$r.result.eligible_to_request_production_permit) 'valid permit-request eligibility false';Assert-RPEq $r.result.live_path $script:RPLive 'valid live path';Assert-RPEq $r.result.current_tree_sha256 $script:RPLocalTree 'valid local tree';Assert-RPEq $r.result.remote_tree_sha256 $script:RPRemoteTree 'valid remote tree';Assert-RPEq $r.result.persistence_fingerprint $script:RPPersist 'valid persistence';Assert-RPNoAuthority $r 'valid';$vc=Test-CustomAppProductionRealPcReadinessResultV010 $r.result;Assert-RPTrue ([bool]$vc.ok) ('valid result invalid '+[string]$vc.reason);$count++
    foreach($mode in @('root-mismatch','baseline-unsafe','baseline-authority','fresh-source-drift','fresh-fingerprint-drift','admission-denied','admission-authority','admission-no-change','persistence-invalid')){$x=Invoke-RP $f $mode;Assert-RPFalse ([bool]$x.ok) "$mode unexpectedly succeeded";Assert-RPNoAuthority $x $mode;$count++}
    $bad=Copy-RP $f.lifecycle;$bad.ambiguous=$true;$x=Invoke-RP $f 'valid' $bad;Assert-RPFalse ([bool]$x.ok) 'ambiguous lifecycle accepted';$count++
    $bad=Copy-RP $f.lifecycle;$bad.locations=@($script:RPLive,(Join-Path $script:RPRoot 'other'));$x=Invoke-RP $f 'valid' $bad;Assert-RPFalse ([bool]$x.ok) 'multi-location lifecycle accepted';$count++
    $wrong=Join-Path $base 'WrongLocal';[IO.Directory]::CreateDirectory($wrong)|Out-Null;$x=Invoke-RP $f 'valid' $null $wrong;Assert-RPFalse ([bool]$x.ok) 'foreign current-user root accepted';$count++
    $good=Invoke-RP $f;$tamper=Copy-RP $good.result;$tamper.production_mutation_authorized=$true;$tamper.result_fingerprint=Get-CustomAppProductionRealPcReadinessSha256V010 (Get-CustomAppProductionRealPcReadinessResultMaterialV010 $tamper);$tc=Test-CustomAppProductionRealPcReadinessResultV010 $tamper;Assert-RPFalse ([bool]$tc.ok) 'rehashed authority tamper accepted';$count++
    $tamper=Copy-RP $good.result;$tamper.result_fingerprint=('f'*64);$tc=Test-CustomAppProductionRealPcReadinessResultV010 $tamper;Assert-RPFalse ([bool]$tc.ok) 'fingerprint tamper accepted';$count++
    Write-Host "CUSTOM_APP_PRODUCTION_REAL_PC_READINESS_ADAPTER_MATRIX_PASS total=$count current_user_roots=true spicetify_direct_child=true fresh_provenance=true live_admission=true persistence_read_only=true permit_not_issued=true zero_authority=true"
} finally {
    $env:LOCALAPPDATA=$oldLocal;$env:APPDATA=$oldApp
    if(Test-Path -LiteralPath $base){[IO.Directory]::Delete($base,$true)}
}
