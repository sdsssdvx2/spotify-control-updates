"""R55 HOLD: final authentic Windows owner cutover + actual WScript and
original R35 protected Git review custody for the R54 shared-mutex candidate.

Reuses the previously accepted R50 real-life installer, full-file Bootstrap,
real WScript/SpotifyExit bridge and source+manifest review routines without
reimplementing or altering the production release/installed user files.

R54 fixes cross-process manual Maintain vs resident discovery; R49 remains
one-discovery, R45 WMI fast event VBS remains byte identical.
"""
from __future__ import annotations

from importlib import util
import json
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
STAGE=HERE/"out"/"release-staging-shared-maintenance-R54"
REVIEW=HERE/"out"/"promotion-review-shared-maintenance-R55"
MAIN="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
VBS="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
EXPECTED_CHUNKS=20
REF="refs/heads/hold/spotify-v0630-shared-maintenance-review-only"

def previous():
    spec=util.spec_from_file_location(
      "spotify_r55_exact_previous_successful_r50_review",
      HERE/"accept-single-discovery-release-R50-HOLD.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("R55_R50_VERIFIED_OWNER_UPDATER_UNAVAILABLE")
    r=util.module_from_spec(spec)
    spec.loader.exec_module(r)
    r.STAGE=STAGE
    r.REVIEW=REVIEW
    r.MAIN=MAIN
    r.AGENT=VBS
    r.REF=REF
    r.EXPECTED_CHUNKS=EXPECTED_CHUNKS
    return r

def run():
    if len(sys.argv)!=2 or sys.argv[1] not in ("prepare-win","bundle-win","custody-linux"):
        raise SystemExit("Usage: R55 prepare-win|bundle-win|custody-linux")
    mode=sys.argv[1]
    r=previous()
    if mode in ("prepare-win","bundle-win"):
        if (os.getenv("GITHUB_ACTIONS")!="true" or
            os.getenv("RUNNER_OS")!="Windows" or
            os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
            raise RuntimeError("R55_HOSTED_WINDOWS_REQUIRED")
        manifest=r.inspect_stage()
        if (manifest["source_commit"]!="f"*40 or
            manifest["latest_version"]!="0.6.30"):
            raise RuntimeError("R55_OFFICIAL_REVIEW_ONLY_STAGE_INVALID")
        if mode=="prepare-win":
            r.prepare_win()
            # R50's otherwise unchanged source-pinned R43 test-preparer
            # embeds the historical R49 stage path. It is a read-side
            # localhost-fixture selector, NOT a release or owner mutation.
            # Select exactly the new R54 stage without touching R28's
            # actual owner-cutover, Bootstrap or rollback semantics.
            preparer=Path(os.environ["RUNNER_TEMP"]).resolve()/(
                "spotify-r43-integrated-prepare.py")
            source=preparer.read_text("utf-8")
            old="out/release-staging-single-discovery-R49"
            new="out/release-staging-shared-maintenance-R54"
            if source.count(old)!=1 or new in source:
                raise RuntimeError("R55_LAST_TEST_FIXTURE_STAGE_POINTER_NOT_UNIQUE")
            preparer.write_text(source.replace(old,new,1),encoding="utf-8")
            if old in preparer.read_text("utf-8"):
                raise RuntimeError("R55_PREVIOUS_RELEASE_TARGET_STILL_ACTIVE")
            print("R55_EXACT_NEW_R54_STAGE_SELECTED_FOR_BOOTSTRAP_FIXTURE=PASS")
            print("R55_EXISTING_R28_OWNER_CUTOVER_PREPARED_EXACT_SHARED_MUTEX_SOURCE=PASS")
        else:
            r.bundle_win()
            print("R55_NEW_R54_SHARED_MUTEX_FULLFILE_GIT_BUNDLE_PREPARED=PASS")
    else:
        if (os.getenv("GITHUB_ACTIONS")!="true" or
            os.getenv("RUNNER_OS")!="Linux" or
            os.getenv("GITHUB_REF")!="refs/heads/validate/spotify-exit-immediate-maintenance-HOLD"):
            raise RuntimeError("R55_RESTRICTED_HOLD_REF_CUSTODY_ONLY")
        r.custody_linux()
        print("R55_FINAL_SHARED_MUTEX_REVIEW_REF_SOURCE_AND_SHA_BOUND=PASS")
        print("R55_PUBLIC_STABLE_MAIN_OR_PREVIOUS_REVIEW_OVERWRITE=NO")

if __name__=="__main__":
    run()
