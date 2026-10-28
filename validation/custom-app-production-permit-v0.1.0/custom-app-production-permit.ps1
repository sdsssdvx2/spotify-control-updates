$CustomAppProductionPermitSchema = 1
$CustomAppProductionPermitManagedBy = 'custom-app-production-permit-v1'
$CustomAppProductionPermitQualifiedAdmissionHead = 'c128595c3ac7eab338f5d23d7041ae56a6822948'
$CustomAppProductionPermitScope = 'production-update-single-use-prerequisite'

function Get-CustomAppProductionPermitSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Get-CustomAppProductionPermitHmacV010 {
    param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][byte[]]$SessionKey)
    if($SessionKey.Length -lt 32){throw 'Production permit session key must be at least 32 bytes.'}
    $h=New-Object Security.Cryptography.HMACSHA256
    try{$h.Key=$SessionKey;return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$h.Dispose()}
}

function Test-CustomAppProductionPermitFixedTimeHexV010 {
    param([AllowNull()][string]$A,[AllowNull()][string]$B)
    if($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length){return $false}
    $diff=0
    for($i=0;$i -lt $A.Length;$i++){$diff=$diff -bor ([int][char]$A[$i] -bxor [int][char]$B[$i])}
    return ($diff -eq 0)
}

function Test-CustomAppProductionPermitSha256V010 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')}
function Test-CustomAppProductionPermitCommitV010 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')}
function Test-CustomAppProductionPermitNonceV010 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')}
function Test-CustomAppProductionPermitSourceV010 {param([AllowNull()][string]$Value)if([string]::IsNullOrWhiteSpace($Value)){return $false};return ($Value.Trim().ToLowerInvariant() -cmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$')}

function Test-CustomAppProductionPermitAdmissionDecisionV010 {
    param([AllowNull()]$Decision)
    if($null -eq $Decision){return [pscustomobject]@{ok=$false;reason='admission-null'}}
    if([int]$Decision.schema -ne 1 -or [string]$Decision.managed_by -cne 'custom-app-live-attested-production-admission-v1'){return [pscustomobject]@{ok=$false;reason='admission-owner-or-schema-mismatch'}}
    if(-not [bool]$Decision.production_admission_eligible -or [string]$Decision.reason -cne 'fresh-current-evidence-plus-live-attested-protocol-qualified'){return [pscustomobject]@{ok=$false;reason='admission-not-current-eligible'}}
    if([bool]$Decision.admission_is_authority -or [bool]$Decision.production_permit_issued -or -not [bool]$Decision.requires_fresh_revalidation_before_any_future_action){return [pscustomobject]@{ok=$false;reason='admission-authority-separation-invalid'}}
    if([string]$Decision.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason='admission-mutation-mode-not-deny'}}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){if([bool]$Decision.$name){return [pscustomobject]@{ok=$false;reason=('admission-'+$name+'-true')}}}
    $nameKey=([string]$Decision.name).Trim();$source=([string]$Decision.source_identity).Trim().ToLowerInvariant();$surface=([string]$Decision.surface_kind).Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($nameKey) -or -not (Test-CustomAppProductionPermitSourceV010 $source)){return [pscustomobject]@{ok=$false;reason='admission-name-or-source-invalid'}}
    try{$repo=[int64]$Decision.github_repo_id}catch{return [pscustomobject]@{ok=$false;reason='admission-repo-id-invalid'}}
    if($repo -le 0 -or $surface -notin @('repo-commit-root','release-asset')){return [pscustomobject]@{ok=$false;reason='admission-repo-or-surface-invalid'}}
    $current=([string]$Decision.current_tree_sha256).Trim().ToLowerInvariant();$remote=([string]$Decision.remote_tree_sha256).Trim().ToLowerInvariant();$commit=([string]$Decision.remote_commit_sha).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionPermitSha256V010 $current) -or -not (Test-CustomAppProductionPermitSha256V010 $remote) -or -not (Test-CustomAppProductionPermitCommitV010 $commit) -or $current -ceq $remote){return [pscustomobject]@{ok=$false;reason='admission-runtime-identity-invalid'}}
    foreach($fp in @('current_eligibility_fingerprint','live_attested_qualification_fingerprint','admission_fingerprint')){if(-not (Test-CustomAppProductionPermitSha256V010 (([string]$Decision.$fp).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('admission-fingerprint-invalid-'+$fp)}}}
    return [pscustomobject]@{ok=$true;reason='admission-current-and-authority-denied';name=$nameKey;source=$source;repo_id=$repo;surface=$surface;current=$current;remote=$remote;commit=$commit;eligibility_fingerprint=([string]$Decision.current_eligibility_fingerprint).Trim().ToLowerInvariant();live_fingerprint=([string]$Decision.live_attested_qualification_fingerprint).Trim().ToLowerInvariant();admission_fingerprint=([string]$Decision.admission_fingerprint).Trim().ToLowerInvariant()}
}

function Get-CustomAppProductionPermitMaterialV010 {
    param([Parameter(Mandatory=$true)]$Permit)
    return @(
        [string]$Permit.schema,[string]$Permit.managed_by,[string]$Permit.qualified_admission_head,[string]$Permit.scope,
        [string]$Permit.name,[string]$Permit.source_identity,[string]$Permit.github_repo_id,[string]$Permit.surface_kind,
        [string]$Permit.current_tree_sha256,[string]$Permit.remote_tree_sha256,[string]$Permit.remote_commit_sha,
        [string]$Permit.current_eligibility_fingerprint,[string]$Permit.live_attested_qualification_fingerprint,[string]$Permit.admission_fingerprint,
        [string]$Permit.issued_at,[string]$Permit.expires_at,[string]$Permit.nonce,[string]$Permit.single_use,
        [string]$Permit.requires_single_use_consumption,[string]$Permit.requires_fresh_admission_revalidation_on_consume,[string]$Permit.permit_is_authority,
        [string]$Permit.production_execution_authorized,[string]$Permit.production_mutation_authorized
    ) -join "`n"
}

function New-CustomAppProductionPermitV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)][string]$Nonce,[DateTimeOffset]$IssuedAt=[DateTimeOffset]::UtcNow,[int]$TtlMinutes=3,[int]$MaxRemoteObservationAgeHours=36
    )
    if($SessionKey.Length -lt 32){throw 'Production permit session key must be at least 32 bytes.'}
    $nonceKey=$Nonce.Trim().ToLowerInvariant();if(-not (Test-CustomAppProductionPermitNonceV010 $nonceKey)){throw 'Production permit nonce must be exactly 32 lowercase hex characters.'}
    if($TtlMinutes -lt 1 -or $TtlMinutes -gt 5){throw 'Production permit TTL must be between 1 and 5 minutes.'}
    $admission=Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -Now $IssuedAt -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    $a=Test-CustomAppProductionPermitAdmissionDecisionV010 -Decision $admission
    if(-not [bool]$a.ok){throw ('Cannot issue production permit prerequisite: '+[string]$a.reason)}
    $permit=[pscustomobject]@{
        schema=$CustomAppProductionPermitSchema;managed_by=$CustomAppProductionPermitManagedBy;qualified_admission_head=$CustomAppProductionPermitQualifiedAdmissionHead;scope=$CustomAppProductionPermitScope
        name=[string]$a.name;source_identity=[string]$a.source;github_repo_id=[int64]$a.repo_id;surface_kind=[string]$a.surface
        current_tree_sha256=[string]$a.current;remote_tree_sha256=[string]$a.remote;remote_commit_sha=[string]$a.commit
        current_eligibility_fingerprint=[string]$a.eligibility_fingerprint;live_attested_qualification_fingerprint=[string]$a.live_fingerprint;admission_fingerprint=[string]$a.admission_fingerprint
        issued_at=$IssuedAt.ToUniversalTime().ToString('o');expires_at=$IssuedAt.AddMinutes($TtlMinutes).ToUniversalTime().ToString('o');nonce=$nonceKey;single_use=$true
        token_id=$null;hmac_sha256=$null;production_permit_issued=$true;permit_is_authority=$false
        requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;replay_protection_requires_external_consumption_ledger=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $material=Get-CustomAppProductionPermitMaterialV010 -Permit $permit
    $permit.token_id=Get-CustomAppProductionPermitSha256V010 -Text $material
    $permit.hmac_sha256=Get-CustomAppProductionPermitHmacV010 -Text $material -SessionKey $SessionKey
    return $permit
}

function Test-CustomAppProductionPermitV010 {
    param(
        [AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason,[AllowNull()][string]$Token=$null)[pscustomobject]@{ok=$false;reason=$Reason;token_id=$Token;production_execution_authorized=$false;production_mutation_authorized=$false;requires_single_use_consumption=$true;requires_fresh_admission_revalidation=$true}}
    if($null -eq $Permit){return & $deny 'permit-null'}
    if([int]$Permit.schema -ne 1 -or [string]$Permit.managed_by -cne $CustomAppProductionPermitManagedBy -or [string]$Permit.qualified_admission_head -cne $CustomAppProductionPermitQualifiedAdmissionHead -or [string]$Permit.scope -cne $CustomAppProductionPermitScope){return & $deny 'permit-owner-schema-scope-or-parent-mismatch' ([string]$Permit.token_id)}
    if(-not [bool]$Permit.production_permit_issued -or [bool]$Permit.permit_is_authority -or -not [bool]$Permit.single_use -or -not [bool]$Permit.requires_single_use_consumption -or -not [bool]$Permit.requires_fresh_admission_revalidation_on_consume -or -not [bool]$Permit.replay_protection_requires_external_consumption_ledger){return & $deny 'permit-scope-or-consumption-flags-invalid' ([string]$Permit.token_id)}
    if([string]$Permit.mutation_mode -cne 'deny'){return & $deny 'permit-mutation-mode-not-deny' ([string]$Permit.token_id)}
    foreach($field in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Permit.$field){return & $deny ('permit-'+$field+'-true') ([string]$Permit.token_id)}}
    if($SessionKey.Length -lt 32){return & $deny 'permit-session-key-too-short' ([string]$Permit.token_id)}
    if(-not (Test-CustomAppProductionPermitNonceV010 ([string]$Permit.nonce)) -or -not (Test-CustomAppProductionPermitSha256V010 ([string]$Permit.token_id)) -or -not (Test-CustomAppProductionPermitSha256V010 ([string]$Permit.hmac_sha256))){return & $deny 'permit-token-identity-invalid' ([string]$Permit.token_id)}
    $issued=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Permit.issued_at,[ref]$issued) -or -not [DateTimeOffset]::TryParse([string]$Permit.expires_at,[ref]$expires)){return & $deny 'permit-time-invalid' ([string]$Permit.token_id)}
    if($expires -le $issued -or $expires -gt $issued.AddMinutes(5)){return & $deny 'permit-ttl-invalid' ([string]$Permit.token_id)}
    if($Now -lt $issued.AddSeconds(-30)){return & $deny 'permit-not-yet-valid' ([string]$Permit.token_id)}
    if($Now -ge $expires){return & $deny 'permit-expired' ([string]$Permit.token_id)}
    $material=Get-CustomAppProductionPermitMaterialV010 -Permit $Permit;$token=Get-CustomAppProductionPermitSha256V010 $material;$hmac=Get-CustomAppProductionPermitHmacV010 $material $SessionKey
    if(-not (Test-CustomAppProductionPermitFixedTimeHexV010 ([string]$Permit.token_id).ToLowerInvariant() $token)){return & $deny 'permit-token-id-mismatch' ([string]$Permit.token_id)}
    if(-not (Test-CustomAppProductionPermitFixedTimeHexV010 ([string]$Permit.hmac_sha256).ToLowerInvariant() $hmac)){return & $deny 'permit-hmac-mismatch' ([string]$Permit.token_id)}
    $admission=Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    $a=Test-CustomAppProductionPermitAdmissionDecisionV010 $admission
    if(-not [bool]$a.ok){return & $deny ('permit-current-admission-denied:'+[string]$a.reason) ([string]$Permit.token_id)}
    $pairs=@(
        @('name',[string]$a.name),@('source_identity',[string]$a.source),@('github_repo_id',[string]$a.repo_id),@('surface_kind',[string]$a.surface),
        @('current_tree_sha256',[string]$a.current),@('remote_tree_sha256',[string]$a.remote),@('remote_commit_sha',[string]$a.commit),
        @('current_eligibility_fingerprint',[string]$a.eligibility_fingerprint),@('live_attested_qualification_fingerprint',[string]$a.live_fingerprint),@('admission_fingerprint',[string]$a.admission_fingerprint)
    )
    foreach($p in $pairs){if(([string]$Permit.($p[0])).Trim().ToLowerInvariant() -cne ([string]$p[1]).Trim().ToLowerInvariant()){return & $deny ('permit-current-'+$p[0]+'-mismatch') ([string]$Permit.token_id)}}
    return [pscustomobject]@{ok=$true;reason='production-permit-cryptographically-valid-prerequisite';token_id=[string]$Permit.token_id;production_execution_authorized=$false;production_mutation_authorized=$false;requires_single_use_consumption=$true;requires_fresh_admission_revalidation=$true;replay_protection_requires_external_consumption_ledger=$true}
}
