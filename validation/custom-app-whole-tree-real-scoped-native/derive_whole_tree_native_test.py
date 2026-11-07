"""Derive a one-shot hosted Windows actual CLI test from the qualified
real-ZIP Triple-ID whole-tree swap / fake-apply / committed-cleanup fixture.

The qualified historical fixture and all its HMAC/backup/mutation code remain
byte-for-byte unchanged; only a separate, disposable genuine native -a
refresh probe is inserted AFTER its verified swap and before existing cleanup.
"""
from pathlib import Path
import hashlib
import subprocess

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OLD=ROOT/"validation/custom-app-production-triple-id-apply-cleanup-e2e-v0.1.0/test_triple_id_apply_cleanup_e2e.ps1"
OLD_BLOB="0d36b5781574535fe3fea3b060b1d7c470d18f40"
MODULE=HERE/"whole-tree-real-scoped-native.ps1"
MODULE_BLOB="7eaa0ebed9495e8e8cefb085f3a5cb1dcf58b133"
OUTPUT=OLD.parent/"ci_real_scoped_native_after_triple_id_generated.ps1"

def once(s,old,new,label):
    n=s.count(old)
    if n!=1:raise RuntimeError(f"{label} requires unique source anchor: count={n}")
    return s.replace(old,new,1)

def pin(path,expected):
    actual=subprocess.check_output(["git","hash-object",str(path)],cwd=ROOT,text=True).strip()
    if actual!=expected:raise RuntimeError(f"qualified source blob changed: {path.name}")

def main():
    pin(OLD,OLD_BLOB);pin(MODULE,MODULE_BLOB)
    if OUTPUT.exists():raise RuntimeError("existing derived fixture cannot be overwritten")
    s=OLD.read_text(encoding="utf-8-sig")
    old_import=". (Join-Path $root 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup-finalization-receipt-v011.ps1')"
    s=once(s,old_import,old_import+
        "\n. (Join-Path $root 'validation/custom-app-whole-tree-real-scoped-native/whole-tree-real-scoped-native.ps1')",
        "import only tested scoped real vendor probe")
    anchor="Check-E2ENoAuthority $adm 'admission'"
    extra=r"""
# V023: the SAME real Triple-ID HMAC permit, same persistently consumed ID,
# same staged/atomically swapped WHOLE app tree (index, manifest, assets)
# is revalidated immediately before a REAL official Spicetify scoped refresh.
# Vendor is restricted to a separate private profile + disposable fake Spotify.
if([string]::IsNullOrWhiteSpace($env:V023_PINNED_EXE)){throw 'V023_OFFICIAL_BINARY_NOT_SUPPLIED'}
$v023native=Join-Path $env:RUNNER_TEMP 'V023Native'
$v023Args=@{
    Name='tagify';LiveAppPath=[string]$script:TIDLive
    StageExecutorResult=$script:PPBStageResult.stage_result
    PostSwapCommon=$script:E2ECommon;Now=$script:E2EAt
    OfficialExecutable=$env:V023_PINNED_EXE
    ExpectedOfficialSha256='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
    PrivateNativeRoot=$v023native
}
$wrongHash=@{};foreach($k in $v023Args.Keys){$wrongHash[$k]=$v023Args[$k]}
$wrongHash.ExpectedOfficialSha256=('0'*64)
$early=Invoke-CustomAppQualifiedWholeTreeScopedNativeV023 @wrongHash
Assert-E2E (-not[bool]$early.ok -and -not[bool]$early.vendor_started -and
    -not(Test-Path -LiteralPath $v023native)) 'official executable digest drift launched or mutated'
$wrongPermit=@{};foreach($k in $script:E2ECommon.Keys){$wrongPermit[$k]=$script:E2ECommon[$k]}
$wrongPermit.SessionKey=[byte[]](33..64)
$wrongPermitArgs=@{};foreach($k in $v023Args.Keys){$wrongPermitArgs[$k]=$v023Args[$k]}
$wrongPermitArgs.PostSwapCommon=$wrongPermit
$early=Invoke-CustomAppQualifiedWholeTreeScopedNativeV023 @wrongPermitArgs
Assert-E2E (-not[bool]$early.ok -and -not[bool]$early.vendor_started -and
    -not(Test-Path -LiteralPath $v023native)) 'wrong HMAC permit launched actual vendor'
$v023result=Invoke-CustomAppQualifiedWholeTreeScopedNativeV023 @v023Args
Assert-E2E ([bool]$v023result.ok -and
    [bool]$v023result.real_official_native_scoped_refresh_verified -and
    [bool]$v023result.signed_permit_and_whole_tree_bound -and
    [bool]$v023result.nontarget_unchanged -and
    [bool]$v023result.live_tree_unchanged -and
    -not[bool]$v023result.production_execution_authorized -and
    -not[bool]$v023result.production_mutation_authorized -and
    -not[bool]$v023result.commit_authorized) ('real upstream scoped native refresh rejected: '+[string]$v023result.reason)
Assert-E2E ([int]$v023result.full_tree_file_count -ge 3 -and
    [string]$v023result.source_tree_sha256 -ceq
      [string]$script:PPBStageResult.stage_result.remote_tree_sha256) 'real official CLI not bound to approved full-tree ZIP'
$afterOfficial=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $script:TIDLive
Assert-E2E ([string]$afterOfficial.tree_sha256 -ceq
    [string]$script:PPBStageResult.stage_result.remote_tree_sha256) 'genuine vendor process modified whole live app unexpectedly'
Write-Host 'TRIPLE_ID_V023_REAL_ZIP_HMAC_WHOLE_TREE_OFFICIAL_SCOPED_REFRESH_PASS'
"""
    s=once(s,anchor,anchor+"\n"+extra.strip("\n"),"real vendor after HMAC post-swap admission")
    for marker in ["TRIPLE_ID_REAL_ZIP_FAKE_APPLY_CLEANUP_E2E_PASS",
                   "TRIPLE_ID_V023_REAL_ZIP_HMAC_WHOLE_TREE_OFFICIAL_SCOPED_REFRESH_PASS"]:
        if s.count(marker)!=1:raise RuntimeError("result marker count drift: "+marker)
    OUTPUT.write_text(s,encoding="utf-8",newline="\n")
    print("V023_DERIVED_TRIPLE_ID_REAL_OFFICIAL_NATIVE_TEST_PASS",
          "bytes",OUTPUT.stat().st_size,
          "sha256",hashlib.sha256(s.encode()).hexdigest())

if __name__=="__main__":main()
