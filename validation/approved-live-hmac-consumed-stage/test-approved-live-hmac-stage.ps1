# Targeted genuine source -> V029 HMAC -> durable one-time DPAPI receipt.
# Two provider families only: V027 has already covered all four real upstream
# full-tree official Spicetify refreshes, V028 has checked all four policy refs.
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
   throw 'V029_TARGETED_HMAC_TEST_REQUIRES_HOSTED_WINDOWS'
}
$env:TEMP=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
$env:TMP=$env:TEMP
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $root 'validation/v0.6.21/addon_policy_registry.ps1.inc'),[Text.Encoding]::UTF8)))
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $root 'validation/v0.6.22/addon_source_adapter_engine.ps1.inc'),[Text.Encoding]::UTF8)))
. (Join-Path $root 'validation/marketplace-source-topology-v0.1.0/marketplace-source-topology.ps1')
. (Join-Path $root 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1')
. (Join-Path $root 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1')
. (Join-Path $root 'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1')
. (Join-Path $root 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1')
. (Join-Path $root 'validation/custom-app-production-permit-v0.1.0/custom-app-production-permit.ps1')
. (Join-Path $root 'validation/approved-custom-app-native-scope/approved-scoped-native.ps1')
. (Join-Path $root 'validation/approved-live-source-acquisition/approved-live-source-acquisition.ps1')
. (Join-Path $PSScriptRoot 'approved-live-hmac-stage.ps1')
function Assert-V029([bool]$Okay,[string]$Text){
    if(-not$Okay){throw ('V029_APPROVED_REAL_STAGE_TEST_FAILED:'+ $Text)}
}
$items=@(
 [pscustomobject]@{name='better-local-files';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true},
 [pscustomobject]@{name='ivLyrics';kind='custom-app';policy='auto';source='ivLis-Studio/ivLyrics';installed=$true}
)
$store=Join-Path $env:RUNNER_TEMP ('v029-single-use-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($store)|Out-Null
$count=0
foreach($item in $items){
    $a=Invoke-ApprovedLiveSourceAcquireV028 -Item $item
    Assert-V029 ([bool]$a.ok -and -not[bool]$a.authenticated_hmac_permit -and
       -not[bool]$a.production_mutation_authorized) ('real V028 source not pending HMAC '+[string]$item.name)
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    $key=New-Object byte[] 32
    $nonceBytes=New-Object byte[] 16
    try{$rng.GetBytes($key);$rng.GetBytes($nonceBytes)}finally{$rng.Dispose()}
    $nonce=([BitConverter]::ToString($nonceBytes)).Replace('-','').ToLowerInvariant()
    $now=[DateTimeOffset]::UtcNow
    try{
        $token=New-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $a -SessionKey $key -Nonce $nonce -Now $now
        Assert-V029 ($token.managed_by -ceq 'approved-live-hmac-stage-v029' -and
           [string]$token.name -ceq [string]$item.name -and
           [string]$token.source_provenance_sha256 -ceq [string]$a.source_provenance_sha256 -and
           [string]$token.archive_sha256 -ceq [string]$a.archive_sha256 -and
           [string]$token.runtime_tree_sha256 -ceq [string]$a.runtime_tree_sha256 -and
           [string]$token.hmac_sha256 -cmatch '^[a-f0-9]{64}$' -and
           -not[bool]$token.production_execution_authorized) ('signed real source permit wrong '+[string]$item.name)
        $test=Test-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $a -Permit $token -SessionKey $key -Now $now
        Assert-V029 ([bool]$test.ok -and -not[bool]$test.production_mutation_authorized) ('valid real source HMAC not verified '+[string]$item.name)
        $bad=($token|ConvertTo-Json -Depth 8|ConvertFrom-Json)
        $bad.runtime_tree_sha256=('a'*64)
        $changed=Test-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $a -Permit $bad -SessionKey $key -Now $now
        Assert-V029 (-not[bool]$changed.ok) ('HMAC-authenticated tree field was alterable '+[string]$item.name)
        $expired=Test-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $a -Permit $token -SessionKey $key -Now ($now.AddMinutes(4))
        Assert-V029 (-not[bool]$expired.ok) ('expired permit accepted '+[string]$item.name)
        $stageIndex=Join-Path ([string]$a.stage_path) 'index.js'
        $beforeBytes=[IO.File]::ReadAllBytes($stageIndex)
        try{
            [IO.File]::AppendAllText($stageIndex,'V029_UNAUTHORIZED_STAGE_CHANGE')
            $stale=Test-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $a -Permit $token -SessionKey $key -Now $now
            Assert-V029 (-not[bool]$stale.ok) ('post-HMAC stage tamper accepted '+[string]$item.name)
        }finally{[IO.File]::WriteAllBytes($stageIndex,$beforeBytes)}
        $zipBytes=[IO.File]::ReadAllBytes([string]$a.archive_path)
        try{
            [IO.File]::AppendAllText([string]$a.archive_path,'V029_ARCHIVE_WRAPPER_TAMPER')
            $zipTamper=Test-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $a -Permit $token -SessionKey $key -Now $now
            Assert-V029 (-not[bool]$zipTamper.ok) ('post-HMAC ZIP tamper accepted '+[string]$item.name)
        }finally{[IO.File]::WriteAllBytes([string]$a.archive_path,$zipBytes)}
        $notInstalled=$item|Select-Object name,kind,policy,source,installed
        $notInstalled.installed=$false
        $removed=Test-ApprovedLiveHmacStagePermitV029 -Item $notInstalled -Acquired $a -Permit $token -SessionKey $key -Now $now
        Assert-V029 (-not[bool]$removed.ok) ('original removed after HMAC signed '+[string]$item.name)
        $fresh=Test-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $a -Permit $token -SessionKey $key -Now $now
        Assert-V029 ([bool]$fresh.ok) ('negative tests damaged otherwise-current real stage '+[string]$item.name)
        Write-Host ('V029_LIVE_APPROVED_UPSTREAM_WHOLE_ZIP_TREE_HMAC_AND_TAMPERS_PASS app='+[string]$item.name)
        $spent=Consume-ApprovedLiveHmacStageOnceV029 -Item $item -Acquired $a -Permit $token -SessionKey $key -ReceiptStore $store -Now $now
        Assert-V029 ([bool]$spent.ok -and [bool]$spent.single_use_consumed -and
          -not[bool]$spent.production_mutation_authorized -and
          [string]$spent.source_provenance_sha256 -ceq [string]$a.source_provenance_sha256) (
          'real source HMAC one-time claim failed '+[string]$item.name)
        $replayDenied=$false
        try{
           [void](Consume-ApprovedLiveHmacStageOnceV029 -Item $item -Acquired $a -Permit $token -SessionKey $key -ReceiptStore $store -Now $now)
        }catch [IO.IOException]{$replayDenied=$true}
        Assert-V029 $replayDenied ('same signed token replay was not rejected '+[string]$item.name)
        $wrong=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $store -TokenId ('0'*64)
        Assert-V029 (-not[bool]$wrong.ok) ('wrong receipt ID read '+[string]$item.name)
        $saved=[IO.File]::ReadAllBytes([string]$spent.receipt_path)
        try{
            $tamper=New-Object byte[] $saved.Length
            [Array]::Copy($saved,$tamper,$saved.Length)
            $tamper[5]=$tamper[5] -bxor 1
            [IO.File]::WriteAllBytes([string]$spent.receipt_path,$tamper)
            $denied=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $store -TokenId ([string]$token.token_id)
            Assert-V029 (-not[bool]$denied.ok) ('DPAPI envelope head tamper accepted '+[string]$item.name)
        }finally{[IO.File]::WriteAllBytes([string]$spent.receipt_path,$saved)}
        $worker=Join-Path $PSScriptRoot 'read-sealed-receipt-fresh-process.ps1'
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -Store $store -TokenId ([string]$token.token_id) -ExpectedTreeSha256 ([string]$a.runtime_tree_sha256)
        Assert-V029 ($LASTEXITCODE -eq 0) ('independent no-key consumption readback failed '+[string]$item.name)
        $receipt=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $store -TokenId ([string]$token.token_id)
        Assert-V029 ([bool]$receipt.ok -and [bool]$receipt.separate_journal_required -and
           -not[bool]$receipt.production_mutation_authorized) ('new process receipt omitted separate central journal requirement '+[string]$item.name)
        $count++
        Write-Host ('V029_APPROVED_LIVE_SOURCE_HMAC_ONCE_DPAPI_FRESH_PROCESS_PASS app='+[string]$item.name+' source='+[string]$a.source)
    }finally{
        [Array]::Clear($key,0,$key.Length)
        Remove-CustomAppStageWorkspaceV010 -Path ([string]$a.workspace_path)
    }
}
Assert-V029 ($count -eq 2) 'both remote acquisition provider types not validated'
Write-Host 'V029_TWO_REAL_UPSTREAM_SOURCE_TYPES_HMAC_SINGLE_USE_AND_FRESH_PROCESS_PASS'
Write-Host 'V029_TRUE_REAL_ZIP_NO_TAGIFY_AUTHORITY_NO_INSTALLED_SPOTIFY_OR_MUTATION_PASS'
