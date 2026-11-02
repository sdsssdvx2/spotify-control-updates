param(
    [Parameter(Mandatory=$true)][string]$ExpectedHead
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$repo=(git rev-parse --show-toplevel).Trim()
$head=(git rev-parse HEAD).Trim()
if($head -cne $ExpectedHead){throw "head mismatch $head != $ExpectedHead"}

$integrationRel='validation/custom-app-production-durable-dual-transaction-id-bridge-integration-v0.1.0/test_custom_app_production_durable_dual_transaction_id_bridge_integration.ps1'
$regressionRel='validation/custom-app-production-durable-dual-transaction-id-bridge-integration-v0.1.0/test_custom_app_production_dual_transaction_id_bridge_regression_v011.ps1'
$work=Join-Path $env:RUNNER_TEMP ('ddib-v011-'+[Guid]::NewGuid().ToString('N'))
$oldHelper=$env:SC_VALIDATION_HELPER_ONLY

function Assert-DDIBRunnerBlobV011 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Expected)
    $actual=(git -C $Root hash-object $Path 2>$null).Trim()
    if($LASTEXITCODE -or $actual -cne $Expected){throw "blob drift $Path $actual != $Expected"}
}

function Materialize-DDIBRunnerPathV011 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$Path,[AllowNull()][string]$ExpectedBlob=$null)
    git -C $Root checkout $Commit -- $Path
    if($LASTEXITCODE){throw "materialization failed $Commit $Path"}
    if(-not [string]::IsNullOrWhiteSpace($ExpectedBlob)){Assert-DDIBRunnerBlobV011 -Root $Root -Path $Path -Expected $ExpectedBlob}
}

function Enable-DDIBRunnerHelperOnlyV011 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string[]]$ExcludedRelativePaths)
    $excluded=@{}
    foreach($r in $ExcludedRelativePaths){$excluded[[IO.Path]::GetFullPath((Join-Path $Root $r))]=$true}
    $guard="`r`nif (`$env:SC_VALIDATION_HELPER_ONLY -ceq '1') { return }`r`n"
    $patched=New-Object System.Collections.Generic.List[string]
    $files=Get-ChildItem -LiteralPath (Join-Path $Root 'validation') -Recurse -File -Filter 'test_*.ps1'
    foreach($file in $files){
        $full=[IO.Path]::GetFullPath($file.FullName)
        if($excluded.ContainsKey($full)){continue}
        $raw=[IO.File]::ReadAllText($full)
        if($raw.IndexOf('SC_VALIDATION_HELPER_ONLY',[StringComparison]::Ordinal)-ge0){continue}
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw "helper-only parse failed before patch $full"}
        $functions=@($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })
        if($functions.Count -eq 0){continue}
        $last=$functions | Sort-Object {$_.Extent.EndOffset} | Select-Object -Last 1
        $offset=[int]$last.Extent.EndOffset
        if($offset -le 0 -or $offset -ge $raw.Length){continue}
        $updated=$raw.Insert($offset,$guard)
        $tokens2=$null;$errors2=$null
        [void][Management.Automation.Language.Parser]::ParseInput($updated,[ref]$tokens2,[ref]$errors2)
        if($errors2.Count){throw "helper-only parse failed after patch $full"}
        [IO.File]::WriteAllText($full,$updated,[Text.UTF8Encoding]::new($false))
        [void]$patched.Add($full)
    }
    $required=@(
        'validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0/test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1',
        'validation/custom-app-production-evidence-bound-recovery-restore-integration-v0.1.0/test_custom_app_production_evidence_bound_recovery_restore_integration.ps1'
    )
    foreach($r in $required){
        $p=[IO.Path]::GetFullPath((Join-Path $Root $r))
        if($p -notin $patched){throw "required parent harness was not helper-only patched: $r"}
    }
    return @($patched)
}

try {
    git worktree add --detach $work $ExpectedHead
    if($LASTEXITCODE){throw 'worktree add failed'}

    $materializeDirs=@(
        @('993af44afee9adb0c28e5fb702cb6ccfbd7cd99c','validation/custom-app-production-recovery-evidence-envelope-v0.1.0'),
        @('57be1dcd10e339e9da2b8f15b9910a2ae1b79c1b','validation/marketplace-lifecycle-settings-core-v0.1.0'),
        @('1a2461a6929e9cabd50d27f95e0744f83443b9e8','validation/custom-app-update-transaction-protocol-v0.1.0'),
        @('7e26187e2360089024e9d72d0701be6f1577a1ef','validation/custom-app-production-crash-recovery-journal-v0.1.0'),
        @('e2b80822835bf5d59dc179e345e098b5bd79759e','validation/custom-app-production-atomic-live-swap-mutation-v0.1.0'),
        @('2c6fc111bc6cb9d7fb4b2cb54f0f660d756177cf','validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0'),
        @('c21a8c72dd8920df8e1faa59eb6aedee76a15e06','validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0'),
        @('c549230acb222bd8132bea22912af5853f316785','validation/custom-app-production-evidence-bound-recovery-restore-integration-v0.1.0')
    )
    foreach($q in $materializeDirs){Materialize-DDIBRunnerPathV011 -Root $work -Commit $q[0] -Path $q[1]}

    $siblings=@(
        @('ddc84778ab4815d4174198727b8d1d052a02182e','validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1','9b039819e7b2278fe4cf15c8585336dd07a8e8e3'),
        @('6ba560e7980c3492fb032ebc720f029caa97b15c','validation/custom-app-production-stage-executor-v0.1.0/custom-app-production-stage-executor.ps1','349d4028997a9cc7a94540286c8b9ba6d6a5b050'),
        @('29fe26f505d2f0fb8d9f47e76b5b819ebe1c129d','validation/custom-app-production-executor-start-gate-v0.1.0/custom-app-production-executor-start-gate.ps1','1fa3ca9e77b4c8a48ef56afd656fd102e1636676'),
        @('29fe26f505d2f0fb8d9f47e76b5b819ebe1c129d','validation/custom-app-production-executor-start-gate-v0.1.0/test_custom_app_production_executor_start_gate.ps1','f63b309beacd2a8f822f6f8c2801c7bb68409c35'),
        @('1401103431e5a647002aef48394dc599c2db421f','validation/custom-app-production-recovery-aware-new-permit-readiness-v0.1.0/custom-app-production-recovery-aware-new-permit-readiness.ps1','0c73b5352c7b9bd29472d3a145a4fc4333d0574b'),
        @('1401103431e5a647002aef48394dc599c2db421f','validation/custom-app-production-recovery-aware-new-permit-readiness-v0.1.0/test_custom_app_production_recovery_aware_new_permit_readiness.ps1','ac323f3b465475bf97b655344d989abe62731d48'),
        @('6bc69d2c8b12d074fa68f3d2ed7688e0846cd23c','validation/custom-app-production-promotion-gate-v0.1.0/custom-app-production-promotion-gate.ps1','1164c197405eac2295f789256e2886068611dd94'),
        @('6bc69d2c8b12d074fa68f3d2ed7688e0846cd23c','validation/custom-app-production-promotion-gate-v0.1.0/test_custom_app_production_promotion_gate.ps1','80b27015fa05951fe2c0f706eb60d212dac17d24'),
        @('b53bcf39f715f1c35c7d1f99e157cdecb0a2a572','validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1','f8c91f5a566b24c82257742942bdc6fecfe68eb2'),
        @('c420a1df6f306c7ba74772b91241cb14abd04738','validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1','e2f2fc656235883d2a82b106289973f6ded409a5'),
        @('6d0e964307aaf0c0a8aeece98d5597e81721538e','validation/custom-app-production-recovery-completion-evidence-v0.1.0/custom-app-production-recovery-completion-evidence.ps1','3795f900cbf8ded834f721f7db7b126aa264b0e8'),
        @('6d0e964307aaf0c0a8aeece98d5597e81721538e','validation/custom-app-production-recovery-completion-evidence-v0.1.0/test_custom_app_production_recovery_completion_evidence.ps1','1451ce0aeb046fe36a1660b12647534b514cd738'),
        @('6d0e964307aaf0c0a8aeece98d5597e81721538e','validation/custom-app-production-recovery-completion-evidence-v0.1.0/probe_custom_app_production_recovery_completion_evidence.ps1','8abbcb7eded67420d2e2b6e8bed3f9636ae9833d'),
        @('993af44afee9adb0c28e5fb702cb6ccfbd7cd99c','validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1','910b1c500d33d6d6e0ad403c701f4c08f473f1a3'),
        @('993af44afee9adb0c28e5fb702cb6ccfbd7cd99c','validation/custom-app-production-recovery-evidence-envelope-v0.1.0/test_custom_app_production_recovery_evidence.ps1','de37d029e175dbec899445dbe983e506a14a1b0a'),
        @('993af44afee9adb0c28e5fb702cb6ccfbd7cd99c','validation/custom-app-production-recovery-evidence-envelope-v0.1.0/probe_custom_app_production_recovery_evidence.ps1','84f73605526373652a4499b7f472537c8e2b5c03'),
        @('57be1dcd10e339e9da2b8f15b9910a2ae1b79c1b','validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1','86c715370021cc1f09c46424172e2163ad56f236'),
        @('1a2461a6929e9cabd50d27f95e0744f83443b9e8','validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1','47b4d4bb08fe7b14ad43de4300556430eb638869'),
        @('7e26187e2360089024e9d72d0701be6f1577a1ef','validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1','a3df7e5d89c594083c10e240e13029ca5640b8ae')
    )
    foreach($q in $siblings){Materialize-DDIBRunnerPathV011 -Root $work -Commit $q[0] -Path $q[1] -ExpectedBlob $q[2]}

    $pins=@(
        @('validation/custom-app-production-durable-dual-transaction-id-bridge-integration-v0.1.0/custom-app-production-durable-dual-transaction-id-bridge-integration.ps1','c9a58a181d3c5f5a230fa895785c3a42a928c8cd'),
        @($integrationRel,'445c73bdd27f376a1d280b56070998bfdb203516'),
        @($regressionRel,'722cafc907fa4bca5568646c0995b9dc78f31279'),
        @('validation/custom-app-production-dual-transaction-id-bridge-v0.1.0/custom-app-production-dual-transaction-id-bridge.ps1','ce018db8c13d569036ca378bbe3b4a2a84ab3bcd'),
        @('validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0/custom-app-production-recovery-aware-permit-pre-apply-preparation.ps1','eaad8a5f161f831bbbada1c1c0957a3dfc80edaa'),
        @('validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0/test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1','62fee2fc47c900ccf2eaec96bdb920727f3c5690'),
        @('validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/custom-app-production-evidence-bound-journal-atomic.ps1','55ca1e3c8d56b2e86a98d8b47e8ac1cc4ccbb6d0'),
        @('validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1','0273d7e28a56759b1d0ec9cbf037483b04d98d63'),
        @('validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1','5fec613c460619da5dbfe88fca5c7334e9e93f76')
    )
    foreach($q in $pins){Assert-DDIBRunnerBlobV011 -Root $work -Path $q[0] -Expected $q[1]}

    $temp=Join-Path $env:RUNNER_TEMP ('ddib-v011-runtime-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($temp)|Out-Null
    $env:TEMP=$temp;$env:TMP=$temp

    $regOut=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $work $regressionRel) 2>&1)
    $regOut | ForEach-Object { Write-Output $_ }
    if($LASTEXITCODE){throw 'canonical dual-id 16-case regression failed'}
    if(($regOut -join "`n").IndexOf('CUSTOM_APP_PRODUCTION_DUAL_TRANSACTION_ID_BRIDGE_REGRESSION_V011_PASS total=16 evidence_drift_distinct=true',[StringComparison]::Ordinal)-lt0){throw 'canonical regression pass marker missing'}

    $patched=@(Enable-DDIBRunnerHelperOnlyV011 -Root $work -ExcludedRelativePaths @($integrationRel,$regressionRel))
    if($patched.Count -lt 2){throw "helper-only patch coverage too small: $($patched.Count)"}
    $env:SC_VALIDATION_HELPER_ONLY='1'
    $intOut=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $work $integrationRel) 2>&1)
    $intOut | ForEach-Object { Write-Output $_ }
    if($LASTEXITCODE){throw 'durable dual-id helper-only integration failed'}
    if(($intOut -join "`n").IndexOf('CUSTOM_APP_PRODUCTION_DURABLE_DUAL_TRANSACTION_ID_BRIDGE_INTEGRATION_PASS cases=8 separate_process_recovery=true',[StringComparison]::Ordinal)-lt0){throw 'durable dual-id integration pass marker missing'}

    $evidence=[ordered]@{
        schema=1
        expected_head=$ExpectedHead
        source_integration_head='408e24ce7f66d1f5f23025a196b19cd8a42fcda7'
        source_integration_test_blob='445c73bdd27f376a1d280b56070998bfdb203516'
        canonical_bridge_regression_cases=16
        byte_real_integration_cases=8
        helper_only_parent_harnesses=$patched.Count
        parent_matrix_reexecution=$false
        separate_process_recovery=$true
        production_code_changed=$false
        launcher_or_shortcut_changed=$false
    }
    $evidence|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'ci-runtime-evidence.json') -Encoding UTF8
    Write-Output "CUSTOM_APP_PRODUCTION_DURABLE_DUAL_TRANSACTION_ID_BRIDGE_INTEGRATION_V011_PASS cases=8 helper_only_parent_harnesses=$($patched.Count)"
}
finally {
    $env:SC_VALIDATION_HELPER_ONLY=$oldHelper
    if(Test-Path -LiteralPath $work){git worktree remove --force $work 2>$null}
}
