"""R136 HOLD product-wide dispatch guard, preserving normal Spotify launch.

Build only from byte-exact published R135; reject unexpected production source.
"""
from pathlib import Path
import hashlib
BASE=Path(__file__).resolve().parent
SOURCE=BASE/"out/owner-v2467-one-approved-attempt-R135/spotify-control.ps1"
OUT=BASE/"out/owner-postadoption-dispatch-gate-R136/spotify-control.ps1"
PARENT="07407f9dd566616395644a5c5bff8a1255701696dab2a074df062bab3ad279b4"
HELPER=r"""
function Assert-R136NoBypassFromOwnerHold {
    param([string]$RequestedAction)
    # Only ordinary playback, observation, or the independently approved
    # R135 single-target action can continue after owner adoption.
    $changes=@(
      'UpdateMarketplace','UpdateSpicetify','SpicetifyRollbackTest',
      'RollbackSpicetify','UpdateSpotify','SpotifyRollbackTest',
      'RollbackSpotify','InstallTasks','SelfUpdate','SelfUpdateRollbackTest',
      'RollbackSelfUpdate','GuardUpdates'
    )
    if($RequestedAction -cin $changes){
        if(Test-R134OwnerReconciledMutationHold){
            throw 'R136_OWNER_ADOPTION_NOT_APPROVAL_FOR_OTHER_MUTATIONS'
        }
    }
}
"""
def digest(b):return hashlib.sha256(b).hexdigest()
def check(x,m):
    if not x:raise RuntimeError("R136_"+m)
def main():
    raw=SOURCE.read_bytes()
    check(digest(raw)==PARENT,"NOT_VERIFIED_R135_PARENT")
    check(raw.startswith(b"\xef\xbb\xbf"),"BOM_MISSING")
    crlf=b"\r\n" in raw
    old=raw.decode("utf-8-sig").replace("\r\n","\n")
    s=old
    loc="\nfunction Test-R134OwnerReconciledMutationHold {"
    check(s.count(loc)==1,"HOLD_POSITION")
    check("function Assert-R136NoBypassFromOwnerHold" not in s,"HELPER_ALREADY_PRESENT")
    s=s.replace(loc,HELPER+loc,1)
    switch="""    switch ($Action) {
        "OwnerSpicetifyOnce" {
"""
    replacement="""    Assert-R136NoBypassFromOwnerHold -RequestedAction $Action
    switch ($Action) {
        "OwnerSpicetifyOnce" {
"""
    check(s.count(switch)==1,"TOP_LEVEL_ACTION_DISPATCH_NOT_EXACT")
    s=s.replace(switch,replacement,1)
    launch="""    Maintain

    $guard = $script:LastGuardResult

    if ($guard -and"""
    guarded="""    Maintain

    $guard = $script:LastGuardResult
    # Launch remains usable, but no unapproved "spicetify auto" may rewrite
    # Spotify Apps while an owner-reconciled or attempted update is held.
    if(Test-R134OwnerReconciledMutationHold){
        $guard=$null
        Write-Log 'R136 owner review active: launching ordinary Spotify without spicetify auto.' 'WARN'
    }

    if ($guard -and"""
    check(s.count(launch)==1,"PLAYBACK_DISPATCH_UNEXPECTED")
    s=s.replace(launch,guarded,1)
    reversed=s.replace(guarded,launch,1).replace(replacement,switch,1).replace(HELPER+loc,loc,1)
    check(reversed==old,"PRODUCTION_REVERSE_NOT_IDENTICAL")
    out=b"\xef\xbb\xbf"+s.replace("\n","\r\n" if crlf else "\n").encode("utf-8")
    check(not OUT.exists(),"DUPLICATE_OUTPUT_NO_OVERWRITE")
    OUT.parent.mkdir(parents=True,exist_ok=True)
    with OUT.open("xb") as fh:fh.write(out)
    check(digest(OUT.read_bytes())==digest(out),"OUTPUT_READBACK")
    print("R136_R135_PINNED_PARENT=PASS")
    print("R136_ALL_MUTATING_DISPATCH_ENTRIES_REQUIRING_SEPARATE_APPROVAL=PASS")
    print("R136_NORMAL_SPOTIFY_PLAYBACK_PRESERVED_WITHOUT_AUTOREWRITE=PASS")
    print("R136_ONLY_DESIGNATED_THREE_EDITS_AND_EXACT_PARENT_REVERSAL=PASS")
    print("R136_CANDIDATE_SHA256="+digest(out))
    print("R136_CANDIDATE_BYTES="+str(len(out)))
if __name__=="__main__":main()
