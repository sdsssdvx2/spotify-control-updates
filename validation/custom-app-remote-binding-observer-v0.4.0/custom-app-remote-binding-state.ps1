$CustomAppRemoteBindingStateSchema = 1

function Copy-CustomAppRemoteBindingObjectV040 {
    param([AllowNull()]$InputObject)
    if($null -eq $InputObject){return $null}
    $copy=[pscustomobject]@{}
    foreach($p in @($InputObject.PSObject.Properties)){$copy|Add-Member -NotePropertyName ([string]$p.Name) -NotePropertyValue $p.Value -Force}
    return $copy
}

function Ensure-CustomAppRemoteBindingState {
    param([Parameter(Mandatory=$true)]$State)
    $State=Normalize-AddonStateObject $State
    [void](Ensure-ObjectNoteProperty -Object $State -Name 'custom_app_remote_sources' -DefaultValue ([pscustomobject]@{}))
    if($null -eq $State.custom_app_remote_sources){$State.custom_app_remote_sources=[pscustomobject]@{}}
    return $State
}

function Get-CustomAppRemoteBindingKeyV040 {
    param([Parameter(Mandatory=$true)][string]$Name)
    if([string]::IsNullOrWhiteSpace($Name)){throw 'Remote binding app name cannot be empty.'}
    return 'custom-app:'+($Name.Trim().ToLowerInvariant())
}

function Ensure-CustomAppRemoteBindingRowV040 {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)][string]$Name)
    $State=Ensure-CustomAppRemoteBindingState $State
    $key=Get-CustomAppRemoteBindingKeyV040 $Name
    if(-not $State.custom_app_remote_sources.PSObject.Properties[$key]){$State.custom_app_remote_sources|Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{})}
    $row=$State.custom_app_remote_sources.PSObject.Properties[$key].Value
    if($null -eq $row){$row=[pscustomobject]@{};$State.custom_app_remote_sources.PSObject.Properties[$key].Value=$row}
    foreach($entry in @(
        @('schema',$CustomAppRemoteBindingStateSchema),@('key',$key),@('managed_by','custom-app-remote-binding-observer-v1'),@('name',$Name),
        @('active',$false),@('source_identity',$null),@('binding',$null),@('first_bound_at',$null),@('last_attempt',$null),@('last_success',$null),
        @('last_status','unobserved'),@('last_reason','not-yet-observed'),@('last_error',$null),@('last_local_tree_sha256',$null),@('last_local_manifest_name',$null),
        @('last_remote_tree_sha256',$null),@('last_remote_commit_sha',$null),@('update_observed',$false),@('requires_reenrollment',$false),
        @('user_removed',$false),@('mutation_mode','deny'),@('auto_update_authorized',$false),@('auto_install_authorized',$false)
    )){[void](Ensure-ObjectNoteProperty -Object $row -Name ([string]$entry[0]) -DefaultValue $entry[1])}
    $row.schema=$CustomAppRemoteBindingStateSchema;$row.key=$key;$row.managed_by='custom-app-remote-binding-observer-v1';$row.name=$Name
    $row.mutation_mode='deny';$row.auto_update_authorized=$false;$row.auto_install_authorized=$false
    return $row
}

function Test-CustomAppRemoteBindingMutationAuthorityV040 {
    param([Parameter(Mandatory=$true)]$Row)
    return ([string]$Row.mutation_mode -cne 'deny' -or [bool]$Row.auto_update_authorized -or [bool]$Row.auto_install_authorized)
}

function Test-CustomAppRemoteObservationDueV040 {
    param([AllowNull()]$Row,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MinimumIntervalHours=24)
    if($MinimumIntervalHours -lt 1 -or $MinimumIntervalHours -gt 168){throw 'Remote observation interval must be between 1 and 168 hours.'}
    if($null -eq $Row -or [string]::IsNullOrWhiteSpace([string]$Row.last_attempt)){return $true}
    $last=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Row.last_attempt,[ref]$last)){return $true}
    return ($Now -ge $last.AddHours($MinimumIntervalHours))
}

function Test-CustomAppRemoteBindingEligibilityV040 {
    param([AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow)
    if($null -eq $LifecycleRow){return [pscustomobject]@{ok=$false;reason='lifecycle-missing';user_removed=$true;source=$null;path=$null}}
    if([string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or [string]$LifecycleRow.kind -cne 'custom-app'){return [pscustomobject]@{ok=$false;reason='lifecycle-owner-or-kind-mismatch';user_removed=$false;source=$null;path=$null}}
    if(-not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed){return [pscustomobject]@{ok=$false;reason='user-removed-or-absent';user_removed=$true;source=$null;path=$null}}
    if([bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$LifecycleRow.locations[0])){return [pscustomobject]@{ok=$false;reason='local-lifecycle-unsafe-or-ambiguous';user_removed=$false;source=$null;path=$null}}
    if($null -eq $ProvenanceRow){return [pscustomobject]@{ok=$false;reason='provenance-missing';user_removed=$false;source=$null;path=[string]$LifecycleRow.locations[0]}}
    $prov=Test-CustomAppRemoteProvenanceRow -Row $ProvenanceRow
    if(-not [bool]$prov.ok){return [pscustomobject]@{ok=$false;reason=('provenance-denied:'+[string]$prov.reason);user_removed=$false;source=$null;path=[string]$LifecycleRow.locations[0]}}
    return [pscustomobject]@{ok=$true;reason='eligible';user_removed=$false;source=[string]$prov.source;path=[string]$LifecycleRow.locations[0]}
}

function Set-CustomAppRemoteBindingInactiveV040 {
    param([Parameter(Mandatory=$true)]$Row,[Parameter(Mandatory=$true)][string]$Status,[Parameter(Mandatory=$true)][string]$Reason,[bool]$RequiresReenrollment=$true,[bool]$UserRemoved=$false,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    $Row.active=$false;$Row.last_attempt=$ObservedAt;$Row.last_status=$Status;$Row.last_reason=$Reason;$Row.last_error=$null
    $Row.update_observed=$false;$Row.requires_reenrollment=$RequiresReenrollment;$Row.user_removed=$UserRemoved
    $Row.mutation_mode='deny';$Row.auto_update_authorized=$false;$Row.auto_install_authorized=$false
    if(Test-CustomAppRemoteBindingMutationAuthorityV040 $Row){throw 'Inactive remote binding row gained mutation authority.'}
    return $Row
}

function Set-CustomAppRemoteBindingObservationFailureV040 {
    param([Parameter(Mandatory=$true)]$Row,[Parameter(Mandatory=$true)][string]$ErrorText,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    $wasActive=[bool]$Row.active;$bindingBefore=$Row.binding;$sourceBefore=$Row.source_identity
    $Row.last_attempt=$ObservedAt;$Row.last_status='remote-observation-failed';$Row.last_reason='network-or-remote-observer-failure';$Row.last_error=$ErrorText;$Row.update_observed=$false
    $Row.active=$wasActive;$Row.binding=$bindingBefore;$Row.source_identity=$sourceBefore
    $Row.mutation_mode='deny';$Row.auto_update_authorized=$false;$Row.auto_install_authorized=$false
    if(Test-CustomAppRemoteBindingMutationAuthorityV040 $Row){throw 'Remote observation failure granted mutation authority.'}
    return $Row
}

function Copy-CustomAppRemoteBindingCandidateForStateV040 {
    param([Parameter(Mandatory=$true)]$Binding,[Parameter(Mandatory=$true)]$RemoteObservation)
    $copy=Copy-CustomAppRemoteBindingObjectV040 $Binding
    if([string]$copy.surface_kind -ceq 'release-asset'){
        $copy|Add-Member -NotePropertyName 'asset_name' -NotePropertyValue ([string]$RemoteObservation.asset_name) -Force
        if($RemoteObservation.PSObject.Properties['asset_id']){$copy|Add-Member -NotePropertyName 'last_observed_asset_id' -NotePropertyValue ([int64]$RemoteObservation.asset_id) -Force}
        if($RemoteObservation.PSObject.Properties['asset_digest_sha256']){$copy|Add-Member -NotePropertyName 'last_observed_asset_digest_sha256' -NotePropertyValue ([string]$RemoteObservation.asset_digest_sha256) -Force}
    }
    $copy|Add-Member -NotePropertyName 'last_verified_remote_tree_sha256' -NotePropertyValue ([string]$RemoteObservation.tree_sha256) -Force
    $copy|Add-Member -NotePropertyName 'last_verified_commit_sha' -NotePropertyValue ([string]$RemoteObservation.commit_sha) -Force
    $copy.mutation_mode='deny';$copy.auto_update_authorized=$false;$copy.auto_install_authorized=$false
    return $copy
}

function Update-CustomAppRemoteBindingFromObservationSetV040 {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$LocalBaseline,
        [Parameter(Mandatory=$true)]$ObservationSet,
        [string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o'))
    )
    $row=Ensure-CustomAppRemoteBindingRowV040 -State $State -Name $Name
    $elig=Test-CustomAppRemoteBindingEligibilityV040 -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow
    if(-not [bool]$elig.ok){
        return Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status 'eligibility-denied' -Reason ([string]$elig.reason) -RequiresReenrollment (-not [bool]$elig.user_removed) -UserRemoved ([bool]$elig.user_removed) -ObservedAt $ObservedAt
    }
    if($null -eq $LocalBaseline -or -not [bool]$LocalBaseline.safe -or -not [bool]$LocalBaseline.installable -or -not (Test-CustomAppRemoteSha256 ([string]$LocalBaseline.tree_sha256)) -or [string]::IsNullOrWhiteSpace([string]$LocalBaseline.manifest_name)){
        return Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status 'local-baseline-denied' -Reason 'local-runtime-not-safe-installable-or-identifiable' -RequiresReenrollment $true -ObservedAt $ObservedAt
    }
    if([string]$ObservationSet.source_identity -cne [string]$elig.source){return Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status 'remote-source-mismatch' -Reason 'observation-set-source-does-not-match-provenance' -RequiresReenrollment $true -ObservedAt $ObservedAt}
    if([bool]$ObservationSet.mutation_authorized -or [bool]$ObservationSet.auto_update_authorized -or [bool]$ObservationSet.auto_install_authorized){throw 'Remote observation set unexpectedly grants authority.'}
    $observations=@($ObservationSet.observations);$errors=@($ObservationSet.errors)
    $row.last_attempt=$ObservedAt;$row.last_local_tree_sha256=[string]$LocalBaseline.tree_sha256;$row.last_local_manifest_name=[string]$LocalBaseline.manifest_name;$row.user_removed=$false

    $binding=$(if($row.active -and $null -ne $row.binding){$row.binding}else{$null})
    if($null -ne $binding){
        if([string]$binding.source_identity -cne [string]$elig.source){return Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status 'binding-source-mismatch' -Reason 'active-binding-source-no-longer-matches-provenance' -RequiresReenrollment $true -ObservedAt $ObservedAt}
        if($observations.Count -eq 0){$msg=$(if($errors.Count){(@($errors|ForEach-Object{([string]$_.surface)+':'+([string]$_.error)}) -join '; ')}else{'no-bound-surface-observation'});return Set-CustomAppRemoteBindingObservationFailureV040 -Row $row -ErrorText $msg -ObservedAt $ObservedAt}
        if($observations.Count -ne 1){return Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status 'bound-surface-ambiguous' -Reason 'expected-exactly-one-bound-surface-observation' -RequiresReenrollment $true -ObservedAt $ObservedAt}
        $obs=$observations[0]
        $decision=Resolve-CustomAppRemoteSourceContractV011 -ProvenanceRow $ProvenanceRow -RemoteObservation $obs -Binding $binding -CurrentLocalTreeSha256 ([string]$LocalBaseline.tree_sha256) -CurrentLocalManifestName ([string]$LocalBaseline.manifest_name)
        if(Test-CustomAppRemoteSourceMutationAuthorityV011 $decision){throw 'Remote binding decision unexpectedly grants mutation authority.'}
        if(-not [bool]$decision.conclusive -or [bool]$decision.requires_reenrollment){return Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status ([string]$decision.status) -Reason ([string]$decision.reason) -RequiresReenrollment $true -ObservedAt $ObservedAt}
        $row.binding=Copy-CustomAppRemoteBindingCandidateForStateV040 -Binding $binding -RemoteObservation $obs
        $row.active=$true;$row.source_identity=[string]$elig.source;$row.last_success=$ObservedAt;$row.last_status=[string]$decision.status;$row.last_reason=[string]$decision.reason;$row.last_error=$null
        $row.last_remote_tree_sha256=[string]$decision.remote_tree_sha256;$row.last_remote_commit_sha=[string]$obs.commit_sha;$row.update_observed=[bool]$decision.update_observed;$row.requires_reenrollment=$false
        if(Test-CustomAppRemoteBindingMutationAuthorityV040 $row){throw 'Verified remote binding row gained mutation authority.'}
        return $row
    }

    if($observations.Count -eq 0){$msg=$(if($errors.Count){(@($errors|ForEach-Object{([string]$_.surface)+':'+([string]$_.error)}) -join '; ')}else{'no-remote-observation'});return Set-CustomAppRemoteBindingObservationFailureV040 -Row $row -ErrorText $msg -ObservedAt $ObservedAt}
    $candidates=New-Object System.Collections.Generic.List[object]
    $denials=New-Object System.Collections.Generic.List[string]
    foreach($obs in $observations){
        $decision=Resolve-CustomAppRemoteSourceContractV011 -ProvenanceRow $ProvenanceRow -RemoteObservation $obs -Binding $null -CurrentLocalTreeSha256 ([string]$LocalBaseline.tree_sha256) -CurrentLocalManifestName ([string]$LocalBaseline.manifest_name)
        if(Test-CustomAppRemoteSourceMutationAuthorityV011 $decision){throw 'Enrollment decision unexpectedly grants mutation authority.'}
        if([bool]$decision.enrollment_candidate -and $null -ne $decision.binding_candidate){$candidates.Add([pscustomobject]@{decision=$decision;observation=$obs})}
        else{$denials.Add(([string]$decision.status)+':'+([string]$decision.reason))}
    }
    if($candidates.Count -ne 1){
        if($candidates.Count -gt 1){$reason='multiple-safe-remote-binding-candidates';$status='binding-ambiguous'}
        elseif($denials.Count){$reason=($denials -join '; ');$status='binding-not-enrolled'}
        else{$reason='no-safe-remote-binding-candidate';$status='binding-not-enrolled'}
        return Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status $status -Reason $reason -RequiresReenrollment $false -ObservedAt $ObservedAt
    }
    $chosen=$candidates[0];$decision=$chosen.decision;$obs=$chosen.observation
    $row.binding=Copy-CustomAppRemoteBindingCandidateForStateV040 -Binding $decision.binding_candidate -RemoteObservation $obs
    $row.active=$true;$row.source_identity=[string]$elig.source;if(-not $row.first_bound_at){$row.first_bound_at=$ObservedAt};$row.last_success=$ObservedAt
    $row.last_status='binding-enrolled';$row.last_reason=[string]$decision.reason;$row.last_error=$null;$row.last_remote_tree_sha256=[string]$decision.remote_tree_sha256;$row.last_remote_commit_sha=[string]$obs.commit_sha
    $row.update_observed=$false;$row.requires_reenrollment=$false;$row.user_removed=$false
    if(Test-CustomAppRemoteBindingMutationAuthorityV040 $row){throw 'Enrolled remote binding row gained mutation authority.'}
    return $row
}

function Update-CustomAppRemoteBindingEligibilityOnlyV040 {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    $row=Ensure-CustomAppRemoteBindingRowV040 -State $State -Name $Name
    $elig=Test-CustomAppRemoteBindingEligibilityV040 -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow
    if([bool]$elig.ok){return $row}
    return Set-CustomAppRemoteBindingInactiveV040 -Row $row -Status 'eligibility-denied' -Reason ([string]$elig.reason) -RequiresReenrollment (-not [bool]$elig.user_removed) -UserRemoved ([bool]$elig.user_removed) -ObservedAt $ObservedAt
}

function Assert-CustomAppRemoteBindingStateDeniedV040 {
    param([Parameter(Mandatory=$true)]$State)
    $State=Ensure-CustomAppRemoteBindingState $State
    foreach($p in @($State.custom_app_remote_sources.PSObject.Properties)){if(Test-CustomAppRemoteBindingMutationAuthorityV040 $p.Value){throw "Remote binding state authority drift: $($p.Name)"}}
    return $true
}
