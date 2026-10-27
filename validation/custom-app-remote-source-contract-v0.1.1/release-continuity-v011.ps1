$CustomAppRemoteSourceContractAmendmentSchema = 1

function Copy-CustomAppRemoteBindingV011 {
    param([Parameter(Mandatory=$true)]$Binding)
    $copy=[pscustomobject]@{}
    foreach($p in @($Binding.PSObject.Properties)){
        $copy|Add-Member -NotePropertyName ([string]$p.Name) -NotePropertyValue $p.Value
    }
    return $copy
}

function New-CustomAppRemoteReleaseDecisionV011 {
    param([string]$Status,[string]$Reason,[bool]$SourceIdentityVerified,[bool]$RepoIdVerified,[bool]$SurfaceVerified,[bool]$LocalContinuityVerified,[bool]$UpdateObserved,[bool]$EnrollmentCandidate,[bool]$RequiresReenrollment,$BindingCandidate,[AllowNull()][string]$RemoteTreeSha256)
    return New-CustomAppRemoteSourceDecision $true $false $Status $Reason $SourceIdentityVerified $RepoIdVerified $SurfaceVerified $LocalContinuityVerified $UpdateObserved $EnrollmentCandidate $RequiresReenrollment $BindingCandidate $RemoteTreeSha256
}

function Resolve-CustomAppRemoteSourceContractV011 {
    param(
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$RemoteObservation,
        [AllowNull()]$Binding,
        [Parameter(Mandatory=$true)][string]$CurrentLocalTreeSha256,
        [Parameter(Mandatory=$true)][string]$CurrentLocalManifestName
    )

    $surface=([string]$RemoteObservation.surface_kind).Trim().ToLowerInvariant()
    if($surface -cne 'release-asset'){
        return Resolve-CustomAppRemoteSourceContract -ProvenanceRow $ProvenanceRow -RemoteObservation $RemoteObservation -Binding $Binding -CurrentLocalTreeSha256 $CurrentLocalTreeSha256 -CurrentLocalManifestName $CurrentLocalManifestName
    }

    try{$zipCount=[int]$RemoteObservation.release_zip_asset_count}catch{$zipCount=-1}
    if($zipCount -ne 1){
        return New-CustomAppRemoteReleaseDecisionV011 'release-asset-selection-denied' 'release-zip-asset-not-unique' $false $false $false $false $false $false $true $null $null
    }

    if($null -eq $Binding){
        $base=Resolve-CustomAppRemoteSourceContract -ProvenanceRow $ProvenanceRow -RemoteObservation $RemoteObservation -Binding $null -CurrentLocalTreeSha256 $CurrentLocalTreeSha256 -CurrentLocalManifestName $CurrentLocalManifestName
        if([bool]$base.enrollment_candidate -and $null -ne $base.binding_candidate){
            $candidate=Copy-CustomAppRemoteBindingV011 -Binding $base.binding_candidate
            $candidate|Add-Member -NotePropertyName 'release_asset_selector' -NotePropertyValue 'unique-zip-asset' -Force
            $candidate|Add-Member -NotePropertyName 'initial_asset_name' -NotePropertyValue ([string]$RemoteObservation.asset_name) -Force
            $candidate|Add-Member -NotePropertyName 'last_observed_asset_name' -NotePropertyValue ([string]$RemoteObservation.asset_name) -Force
            $base.binding_candidate=$candidate
        }
        return $base
    }

    if([string]$Binding.surface_kind -ceq 'release-asset'){
        if([string]$Binding.release_asset_selector -cne 'unique-zip-asset'){
            return New-CustomAppRemoteReleaseDecisionV011 'binding-denied' 'release-asset-selector-missing-or-unsupported' $true $false $true $false $false $false $true $null ([string]$RemoteObservation.tree_sha256)
        }
        $compat=Copy-CustomAppRemoteBindingV011 -Binding $Binding
        $previousName=[string]$Binding.asset_name
        $compat.asset_name=[string]$RemoteObservation.asset_name
        $base=Resolve-CustomAppRemoteSourceContract -ProvenanceRow $ProvenanceRow -RemoteObservation $RemoteObservation -Binding $compat -CurrentLocalTreeSha256 $CurrentLocalTreeSha256 -CurrentLocalManifestName $CurrentLocalManifestName
        $base|Add-Member -NotePropertyName 'release_asset_selector' -NotePropertyValue 'unique-zip-asset' -Force
        $base|Add-Member -NotePropertyName 'release_asset_name_changed' -NotePropertyValue ($previousName -cne [string]$RemoteObservation.asset_name) -Force
        $base|Add-Member -NotePropertyName 'previous_asset_name' -NotePropertyValue $previousName -Force
        $base|Add-Member -NotePropertyName 'observed_asset_name' -NotePropertyValue ([string]$RemoteObservation.asset_name) -Force
        return $base
    }

    return Resolve-CustomAppRemoteSourceContract -ProvenanceRow $ProvenanceRow -RemoteObservation $RemoteObservation -Binding $Binding -CurrentLocalTreeSha256 $CurrentLocalTreeSha256 -CurrentLocalManifestName $CurrentLocalManifestName
}

function Test-CustomAppRemoteSourceMutationAuthorityV011 {
    param([Parameter(Mandatory=$true)]$Decision)
    return Test-CustomAppRemoteSourceMutationAuthority -Decision $Decision
}
