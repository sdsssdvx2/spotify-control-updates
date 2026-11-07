"""Derive one hosted Windows test from the historical HMAC real-ZIP fixture.

Do not modify its pinned input or synthesize/forge an approval receipt:
the existing qualified test produces actual issuer, one-time consumption store,
physical readback and current-start HMAC proof. Only the candidate payload is
restricted from 3 files to the V020 single-index supported subset.
"""
from __future__ import annotations
from pathlib import Path
import hashlib, subprocess

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OLD=ROOT/"validation/custom-app-production-byte-real-prepared-stage-handoff-v0.1.0/test_custom_app_production_byte_real_prepared_stage_handoff.ps1"
OLD_BLOB="8534c47d13ba07a2933ce6e1cc4cd16e70dae538"
MODULE=HERE/"scoped-signed-stage-admission.ps1"
MODULE_BLOB="bb0c03f32eac496ad37e512f069ab0644de90712"
OUTPUT=OLD.parent/"ci_scoped_signed_stage_bridge_generated.ps1"

def one(s, old, new, title):
    count=s.count(old)
    if count!=1: raise RuntimeError(f"{title}: expected unique insertion, got {count}")
    return s.replace(old,new,1)

def pin(p, expected):
    actual=subprocess.check_output(["git","hash-object",str(p)],cwd=ROOT,text=True).strip()
    if actual!=expected:raise RuntimeError(f"qualified source pin mismatch: {p.name}")

def main():
    pin(OLD,OLD_BLOB)
    pin(MODULE,MODULE_BLOB)
    if OUTPUT.exists():raise RuntimeError("generated test already exists; refuse replacement")
    src=OLD.read_text(encoding="utf-8-sig")
    # This is not an approval shortcut: the qualified test builds a new real
    # archive and creates a fresh source-bound issuer, store and start permit.
    src=one(src,
        """      [pscustomobject]@{path='manifest.json';value='{"name":"tagify"}'},
      [pscustomobject]@{path='assets/check.txt';value='byte-real-prepared-new-permit'}""",
        """      [pscustomobject]@{path='manifest.json';value='{"name":"tagify"}'}""",
        "prepare exact two-file source ZIP")
    old_import=". (Join-Path $PSScriptRoot 'custom-app-production-byte-real-prepared-stage-handoff.ps1')"
    new_import=old_import+"\n. (Join-Path $root 'validation/custom-app-scoped-signed-stage-native-admission/scoped-signed-stage-admission.ps1')"
    src=one(src,old_import,new_import,"import read-only native source bridge")
    anchor="Assert-BRH ([string]$post.consumption_id -ceq [string]$saved.receipt.consumption_id) 'consumption identity drift'"
    tests=r"""
# Only the REAL signed ZIP+HMAC permit+persisted consumption may yield this
# native candidate; it does not approve installation or accept extra assets.
$stageArgs=@{
    Name='tagify';WorkspacePath=$script:BRHWorkspace
    ArchivePath=$script:BRHZip;ArchiveSha256=$script:BRHZipHash
    StagePath=$script:BRHStage;ExtractedStageResult=$script:BRHExtract
    LifecycleRow=$script:BRHBundle.lifecycle;BindingRow=$script:BRHBundle.binding
    IssuerResult=$issued;ExecutorStartResult=$start;SessionKey=$script:DINPIKey
    AllowedRoot=$script:BRHAllowedRoot
    ConsumptionStoreDirectory=$script:BRHConsumptionStore
    Now=$now
}
$nativeCandidate=Resolve-CustomAppScopedSignedStageCandidateV021 @stageArgs
Assert-BRH ([bool]$nativeCandidate.ok -and
    [bool]$nativeCandidate.authenticated_stage_and_permit_verified -and
    [bool]$nativeCandidate.single_index_subset_qualified -and
    -not[bool]$nativeCandidate.ready_to_apply -and
    -not[bool]$nativeCandidate.production_mutation_authorized) (
      'real-byte HMAC native candidate read-only bind denied: '+[string]$nativeCandidate.reason)
$actualIndex=Join-Path $script:BRHStage 'index.js'
Assert-BRH ([string]$nativeCandidate.candidate_index_path -ceq $actualIndex -and
    [string]$nativeCandidate.candidate_index_sha256 -ceq
      (Get-FileHash -LiteralPath $actualIndex -Algorithm SHA256).Hash.ToLowerInvariant() -and
    [string]$nativeCandidate.stage_tree_sha256 -ceq
      [string]$script:BRHExtract.tree_sha256) 'native candidate exact staged index/tree not bound'
$originalCandidateBytes=[IO.File]::ReadAllBytes($actualIndex)
Assert-BRH ([bool]$nativeCandidate.candidate_is_immutable_snapshot -and
    -not [string]::IsNullOrWhiteSpace([string]$nativeCandidate.candidate_index_bytes_base64)) 'native snapshot payload missing'
Assert-BRH ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$nativeCandidate.candidate_index_bytes_base64)) -ceq
    [Text.Encoding]::UTF8.GetString($originalCandidateBytes)) 'native captured bytes did not match HMAC-bound source'
$nativeSnapshot=[string]$nativeCandidate.candidate_index_bytes_base64
try{
    [IO.File]::AppendAllText($actualIndex,'NATIVE_STAGE_POST_SNAPSHOT_TAMPER')
    $badNative=Resolve-CustomAppScopedSignedStageCandidateV021 @stageArgs
    Assert-BRH (-not[bool]$badNative.ok -and -not[bool]$badNative.production_mutation_authorized) 'candidate stage changed after initial read was admitted'
    Assert-BRH ([string]$nativeCandidate.candidate_index_bytes_base64 -ceq $nativeSnapshot) 'immutable captured source changed after stage mutation'
}finally{[IO.File]::WriteAllBytes($actualIndex,$originalCandidateBytes)}
Write-Host 'SIGNED_STAGE_NATIVE_V021_PREPARED_SOURCE_BYTES_SNAPSHOT_TAMPER_DENIED_PASS'
Write-Host 'SIGNED_STAGE_NATIVE_V021_REAL_ZIP_HMAC_CONSUMPTION_INDEX_BIND_PASS'
$stageArgs.SessionKey=[byte[]](33..64)
$badNative=Resolve-CustomAppScopedSignedStageCandidateV021 @stageArgs
Assert-BRH (-not[bool]$badNative.ok -and -not[bool]$badNative.production_mutation_authorized) 'wrong HMAC key admitted native candidate'
$stageArgs.SessionKey=$script:DINPIKey
$stageArgs.Name='unowned'
$badNative=Resolve-CustomAppScopedSignedStageCandidateV021 @stageArgs
Assert-BRH (-not[bool]$badNative.ok) 'different app identity admitted native candidate'
$stageArgs.Name='tagify'
$third=Join-Path $script:BRHStage 'style.css'
try{
    [IO.File]::WriteAllText($third,'UNAPPROVED_EXTRA_ASSET')
    $badNative=Resolve-CustomAppScopedSignedStageCandidateV021 @stageArgs
    Assert-BRH (-not[bool]$badNative.ok -and -not[bool]$badNative.production_mutation_authorized) 'unbound extra style admitted'
}finally{if([IO.File]::Exists($third)){[IO.File]::Delete($third)}}
$stageArgs.ArchiveSha256=('0'*64)
$badNative=Resolve-CustomAppScopedSignedStageCandidateV021 @stageArgs
Assert-BRH (-not[bool]$badNative.ok) 'archive SHA drift admitted'
$stageArgs.ArchiveSha256=$script:BRHZipHash
$nativeAgain=Resolve-CustomAppScopedSignedStageCandidateV021 @stageArgs
Assert-BRH ([bool]$nativeAgain.ok -and
    [string]$nativeAgain.candidate_index_sha256 -ceq [string]$nativeCandidate.candidate_index_sha256) 'native source stable HMAC readback failed'
Write-Host 'SIGNED_STAGE_NATIVE_V021_MUTATION_FREE_NEGATIVES_PASS wrong_key=true wrong_app=true extra_asset=true wrong_zip_sha=true'
"""
    src=one(src,anchor,anchor+"\n"+tests.strip("\n"),"bind actual stage into scoped V021")
    for marker in ("CUSTOM_APP_PRODUCTION_BYTE_REAL_PREPARED_STAGE_TRIPLE_ID_HANDOFF_PASS",
                   "SIGNED_STAGE_NATIVE_V021_REAL_ZIP_HMAC_CONSUMPTION_INDEX_BIND_PASS",
                   "SIGNED_STAGE_NATIVE_V021_MUTATION_FREE_NEGATIVES_PASS"):
        if src.count(marker)!=1:raise RuntimeError(f"marker count incorrect: {marker}")
    OUTPUT.write_text(src,encoding="utf-8",newline="\n")
    print("SIGNED_STAGE_NATIVE_V021_DERIVED_REAL_HMAC_FIXTURE_PASS",
          "bytes",OUTPUT.stat().st_size,"sha256",hashlib.sha256(src.encode()).hexdigest())

if __name__=="__main__":main()
