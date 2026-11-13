"""R137 HOLD: pre-consumption official release and migration readiness checks.

The R135 owner one-shot claim may not be consumed when v2.46.4 recovery
metadata or exact target v2.46.7 x64 metadata is missing or changes.
Changes limited to one new read-only helper and its pre-claim invocation.
"""
from pathlib import Path
import hashlib
BASE=Path(__file__).resolve().parent
PARENT=BASE/"out/owner-postadoption-dispatch-gate-R136/spotify-control.ps1"
OUT=BASE/"out/owner-release-readiness-R137/spotify-control.ps1"
PARENT_SHA="0f059208b231f9f8ec3e8829117785a319d52a3ded3a745147caf7039a7eee3d"
HELPER=r"""
function Assert-R137OfficialSpicetifyPairReady {
    # Perform read-only GitHub release checks before consuming the only
    # permitted R135 transaction attempt. A bad release cannot burn consent.
    foreach($version in @('2.46.4','2.46.7')){
        $r=Get-SpicetifyReleaseInfoForVersion -Version $version
        if($null -eq $r -or -not [bool]$r.Verified -or
           [string]$r.Tag -cne ('v'+$version) -or
           [string]$r.Version -cne $version -or
           [string]$r.Architecture -cne 'x64' -or
           [int64]$r.AssetSize -le 0 -or
           [string]$r.AssetName -cne ('spicetify-'+$version+'-windows-x64.zip') -or
           [string]$r.AssetUrl -cne ('https://github.com/spicetify/cli/releases/download/v'+
                $version+'/spicetify-'+$version+'-windows-x64.zip') -or
           [string]$r.AssetDigest -cnotmatch '^sha256:[a-f0-9]{64}$'){
            throw ('R137_OFFICIAL_RELEASE_NOT_READY_'+($version -replace '\.','_'))
        }
        if($version -ceq '2.46.4' -and
           [string]$r.AssetDigest -cne
             'sha256:0490380bf59e00c94cf6cb12bfac5152791b91bb8009aceef53c49815b45a56f'){
            throw 'R137_EXACT_ROLLBACK_ASSET_SHA_MISMATCH'
        }
        if($version -ceq '2.46.7' -and
           [string]$r.AssetDigest -cne
             'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'){
            throw 'R137_EXACT_TARGET_ASSET_SHA_MISMATCH'
        }
    }
    return $true
}
"""
def sha(data):return hashlib.sha256(data).hexdigest()
def require(condition,label):
    if not condition:raise RuntimeError("R137_"+label)
def main():
    raw=PARENT.read_bytes()
    require(sha(raw)==PARENT_SHA,"UNVERIFIED_R136_PARENT")
    require(raw.startswith(b"\xef\xbb\xbf"),"BOM_MISSING")
    crlf=b"\r\n" in raw
    original=raw.decode("utf-8-sig").replace("\r\n","\n")
    source=original
    position="\nfunction Invoke-R135OwnerSpicetifyOneShot {"
    require(source.count(position)==1,"PRECLAIM_FUNCTION_NOT_UNIQUE")
    require("function Assert-R137OfficialSpicetifyPairReady" not in source,"ALREADY_PATCHED")
    source=source.replace(position,HELPER+position,1)
    marker="""       $id=[string]$txn.id
       if($id -cnotmatch '^\\d{8}-\\d{6}-[a-f0-9]{8}$'){"""
    addition="""       # Validate the official old-version rollback asset and exactly pinned
       # v2.46.7 before the durable one-use claim is created. No native calls.
       $managed=Get-SpicetifyManagedInstallInfo
       if($null -eq $managed -or -not [bool]$managed.Managed -or
          [string]$managed.Version -cne '2.46.4' -or
          [string]$managed.Path -cne $exe){
           throw 'R137_OFFICIAL_MANAGED_BASELINE_NOT_READY'
       }
       $migrationClass=Get-SpicetifyBackupMigrationClass -InstalledVersion '2.46.4' -TargetVersion '2.46.7' -BackupWith '2.46.4'
       if([string]$migrationClass -cne 'VERSION_CHANGE_REQUIRES_ATOMIC_BACKUP_REPROCESSING'){
           throw 'R137_BACKUP_PREPROCESSOR_MIGRATION_NOT_READY'
       }
       [void](Assert-R137OfficialSpicetifyPairReady)
       if(Test-SpotifyRunning){throw 'R137_SPOTIFY_RESTARTED_BEFORE_APPROVAL_CONSUMPTION'}
       $id=[string]$txn.id
       if($id -cnotmatch '^\\d{8}-\\d{6}-[a-f0-9]{8}$'){"""
    require(source.count(marker)==1,"R135_PRECLAIM_SOURCE_ANCHOR")
    source=source.replace(marker,addition,1)
    back=source.replace(addition,marker,1).replace(HELPER+position,position,1)
    require(back==original,"PARENT_REVERSE_NOT_IDENTICAL")
    out=b"\xef\xbb\xbf"+source.replace("\n","\r\n" if crlf else "\n").encode("utf-8")
    require(not OUT.exists(),"OUTPUT_EXISTS_NO_OVERWRITE")
    OUT.parent.mkdir(parents=True,exist_ok=True)
    with OUT.open("xb") as f:f.write(out)
    require(sha(OUT.read_bytes())==sha(out),"OUTPUT_READBACK_INVALID")
    print("R137_EXACT_R136_PARENT_AND_REVERSE=PASS")
    print("R137_OLD_ROLLBACK_RELEASE_AND_TARGET_PRECLAIM=PASS")
    print("R137_NO_EXTRA_MODEL_NATIVE_OR_USER_CALLS=YES")
    print("R137_CANDIDATE_SHA256="+sha(out))
    print("R137_CANDIDATE_BYTES="+str(len(out)))
if __name__=="__main__":main()
