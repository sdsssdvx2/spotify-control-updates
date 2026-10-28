$CustomAppFixtureCanaryPermitSchema = 1
$CustomAppFixtureCanaryPermitManagedBy = 'custom-app-fixture-canary-permit-v1'
$CustomAppFixtureCanaryConsumptionManagedBy = 'custom-app-fixture-canary-consumption-v1'
$CustomAppFixtureCanaryQualifiedEligibilityHead = '979e9d6362ead31016b9532f98629d6bcc2bbb56'
$CustomAppFixtureCanaryScope = 'fixture-canary-only'

function Get-CustomAppFixtureCanaryStringSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Get-CustomAppFixtureCanaryHmacSha256V010 {
    param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][byte[]]$SessionKey)
    if($SessionKey.Length -lt 32){throw 'Fixture canary session key must be at least 32 bytes.'}
    $h=New-Object System.Security.Cryptography.HMACSHA256
    try{
        $h.Key=$SessionKey
        return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())
    }finally{$h.Dispose()}
}

function Test-CustomAppFixtureCanaryFixedTimeHexV010 {
    param([AllowNull()][string]$A,[AllowNull()][string]$B)
    if($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length){return $false}
    $diff=0
    for($i=0;$i -lt $A.Length;$i++){$diff=$diff -bor ([int][char]$A[$i] -bxor [int][char]$B[$i])}
    return ($diff -eq 0)
}

function Test-CustomAppFixtureCanarySha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppFixtureCanaryCommitShaV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')
}

function Test-CustomAppFixtureCanaryNonceV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')
}

function Test-CustomAppFixtureCanarySourceV010 {
    param([AllowNull()][string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){return $false}
    return ($Value.Trim().ToLowerInvariant() -cmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$')
}

function Get-CustomAppFixtureCanaryRootV010 {
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    return [IO.Path]::GetFullPath((Join-Path (Join-Path $temp 'spotify-control-stage-acquisition') 'fixture-canary-v010')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}

function Test-CustomAppFixtureCanaryProductionAuthorityDeniedV010 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('mutation_mode','mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
    }
    if([string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if([bool]$Object.$name){return [pscustomobject]@{ok=$false;reason=($Label+'-'+$name+'-true')}}
    }
    return [pscustomobject]@{ok=$true;reason=($Label+'-production-authority-denied')}
}

function Test-CustomAppFixtureCanaryEligibilityDecisionV010 {
    param([AllowNull()]$Decision)
    if($null -eq $Decision){return [pscustomobject]@{ok=$false;reason='eligibility-decision-null'}}
    if([int]$Decision.schema -ne 1 -or [string]$Decision.managed_by -cne 'custom-app-promotion-eligibility-v1'){return [pscustomobject]@{ok=$false;reason='eligibility-owner-or-schema-mismatch'}}
    $authority=Test-CustomAppFixtureCanaryProductionAuthorityDeniedV010 -Object $Decision -Label 'eligibility-decision'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason}}
    if(-not [bool]$Decision.promotion_candidate_eligible -or -not [bool]$Decision.requires_revalidation_before_any_mutation){return [pscustomobject]@{ok=$false;reason='eligibility-not-current-candidate'}}
    $name=([string]$Decision.name).Trim();$source=([string]$Decision.source_identity).Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($name) -or -not (Test-CustomAppFixtureCanarySourceV010 $source)){return [pscustomobject]@{ok=$false;reason='eligibility-name-or-source-invalid'}}
    try{$repoId=[int64]$Decision.github_repo_id}catch{return [pscustomobject]@{ok=$false;reason='eligibility-repo-id-invalid'}}
    $surface=([string]$Decision.surface_kind).Trim().ToLowerInvariant()
    if($repoId -le 0 -or $surface -notin @('repo-commit-root','release-asset')){return [pscustomobject]@{ok=$false;reason='eligibility-repo-or-surface-invalid'}}
    $current=([string]$Decision.current_tree_sha256).Trim().ToLowerInvariant();$remote=([string]$Decision.remote_tree_sha256).Trim().ToLowerInvariant();$commit=([string]$Decision.remote_commit_sha).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppFixtureCanarySha256V010 $current) -or -not (Test-CustomAppFixtureCanarySha256V010 $remote) -or -not (Test-CustomAppFixtureCanaryCommitShaV010 $commit) -or $current -ceq $remote){return [pscustomobject]@{ok=$false;reason='eligibility-runtime-identity-invalid'}}
    foreach($fpName in @('provenance_fingerprint','binding_fingerprint','protocol_qualification_fingerprint','eligibility_fingerprint')){
        if(-not (Test-CustomAppFixtureCanarySha256V010 (([string]$Decision.$fpName).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('eligibility-fingerprint-invalid-'+$fpName)}}
    }
    return [pscustomobject]@{
        ok=$true;reason='eligibility-current-and-production-denied';name=$name;source=$source;repo_id=$repoId;surface=$surface
        current_tree_sha256=$current;remote_tree_sha256=$remote;remote_commit_sha=$commit
        provenance_fingerprint=([string]$Decision.provenance_fingerprint).Trim().ToLowerInvariant()
        binding_fingerprint=([string]$Decision.binding_fingerprint).Trim().ToLowerInvariant()
        protocol_fingerprint=([string]$Decision.protocol_qualification_fingerprint).Trim().ToLowerInvariant()
        eligibility_fingerprint=([string]$Decision.eligibility_fingerprint).Trim().ToLowerInvariant()
    }
}

function Get-CustomAppFixtureCanaryPermitMaterialV010 {
    param([Parameter(Mandatory=$true)]$Permit)
    return @(
        [string]$Permit.schema,[string]$Permit.managed_by,[string]$Permit.qualified_eligibility_head,[string]$Permit.scope,
        [string]$Permit.name,[string]$Permit.source_identity,[string]$Permit.github_repo_id,[string]$Permit.surface_kind,
        [string]$Permit.current_tree_sha256,[string]$Permit.remote_tree_sha256,[string]$Permit.remote_commit_sha,
        [string]$Permit.provenance_fingerprint,[string]$Permit.binding_fingerprint,[string]$Permit.protocol_qualification_fingerprint,[string]$Permit.eligibility_fingerprint,
        [string]$Permit.fixture_root,[string]$Permit.issued_at,[string]$Permit.expires_at,[string]$Permit.nonce,[string]$Permit.single_use
    ) -join "`n"
}

function New-CustomAppFixtureCanaryPermitV010 {
    param(
        [Parameter(Mandatory=$true)]$EligibilityDecision,
        [Parameter(Mandatory=$true)][string]$FixtureRoot,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][string]$Nonce,
        [DateTimeOffset]$IssuedAt=[DateTimeOffset]::UtcNow,
        [int]$TtlMinutes=5
    )
    $elig=Test-CustomAppFixtureCanaryEligibilityDecisionV010 -Decision $EligibilityDecision
    if(-not [bool]$elig.ok){throw ('Cannot issue fixture canary permit: '+[string]$elig.reason)}
    if($SessionKey.Length -lt 32){throw 'Fixture canary session key must be at least 32 bytes.'}
    $nonceKey=$Nonce.Trim().ToLowerInvariant();if(-not (Test-CustomAppFixtureCanaryNonceV010 $nonceKey)){throw 'Fixture canary nonce must be exactly 32 lowercase hex characters.'}
    if($TtlMinutes -lt 1 -or $TtlMinutes -gt 10){throw 'Fixture canary permit TTL must be between 1 and 10 minutes.'}
    $requiredRoot=Get-CustomAppFixtureCanaryRootV010
    $root=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not $root.Equals($requiredRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture canary permit root must equal the dedicated fixture canary root.'}
    $expires=$IssuedAt.AddMinutes($TtlMinutes)
    $permit=[pscustomobject]@{
        schema=$CustomAppFixtureCanaryPermitSchema;managed_by=$CustomAppFixtureCanaryPermitManagedBy;qualified_eligibility_head=$CustomAppFixtureCanaryQualifiedEligibilityHead;scope=$CustomAppFixtureCanaryScope
        name=[string]$elig.name;source_identity=[string]$elig.source;github_repo_id=[int64]$elig.repo_id;surface_kind=[string]$elig.surface
        current_tree_sha256=[string]$elig.current_tree_sha256;remote_tree_sha256=[string]$elig.remote_tree_sha256;remote_commit_sha=[string]$elig.remote_commit_sha
        provenance_fingerprint=[string]$elig.provenance_fingerprint;binding_fingerprint=[string]$elig.binding_fingerprint;protocol_qualification_fingerprint=[string]$elig.protocol_fingerprint;eligibility_fingerprint=[string]$elig.eligibility_fingerprint
        fixture_root=$requiredRoot;issued_at=$IssuedAt.ToUniversalTime().ToString('o');expires_at=$expires.ToUniversalTime().ToString('o');nonce=$nonceKey;single_use=$true
        token_id=$null;hmac_sha256=$null;requires_fresh_eligibility_revalidation=$true;requires_single_use_consumption=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
        fixture_canary_execution_authorized=$true
    }
    $material=Get-CustomAppFixtureCanaryPermitMaterialV010 -Permit $permit
    $permit.token_id=Get-CustomAppFixtureCanaryStringSha256V010 -Text $material
    $permit.hmac_sha256=Get-CustomAppFixtureCanaryHmacSha256V010 -Text $material -SessionKey $SessionKey
    return $permit
}

function Test-CustomAppFixtureCanaryPermitV010 {
    param(
        [AllowNull()]$Permit,[AllowNull()]$EligibilityDecision,[Parameter(Mandatory=$true)][string]$FixtureRoot,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    if($null -eq $Permit){return [pscustomobject]@{ok=$false;reason='permit-null';token_id=$null}}
    if([int]$Permit.schema -ne 1 -or [string]$Permit.managed_by -cne $CustomAppFixtureCanaryPermitManagedBy -or [string]$Permit.qualified_eligibility_head -cne $CustomAppFixtureCanaryQualifiedEligibilityHead -or [string]$Permit.scope -cne $CustomAppFixtureCanaryScope){return [pscustomobject]@{ok=$false;reason='permit-owner-schema-scope-or-parent-mismatch';token_id=$null}}
    $authority=Test-CustomAppFixtureCanaryProductionAuthorityDeniedV010 -Object $Permit -Label 'permit'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason;token_id=$null}}
    if(-not $Permit.PSObject.Properties['fixture_canary_execution_authorized'] -or -not [bool]$Permit.fixture_canary_execution_authorized -or -not [bool]$Permit.single_use -or -not [bool]$Permit.requires_fresh_eligibility_revalidation -or -not [bool]$Permit.requires_single_use_consumption){return [pscustomobject]@{ok=$false;reason='permit-fixture-scope-flags-invalid';token_id=$null}}
    if($SessionKey.Length -lt 32){return [pscustomobject]@{ok=$false;reason='permit-session-key-too-short';token_id=$null}}
    $elig=Test-CustomAppFixtureCanaryEligibilityDecisionV010 -Decision $EligibilityDecision
    if(-not [bool]$elig.ok){return [pscustomobject]@{ok=$false;reason=('permit-current-eligibility-denied:'+[string]$elig.reason);token_id=$null}}
    $requiredRoot=Get-CustomAppFixtureCanaryRootV010
    try{$requestedRoot=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);$permitRoot=[IO.Path]::GetFullPath([string]$Permit.fixture_root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)}catch{return [pscustomobject]@{ok=$false;reason='permit-fixture-root-invalid';token_id=$null}}
    if(-not $requestedRoot.Equals($requiredRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $permitRoot.Equals($requiredRoot,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='permit-fixture-root-scope-mismatch';token_id=$null}}
    if(-not (Test-CustomAppFixtureCanaryNonceV010 ([string]$Permit.nonce)) -or -not (Test-CustomAppFixtureCanarySha256V010 ([string]$Permit.token_id)) -or -not (Test-CustomAppFixtureCanarySha256V010 ([string]$Permit.hmac_sha256)){return [pscustomobject]@{ok=$false;reason='permit-token-identity-invalid';token_id=$null}}
    $issued=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Permit.issued_at,[ref]$issued) -or -not [DateTimeOffset]::TryParse([string]$Permit.expires_at,[ref]$expires)){return [pscustomobject]@{ok=$false;reason='permit-time-invalid';token_id=[string]$Permit.token_id}}
    if($expires -le $issued -or $expires -gt $issued.AddMinutes(10)){return [pscustomobject]@{ok=$false;reason='permit-ttl-invalid';token_id=[string]$Permit.token_id}}
    if($Now -lt $issued.AddSeconds(-30)){return [pscustomobject]@{ok=$false;reason='permit-not-yet-valid';token_id=[string]$Permit.token_id}}
    if($Now -ge $expires){return [pscustomobject]@{ok=$false;reason='permit-expired';token_id=[string]$Permit.token_id}}
    foreach($pair in @(
        @('name',[string]$elig.name),@('source_identity',[string]$elig.source),@('github_repo_id',[string]$elig.repo_id),@('surface_kind',[string]$elig.surface),
        @('current_tree_sha256',[string]$elig.current_tree_sha256),@('remote_tree_sha256',[string]$elig.remote_tree_sha256),@('remote_commit_sha',[string]$elig.remote_commit_sha),
        @('provenance_fingerprint',[string]$elig.provenance_fingerprint),@('binding_fingerprint',[string]$elig.binding_fingerprint),@('protocol_qualification_fingerprint',[string]$elig.protocol_fingerprint),@('eligibility_fingerprint',[string]$elig.eligibility_fingerprint)
    )){if([string]$Permit.($pair[0]) -cne [string]$pair[1]){return [pscustomobject]@{ok=$false;reason=('permit-current-eligibility-binding-mismatch-'+[string]$pair[0]);token_id=[string]$Permit.token_id}}}
    $material=Get-CustomAppFixtureCanaryPermitMaterialV010 -Permit $Permit
    $expectedId=Get-CustomAppFixtureCanaryStringSha256V010 -Text $material
    if(-not (Test-CustomAppFixtureCanaryFixedTimeHexV010 -A ([string]$Permit.token_id) -B $expectedId)){return [pscustomobject]@{ok=$false;reason='permit-token-id-mismatch';token_id=[string]$Permit.token_id}}
    $expectedMac=Get-CustomAppFixtureCanaryHmacSha256V010 -Text $material -SessionKey $SessionKey
    if(-not (Test-CustomAppFixtureCanaryFixedTimeHexV010 -A ([string]$Permit.hmac_sha256) -B $expectedMac)){return [pscustomobject]@{ok=$false;reason='permit-hmac-mismatch';token_id=[string]$Permit.token_id}}
    return [pscustomobject]@{
        ok=$true;reason='fixture-canary-permit-current-hmac-bound';token_id=[string]$Permit.token_id;name=[string]$elig.name;source_identity=[string]$elig.source
        eligibility_fingerprint=[string]$elig.eligibility_fingerprint;fixture_root=$requiredRoot;expires_at=$expires.ToUniversalTime().ToString('o')
        fixture_canary_execution_authorized=$true;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function New-CustomAppFixtureCanaryConsumptionStateV010 {
    return [pscustomobject]@{
        schema=1;managed_by=$CustomAppFixtureCanaryConsumptionManagedBy;consumed_token_ids=@()
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Invoke-CustomAppFixtureCanaryPermitConsumptionV010 {
    param(
        [AllowNull()]$Permit,[AllowNull()]$EligibilityDecision,[Parameter(Mandatory=$true)][string]$FixtureRoot,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)]$ConsumptionState,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $stateAuthority=Test-CustomAppFixtureCanaryProductionAuthorityDeniedV010 -Object $ConsumptionState -Label 'consumption-state'
    if(-not [bool]$stateAuthority.ok -or [int]$ConsumptionState.schema -ne 1 -or [string]$ConsumptionState.managed_by -cne $CustomAppFixtureCanaryConsumptionManagedBy){return [pscustomobject]@{ok=$false;reason='consumption-state-invalid';next_state=$ConsumptionState;fixture_canary_execution_authorized=$false;production_mutation_authorized=$false}}
    $verified=Test-CustomAppFixtureCanaryPermitV010 -Permit $Permit -EligibilityDecision $EligibilityDecision -FixtureRoot $FixtureRoot -SessionKey $SessionKey -Now $Now
    if(-not [bool]$verified.ok){return [pscustomobject]@{ok=$false;reason=[string]$verified.reason;next_state=$ConsumptionState;fixture_canary_execution_authorized=$false;production_mutation_authorized=$false}}
    $tokenId=[string]$verified.token_id
    foreach($used in @($ConsumptionState.consumed_token_ids)){if([string]$used -ceq $tokenId){return [pscustomobject]@{ok=$false;reason='permit-replay-detected';next_state=$ConsumptionState;fixture_canary_execution_authorized=$false;production_mutation_authorized=$false}}}
    $ids=New-Object System.Collections.Generic.List[string]
    foreach($used in @($ConsumptionState.consumed_token_ids)){if(-not [string]::IsNullOrWhiteSpace([string]$used)){$ids.Add([string]$used)}}
    $ids.Add($tokenId)
    $next=[pscustomobject]@{
        schema=1;managed_by=$CustomAppFixtureCanaryConsumptionManagedBy;consumed_token_ids=@($ids)
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
    return [pscustomobject]@{
        ok=$true;reason='fixture-canary-permit-consumed-once';token_id=$tokenId;next_state=$next
        fixture_canary_execution_authorized=$true;fixture_root=[string]$verified.fixture_root;eligibility_fingerprint=[string]$verified.eligibility_fingerprint
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}
