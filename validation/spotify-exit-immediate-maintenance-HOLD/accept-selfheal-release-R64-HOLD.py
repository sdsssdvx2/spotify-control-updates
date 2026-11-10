"""R64 HOLD: exact previous R55 native Windows Bootstrap owner cutover +
R50/R39 Git source commit and R35 immutable custody for the new R63 self-healing
two-rapid-session WScript agent, with byte-identical R54 main and r17 addon.

Only an isolated hosted fixture read-side stage locator is changed. No
owner/OS change, no publication and no overwrite of older review branches.
"""
from __future__ import annotations
from importlib import util
import os
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
STAGE=HERE/"out"/"release-staging-selfheal-R64"
REVIEW=HERE/"out"/"promotion-review-selfheal-R64"
MAIN="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
AGENT="82f4547a33149a7db2d39b24745c0e3a5a04646bed693c5a6e93d01625798acc"
REF="refs/heads/hold/spotify-v0630-selfheal-review-only"

def run():
    if len(sys.argv)!=2 or sys.argv[1] not in ("prepare-win","bundle-win","custody-linux"):
        raise SystemExit("Usage: R64 prepare-win|bundle-win|custody-linux")
    mode=sys.argv[1]
    spec=util.spec_from_file_location("spotify_r59_reuse_true_r55_owner_cutover",
                                      HERE/"accept-shared-mutex-release-R55-HOLD.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("R64_REAL_R55_ACCEPTANCE_NOT_AVAILABLE")
    old=util.module_from_spec(spec)
    spec.loader.exec_module(old)
    old.STAGE=STAGE
    old.REVIEW=REVIEW
    old.MAIN=MAIN
    old.VBS=AGENT
    old.REF=REF
    old.run()
    if mode=="prepare-win":
        preparer=Path(os.environ["RUNNER_TEMP"]).resolve()/(
            "spotify-r43-integrated-prepare.py")
        source=preparer.read_text("utf-8")
        old_path="out/release-staging-shared-maintenance-R54"
        new_path="out/release-staging-selfheal-R64"
        if source.count(old_path)!=1 or new_path in source:
            raise RuntimeError("R64_READ_ONLY_FIXTURE_DOES_NOT_USE_R54_STAGE")
        preparer.write_text(source.replace(old_path,new_path,1),encoding="utf-8")
        print("R64_NATIVE_OWNER_UPGRADE_TARGET_NEW_R58_WMI_VBS=EXACT")
    elif mode=="bundle-win":
        receipt=json.loads((REVIEW/"promotion-receipt-HOLD.json").read_text("utf-8"))
        if (receipt["source_package_chunks"]!=20 or
            receipt["git_commits_to_fast_forward"]!=2 or
            receipt["release_published"] is not False or
            receipt["owner_approval_granted"] is not False):
            raise RuntimeError("R64_REVIEW_BUNDLE_OR_RELEASE_SCOPE_DRIFT")
        print("R64_VERIFIED_MAIN_PARENT_20_CHUNKS_EVENT_VBS_REVIEW_ONLY=PASS")
    else:
        print("R64_EXACT_NEW_R58_VBS_REVIEW_GIT_REF_PRESERVED=PASS")
        print("R64_PUBLIC_MAIN_AND_ALL_PREVIOUS_REVIEW_REFS=UNMODIFIED")

if __name__=="__main__":
    run()
