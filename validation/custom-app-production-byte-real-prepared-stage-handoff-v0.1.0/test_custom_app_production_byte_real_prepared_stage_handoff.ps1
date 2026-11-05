$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-dual-id-new-permit-executor-start-gate-v0.1.0/test_custom_app_production_dual_id_new_permit_executor_start_gate.ps1')
. (Join-Path $root 'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1')
. (Join-Path $root 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1')
. (Join-Path $root 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-byte-real-prepared-stage-handoff.ps1')

function Assert-BRH([bool]$ok,[string]$reason){if(-not$ok){throw $reason}}
function Assert-BRHDenied($x,[string]$label){
    Assert-BRH (-not[bool]$x.ok) ("$label unexpectedly accepted: "+[string]$x.reason)
    Assert-BRH (-not[bool]$x.ready_to_apply -and -not[bool]$x.production_mutation_authorized) "$label authority escaped"
}
function Copy-BRH($x){return ($x|ConvertTo-Json -Depth 100|ConvertFrom-Json)}

# Make a byte-real ZIP and validate/extract it BEFORE issuing any new permit.
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
$script:BRHWorkspace=New-CustomAppStageWorkspaceV010
$script:BRHZip=Join-Path $script:BRHWorkspace 'tagify-remote-v2.zip'
$script:BRHStage=Join-Path $script:BRHWorkspace 'candidate'
$fs=[IO.File]::Open($script:BRHZip,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$archive=New-Object IO.Compression.ZipArchive($fs,[IO.Compression.ZipArchiveMode]::Create,$false)
try{
    foreach($item in @(
      [pscustomobject]@{path='index.js';value="console.log('tagify-version-2')"},
      [pscustomobject]@{path='manifest.json';value='{"name":"tagify"}'},
      [pscustomobject]@{path='assets/check.txt';value='byte-real-prepared-new-permit'}
    )){
        $entry=$archive.CreateEntry([string]$item.path,[IO.Compression.CompressionLevel]::Optimal)
        $bytes=[Text.Encoding]::UTF8.GetBytes([string]$item.value)
        $writer=$entry.Open();try{$writer.Write($bytes,0,$bytes.Length)}finally{$writer.Dispose()}
    }
}finally{$archive.Dispose();$fs.Dispose()}
$script:BRHZipHash=(Get-FileHash -LiteralPath $script:BRHZip -Algorithm SHA256).Hash.ToLowerInvariant()
$e=Get-CustomAppObserverZipEvidence -ZipPath $script:BRHZip -WrapperMode auto
Assert-BRH ([bool]$e.manifest_valid -and [string]$e.manifest_name -ceq 'tagify') 'byte-real archive proof invalid'
$script:BRHExtract=Expand-CustomAppStageArchiveV010 -ZipPath $script:BRHZip -Destination $script:BRHStage -ValidationRoot $script:BRHWorkspace -WrapperMode auto -Name 'tagify' -ExpectedTreeSha256 ([string]$e.tree_sha256) -ExpectedManifestName 'tagify'
Assert-BRH ([string]$script:BRHExtract.tree_sha256 -ceq [string]$e.tree_sha256) 'archive/extract tree drift'

# Build one fresh synthetic historical-recovery fixture but bind its CURRENT
# new-cycle remote tree to these real extracted bytes before readiness/issuance.
$q=New-DINPFixtureV010 'real-archive'
$q.bundle=New-DINPPromotionBundleV010 -X $q.x -HousekeepingResult $q.house.result -At $q.at -RemoteTree ([string]$script:BRHExtract.tree_sha256)
# The signed remote release-asset binding must also pin the EXACT ZIP bytes.
$q.bundle.binding.binding.last_observed_asset_digest_sha256=$script:BRHZipHash
[void](Sync-PromotionBundleFingerprints -Bundle $q.bundle)
$script:BRHBundle=$q.bundle
$script:BRHAt=$q.at

function Invoke-BRH {
    param($Issuer=$null,$Start=$null,[byte[]]$Key=$null,$Lifecycle=$null,$Binding=$null,$StagePath=$null,$ArchiveHash=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue)
    if($null-eq$Lifecycle){$Lifecycle=$script:BRHBundle.lifecycle}
    if($null-eq$Binding){$Binding=$script:BRHBundle.binding}
    if([string]::IsNullOrWhiteSpace([string]$StagePath)){$StagePath=$script:BRHStage}
    if([string]::IsNullOrWhiteSpace([string]$ArchiveHash)){$ArchiveHash=$script:BRHZipHash}
    if($At-eq[DateTimeOffset]::MinValue){$At=$script:BRHAt}
    $args=@{Name='tagify';WorkspacePath=$script:BRHWorkspace;ArchivePath=$script:BRHZip;ArchiveSha256=$ArchiveHash;StagePath=$StagePath;ExtractedStageResult=$script:BRHExtract;LifecycleRow=$Lifecycle;BindingRow=$Binding;IssuerResult=$Issuer;ExecutorStartResult=$Start;SessionKey=$Key;Now=$At}
    return Test-CustomAppProductionByteRealPreparedStageHandoffV010 @args
}
$count=0
$pre=Invoke-BRH
Assert-BRH ([bool]$pre.ok -and [bool]$pre.byte_real_stage_attested) ('pre-permit ZIP denied: '+[string]$pre.reason)
Assert-BRH (-not[bool]$pre.new_permit_bound -and -not[bool]$pre.ready_to_apply) 'pre-permit stage became authority'
Assert-BRH ([string]$pre.stage_tree_sha256 -ceq [string]$q.bundle.binding.last_remote_tree_sha256) 'pre-stage remote SHA wrong'
$count++

$prior=Invoke-DINPV010 $q
Assert-BRH ([bool]$prior.ok) ('real-byte prior readiness denied: '+[string]$prior.reason)
$manifest=[string]$q.bundle.binding.binding.manifest_name
$live=New-AdmissionFixture -Name ([string]$q.bundle.lifecycle.name) -Source ([string]$q.bundle.provenance.source_identity) -Manifest $manifest
$live.lifecycle=$q.bundle.lifecycle;$live.provenance=$q.bundle.provenance;$live.binding=$q.bundle.binding
$live.baseline=[pscustomobject]@{safe=$true;installable=$true;tree_sha256=[string]$q.house.result.live_runtime_tree_sha256;manifest_name=$manifest;path=[string]$q.x.f.x.fixture.q.x.live}
$f=[pscustomobject]@{q=$q;prior=$prior.receipt;live=$live;new_id=(Get-DINPIANewTransactionId 'real-archive')}
$a=Invoke-DINPIAV010 -F $f
Assert-BRH ([bool]$a.ok) ('real-byte admission denied: '+[string]$a.reason)
$ic=[pscustomobject]@{f=$f;admission=$a.receipt}
$issued=Invoke-DINPIIssuerV010 -Q $ic
Assert-BRH ([bool]$issued.ok) ('real-byte issuer denied: '+[string]$issued.reason)
Assert-BRH ([string]$issued.receipt.current_remote_tree_sha256 -ceq [string]$script:BRHExtract.tree_sha256) 'issuer did not sign extracted byte tree'
$count++

$rc=[pscustomobject]@{i=$ic;issuer=$issued;state=(New-CustomAppProductionPermitReservationStateV010);at=$q.at.AddSeconds(1)}
$reserve=Invoke-DINPRV010 -Q $rc
Assert-BRH ([bool]$reserve.ok) ('real-byte reservation denied: '+[string]$reserve.reason)
$rs=Join-Path $q.x.f.trust ('real-archive-reservation-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $rs 'history'))|Out-Null
$rp=[pscustomobject]@{q=$rc;reservation=$reserve;store=$rs;at=$rc.at.AddMilliseconds(500)}
$durableReservation=Invoke-DINPPV010 -P $rp -ReservationResult $reserve -IssuerResult $issued
Assert-BRH ([bool]$durableReservation.ok) ('real-byte durable reservation denied: '+[string]$durableReservation.reason)
$consumed=Invoke-DINCV010 -P $rp -Persist $durableReservation -Issuer $issued -At $rp.at.AddMilliseconds(100)
Assert-BRH ([bool]$consumed.ok) ('real-byte one-time consumption denied: '+[string]$consumed.reason)
$cs=Join-Path $q.x.f.trust ('real-archive-consumption-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $cs 'history'))|Out-Null
$cf=[pscustomobject]@{p=$rp;candidate=$consumed;store=$cs;at=$rp.at.AddMilliseconds(200)}
$saved=Invoke-DNCPV010 -F $cf -Candidate $consumed -ReservationPersistence $durableReservation -Issuer $issued
Assert-BRH ([bool]$saved.ok) ('real-byte consumption persistence denied: '+[string]$saved.reason)
$now=$cf.at.AddMilliseconds(100)
$start=Invoke-TDSV010 -F $cf -Persistence $saved -Issuer $issued -Permit $issued.permit -Key $script:DINPIKey -At $now
Assert-BRH ([bool]$start.ok) ('signed real-byte start denied: '+[string]$start.reason)
Assert-BRH ([bool]$start.staging_eligible -and -not[bool]$start.production_mutation_authorized) 'signed start changed mutation authority'
$count++

$post=Invoke-BRH -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
Assert-BRH ([bool]$post.ok) ('same byte-real signed transaction denied: '+[string]$post.reason)
Assert-BRH ([bool]$post.new_permit_bound -and -not[bool]$post.ready_to_apply) 'signed handoff falsely granted apply'
Assert-BRH ([string]$post.consumption_id -ceq [string]$saved.receipt.consumption_id) 'consumption identity drift'
$count++

$bad=Invoke-BRH -Issuer $issued -Start $start -Key ([byte[]](33..64)) -At $now
Assert-BRHDenied $bad 'wrong ephemeral key'
$count++

$badIssuer=Copy-BRH $issued;$badIssuer.receipt.current_remote_tree_sha256=('0'*64)
$bad=Invoke-BRH -Issuer $badIssuer -Start $start -Key $script:DINPIKey -At $now
Assert-BRHDenied $bad 'issuer remote-tree transplant'
$count++

$badStart=Copy-BRH $start;$badStart.receipt.new_permit_transaction_id=('f'*64)
$badStart.receipt.start_fingerprint=Get-DualIdNewExecutorStartShaV010 (Get-DualIdNewExecutorStartMaterialV010 -Receipt $badStart.receipt)
$bad=Invoke-BRH -Issuer $issued -Start $badStart -Key $script:DINPIKey -At $now
Assert-BRHDenied $bad 'rehashed new-permit ID transplant'
$count++

$late=Invoke-BRH -Issuer $issued -Start $start -Key $script:DINPIKey -At $cf.at.AddSeconds(10)
Assert-BRHDenied $late 'expired staging eligibility'
$count++

$removed=Copy-BRH $q.bundle.lifecycle;$removed.user_removed=$true
$bad=Invoke-BRH -Lifecycle $removed -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
Assert-BRHDenied $bad 'user removed after new permit'
$count++

$binding=Copy-BRH $q.bundle.binding;$binding.auto_install_authorized=$true
$bad=Invoke-BRH -Binding $binding -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
Assert-BRHDenied $bad 'source auto-install authority escalated'
$count++

$digestBad=Copy-BRH $q.bundle.binding;$digestBad.binding.last_observed_asset_digest_sha256=('0'*64)
$bad=Invoke-BRH -Binding $digestBad -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
Assert-BRHDenied $bad 'frozen remote release asset digest changed'
$count++

$commitBad=Copy-BRH $q.bundle.binding;$commitBad.last_remote_commit_sha=('0'*40)
$bad=Invoke-BRH -Binding $commitBad -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
Assert-BRHDenied $bad 'remote commit changed after signing'
$count++

$bad=Invoke-BRH -StagePath ([IO.Path]::GetTempPath()) -At $now
Assert-BRHDenied $bad 'candidate path escaped sandbox'
$count++

$beforeZip=[IO.File]::ReadAllBytes($script:BRHZip)
try{
    [IO.File]::AppendAllText($script:BRHZip,'zip tamper')
    $bad=Invoke-BRH -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
    Assert-BRHDenied $bad 'ZIP changed after permit'
}finally{[IO.File]::WriteAllBytes($script:BRHZip,$beforeZip)}
$count++

$entry=Join-Path $script:BRHStage 'index.js';$beforeEntry=[IO.File]::ReadAllBytes($entry)
try{
    [IO.File]::AppendAllText($entry,'stage tamper')
    $bad=Invoke-BRH -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
    Assert-BRHDenied $bad 'stage bytes changed after permit'
}finally{[IO.File]::WriteAllBytes($entry,$beforeEntry)}
$count++

$git=Join-Path $script:BRHStage '.git'
try{
    [IO.Directory]::CreateDirectory($git)|Out-Null
    $bad=Invoke-BRH -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
    Assert-BRHDenied $bad 'injected VCS metadata'
}finally{if(Test-Path -LiteralPath $git){[IO.Directory]::Delete($git,$true)}}
$count++

$again=Invoke-BRH -Issuer $issued -Start $start -Key $script:DINPIKey -At $now
Assert-BRH ([bool]$again.ok) ('restored exact stage denied: '+[string]$again.reason)
Assert-BRH ([string]$again.stage_tree_sha256 -ceq [string]$post.stage_tree_sha256) 'read-only repeat stage SHA changed'
$count++

if($count-ne17){throw "byte-real prepared stage handoff case count $count expected 17"}
Write-Host "CUSTOM_APP_PRODUCTION_BYTE_REAL_PREPARED_STAGE_TRIPLE_ID_HANDOFF_PASS cases=$count actual_zip_before_permit=true same_hmac_permit_and_durable_consumption=true stage_tree_rechecked=true wrong_key_id_and_bytes_denied=true zero_authority=true"
