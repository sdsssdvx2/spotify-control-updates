"""R46 HOLD: original real-main-parent R39 Git candidate writer, changed only
to source the R45 event-driven resident rather than the legacy 60s poll VBS.
Preserve all prior distinct review refs. No release publication.
"""
from __future__ import annotations
from importlib import util
import json
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
STAGE=HERE/"out"/"release-staging-eventdriven-R46"
REVIEW=HERE/"out"/"promotion-review-eventdriven-R46"
EXPECTED_VBS="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"

def run():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R46_GITHUB_HOSTED_WINDOWS_ONLY")
    if REVIEW.exists():
        raise RuntimeError("R46_REVIEW_ALREADY_EXISTS")
    manifest=json.loads((STAGE/"manifest-UNPUBLISHABLE.json").read_text("ascii"))
    selected={e["path"]:e["sha256"] for e in manifest["latest_files"]}
    if selected.get("bin/spotify-control-agent.vbs")!=EXPECTED_VBS:
        raise RuntimeError("R46_FAST_VBS_NOT_IN_OFFICIAL_MANIFEST")
    path=HERE/"build-integrated-review-git-bundle-R39-HOLD.py"
    spec=util.spec_from_file_location("spotify_r39_original_git_two_commit",
                                      path)
    if spec is None or spec.loader is None:
        raise RuntimeError("R46_GIT_BUILDER_UNAVAILABLE")
    m=util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.STAGE=STAGE
    m.REVIEW=REVIEW
    m.PIN_AGENT=EXPECTED_VBS
    m.main()
    receipt=json.loads((REVIEW/"promotion-receipt-HOLD.json").read_text("utf-8"))
    if (receipt["source_package_chunks"]!=20 or
        receipt["git_commits_to_fast_forward"]!=2 or
        receipt["payload_set_sha256"]!=manifest["payload_set_sha256"] or
        receipt["status"]!="REVIEW_CANDIDATE_ONLY_NOT_AUTHORIZED_NOT_PUBLISHED" or
        receipt["release_published"] is not False or
        receipt["owner_approval_granted"] is not False):
        raise RuntimeError("R46_REVIEW_RECEIPT_PROVENANCE_CHANGED")
    print("R46_EVENT_DRIVEN_FULL_FILE_GIT_REVIEW_BUNDLE=SHA256_PASS")
    print("R46_OLD_REVIEW_REFS_AND_PUBLIC_MAIN=NOT_MODIFIED")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No arguments")
    run()
