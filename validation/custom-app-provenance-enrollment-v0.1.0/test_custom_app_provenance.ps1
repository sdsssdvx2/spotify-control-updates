param([string]$CorePath=(Join-Path $PSScriptRoot 'custom-app-provenance.ps1'))
$ErrorActionPreference='Stop'
. (Resolve-Path $CorePath)

function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-False([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual='$Actual' expected='$Expected'"}}

function New-AppFixture([string]$Root,[string]$Name){$p=Join-Path $Root $Name;New-Item -ItemType Directory -Force -Path $p|Out-Null;return $p}
function Set-GitOrigin([string]$App,[string]$Url){$g=Join-Path $App '.git';New-Item -ItemType Directory -Force -Path $g|Out-Null;@("[core]","    repositoryformatversion = 0","[remote \"origin\"]","    url = $Url","    fetch = +refs/heads/*:refs/remotes/origin/*")|Set-Content -LiteralPath (Join-Path $g 'config') -Encoding UTF8}
function Set-PackageRepo([string]$App,[string]$Url){$o=[ordered]@{name=(Split-Path -Leaf $App);version='1.0.0';repository=[ordered]@{type='git';url=$Url}};$o|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $App 'package.json') -Encoding UTF8}
function New-State([string]$Name,[string]$Path){$key='custom-app:'+$Name.ToLowerInvariant();$life=[pscustomobject]@{};$life|Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{managed_by='dynamic-spicetify-v1';kind='custom-app';name=$Name;present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($Path)});return [pscustomobject]@{lifecycle=$life}}
function Get-ProvRow($State,[string]$Name){$key='custom-app:'+$Name.ToLowerInvariant();return $State.custom_app_provenance.PSObject.Properties[$key].Value}

$root=Join-Path $env:TEMP ('custom-app-provenance-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root|Out-Null
try{
    foreach($case in @(
        @('https://github.com/Owner/Repo.git','owner/repo',$true),
        @('git+https://github.com/Owner/Repo.git','owner/repo',$true),
        @('ssh://git@github.com/Owner/Repo.git','owner/repo',$true),
        @('git@github.com:Owner/Repo.git','owner/repo',$true),
        @('git://github.com/Owner/Repo.git','owner/repo',$false),
        @('http://github.com/Owner/Repo.git','owner/repo',$false)
    )){$c=ConvertTo-GitHubRepositoryClaim ([string]$case[0]);Assert-True $c.ok "URL normalization failed: $($case[0])";Assert-Eq $c.identity $case[1] 'normalized repository identity mismatch';Assert-Eq ([bool]$c.secure) ([bool]$case[2]) 'secure transport classification mismatch'}
    foreach($bad in @('https://gitlab.com/a/b','https://github.com/a/b/tree/main','https://github.com/a/b?x=1','github:a/b','a/b','')){Assert-False (ConvertTo-GitHubRepositoryClaim $bad).ok "Unsafe/non-exact repository URL accepted: $bad"}

    $gitOnly=New-AppFixture $root 'git-only';Set-GitOrigin $gitOnly 'https://github.com/Example/App.git'
    $e=Get-CustomAppLocalProvenanceEvidence -Name 'git-only' -AppPath $gitOnly
    Assert-Eq $e.status 'proven-local-git-origin' 'secure git origin was not proven';Assert-Eq $e.source_candidate 'example/app' 'git origin source mismatch';Assert-True $e.source_proven 'secure git origin not marked proven';Assert-False $e.mutation_authorized 'proven source incorrectly gained mutation authority'

    $corroborated=New-AppFixture $root 'corroborated';Set-GitOrigin $corroborated 'git@github.com:Example/App.git';Set-PackageRepo $corroborated 'git+https://github.com/example/app.git'
    $e2=Get-CustomAppLocalProvenanceEvidence -Name 'corroborated' -AppPath $corroborated
    Assert-Eq $e2.status 'proven-local-git-origin-corroborated' 'matching package repository did not corroborate git origin';Assert-True $e2.source_proven 'corroborated source not proven'

    $packageOnly=New-AppFixture $root 'package-only';Set-PackageRepo $packageOnly 'https://github.com/Example/App.git'
    $e3=Get-CustomAppLocalProvenanceEvidence -Name 'package-only' -AppPath $packageOnly
    Assert-Eq $e3.status 'declared-package-only' 'package-only source classification mismatch';Assert-Eq $e3.source_candidate 'example/app' 'package-only candidate mismatch';Assert-False $e3.source_proven 'package-only declaration was incorrectly promoted to proven source'

    $conflict=New-AppFixture $root 'conflict';Set-GitOrigin $conflict 'https://github.com/example/app.git';Set-PackageRepo $conflict 'https://github.com/other/fork.git'
    $e4=Get-CustomAppLocalProvenanceEvidence -Name 'conflict' -AppPath $conflict
    Assert-Eq $e4.status 'conflicting-source-claims' 'conflicting source claims did not fail closed';Assert-False $e4.source_proven 'conflicting source claims were proven';Assert-True $e4.requires_reenrollment 'conflict did not require re-enrollment'

    $insecure=New-AppFixture $root 'insecure';Set-GitOrigin $insecure 'git://github.com/example/app.git'
    $e5=Get-CustomAppLocalProvenanceEvidence -Name 'insecure' -AppPath $insecure
    Assert-Eq $e5.status 'unsafe-or-inconclusive-evidence' 'insecure git origin did not fail closed';Assert-False $e5.source_proven 'insecure git origin was proven'

    $gitFile=New-AppFixture $root 'git-file';Set-Content -LiteralPath (Join-Path $gitFile '.git') -Value 'gitdir: C:\outside' -Encoding ASCII
    $e6=Get-CustomAppLocalProvenanceEvidence -Name 'git-file' -AppPath $gitFile
    Assert-Eq $e6.status 'unsafe-or-inconclusive-evidence' '.git file indirection was not denied';Assert-False $e6.source_proven '.git file indirection was proven'

    $badPackage=New-AppFixture $root 'bad-package';Set-Content -LiteralPath (Join-Path $badPackage 'package.json') -Value '{bad json' -Encoding UTF8
    $e7=Get-CustomAppLocalProvenanceEvidence -Name 'bad-package' -AppPath $badPackage
    Assert-Eq $e7.status 'unsafe-or-inconclusive-evidence' 'malformed package.json did not fail closed'

    $none=New-AppFixture $root 'unresolved';$e8=Get-CustomAppLocalProvenanceEvidence -Name 'unresolved' -AppPath $none
    Assert-Eq $e8.status 'unresolved' 'missing provenance did not remain unresolved';Assert-False $e8.source_proven 'missing provenance was proven'

    $abs=Get-CustomAppLocalProvenanceEvidence -Name 'missing' -AppPath (Join-Path $root 'does-not-exist')
    Assert-Eq $abs.status 'absent' 'absent app classification mismatch';Assert-False $abs.source_proven 'absent app was proven'

    $state=New-State 'git-only' $gitOnly
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $e -ObservedAt '2026-10-28T01:00:00+00:00'
    Assert-Eq $row.source_identity 'example/app' 'first strong provenance enrollment failed';Assert-Eq $row.last_proven_source 'example/app' 'historical proven source missing';Assert-False $row.requires_reenrollment 'fresh strong enrollment unexpectedly requires re-enrollment';Assert-False (Test-CustomAppProvenanceMutationAuthority $row) 'provenance enrollment expanded mutation authority'

    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $e -ObservedAt '2026-10-28T01:01:00+00:00'
    Assert-Eq $row.source_identity 'example/app' 'same-source observation broke enrollment';Assert-False $row.source_changed 'same source marked changed'

    $life=$state.lifecycle.PSObject.Properties['custom-app:git-only'].Value;$life.present=$false;$life.user_removed=$true
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $e -ObservedAt '2026-10-28T01:02:00+00:00'
    Assert-Eq $row.source_status 'user-removed' 'user removal did not tombstone active provenance';Assert-Eq $row.source_identity $null 'user-removed app retained active source identity';Assert-Eq $row.last_proven_source 'example/app' 'user removal destroyed historical provenance';Assert-False (Test-CustomAppProvenanceMutationAuthority $row) 'removed app gained mutation authority'

    $life.present=$true;$life.user_removed=$false
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $e -ObservedAt '2026-10-28T01:03:00+00:00'
    Assert-Eq $row.source_identity 'example/app' 'same-source explicit reinstall was not re-enrolled';Assert-False $row.requires_reenrollment 'same-source reinstall remained blocked'

    $swapped=New-AppFixture $root 'swapped';Set-GitOrigin $swapped 'https://github.com/other/fork.git';$swapEvidence=Get-CustomAppLocalProvenanceEvidence -Name 'git-only' -AppPath $swapped
    $life.locations=@($swapped)
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $swapEvidence -ObservedAt '2026-10-28T01:04:00+00:00'
    Assert-Eq $row.source_status 'source-change-blocked' 'source swap was not blocked';Assert-Eq $row.source_identity $null 'source swap retained active trusted identity';Assert-Eq $row.last_proven_source 'example/app' 'source swap overwrote historical trusted source';Assert-Eq $row.observed_source_candidate 'other/fork' 'source swap candidate not recorded';Assert-True $row.requires_reenrollment 'source swap did not require re-enrollment';Assert-True $row.source_changed 'source swap not marked changed';Assert-False (Test-CustomAppProvenanceMutationAuthority $row) 'source swap gained mutation authority'

    $life.ambiguous=$true;$life.safe_local_identity=$false;$life.locations=@($gitOnly,$swapped)
    $row=Update-CustomAppProvenanceEnrollment -State $state -Evidence $e -ObservedAt '2026-10-28T01:05:00+00:00'
    Assert-Eq $row.source_status 'unsafe-local-lifecycle' 'ambiguous lifecycle did not fail closed';Assert-Eq $row.source_identity $null 'ambiguous lifecycle retained active source identity'

    $stateMissing=[pscustomobject]@{lifecycle=[pscustomobject]@{}}
    $rowMissing=Update-CustomAppProvenanceEnrollment -State $stateMissing -Evidence $e -ObservedAt '2026-10-28T01:06:00+00:00'
    Assert-Eq $rowMissing.source_status 'lifecycle-missing-or-owner-mismatch' 'missing lifecycle did not fail closed';Assert-True $rowMissing.requires_reenrollment 'missing lifecycle did not require re-enrollment';Assert-False (Test-CustomAppProvenanceMutationAuthority $rowMissing) 'missing lifecycle gained mutation authority'

    $weakState=New-State 'package-only' $packageOnly
    $weakRow=Update-CustomAppProvenanceEnrollment -State $weakState -Evidence $e3 -ObservedAt '2026-10-28T01:07:00+00:00'
    Assert-Eq $weakRow.source_status 'declared-package-only' 'weak package-only evidence status drift';Assert-Eq $weakRow.source_identity $null 'package-only evidence became active source enrollment';Assert-False (Test-CustomAppProvenanceMutationAuthority $weakRow) 'package-only evidence gained mutation authority'

    Write-Host 'CUSTOM_APP_PROVENANCE_ACCEPTANCE_PASS cases=url-normalization,git-origin,corroboration,package-only,conflict,insecure,git-indirection,malformed-json,unresolved,absent,enroll,repeat,delete,reinstall,source-swap,ambiguous-lifecycle,missing-lifecycle,weak-ledger'
}finally{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
