"""Derive a real-vendor journaled success and commit test from the original
qualified HMAC Triple-ID / evidence-bound whole-tree source mutation fixture.

No fake apply result is imported or adapted. The original historical test
is pinned, used through its real candidate-live journal, and its fake tail is
replaced only in a generated throwaway CI test. The native result is NEW schema.
"""
from pathlib import Path
import subprocess, hashlib

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OLD=ROOT/"validation/custom-app-production-triple-id-journaled-forward-commit-v0.1.0/test_triple_id_journaled_forward_commit.ps1"
OUTPUT=OLD.parent/"ci_real_native_journaled_forward_generated.ps1"
PINS={
 OLD:"e19fbbf16eee5be3dc76cabe482f12a8132636fb",
 HERE/"native-journal-admission.ps1":"10a423e39eee0a2e176e3d5f65a496ac40961377",
 HERE/"native-journal-receipt.ps1":"09642bdef0d7cc82ed13489e18c3235fefb1bea3",
 HERE/"verify-native-receipt-fresh-process.ps1":"5f1e4a430dcbc4b410ec8325b418ad5b7e100df6",
 ROOT/"validation/custom-app-whole-tree-real-scoped-native/whole-tree-real-scoped-native.ps1":"c48c15aa6c342df0f6190c0cc8ea58c238c2bd08",
}
def once(src,old,new,label):
    n=src.count(old)
    if n!=1: raise RuntimeError(f"{label}: anchor count={n}")
    return src.replace(old,new,1)

def main():
    if OUTPUT.exists():raise RuntimeError("throwaway output already exists")
    for path,pin in PINS.items():
        sha=subprocess.check_output(["git","hash-object",str(path)],cwd=ROOT,text=True).strip()
        if sha!=pin:raise RuntimeError(f"qualified source drift {path.name}: {sha}")
    src=OLD.read_text(encoding="utf-8-sig")
    import_anchor=")){. (Join-Path $root $rel)}"
    new_import=import_anchor+"""
. (Join-Path $root 'validation/custom-app-whole-tree-real-scoped-native/whole-tree-real-scoped-native.ps1')
. (Join-Path $root 'validation/custom-app-real-native-journaled-forward-commit/native-journal-admission.ps1')
. (Join-Path $root 'validation/custom-app-real-native-journaled-forward-commit/native-journal-receipt.ps1')"""
    src=once(src,import_anchor,new_import,"genuine vendor + native proof modules")
    cutoff="$control=Join-Path $env:RUNNER_TEMP ('triple-id-journal-forward-fake-'"
    if src.count(cutoff)!=1:raise RuntimeError("qualified source fake-tail boundary not unique")
    head=src[:src.index(cutoff)]
    body=r"""
# Existing evidence-bound atomic has already durably transitioned PREPARED
# through CANDIDATE-LIVE. The source, backups, HMAC and current permit were
# all verified by the historical prefix with REAL ZIP bytes.
Assert-JF (-not[string]::IsNullOrWhiteSpace($env:V024_OFFICIAL_EXE)) 'official vendor source missing'
$stageResult=$script:PPBStageResult.stage_result
$now=$script:PPBAt.AddMilliseconds(650)
$finalFp=Hash-JF ((@('real-vendor-journaled-finalization','actual-third-id',
  $script:JFTx,[string]$atomic.result.result_fingerprint,
  [string]$p.preparation_fingerprint,[string]$preApplyJournalState.runtime.tree_sha256,
  [string]$preApplyJournalState.git.tree_sha256,
  [string]$preApplyJournalState.persistence.fingerprint,
  'old-live-retained-for-rollback') -join [Environment]::NewLine))
$proof=@{
 Name='tagify';LiveAppPath=[string]$script:TIDLive
 AllowedRoot=[string]$script:JFAllowed;JournalStoreDirectory=[string]$script:JFStore
 ConsumptionStoreDirectory=[string]$cf3.store
 ExpectedJournalTransactionId=[string]$script:JFTx
 ExpectedFinalizationFingerprint=[string]$finalFp
 ExpectedGitTreeSha256=[string]$script:BeforeGit.tree_sha256
 Permit=$script:PPBIssuer.permit;SessionKey=$script:DINPIKey
 PreparedResult=$p;StageExecutorResult=$stageResult
 EvidenceBoundAtomicResult=$atomic.result;LifecycleRow=$q.bundle.lifecycle
 ProvenanceRow=$q.bundle.provenance;BindingRow=$q.bundle.binding
 LocalAppDataRoot=[string]$script:PPBLocal
 AppDataRoot=[string]$script:PPBRoaming;Now=$now
}
$beforeDenied=Test-CustomAppRealNativeJournalAdmissionV024 -Proof $proof -ExpectedPhase 'transaction-finalized'
Assert-JF (-not[bool]$beforeDenied.ok) 'journal-native gate accepted before finalization barrier'
$jr=Append-JF 'candidate-live' 'transaction-finalized' $finalFp
$initial=Test-CustomAppRealNativeJournalAdmissionV024 -Proof $proof -ExpectedPhase 'transaction-finalized'
Assert-JF ([bool]$initial.ok -and [bool]$initial.signed_permit_and_whole_tree_bound -and
  -not[bool]$initial.production_mutation_authorized) ('qualified journal admission denied: '+[string]$initial.reason)
$bad=@{};foreach($k in $proof.Keys){$bad[$k]=$proof[$k]}
$bad.SessionKey=[byte[]](33..64)
$denied=Test-CustomAppRealNativeJournalAdmissionV024 -Proof $bad -ExpectedPhase 'transaction-finalized'
Assert-JF (-not[bool]$denied.ok -and -not[bool]$denied.production_mutation_authorized) 'wrong HMAC session key admitted'
$bad.SessionKey=$proof.SessionKey
$bad.ExpectedFinalizationFingerprint=('0'*64)
$denied=Test-CustomAppRealNativeJournalAdmissionV024 -Proof $bad -ExpectedPhase 'transaction-finalized'
Assert-JF (-not[bool]$denied.ok) 'wrong durable finalization anchor admitted'
Write-Host 'REAL_NATIVE_V024_WRONG_HMAC_AND_JOURNAL_ANCHOR_DENIED_PASS'
$private=Join-Path $env:RUNNER_TEMP 'V024Native'
$nativeArgs=@{
 Name='tagify';LiveAppPath=[string]$script:TIDLive
 StageExecutorResult=$stageResult;JournalProof=$proof
 Now=$now;OfficialExecutable=$env:V024_OFFICIAL_EXE
 ExpectedOfficialSha256='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
 PrivateNativeRoot=$private
}
$wrongOfficial=@{};foreach($k in $nativeArgs.Keys){$wrongOfficial[$k]=$nativeArgs[$k]}
$wrongOfficial.ExpectedOfficialSha256=('0'*64)
$denied=Invoke-CustomAppQualifiedWholeTreeScopedNativeV023 @wrongOfficial
Assert-JF (-not[bool]$denied.ok -and -not[bool]$denied.vendor_started -and
  -not(Test-Path $private)) 'wrong genuine executable SHA launched vendor or created private state'
# Persist the original V010 apply-starting barrier BEFORE the real vendor call.
$started=Append-JF 'transaction-finalized' 'apply-starting' $finalFp
$preflight=Test-CustomAppRealNativeJournalAdmissionV024 -Proof $proof -ExpectedPhase 'apply-starting'
Assert-JF ([bool]$preflight.ok) ('journal changed at prelaunch: '+[string]$preflight.reason)
$badProof=@{};foreach($k in $proof.Keys){$badProof[$k]=$proof[$k]}
$badProof.SessionKey=[byte[]](33..64)
$wrongArgs=@{};foreach($k in $nativeArgs.Keys){$wrongArgs[$k]=$nativeArgs[$k]}
$wrongArgs.JournalProof=$badProof
$denied=Invoke-CustomAppQualifiedWholeTreeScopedNativeV023 @wrongArgs
Assert-JF (-not[bool]$denied.ok -and -not[bool]$denied.vendor_started -and
  -not(Test-Path $private)) 'wrong signed HMAC launched genuine native vendor'
$vendor=Invoke-CustomAppQualifiedWholeTreeScopedNativeV023 @nativeArgs
Assert-JF ([bool]$vendor.ok -and [bool]$vendor.vendor_started -and
  [bool]$vendor.real_official_native_scoped_refresh_verified -and
  [bool]$vendor.signed_permit_and_whole_tree_bound -and
  [bool]$vendor.nontarget_unchanged -and [bool]$vendor.live_tree_unchanged -and
  -not[bool]$vendor.production_mutation_authorized -and
  [string]$vendor.journal_transaction_id -ceq $script:JFTx) (
    'real scoped upstream vendor execution failed: '+[string]$vendor.reason)
$pending=Append-JF 'apply-starting' 'apply-returned-success-pending-verification' $finalFp
$durable=Save-CustomAppRealNativeReceiptV024 -NativeResult $vendor -Proof $proof -StartedJournal $started -PendingJournal $pending
Assert-JF ([bool]$durable.ok -and
  [string]$durable.fingerprint -cmatch '^[a-f0-9]{64}$') 'durable real-vendor success fingerprint missing'
$wrongRead=Read-CustomAppRealNativeReceiptV024 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx -ExpectedApplyFingerprint ('0'*64) -RequireApplyVerified:$false
Assert-JF (-not[bool]$wrongRead.ok) 'incorrect genuine-vendor fingerprint accepted'
$verified=Append-JF 'apply-returned-success-pending-verification' 'apply-verified' $finalFp $durable.fingerprint
Assert-JF ([string]$verified.entry.apply_result_fingerprint -ceq [string]$durable.fingerprint) 'journal real-native verification not bound'
$read=Read-CustomAppRealNativeReceiptV024 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx -ExpectedApplyFingerprint $durable.fingerprint
Assert-JF ([bool]$read.ok) ('real native journal receipt readback denied: '+[string]$read.reason)
# Independently open only the immutable V010 journal, real result and scoped
# XPUI bytes. Absolutely no signing session key or permit is serialized.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'validation/custom-app-real-native-journaled-forward-commit/verify-native-receipt-fresh-process.ps1') -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx -ExpectedApplyFingerprint $durable.fingerprint
Assert-JF ($LASTEXITCODE -eq 0) ('independent real-vendor receipt checker exit '+$LASTEXITCODE)
Write-Host 'REAL_NATIVE_V024_HMAC_ZIP_WHOLE_TREE_OFFICIAL_SCOPED_APPLY_VERIFIED_PASS'
# RETAIN all backups until real native evidence has been recorded in durable
# journal. Never manufacture a legacy generic fake apply result for cleanup.
$jr=Append-JF 'apply-verified' 'cleanup-starting' $finalFp $durable.fingerprint
Assert-JF (Test-Path -LiteralPath ([string]$atomic.result.transaction_root) -PathType Container) 'cleanup barrier entered without transaction root'
$txn=[string]$atomic.result.transaction_root
Remove-CustomAppAtomicDirectoryV010 -Path $txn -ExpectedParent ([IO.Path]::GetDirectoryName($txn)) -ExpectedName ([IO.Path]::GetFileName($txn))
[void](Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$stageArtifact.path) -ExpectedRoot ([string]$stageArtifact.root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'isolated-stage')
[void](Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$appArtifact.path) -ExpectedRoot ([string]$appArtifact.root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'isolated-app-backup')
[void](Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$persistArtifact.path) -ExpectedRoot ([string]$persistArtifact.root) -ExpectedNamePattern '^txn-\d{8}-\d{6}-[0-9a-fA-F]{8}$' -Label 'isolated-persistence-backup')
foreach($p in @($txn,$stageArtifact.path,$appArtifact.path,$persistArtifact.path)){
    Assert-JF (-not(Test-Path -LiteralPath ([string]$p))) 'bounded cleanup left transaction artifact'
}
$committed=Snapshot-JF $false
$cleanupFp=Hash-JF ((@('real-vendor-authentic-commit-clean',$script:JFTx,
    [string]$finalFp,[string]$durable.fingerprint,
    [string]$committed.runtime.tree_sha256,[string]$committed.git.tree_sha256,
    [string]$committed.persistence.fingerprint) -join [Environment]::NewLine))
$terminal=Append-JF 'cleanup-starting' 'committed-clean' $finalFp $durable.fingerprint $cleanupFp
Assert-JF ([string]$terminal.entry.apply_result_fingerprint -ceq [string]$durable.fingerprint -and
    [string]$terminal.entry.cleanup_result_fingerprint -ceq $cleanupFp -and
    [int64]$terminal.revision -eq 9 -and [int]$terminal.history_count -eq 10) 'native terminal journal chain invalid'
$class=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead (Read-JF 'committed-clean') -ExpectedTransactionId $script:JFTx
Assert-JF ([bool]$class.ok -and [bool]$class.no_action -and
    [string]$class.classification -ceq 'no-action-new-permit-required-for-future-update') 'native committed-clean still requests rollback'
$receiptCheck=Read-CustomAppRealNativeReceiptV024 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx -ExpectedApplyFingerprint $durable.fingerprint
Assert-JF ([bool]$receiptCheck.ok) 'terminal real-vendor proof not independently readable'
$headBefore=[string](Read-JF 'committed-clean').entry.entry_sha256
$replayed=$false
try{[void](Append-JF 'candidate-live' 'transaction-finalized' $finalFp)}catch{$replayed=$true}
Assert-JF ($replayed -and [string](Read-JF 'committed-clean').entry.entry_sha256 -ceq $headBefore) 'terminal native journal replay mutated state'
# A user/output edit after commit must fail closed; do not restore or touch
# saved real source, and do not re-run the official vendor a second time.
$target=[string]$durable.receipt.private_target_path
$original=[IO.File]::ReadAllBytes($target)
try{
    [IO.File]::AppendAllText($target,'V024_POST_TERMINAL_UNAUTHORIZED_EDIT')
    $badRead=Read-CustomAppRealNativeReceiptV024 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx -ExpectedApplyFingerprint $durable.fingerprint
    Assert-JF (-not[bool]$badRead.ok) 'postterminal XPUI modification accepted as verified'
}finally{[IO.File]::WriteAllBytes($target,$original)}
Assert-JF ([bool](Read-CustomAppRealNativeReceiptV024 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx -ExpectedApplyFingerprint $durable.fingerprint).ok) 'original exact official output not restored in private fixture'
[void](Snapshot-JF $false)
Assert-JF ([string](Read-JF 'committed-clean').entry.entry_sha256 -ceq $headBefore) 'post-commit negative changed journal'
Write-Host 'REAL_NATIVE_V024_OFFICIAL_SCOPED_FORWARD_COMMITTED_CLEAN_PASS HMAC_ZIP=true whole_tree=true central_journal=true real_vendor_once=true fake_apply=false real_output_SHA_bound=true independent_no_key_receipt=true backups_deleted_only_after_verified=true terminal_replay_denied=true source_git_persistence_preserved=true operating_main_frozen=true'
"""
    out=head+body.strip()+"\n"
    if out.count('REAL_NATIVE_V024_OFFICIAL_SCOPED_FORWARD_COMMITTED_CLEAN_PASS')!=1:raise RuntimeError('final marker duplicated')
    OUTPUT.write_text(out,encoding="utf-8",newline="\n")
    print("REAL_NATIVE_V024_DERIVED_EVIDENCE_BOUND_JOURNAL_PASS",len(out.encode()),
          hashlib.sha256(out.encode()).hexdigest())

if __name__=="__main__":main()
