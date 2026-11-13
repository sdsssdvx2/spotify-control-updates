"""R135 HOLD: exact-owner v2.46.7 one-attempt grant with durable no-replay claim.

Explicit invocation in R135 product is the *only* authorization. R134
post-adoption default hold remains active for AgentTick, Maintain, and all
subsequent calls even after a successful upgrade. Never automatically retry.
"""
from __future__ import annotations
from pathlib import Path
import hashlib

BASE=Path(__file__).resolve().parent
SOURCE=BASE/"out/owner-postadoption-default-hold-R134/spotify-control.ps1"
OUT=BASE/"out/owner-v2467-one-approved-attempt-R135/spotify-control.ps1"
PARENT="99e1bc36667400fa8fc7a5464ec20d3b4e84ee648e979c746c18d9848b0f47fa"
HELPERS=r"""
function Get-R135OwnerAttemptPath {
    return (Join-Path $Root 'owner-recovery\r135-v2467-owner-once-claim.v1.json')
}

function Read-R135OwnerAttempt {
    $path=Get-R135OwnerAttemptPath
    if(-not (Test-Path -LiteralPath $path)){return $null}
    $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($file.PSIsContainer -or
       ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
       throw 'R135_ATTEMPT_RECORD_UNSAFE'
    }
    $claim=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$claim.schema -cne '1' -or
       [string]$claim.kind -cne 'R135_ONE_OWNER_ATTEMPT_NO_REPLAY' -or
       [string]$claim.target_version -cne '2.46.7' -or
       [string]$claim.target_asset_sha256 -cne 'c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e' -or
       [string]$claim.owner_transaction_id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
       [string]$claim.owner_ledger_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$claim.owner_adoption_evidence_sha256 -cnotmatch '^[a-f0-9]{64}$'){
       throw 'R135_ATTEMPT_RECORD_NOT_TRUSTED'
    }
    return $claim
}

function Assert-R135ActiveOwnerAttempt {
    param($Txn)
    if($script:R135ActiveOwnerAttempt -ne $true -or
       $null -eq $script:R135ClaimSHA -or
       $script:R135AttemptCalls -ne 1){
       throw 'R135_NO_PROCESS_BOUND_APPROVAL'
    }
    $path=Get-R135OwnerAttemptPath
    if((Get-ExactFileSha256 -Path $path) -cne [string]$script:R135ClaimSHA){
       throw 'R135_OWNER_ATTEMPT_CLAIM_CHANGED'
    }
    $c=Read-R135OwnerAttempt
    if([string]$c.owner_transaction_id -cne [string]$script:R135OwnerId){
       throw 'R135_OWNER_ATTEMPT_NOT_SESSION_BOUND'
    }
    if([string]$Txn.status -ceq 'owner-reviewed-preimage'){
       [void](Assert-SpicetifyOwnerPreimageAdoption $Txn)
       if([string]$c.owner_transaction_id -cne [string]$Txn.id -or
          [string]$c.owner_ledger_sha256 -cne
             (Get-ExactFileSha256 -Path $SpicetifyTransactionPath) -or
          [string]$c.owner_adoption_evidence_sha256 -cne
             [string]$Txn.owner_reconciliation.evidence_sha256){
          throw 'R135_OWNER_ATTEMPT_LEDGER_NOT_IDENTICAL'
       }
    }
    return $true
}

function Invoke-R135OwnerSpicetifyOneShot {
    param([string]$OwnerApproval,[switch]$ForceReinstall)
    if($OwnerApproval -cne 'APPROVE_R135_SPICETIFY_2467_ONE_NATIVE_ATTEMPT'){
       throw 'R135_EXPLICIT_OWNER_APPROVAL_REQUIRED'
    }
    if($ForceReinstall){throw 'R135_FORCE_REINSTALL_NOT_AUTHORIZED'}
    if($script:R135ActiveOwnerAttempt -eq $true -or
       $script:R135AttemptCalls -ne 0){throw 'R135_ONE_PER_PROCESS_ONLY'}
    if(Test-SpotifyRunning){throw 'R135_SPOTIFY_MUST_BE_CLOSED'}
    $lease=Enter-SpotifyControlMutex -Purpose 'Maintenance'
    if($null -eq $lease){throw 'R135_PRODUCT_MAINTENANCE_LEASE_BUSY'}
    $agentLease=$null
    try{
       $agentLease=Enter-SpotifyControlMutex -Purpose 'AgentTick'
       if($null -eq $agentLease){throw 'R135_PRODUCT_AGENT_LEASE_BUSY'}
       if(Test-SpotifyRunning){throw 'R135_SPOTIFY_RESTARTED'}
       if($null -ne (Read-R135OwnerAttempt)){
          throw 'R135_PREVIOUS_ATTEMPT_EXISTS_NO_AUTO_RETRY'
       }
       $txn=Get-SpicetifyTransaction
       if($null -eq $txn -or [string]$txn.status -cne 'owner-reviewed-preimage' -or
          -not [bool]$txn.root_transaction){
          throw 'R135_OWNER_CURRENT_PREIMAGE_NOT_ADOPTED'
       }
       [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
       $oldVersion='2.46.4'
       if([string]$txn.before_version -cne $oldVersion){
          throw 'R135_UNEXPECTED_OWNER_CLI_BASELINE'
       }
       $exe=Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
       $actualExe=Get-ExactFileSha256 -Path $exe
       if($actualExe -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
          throw 'R135_OFFICIAL_2464_EXECUTABLE_DRIFT'
       }
       $currentTree=Get-SpicetifyRootManifest -Path ([string]$txn.target_root)
       if([string]$currentTree.TreeSha256 -cne [string]$txn.before_tree_sha256){
          throw 'R135_OWNER_ROOT_DRIFT'
       }
       $config=Join-Path $env:APPDATA 'spicetify\config-xpui.ini'
       if([string](Get-IniSectionValue -Path $config -Section 'Backup' -Key 'with') -cne $oldVersion){
          throw 'R135_OLD_PREPROCESSOR_NOT_TRUSTED'
       }
       $id=[string]$txn.id
       if($id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$'){
          throw 'R135_INVALID_PARENT_TRANSACTION_ID'
       }
       $ledgerHash=Get-ExactFileSha256 -Path $SpicetifyTransactionPath
       $evidenceHash=[string]$txn.owner_reconciliation.evidence_sha256
       if($ledgerHash -cnotmatch '^[a-f0-9]{64}$' -or
          $evidenceHash -cnotmatch '^[a-f0-9]{64}$'){
          throw 'R135_MISSING_OWNER_PROVENANCE'
       }
       $claimPath=Get-R135OwnerAttemptPath
       $dir=Split-Path -Parent $claimPath
       if(-not (Test-Path -LiteralPath $dir -PathType Container)){
          throw 'R135_OWNER_RECOVERY_ROOT_MISSING'
       }
       $claim=[ordered]@{
          schema=1
          kind='R135_ONE_OWNER_ATTEMPT_NO_REPLAY'
          target_version='2.46.7'
          target_asset_sha256='c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'
          owner_transaction_id=$id
          owner_ledger_sha256=$ledgerHash
          owner_adoption_evidence_sha256=$evidenceHash
          old_executable_sha256=$actualExe
          issued_at=[DateTimeOffset]::UtcNow.ToString('o')
       }
       $bytes=[Text.UTF8Encoding]::new($false).GetBytes(
           ($claim | ConvertTo-Json -Depth 6))
       $sha=[Security.Cryptography.SHA256]::Create()
       try{$digest=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
       finally{$sha.Dispose()}
       # FileMode.CreateNew is a durable no-overwrite global attempt budget.
       # Claim is committed before release discovery, native calls, or any swap.
       $stream=[IO.FileStream]::new($claimPath,[IO.FileMode]::CreateNew,
               [IO.FileAccess]::Write,[IO.FileShare]::None)
       try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}
       finally{$stream.Dispose()}
       $script:R135ClaimSHA=$digest
       $script:R135OwnerId=$id
       $script:R135AttemptCalls=1
       $script:R135ActiveOwnerAttempt=$true
       [void](Assert-R135ActiveOwnerAttempt $txn)
       Write-Log ('R135 owner-approved single target v2.46.7: attempt recorded BEFORE any target network/native call; no retry on uncertainty. original='+$id) 'WARN'
       $state=Ensure-StateShape (Load-State)
       $result=Invoke-SpicetifyTransactionalMaintenance -State $state
       if(-not [bool]$result.Success -or
          [string]$result.Status -cne 'committed' -or
          -not [bool]$result.Changed){
          throw 'R135_APPROVED_ATTEMPT_NOT_COMMITTED_NO_RETRY'
       }
       $installed=Get-SpicetifyTransaction
       if([string]$installed.status -cne 'committed' -or
          [string]$installed.after_version -cne '2.46.7' -or
          [string]$installed.before_version -cne '2.46.4'){
          throw 'R135_POST_COMMIT_VERSION_OR_JOURNAL_INVALID'
       }
       Write-Host 'R135_APPROVED_ONE_ATTEMPT_COMMITTED=YES'
       Write-Host 'R135_NEXT_AUTOMATIC_OR_MANUAL_MUTATION=HOLD_SEPARATE_APPROVAL'
       return $result
    }finally{
       $script:R135ActiveOwnerAttempt=$false
       if($null -ne $agentLease){Exit-SpotifyControlMutex -Mutex $agentLease}
       Exit-SpotifyControlMutex -Mutex $lease
    }
}
"""

def sha(b):return hashlib.sha256(b).hexdigest()
def check(ok,why):
    if not ok: raise RuntimeError("R135_"+why)
def splice(s,fn,edits):
    marker="\nfunction "+fn+" {"
    check(s.count(marker)==1,"NON_UNIQUE_FUNCTION_"+fn)
    start=s.index(marker)+1
    end=s.find("\nfunction ",start+len(marker))
    if end<0:end=len(s)
    before=s[start:end]
    after=before
    for old,new,why in edits:
        check(after.count(old)==1,"ANCHOR_"+fn+"_"+why)
        after=after.replace(old,new,1)
    check(after!=before,"UNCHANGED_"+fn)
    return s[:start]+after+s[end:],(before,after)
def main():
    raw=SOURCE.read_bytes()
    check(sha(raw)==PARENT,"NOT_R134_EXACT_PARENT")
    check(raw.startswith(b"\xef\xbb\xbf"),"PARENT_BOM_MISSING")
    crlf=b"\r\n" in raw
    original=raw.decode("utf-8-sig").replace("\r\n","\n")
    t=original
    changes=[]
    t,entry=splice(t,"Test-R134OwnerReconciledMutationHold",[
      ("""    $txn=Get-SpicetifyTransaction
    if($null -eq $txn){return $false}
    if([string]$txn.status -ceq 'owner-reviewed-preimage'){
        [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
        return $true
    }
    return $false""",
       """    $txn=Get-SpicetifyTransaction
    $claim=Read-R135OwnerAttempt
    if($null -ne $claim){
        if($script:R135ActiveOwnerAttempt -eq $true){
            [void](Assert-R135ActiveOwnerAttempt $txn)
            return $false
        }
        return $true
    }
    if($null -eq $txn){return $false}
    if([string]$txn.status -ceq 'owner-reviewed-preimage'){
        [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
        return $true
    }
    return $false""","persistent_claim_hold")
    ]);changes.append(("Test-R134OwnerReconciledMutationHold",)+entry)
    t,entry=splice(t,"Start-SpicetifyCliTransaction",[
      ("""    $latest = Get-SpicetifyLatestReleaseInfo
    if (-not $latest.Verified) { throw $latest.Error }""",
       """    $latest = if($script:R135ActiveOwnerAttempt -eq $true){
        [void](Assert-R135ActiveOwnerAttempt $existing)
        Get-SpicetifyReleaseInfoForVersion -Version '2.46.7'
    }else{
        Get-SpicetifyLatestReleaseInfo
    }
    if (-not $latest.Verified) { throw $latest.Error }
    if($script:R135ActiveOwnerAttempt -eq $true -and
       ([string]$latest.Tag -cne 'v2.46.7' -or
        [string]$latest.Version -cne '2.46.7' -or
        [string]$latest.Architecture -cne 'x64' -or
        [string]$latest.AssetDigest -cne
          'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e')){
        throw 'R135_OFFICIAL_TARGET_2467_ASSET_PIN_MISMATCH'
    }""","target_exact_digest_only")
    ]);changes.append(("Start-SpicetifyCliTransaction",)+entry)
    # Helper appended before the existing owner-adoption hold.
    marker="\nfunction Test-R134OwnerReconciledMutationHold {"
    check(t.count(marker)==1,"OWNER_HOLD_HELPER_POSITION")
    check("function Invoke-R135OwnerSpicetifyOneShot" not in t,"HELPERS_ALREADY_PRESENT")
    t=t.replace(marker,HELPERS+marker,1)
    prefix='    [string]$AgentEvent = "Manual",\n    [switch]$Force'
    replace='    [string]$AgentEvent = "Manual",\n    [string]$OwnerOnceApproval = "",\n    [switch]$Force'
    check(t.count(prefix)==1,"PARAMETER_PREFIX_MISMATCH")
    t=t.replace(prefix,replace,1)
    choices='"GuardUpdates","Status")]'
    check(t.count(choices)==1,"ACTION_CHOICES_MISMATCH")
    t=t.replace(choices,'"GuardUpdates","Status","OwnerSpicetifyOnce")]',1)
    action='    switch ($Action) {\n'
    check(t.count(action)==1,"SWITCH_NOT_UNIQUE")
    t=t.replace(action,action+"""        "OwnerSpicetifyOnce" {
            [void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval $OwnerOnceApproval -ForceReinstall:$Force)
        }

""",1)
    # Source-only reverse audit excludes the deliberately new command surface.
    rev=t.replace("""        "OwnerSpicetifyOnce" {
            [void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval $OwnerOnceApproval -ForceReinstall:$Force)
        }

""","",1)
    rev=rev.replace('"GuardUpdates","Status","OwnerSpicetifyOnce")]','"GuardUpdates","Status")]',1)
    rev=rev.replace(replace,prefix,1)
    rev=rev.replace(HELPERS+marker,marker,1)
    for name,old,new in reversed(changes):
        check(rev.count(new)==1,"REVERSE_NOT_UNIQUE_"+name)
        rev=rev.replace(new,old,1)
    check(rev==original,"R134_UNEXPECTED_SOURCE_DRIFT")
    out=b"\xef\xbb\xbf"+t.replace("\n","\r\n" if crlf else "\n").encode("utf-8")
    check(not OUT.exists(),"OUTPUT_ALREADY_PRESENT")
    OUT.parent.mkdir(parents=True,exist_ok=True)
    with OUT.open("xb") as stream:stream.write(out)
    check(sha(OUT.read_bytes())==sha(out),"OUTPUT_READBACK_MISMATCH")
    print("R135_R134_EXACT_BYTE_PARENT=PASS")
    print("R135_SINGLE_OWNER_ACTION_AND_DURABLE_NO_REPLAY_BOUNDARY=PASS")
    print("R135_OFFICIAL_V2467_ASSET_SHA256_PINNED=PASS")
    print("R135_DEFAULT_HOLD_SURVIVES_COMMIT_AND_FAILURE=PASS")
    print("R135_REVERSE_SOURCE_AUDIT=PASS")
    print("R135_PUBLISHED_SOURCE_ONLY_NO_OWNER_RUNTIME=YES")
    print("R135_CANDIDATE_SHA256="+sha(out))
    print("R135_CANDIDATE_BYTES="+str(len(out)))

if __name__=="__main__":main()
