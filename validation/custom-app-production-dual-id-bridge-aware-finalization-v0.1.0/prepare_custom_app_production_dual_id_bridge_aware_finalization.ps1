param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$RunnerTemp
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

function Materialize-DBAFDependencyV011 {
    param([string]$Commit,[string]$Path,[string]$ExpectedBlob)
    git -C $RepoRoot cat-file -e "$Commit^{commit}" 2>$null
    if($LASTEXITCODE){git -C $RepoRoot fetch --no-tags origin $Commit | Out-Null;if($LASTEXITCODE){throw "dependency fetch failed $Commit"}}
    $out=Join-Path $RepoRoot $Path
    New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent)|Out-Null
    $spec="$Commit`:$Path"
    $env:DBAF_SRC=$spec;$env:DBAF_OUT=$out;$env:DBAF_REPO=$RepoRoot
    python -c "import os,subprocess,pathlib; pathlib.Path(os.environ['DBAF_OUT']).write_bytes(subprocess.check_output(['git','-C',os.environ['DBAF_REPO'],'cat-file','blob',os.environ['DBAF_SRC']]))"
    if($LASTEXITCODE){throw "dependency materialize failed $spec"}
    $actual=(git -C $RepoRoot hash-object $out).Trim()
    if($actual-cne$ExpectedBlob){throw "dependency blob drift $Path $actual != $ExpectedBlob"}
}

$deps=@(
  @('13f4314b81816b1b1c3bb3c2fb4280b6c015f8de','validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1','f8c91f5a566b24c82257742942bdc6fecfe68eb2'),
  @('13f4314b81816b1b1c3bb3c2fb4280b6c015f8de','validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1','83156d9c14e40061a0728d28b582c1e65684a4a2'),
  @('c420a1df6f306c7ba74772b91241cb14abd04738','validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1','e2f2fc656235883d2a82b106289973f6ded409a5'),
  @('57be1dcd10e339e9da2b8f15b9910a2ae1b79c1b','validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1','86c715370021cc1f09c46424172e2163ad56f236'),
  @('1a2461a6929e9cabd50d27f95e0744f83443b9e8','validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1','47b4d4bb08fe7b14ad43de4300556430eb638869'),
  @('7e26187e2360089024e9d72d0701be6f1577a1ef','validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1','a3df7e5d89c594083c10e240e13029ca5640b8ae'),
  @('993af44afee9adb0c28e5fb702cb6ccfbd7cd99c','validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1','910b1c500d33d6d6e0ad403c701f4c08f473f1a3'),
  @('b266bad660d4b7bc87e7093c5b12f0cff1dc466f','validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1','ae49409973164052d5830b981d804707f9d62b6c'),
  @('ffb5aad4a605691ee7b80392498b0cb6fa4e4052','validation/custom-app-production-recovery-preflight-v0.1.0/custom-app-production-recovery-preflight.ps1','b1816a24849a559b4da2537aa1b2436124fbee50'),
  @('ffb5aad4a605691ee7b80392498b0cb6fa4e4052','validation/custom-app-production-recovery-execution-admission-v0.1.0/custom-app-production-recovery-execution-admission.ps1','e8804a7c53ad0d3e5420e037d468d9c397e52529'),
  @('5232e5adeb13e6942acb210b3cd13058e1eaaf05','validation/custom-app-production-recovery-evidence-admission-integration-v0.1.0/custom-app-production-recovery-evidence-admission-integration.ps1','c92c727b5a2217f5b84a1072608bfc4662e68926'),
  @('d3969a746ed1736fe93586bd025116c2526fbff5','validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1','387d97b10d493b3794b24fba2bac67cf39491444'),
  @('d9a1face71511bdaeeef4e8c761415ef9ec95fc0','validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1','0273d7e28a56759b1d0ec9cbf037483b04d98d63'),
  @('574fe182168271fa3497d58e269e9af1f60d9033','validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1','e91fa6a125f77352907c1119f6d9f47be9682550'),
  @('e2b80822835bf5d59dc179e345e098b5bd79759e','validation/custom-app-production-atomic-live-swap-mutation-v0.1.0/custom-app-production-atomic-live-swap-mutation.ps1','394e7bda96501f9ac320ceabe96b4cf96661fe2d'),
  @('e2b80822835bf5d59dc179e345e098b5bd79759e','validation/custom-app-production-atomic-live-swap-mutation-v0.1.0/test_custom_app_production_atomic_live_swap_mutation.ps1','d15e0768162b0659c57602eaf0242b035b48b0c7'),
  @('fe07d410531ea13c8fca379b01405631a3763e84','validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1','f7372b069fbfe6a0f8d8a0aad45312ffd33d9f0a'),
  @('c3e1f960447ba84d2410af9c37a22a384f2a5436','validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1','5fec613c460619da5dbfe88fca5c7334e9e93f76'),
  @('11386815b91c71364fa7a67fabdc8c0386fbd982','validation/custom-app-production-recovery-restore-monotonic-time-v0.1.0/patch_recovery_restore_executor_monotonic_time.py','5d698f82aa60f56b1e90e4f5ad530a45879a31ab'),
  @('115411ed1a16f66a168443fb03b6e164fd114c0d','validation/custom-app-production-dual-transaction-id-bridge-v0.1.0/custom-app-production-dual-transaction-id-bridge.ps1','ce018db8c13d569036ca378bbe3b4a2a84ab3bcd'),
  @('234fef1e5c83395250ec97914579c55fee89cd21','validation/custom-app-production-dual-transaction-id-bridge-v0.1.0/test_custom_app_production_dual_transaction_id_bridge.ps1','1d0257aee38d0cc90d9a05d53caaf7c425bbcf96'),
  @('408e24ce7f66d1f5f23025a196b19cd8a42fcda7','validation/custom-app-production-durable-dual-transaction-id-bridge-integration-v0.1.0/custom-app-production-durable-dual-transaction-id-bridge-integration.ps1','c9a58a181d3c5f5a230fa895785c3a42a928c8cd'),
  @('9adc2d3f327a59349cb42fa17ad8d601a3b02197','validation/custom-app-production-evidence-bound-recovery-restart-v0.1.0/invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1','9c039860ff0645153205691a11e89d8eb844d43c'),
  @('63bf08db57bb0a1c2b75adc1eb65aa43352c34e6','validation/custom-app-production-lightweight-dual-id-restart-bridge-v0.1.0/test_custom_app_production_lightweight_dual_id_restart_bridge.ps1','af4b611855453991d7d0455f5fcc5a23c2e2c83e'),
  @('2c6fc111bc6cb9d7fb4b2cb54f0f660d756177cf','validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-mutation.ps1','79580da78443a18bd281d4fce61c4a57d958a196'),
  @('2c6fc111bc6cb9d7fb4b2cb54f0f660d756177cf','validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-repair-v011.ps1','210c4dda2311eb5defcbcd74977e4f4148ea7c38'),
  @('c21a8c72dd8920df8e1faa59eb6aedee76a15e06','validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/custom-app-production-evidence-bound-journal-atomic.ps1','55ca1e3c8d56b2e86a98d8b47e8ac1cc4ccbb6d0'),
  @('c21a8c72dd8920df8e1faa59eb6aedee76a15e06','validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1','dad1028758e3f03aebd86a84adc5c1d26a37bee3'),
  @('cb2e50b715a7d7f1bbc7b3b810104cefff7f7d50','validation/custom-app-production-recovery-aware-permit-atomic-live-swap-v0.1.0/custom-app-production-recovery-aware-permit-atomic-live-swap.ps1','e3506fd65de02978b4c79c1a367461b5496ae3b9'),
  @('0c32a30cf61dc9f3e61725d30d5df1df9a73ef56','validation/custom-app-production-recovery-aware-permit-transaction-finalization-v0.1.0/custom-app-production-recovery-aware-permit-transaction-finalization.ps1','9c725e47d432addac24fe4a6cd59e37af393b6c7')
)
foreach($d in $deps){Materialize-DBAFDependencyV011 -Commit $d[0] -Path $d[1] -ExpectedBlob $d[2]}

$restore=Join-Path $RepoRoot 'validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1'
$patcher=Join-Path $RepoRoot 'validation/custom-app-production-recovery-restore-monotonic-time-v0.1.0/patch_recovery_restore_executor_monotonic_time.py'
$patched=Join-Path $RunnerTemp 'dbaf-monotonic-restore.ps1'
python $patcher --source $restore --output $patched
if($LASTEXITCODE){throw 'monotonic recovery patch failed'}
$patchedSha=(Get-FileHash -LiteralPath $patched -Algorithm SHA256).Hash.ToLowerInvariant()
if($patchedSha-cne'1fa0f849682d4f8cbc37c35dc1474fc436a75ada064fa4912ae6951d4968aff3'){throw "patched recovery SHA drift $patchedSha"}
$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($patched,[ref]$tokens,[ref]$errors)
if($errors.Count){$errors|ForEach-Object{Write-Error $_};throw 'monotonic patched recovery PS5.1 parse failed'}
Copy-Item -LiteralPath $patched -Destination $restore -Force
Write-Output 'DUAL_ID_BRIDGE_AWARE_FINALIZATION_DEPENDENCIES_MONOTONIC_V012_PASS'
