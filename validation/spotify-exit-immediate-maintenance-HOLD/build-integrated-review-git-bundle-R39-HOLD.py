"""R39 HOLD: preserve the R38 combined functional future release as a real
public-main-parent two-commit Git bundle, without publishing any update.

Runs only after targeted R37/R38 Windows acceptance, in a fresh Windows CI
temporary directory. Reuses the existing R34 vetted Git bundle author but
binds it to the R38 integrated candidate (not obsolete R34 shortcut-only).
"""
from __future__ import annotations

import hashlib
from importlib import util
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
STAGE=HERE/"out"/"release-staging-combined"
REVIEW=HERE/"out"/"promotion-review-integrated-HOLD"
PIN_NEW_MAIN="7caf4afe19c283aef3b5bebb30e0e598b10de147d3ab1ddd9724bf90594c59fe"
PIN_AGENT="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
PIN_ADDON="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"

def sha(b):
    return hashlib.sha256(b).hexdigest()

def main():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R39_FROZEN_WINDOWS_CI_ONLY")
    doc=json.loads((STAGE/"manifest-UNPUBLISHABLE.json").read_text("ascii"))
    pins={row["path"]:row["sha256"] for row in doc["latest_files"]}
    if (pins!={"bin/spotify-control.ps1":PIN_NEW_MAIN,
               "bin/spotify-control-agent.vbs":PIN_AGENT,
               "bin/addon-manager.ps1":PIN_ADDON} or
        doc["source_commit"]!="f"*40 or
        doc["latest_version"]!="0.6.30" or
        len(doc["updates"])!=19):
        raise RuntimeError("R39_UNREVIEWED_PREVIOUS_CANDIDATE_OR_WRONG_PAYLOAD")
    p=HERE/"prepare-offline-promotion-bundle-HOLD.py"
    spec=util.spec_from_file_location("spotify_r34_parent_reusable_git_bundle",p)
    if spec is None or spec.loader is None:
        raise RuntimeError("R39_GIT_PREPARE_HELPER_UNAVAILABLE")
    mod=util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    # Separate source, destination and scratch from the older v0.6.30
    # shortcut-only HOLD candidate. Never overwrite that review.
    mod.STAGE=STAGE
    mod.OUTPUT=REVIEW
    mod.SCRATCH=Path(os.environ["RUNNER_TEMP"]).resolve()/(
        "spotify-v0630-integrated-two-commit-review")
    mod.run()
    rec=json.loads((REVIEW/"promotion-receipt-HOLD.json").read_text("utf-8"))
    manifest_sha=sha((STAGE/"manifest-UNPUBLISHABLE.json").read_bytes())
    if (rec["status"]!="REVIEW_CANDIDATE_ONLY_NOT_AUTHORIZED_NOT_PUBLISHED" or
        rec["payload_set_sha256"]!=doc["payload_set_sha256"] or
        rec["source_package_chunks"]!=20 or
        rec["git_commits_to_fast_forward"]!=2 or
        not all(rec[k] is False for k in (
           "release_published","github_ref_updated","operating_windows_modified",
           "owner_approval_granted","public_manifest_changed"))):
        raise RuntimeError("R39_REVIEW_BUNDLE_RECEIPT_SCOPE_DRIFT")
    print("R39_INTEGRATED_MANIFEST_UNPUBLISHABLE_SHA256="+manifest_sha)
    print("R39_SOURCE_CHUNKS_20_AND_BOTH_COMBINED_TARGETS_BUNDLE=PASS")
    print("R39_REVIEW_ONLY_NO_PRODUCTION_UPDATE_OR_OWNER_APPROVAL=YES")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No arguments.")
    main()
