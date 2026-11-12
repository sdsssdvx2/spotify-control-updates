"""R112 HOLD: v0.6.30 private installation may be newer than stable v0.6.28.
Allow unrelated health-checked maintenance, but NEVER authorize self-update,
downgrade, signature bypass, or any other failed-discovery source.
Two exact source-function edits, no operating file writes/publication.
"""
from __future__ import annotations
import hashlib,os
from pathlib import Path

HERE=Path(__file__).resolve().parent
SOURCE=HERE/"out/release-staging-boot-wmi-R70/bin/spotify-control.ps1"
PIN="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
OUT=HERE/"out/private-stable-ahead-R112/spotify-control.ps1"
BOOT="d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6"

def require(ok:bool,label:str)->None:
    if not ok:raise RuntimeError("R112_"+label)

def sha(data:bytes)->str:return hashlib.sha256(data).hexdigest()

def one(s:str,old:str,new:str,label:str)->str:
    require(s.count(old)==1,"EXACT_SOURCE_ANCHOR_"+label)
    return s.replace(old,new,1)

def span(s:str,name:str)->tuple[int,int]:
    marker="\nfunction "+name+" {"
    require(s.count(marker)==1,"UNIQUE_SOURCE_FUNCTION_"+name)
    i=s.index(marker)+1
    following=s.find("\nfunction ",i+len(marker))
    return i,following if following>=0 else len(s)

def patch_selfupdate(body:str)->str:
    old='    if ($r.ExitCode -ne 0 -or $null -eq $r.Report -or -not [bool]$r.Report.success) {'
    new=r'''    # The official v1.0.6 bootstrap authenticated the stable manifest and
    # then refused a forward-only plan because a private, exact version is
    # already ahead of published stable. This is NOT a failed Spicetify check.
    # Never treat an arbitrary bootstrap/network/integrity error as benign.
    $privateAhead=$false
    if ($r.ExitCode -eq 1 -and $null -ne $r.Report -and
        $r.Report.success -eq $false -and
        [string]$r.Report.action -ceq "Check" -and
        [string]$r.Report.bootstrap_version -ceq "1.0.6" -and
        [string]$r.Report.installed_version -ceq "0.6.30" -and
        [string]$ScriptVersion -ceq "0.6.30" -and
        [string]$r.Report.manifest_url -ceq
          "https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json" -and
        [string]$r.Report.error -ceq
          "Automatic Spotify Control downgrade refused: installed=0.6.30 latest=0.6.28" -and
        [string]$r.Report.transaction_status -cin @("","committed")) {
        try {
            $boot=(Get-Item -LiteralPath $SelfUpdater -Force -ErrorAction Stop)
            if (-not $boot.PSIsContainer -and
                ($boot.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                [long]$boot.Length -eq 42963 -and
                (Get-FileHash -LiteralPath $SelfUpdater -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -ceq
                "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6") {
                $privateAhead=$true
            }
        } catch { $privateAhead=$false }
    }
    if ($privateAhead) {
        return [pscustomobject]@{
            Verified=$false;TrustedStableBehindPrivate=$true;
            UpdateAvailable=$false;InstalledVersion=$ScriptVersion;
            LatestVersion="0.6.28";BootstrapVersion="1.0.6";
            SourceCommit=$null;PayloadSetSha256=$null;
            TransactionId=[string]$r.Report.transaction_id;
            TransactionStatus=[string]$r.Report.transaction_status;
            Error="trusted-private-version-ahead-of-public-stable-self-update-disabled"
        }
    }
    if ($r.ExitCode -ne 0 -or $null -eq $r.Report -or -not [bool]$r.Report.success) {'''
    body=one(body,old,new,"PINNED_BOOTSTRAP_AHEAD_TRUST_ADMISSION")
    body=one(body,
      "Verified=$false; UpdateAvailable=$false; InstalledVersion=$ScriptVersion;",
      "Verified=$false; TrustedStableBehindPrivate=$false; UpdateAvailable=$false; InstalledVersion=$ScriptVersion;",
      "FAILURE_NOT_AHEAD")
    body=one(body,"        Verified=$true\n",
      "        Verified=$true\n        TrustedStableBehindPrivate=$false\n","SUCCESS_NOT_AHEAD")
    return body

def patch_check(body:str)->str:
    body=one(body,
      '        if (-not $selfUpdate.Verified) { $errors.Add("Spotify Control self-update discovery: $($selfUpdate.Error)") }',
      '''        if (-not $selfUpdate.Verified) {
            if ($selfUpdate.TrustedStableBehindPrivate -eq $true) {
                # No self-update is permitted. Independent Spicetify/addon
                # checks still have to pass their existing fail-closed guards.
                $warnings.Add("Pinned private v0.6.30 is newer than authenticated public stable v0.6.28; self-update disabled.")
            } else {
                $errors.Add("Spotify Control self-update discovery: $($selfUpdate.Error)")
            }
        }''',"HEALTH_CHECK_DISTINGUISHES_TRUSTED_AHEAD_ONLY")
    body=one(body,
      "            Verified=(-not [string]::IsNullOrWhiteSpace([string]$State.self_update_latest_version))",
      "            Verified=(-not [string]::IsNullOrWhiteSpace([string]$State.self_update_latest_version))\n            TrustedStableBehindPrivate=$false",
      "CACHED_STATUS_DOES_NOT_IMPLY_AHEAD")
    return body

def main()->None:
    require(os.getenv("GITHUB_ACTIONS")=="true" and
            os.getenv("RUNNER_OS")=="Windows" and
            os.getenv("RUNNER_ENVIRONMENT")=="github-hosted",
            "HOSTED_WINDOWS_SOURCE_BUILD_ONLY")
    original=SOURCE.read_bytes()
    require(sha(original)==PIN,"PRODUCTION_V0630_SOURCE_BYTES_CHANGED")
    newline="\r\n" if b"\r\n" in original else "\n"
    bom=b"\xef\xbb\xbf" if original.startswith(b"\xef\xbb\xbf") else b""
    plain=original.decode("utf-8-sig").replace("\r\n","\n")
    s=plain
    a,b=span(s,"Get-SelfUpdateCheckResult")
    original_self=s[a:b];revised_self=patch_selfupdate(original_self)
    require(revised_self!=original_self,"SELFUPDATE_NOT_CHANGED")
    s=s[:a]+revised_self+s[b:]
    c,d=span(s,"Invoke-MaintenanceCheckPhase")
    original_check=s[c:d];revised_check=patch_check(original_check)
    require(revised_check!=original_check,"CHECK_NOT_CHANGED")
    s=s[:c]+revised_check+s[d:]
    require(s.count(revised_self)==1 and s.count(revised_check)==1,
            "MODIFIED_FUNCTION_NOT_UNIQUE")
    reverse=s.replace(revised_check,original_check,1).replace(
        revised_self,original_self,1)
    require(reverse==plain,"EXACT_TWO_FUNCTION_REPLAY_MISMATCH")
    require(bom+reverse.replace("\n",newline).encode("utf-8")==original,
            "ORIGINAL_SOURCE_BYTES_NOT_RECOVERABLE")
    body=bom+s.replace("\n",newline).encode("utf-8")
    require(body!=original,"CANDIDATE_UNCHANGED")
    require(s.count("TrustedStableBehindPrivate=$true")==1,"AHEAD_FLAG_SINGLE_SOURCE")
    require("Invoke-MaintenanceMutationPhase -State $State" in s,
            "MUTATION_ENTRYPOINT_MISSING")
    require(revised_check.count('if (-not $selfUpdate.Verified) {')==1,
            "CHECK_HANDLER_DUPLICATED")
    require(not OUT.exists(),"EXISTING_CANDIDATE_NOT_OVERWRITTEN")
    OUT.parent.mkdir(parents=True,exist_ok=True)
    with OUT.open("xb") as f:f.write(body)
    require(sha(OUT.read_bytes())==sha(body),"POST_WRITE_SHA_CHANGED")
    print("R112_ORIGINAL_MAIN_SHA256=PASS")
    print("R112_ONLY_SELFUPDATE_RESULT_AND_CHECK_HEALTH_HANDLERS_CHANGED=PASS")
    print("R112_BOOTSTRAP_V106_SHA_PIN_REQUIRED=PASS")
    print("R112_PUBLIC_RELEASE_AND_OPERATING_OWNER_FILES=UNCHANGED")
    print("R112_CANDIDATE_SHA256="+sha(body))
if __name__=="__main__":main()
