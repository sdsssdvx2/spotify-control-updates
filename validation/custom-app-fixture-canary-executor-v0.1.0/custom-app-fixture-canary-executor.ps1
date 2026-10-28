$CustomAppFixtureCanaryExecutorSchema = 1
$CustomAppFixtureCanaryExecutorManagedBy = 'custom-app-fixture-canary-executor-v1'
$CustomAppFixtureCanaryExecutorQualifiedPermitHead = '79c7ef064a216ee3ff34328be282d742f0f7abc0'

function Test-CustomAppFixtureCanaryExecutorPathWithinV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$false)
    $r=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $p=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)){return $AllowRoot}
    return $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}

function Test-CustomAppFixtureCanaryExecutorPathChainV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[string]$Label='path',[bool]$RequireExisting=$false)
    $r=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $p=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not (Test-CustomAppFixtureCanaryExecutorPathWithinV010 -Root $r -Path $p -AllowRoot:$true)){throw "$Label escaped dedicated fixture canary root."}
    if(-not (Test-Path -LiteralPath $r -PathType Container)){throw "$Label dedicated fixture canary root is missing."}
    $rootItem=Get-Item -LiteralPath $r -Force -ErrorAction Stop
    if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label dedicated fixture canary root is a reparse point."}
    $probe=$p
    while(-not $probe.Equals($r,[StringComparison]::OrdinalIgnoreCase)){
        if(Test-Path -LiteralPath $probe){
            $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label contains a reparse-point ancestor."}
        }
        $parent=[IO.Directory]::GetParent($probe)
        if($null -eq $parent){throw "$Label parent chain escaped fixture root."}
        $probe=$parent.FullName
        if(-not ($probe.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $probe.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw "$Label parent chain escaped fixture root."}
    }
    if($RequireExisting -and -not (Test-Path -LiteralPath $p)){throw "$Label is missing."}
    return $p
}

function Test-CustomAppFixtureCanaryExecutorDeniedAuthorityV010 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('mutation_mode','mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
    }
    if([string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if([bool]$Object.$name){return [pscustomobject]@{ok=$false;reason=($Label+'-'+$name+'-true')}}
    }
    return [pscustomobject]@{ok=$true;reason=($Label+'-strict-production-deny')}
}

function Get-CustomAppFixtureCanaryFreshEligibilityV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$ProtocolQualification,
        [Parameter(Mandatory=$true)][DateTimeOffset]$Now
    )
    $root=Get-CustomAppFixtureCanaryRootV010
    [void](Test-CustomAppFixtureCanaryExecutorPathChainV010 -Root $root -Path $root -Label 'eligibility root' -RequireExisting:$true)
    if($null -eq $LifecycleRow -or @($LifecycleRow.locations).Count -ne 1){return [pscustomobject]@{ok=$false;reason='executor-lifecycle-not-single-path';decision=$null;baseline=$null}}
    try{$live=Test-CustomAppFixtureCanaryExecutorPathChainV010 -Root $root -Path ([string]$LifecycleRow.locations[0]) -Label 'executor live path' -RequireExisting:$true}catch{return [pscustomobject]@{ok=$false;reason=('executor-live-path-denied:'+[string]$_.Exception.Message);decision=$null;baseline=$null}}
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $live
    if(-not [bool]$baseline.safe -or -not [bool]$baseline.installable){return [pscustomobject]@{ok=$false;reason='executor-current-runtime-not-safe-installable';decision=$null;baseline=$baseline}}
    if(-not $baseline.PSObject.Properties['path']){$baseline|Add-Member -NotePropertyName path -NotePropertyValue $live}
    else{$baseline.path=$live}
    $decision=Resolve-CustomAppPromotionEligibilityV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $baseline -ProtocolQualification $ProtocolQualification -Now $Now
    $authority=Test-CustomAppFixtureCanaryExecutorDeniedAuthorityV010 -Object $decision -Label 'fresh-eligibility'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason;decision=$decision;baseline=$baseline}}
    if(-not [bool]$decision.promotion_candidate_eligible){return [pscustomobject]@{ok=$false;reason=('fresh-eligibility-denied:'+[string]$decision.reason);decision=$decision;baseline=$baseline}}
    return [pscustomobject]@{ok=$true;reason='fresh-eligibility-current';decision=$decision;baseline=$baseline;live_path=$live}
}

function Test-CustomAppFixtureCanaryExecutorPermitGateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$ProtocolQualification,
        [Parameter(Mandatory=$true)]$Permit,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][DateTimeOffset]$Now,
        [AllowNull()][string]$ExpectedEligibilityFingerprint=$null,
        [string]$Phase='gate'
    )
    $fresh=Get-CustomAppFixtureCanaryFreshEligibilityV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -ProtocolQualification $ProtocolQualification -Now $Now
    if(-not [bool]$fresh.ok){return [pscustomobject]@{ok=$false;reason=($Phase+':'+[string]$fresh.reason);fresh=$fresh;permit_check=$null}}
    $fp=([string]$fresh.decision.eligibility_fingerprint).Trim().ToLowerInvariant()
    if(-not [string]::IsNullOrWhiteSpace($ExpectedEligibilityFingerprint) -and $fp -cne $ExpectedEligibilityFingerprint.Trim().ToLowerInvariant()){
        return [pscustomobject]@{ok=$false;reason=($Phase+':eligibility-fingerprint-changed');fresh=$fresh;permit_check=$null}
    }
    $root=Get-CustomAppFixtureCanaryRootV010
    $check=Test-CustomAppFixtureCanaryPermitV010 -Permit $Permit -EligibilityDecision $fresh.decision -FixtureRoot $root -SessionKey $SessionKey -Now $Now
    if(-not [bool]$check.ok){return [pscustomobject]@{ok=$false;reason=($Phase+':'+[string]$check.reason);fresh=$fresh;permit_check=$check}}
    if(-not [bool]$check.fixture_canary_execution_authorized -or [bool]$check.canary_execution_authorized -or [bool]$check.production_mutation_authorized){return [pscustomobject]@{ok=$false;reason=($Phase+':permit-authority-separation-failed');fresh=$fresh;permit_check=$check}}
    return [pscustomobject]@{ok=$true;reason=($Phase+':fresh-eligibility-and-hmac-current');fresh=$fresh;permit_check=$check;eligibility_fingerprint=$fp}
}

function Get-CustomAppFixtureCanaryConsumptionDirectoryV010 {
    $root=Get-CustomAppFixtureCanaryRootV010
    return [IO.Path]::GetFullPath((Join-Path $root '.consumed-permits'))
}

function Use-CustomAppFixtureCanaryPermitDurablyV010 {
    param(
        [Parameter(Mandatory=$true)]$Permit,
        [Parameter(Mandatory=$true)]$EligibilityDecision,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)]$ConsumptionState,
        [Parameter(Mandatory=$true)][DateTimeOffset]$Now
    )
    $root=Get-CustomAppFixtureCanaryRootV010
    $dir=Get-CustomAppFixtureCanaryConsumptionDirectoryV010
    [void](Test-CustomAppFixtureCanaryExecutorPathChainV010 -Root $root -Path $dir -Label 'permit consumption directory' -RequireExisting:$true)
    $dirItem=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
    if(($dirItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return [pscustomobject]@{ok=$false;reason='permit-consumption-directory-reparse';next_state=$ConsumptionState;marker_path=$null}}
    $memory=Invoke-CustomAppFixtureCanaryPermitConsumptionV010 -Permit $Permit -EligibilityDecision $EligibilityDecision -FixtureRoot $root -SessionKey $SessionKey -ConsumptionState $ConsumptionState -Now $Now
    if(-not [bool]$memory.ok){return [pscustomobject]@{ok=$false;reason=[string]$memory.reason;next_state=$ConsumptionState;marker_path=$null}}
    $token=([string]$memory.token_id).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppFixtureCanarySha256V010 $token)){return [pscustomobject]@{ok=$false;reason='durable-consumption-token-invalid';next_state=$ConsumptionState;marker_path=$null}}
    $marker=Test-CustomAppFixtureCanaryExecutorPathChainV010 -Root $root -Path (Join-Path $dir ($token+'.used')) -Label 'permit consumption marker'
    $stream=$null;$writer=$null
    try{
        try{$stream=[IO.File]::Open($marker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)}catch [IO.IOException]{return [pscustomobject]@{ok=$false;reason='durable-permit-replay-detected';next_state=$ConsumptionState;marker_path=$marker}}
        $writer=New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($false)),1024,$true)
        $writer.WriteLine($token);$writer.WriteLine(([string]$memory.eligibility_fingerprint).Trim().ToLowerInvariant());$writer.WriteLine($Now.ToUniversalTime().ToString('o'));$writer.Flush();$stream.Flush()
    }finally{if($null -ne $writer){$writer.Dispose()};if($null -ne $stream){$stream.Dispose()}}
    $markerItem=Get-Item -LiteralPath $marker -Force -ErrorAction Stop
    if(($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $markerItem.Length -le 0){return [pscustomobject]@{ok=$false;reason='durable-permit-marker-invalid';next_state=$ConsumptionState;marker_path=$marker}}
    return [pscustomobject]@{ok=$true;reason='permit-consumed-memory-and-disk-before-external-mutation';next_state=$memory.next_state;marker_path=$marker;token_id=$token;eligibility_fingerprint=[string]$memory.eligibility_fingerprint}
}

function Test-CustomAppFixtureCanaryConsumptionMarkerV010 {
    param([Parameter(Mandatory=$true)][string]$MarkerPath,[Parameter(Mandatory=$true)][string]$TokenId,[Parameter(Mandatory=$true)][string]$EligibilityFingerprint)
    $root=Get-CustomAppFixtureCanaryRootV010
    try{$marker=Test-CustomAppFixtureCanaryExecutorPathChainV010 -Root $root -Path $MarkerPath -Label 'pre-apply consumption marker' -RequireExisting:$true}catch{return [pscustomobject]@{ok=$false;reason=('consumption-marker-path-denied:'+[string]$_.Exception.Message)}}
    $item=Get-Item -LiteralPath $marker -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return [pscustomobject]@{ok=$false;reason='consumption-marker-reparse'}}
    $lines=@(Get-Content -LiteralPath $marker -ErrorAction Stop)
    if($lines.Count -lt 2 -or ([string]$lines[0]).Trim().ToLowerInvariant() -cne $TokenId.Trim().ToLowerInvariant() -or ([string]$lines[1]).Trim().ToLowerInvariant() -cne $EligibilityFingerprint.Trim().ToLowerInvariant()){
        return [pscustomobject]@{ok=$false;reason='consumption-marker-content-mismatch'}
    }
    return [pscustomobject]@{ok=$true;reason='consumption-marker-current'}
}

function New-CustomAppFixtureCanaryExecutorResultV010 {
    param([string]$Name,[string]$Status,[string]$Reason,[bool]$Committed=$false,[bool]$RolledBack=$false,[AllowNull()]$ShadowResult=$null,[AllowNull()]$NextConsumptionState=$null,[AllowNull()][string]$TokenId=$null,[AllowNull()][string]$MarkerPath=$null,[AllowNull()][string]$EligibilityFingerprint=$null)
    return [pscustomobject]@{
        schema=$CustomAppFixtureCanaryExecutorSchema;managed_by=$CustomAppFixtureCanaryExecutorManagedBy;qualified_permit_head=$CustomAppFixtureCanaryExecutorQualifiedPermitHead
        name=$Name;status=$Status;reason=$Reason;committed=$Committed;rolled_back=$RolledBack;shadow_result=$ShadowResult;next_consumption_state=$NextConsumptionState
        token_id=$TokenId;marker_path=$MarkerPath;eligibility_fingerprint=$EligibilityFingerprint;fixture_canary_execution_authorized=$false
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Invoke-CustomAppFixtureCanaryExecutorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$ProtocolQualification,
        [Parameter(Mandatory=$true)]$Permit,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)]$ConsumptionState,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$PersistenceBackupRoot,
        [AllowNull()]$PreStageNow=$null,
        [AllowNull()]$PreApplyNow=$null,
        [switch]$InjectTransactionPostApplyFailure,
        [switch]$InjectPersistenceDriftAfterApply,
        [AllowNull()][string]$PersistenceDriftTarget=$null
    )
    $root=Get-CustomAppFixtureCanaryRootV010
    try{
        [void](Test-CustomAppFixtureCanaryExecutorPathChainV010 -Root $root -Path $root -Label 'executor root' -RequireExisting:$true)
        [void](Test-CustomAppFixtureCanaryExecutorPathChainV010 -Root $root -Path (Get-CustomAppFixtureCanaryConsumptionDirectoryV010) -Label 'executor consumption directory' -RequireExisting:$true)
        foreach($entry in @(@($LocalAppDataRoot,'local persistence root'),@($AppDataRoot,'roaming persistence root'),@($PersistenceBackupRoot,'persistence backup root'))){[void](Test-CustomAppFixtureCanaryExecutorPathChainV010 -Root $root -Path ([string]$entry[0]) -Label ([string]$entry[1]))}
    }catch{return New-CustomAppFixtureCanaryExecutorResultV010 -Name $Name -Status 'denied-before-consumption' -Reason ([string]$_.Exception.Message) -NextConsumptionState $ConsumptionState}

    $stageNow=if($null -eq $PreStageNow){[DateTimeOffset]::UtcNow}else{[DateTimeOffset]$PreStageNow}
    $pre=Test-CustomAppFixtureCanaryExecutorPermitGateV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -ProtocolQualification $ProtocolQualification -Permit $Permit -SessionKey $SessionKey -Now $stageNow -Phase 'pre-stage'
    if(-not [bool]$pre.ok){return New-CustomAppFixtureCanaryExecutorResultV010 -Name $Name -Status 'denied-before-consumption' -Reason ([string]$pre.reason) -NextConsumptionState $ConsumptionState}
    $eligibilityFingerprint=[string]$pre.eligibility_fingerprint
    $consumed=Use-CustomAppFixtureCanaryPermitDurablyV010 -Permit $Permit -EligibilityDecision $pre.fresh.decision -SessionKey $SessionKey -ConsumptionState $ConsumptionState -Now $stageNow
    if(-not [bool]$consumed.ok){return New-CustomAppFixtureCanaryExecutorResultV010 -Name $Name -Status 'denied-before-staging' -Reason ([string]$consumed.reason) -NextConsumptionState $ConsumptionState -EligibilityFingerprint $eligibilityFingerprint -MarkerPath ([string]$consumed.marker_path}

    $stage=$null;$originalStageRoot=$null;$originalTx=$null;$stageRootOverridden=$false;$txOverridden=$false
    try{
        $originalStageRoot=(Get-Item -LiteralPath 'Function:\Get-CustomAppStageWorkspaceRootV010' -ErrorAction Stop).ScriptBlock
        $script:CustomAppFixtureCanaryExecutorRootOverrideV010=$root
        Set-Item -LiteralPath 'Function:\Get-CustomAppStageWorkspaceRootV010' -Value { return [string]$script:CustomAppFixtureCanaryExecutorRootOverrideV010 }
        $stageRootOverridden=$true

        $stage=Invoke-CustomAppStageAcquisitionV010 -Name $Name -BindingRow $BindingRow
        $applyGateNow=if($null -eq $PreApplyNow){[DateTimeOffset]::UtcNow}else{[DateTimeOffset]$PreApplyNow}
        $postStage=Test-CustomAppFixtureCanaryExecutorPermitGateV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -ProtocolQualification $ProtocolQualification -Permit $Permit -SessionKey $SessionKey -Now $applyGateNow -ExpectedEligibilityFingerprint $eligibilityFingerprint -Phase 'post-stage'
        if(-not [bool]$postStage.ok){return New-CustomAppFixtureCanaryExecutorResultV010 -Name $Name -Status 'denied-after-staging' -Reason ([string]$postStage.reason) -NextConsumptionState $consumed.next_state -TokenId ([string]$consumed.token_id) -MarkerPath ([string]$consumed.marker_path) -EligibilityFingerprint $eligibilityFingerprint}
        if([string]$stage.status -cne 'staged-verified' -or [string]$stage.remote_tree_sha256 -cne [string]$Permit.remote_tree_sha256 -or [string]$stage.commit_sha -cne [string]$Permit.remote_commit_sha){return New-CustomAppFixtureCanaryExecutorResultV010 -Name $Name -Status 'denied-after-staging' -Reason 'staged-identity-does-not-match-consumed-permit' -NextConsumptionState $consumed.next_state -TokenId ([string]$consumed.token_id) -MarkerPath ([string]$consumed.marker_path) -EligibilityFingerprint $eligibilityFingerprint}

        $originalTx=(Get-Item -LiteralPath 'Function:\Invoke-CustomAppUpdateFixtureTransactionV010' -ErrorAction Stop).ScriptBlock
        $script:CustomAppFixtureCanaryExecutorOriginalTransactionV010=$originalTx
        $script:CustomAppFixtureCanaryExecutorApplyContextV010=[pscustomobject]@{
            name=$Name;lifecycle=$LifecycleRow;provenance=$ProvenanceRow;binding=$BindingRow;protocol=$ProtocolQualification;permit=$Permit;session_key=$SessionKey
            eligibility_fingerprint=$eligibilityFingerprint;marker_path=[string]$consumed.marker_path;token_id=[string]$consumed.token_id;apply_now_override=$PreApplyNow
        }
        Set-Item -LiteralPath 'Function:\Invoke-CustomAppUpdateFixtureTransactionV010' -Value {
            param(
                [Parameter(Mandatory=$true)]$Plan,
                [Parameter(Mandatory=$true)][string]$ValidationRoot,
                [Parameter(Mandatory=$true)]$PersistenceProof,
                [switch]$InjectPostApplyFailure,
                [switch]$InjectRollbackFailure
            )
            $ctx=$script:CustomAppFixtureCanaryExecutorApplyContextV010
            if($null -eq $ctx){return [pscustomobject]@{schema=1;transaction_id=[string]$Plan.transaction_id;status='denied-before-apply';committed=$false;rolled_back=$false;rollback_verified=$false;reason='fixture-canary-apply-context-missing';mutation_mode='deny';production_mutation_authorized=$false}}
            $now=if($null -eq $ctx.apply_now_override){[DateTimeOffset]::UtcNow}else{[DateTimeOffset]$ctx.apply_now_override}
            $gate=Test-CustomAppFixtureCanaryExecutorPermitGateV010 -Name ([string]$ctx.name) -LifecycleRow $ctx.lifecycle -ProvenanceRow $ctx.provenance -BindingRow $ctx.binding -ProtocolQualification $ctx.protocol -Permit $ctx.permit -SessionKey ([byte[]]$ctx.session_key) -Now $now -ExpectedEligibilityFingerprint ([string]$ctx.eligibility_fingerprint) -Phase 'pre-apply'
            if(-not [bool]$gate.ok){return [pscustomobject]@{schema=1;transaction_id=[string]$Plan.transaction_id;status='denied-before-apply';committed=$false;rolled_back=$false;rollback_verified=$false;reason=[string]$gate.reason;mutation_mode='deny';production_mutation_authorized=$false}}
            $marker=Test-CustomAppFixtureCanaryConsumptionMarkerV010 -MarkerPath ([string]$ctx.marker_path) -TokenId ([string]$ctx.token_id) -EligibilityFingerprint ([string]$ctx.eligibility_fingerprint)
            if(-not [bool]$marker.ok){return [pscustomobject]@{schema=1;transaction_id=[string]$Plan.transaction_id;status='denied-before-apply';committed=$false;rolled_back=$false;rollback_verified=$false;reason=('pre-apply:'+[string]$marker.reason);mutation_mode='deny';production_mutation_authorized=$false}}
            if([string]$Plan.expected_remote_tree_sha256 -cne [string]$ctx.permit.remote_tree_sha256 -or [string]$Plan.expected_remote_commit_sha -cne [string]$ctx.permit.remote_commit_sha){return [pscustomobject]@{schema=1;transaction_id=[string]$Plan.transaction_id;status='denied-before-apply';committed=$false;rolled_back=$false;rollback_verified=$false;reason='pre-apply:transaction-plan-does-not-match-consumed-permit';mutation_mode='deny';production_mutation_authorized=$false}}
            return & $script:CustomAppFixtureCanaryExecutorOriginalTransactionV010 -Plan $Plan -ValidationRoot $ValidationRoot -PersistenceProof $PersistenceProof -InjectPostApplyFailure:$InjectPostApplyFailure -InjectRollbackFailure:$InjectRollbackFailure
        }
        $txOverridden=$true

        $shadow=Invoke-CustomAppShadowWithAcquiredStageV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $stage -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -PersistenceBackupRoot $PersistenceBackupRoot -InjectTransactionPostApplyFailure:$InjectTransactionPostApplyFailure -InjectPersistenceDriftAfterApply:$InjectPersistenceDriftAfterApply -PersistenceDriftTarget $PersistenceDriftTarget
        $stage=$null
        if([string]$shadow.status -eq 'committed-shadow-fixture' -and [bool]$shadow.committed){
            $out=New-CustomAppFixtureCanaryExecutorResultV010 -Name $Name -Status 'committed-fixture-canary' -Reason 'consumed-hmac-permit-and-fresh-preapply-gate-committed' -Committed $true -ShadowResult $shadow -NextConsumptionState $consumed.next_state -TokenId ([string]$consumed.token_id) -MarkerPath ([string]$consumed.marker_path) -EligibilityFingerprint $eligibilityFingerprint
            $out.fixture_canary_execution_authorized=$true
            return $out
        }
        return New-CustomAppFixtureCanaryExecutorResultV010 -Name $Name -Status 'denied-or-rolled-back-fixture-canary' -Reason ([string]$shadow.reason) -RolledBack ([bool]$shadow.rolled_back) -ShadowResult $shadow -NextConsumptionState $consumed.next_state -TokenId ([string]$consumed.token_id) -MarkerPath ([string]$consumed.marker_path) -EligibilityFingerprint $eligibilityFingerprint
    }catch{
        return New-CustomAppFixtureCanaryExecutorResultV010 -Name $Name -Status 'denied-or-failed-fixture-canary' -Reason ([string]$_.Exception.Message) -NextConsumptionState $consumed.next_state -TokenId ([string]$consumed.token_id) -MarkerPath ([string]$consumed.marker_path) -EligibilityFingerprint $eligibilityFingerprint
    }finally{
        if($txOverridden -and $null -ne $originalTx){try{Set-Item -LiteralPath 'Function:\Invoke-CustomAppUpdateFixtureTransactionV010' -Value $originalTx}catch{}}
        $script:CustomAppFixtureCanaryExecutorOriginalTransactionV010=$null;$script:CustomAppFixtureCanaryExecutorApplyContextV010=$null
        if($null -ne $stage -and $stage.PSObject.Properties['workspace_path']){try{Remove-CustomAppStageWorkspaceV010 -Path ([string]$stage.workspace_path)}catch{}}
        if($stageRootOverridden -and $null -ne $originalStageRoot){try{Set-Item -LiteralPath 'Function:\Get-CustomAppStageWorkspaceRootV010' -Value $originalStageRoot}catch{}}
        $script:CustomAppFixtureCanaryExecutorRootOverrideV010=$null
    }
}