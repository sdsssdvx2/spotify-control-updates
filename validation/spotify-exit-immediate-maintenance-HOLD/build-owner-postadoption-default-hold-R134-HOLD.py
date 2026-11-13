"""R134 HOLD: default-deny automatic mutation after R132 current-preimage adoption.

Only the exact R131 Windows native candidate SHA is a valid parent.  All
existing source functions are preserved except the four guarded entry points;
explicit R132 adoption is NOT equivalent to approval of a new CLI upgrade.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
HERE = Path(__file__).resolve().parent
SOURCE = HERE / "out/atomic-spicetify-preprocess-migration-R131/spotify-control.ps1"
OUTPUT = HERE / "out/owner-postadoption-default-hold-R134/spotify-control.ps1"
PARENT_SHA256 = "16db29223a50c9b2a504a543ab01fa898660642904e4be0414b959195bb113b1"
HELPER = r"""
function Test-R134OwnerReconciledMutationHold {
    # Read the authoritative journal on EVERY mutation admission. State flags,
    # including agent_mutation_enabled=true from before R132 adoption, cannot
    # authorize a new Spicetify CLI upgrade or an unrelated maintenance write.
    $txn=Get-SpicetifyTransaction
    if($null -eq $txn){return $false}
    if([string]$txn.status -ceq 'owner-reviewed-preimage'){
        [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
        return $true
    }
    return $false
}
"""

def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def assert_(x, message):
    if not x:
        raise RuntimeError("R134_"+message)

def splice(src: str, name: str, changes):
    marker = "\nfunction "+name+" {"
    assert_(src.count(marker)==1, "FUNCTION_NOT_EXACT_"+name)
    start = src.index(marker)+1
    end = src.find("\nfunction ", start+len(marker))
    if end<0: end=len(src)
    old = src[start:end]
    current = old
    for before,after,label in changes:
        assert_(current.count(before)==1, "ANCHOR_"+name+"_"+label)
        current = current.replace(before,after,1)
    assert_(current!=old, "UNCHANGED_"+name)
    return src[:start]+current+src[end:],(name,old,current)

def main():
    raw=SOURCE.read_bytes()
    assert_(sha(raw)==PARENT_SHA256,"PARENT_SHA_INVALID")
    assert_(raw.startswith(b"\xef\xbb\xbf"),"PARENT_EXPECTED_BOM_ABSENT")
    crlf=b"\r\n" in raw
    original=raw.decode("utf-8-sig").replace("\r\n","\n")
    source=original
    history=[]
    source,rec=splice(source,"Start-SpicetifyCliTransaction",[
        ("""    param([switch]$ForceReinstall)
    if (Test-SpotifyRunning)""",
         """    param([switch]$ForceReinstall)
    if(Test-R134OwnerReconciledMutationHold){
        throw 'R134_OWNER_ADOPTION_NOT_UPGRADE_APPROVAL'
    }
    if (Test-SpotifyRunning)""","direct_cli_admission")
    ]);history.append(rec)
    source,rec=splice(source,"Rollback-SpicetifyCliTransaction",[
        ("""    $txn = Get-SpicetifyTransaction
    if (-not $txn)""",
         """    $txn = Get-SpicetifyTransaction
    if([string]$txn.status -ceq 'owner-reviewed-preimage'){
        [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
        throw 'R134_OWNER_ADOPTION_NOT_ROLLBACK_PERMISSION'
    }
    if (-not $txn)""","direct_rollback_admission")
    ]);history.append(rec)
    source,rec=splice(source,"Invoke-MaintenanceMutationPhase",[
        ("""    $State = Ensure-StateShape $State
    if (Test-SpotifyRunning)""",
         """    $State = Ensure-StateShape $State
    if(Test-R134OwnerReconciledMutationHold){
        Write-Log 'R134 owner-reviewed baseline is observation-only until a separate owner upgrade approval.' 'WARN'
        return $State
    }
    if (Test-SpotifyRunning)""","product_mutation_boundary")
    ]);history.append(rec)
    source,rec=splice(source,"Maintain",[
        ("""    $State = Ensure-StateShape (Load-State)
    $State = Migrate-StateFromLog $State
    # A concurrent owner disarm""",
         """    $State = Ensure-StateShape (Load-State)
    if(Test-R134OwnerReconciledMutationHold){
        Write-Log 'R134 owner-reviewed baseline: resident and manual maintenance mutation held until separate owner approval.' 'WARN'
        return
    }
    $State = Migrate-StateFromLog $State
    # A concurrent owner disarm""","resident_and_manual_mutation_boundary")
    ]);history.append(rec)
    marker="\nfunction Start-SpicetifyCliTransaction {"
    assert_(source.count(marker)==1,"HELPER_INSERTION_POSITION_NOT_EXACT")
    assert_(source.count("function Test-R134OwnerReconciledMutationHold")==0,"HELPER_ALREADY_PRESENT")
    source=source.replace(marker,HELPER+marker,1)
    reverse=source.replace(HELPER+marker,marker,1)
    for name,old,new in reversed(history):
        assert_(reverse.count(new)==1,"REVERSE_NOT_UNIQUE_"+name)
        reverse=reverse.replace(new,old,1)
    assert_(reverse==original,"PARENT_UNEXPECTED_SOURCE_CHANGE")
    out=b"\xef\xbb\xbf"+source.replace("\n","\r\n" if crlf else "\n").encode("utf-8")
    assert_(not OUTPUT.exists(),"OUTPUT_ALREADY_EXISTS")
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    with OUTPUT.open("xb") as f:f.write(out)
    assert_(sha(OUTPUT.read_bytes())==sha(out),"OUTPUT_SHA_READBACK_FAILED")
    print("R134_EXACT_R131_BYTE_PARENT_SHA=PASS")
    print("R134_FOUR_REAL_ENTRYPOINTS_DEFAULT_DENY_AFTER_R132=PASS")
    print("R134_PARENT_REVERSE_EXACT=PASS")
    print("R134_OWNER_OPERATING_FILES_AND_PUBLIC_MAIN=UNTOUCHED")
    print("R134_CANDIDATE_SHA256="+sha(out))
    print("R134_CANDIDATE_BYTES="+str(len(out)))

if __name__=="__main__":
    main()
