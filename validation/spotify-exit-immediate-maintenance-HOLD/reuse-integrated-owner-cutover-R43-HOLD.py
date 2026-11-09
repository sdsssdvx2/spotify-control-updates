"""R43 HOLD: build a hosted-only R28 resident-cutover exercise from the
exact already-accepted Windows R28 scenario, not a recreated test.

Differences from the pinned R28 hosted script are restricted to:
  - the fixture preparer's read-side stage path (integrated R38),
  - the expected integrated stage receipt path,
  - a positive exact SHA assertion on the NEW combined main/agent bytes.
The actual R28 driver, real WScript process inspection, owner locks,
protected shortcut, Bootstrap, transaction, rollback and cleanup remain intact.
Creates ephemeral scripts only under GitHub Windows RUNNER_TEMP.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
TARGET=ROOT/".github/workflows/validate-future-managed-shortcut-owner-preservation-HOLD.yml"
SOURCE_BLOB="ab0488b61120431a9a9a3ee68a7228448c29d126"
BEGIN="      - name: R28 one-approval exact resident upgrade, true Bootstrap then hosted-only rollback and tamper rejection\n"
END="      - name: R30 factual release admission and corruption negatives from exact staged chunk set\n"
COMBINED="validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging-combined"
MAIN_SHA="7caf4afe19c283aef3b5bebb30e0e598b10de147d3ab1ddd9724bf90594c59fe"
AGENT_SHA="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"


def require(cond:bool,code:str)->None:
    if not cond:
        raise RuntimeError(code)


def run():
    require(os.getenv("GITHUB_ACTIONS")=="true" and
        os.getenv("RUNNER_OS")=="Windows" and
        os.getenv("RUNNER_ENVIRONMENT")=="github-hosted",
        "R43_GITHUB_HOSTED_WINDOWS_ONLY")
    dest=Path(os.environ["RUNNER_TEMP"]).resolve()
    require(dest.is_dir() and not dest.is_symlink(),"R43_TRUSTED_RUNNER_TEMP_REQUIRED")
    idx=subprocess.run(["git","rev-parse",":"+TARGET.relative_to(ROOT).as_posix()],
          cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
    require(idx.returncode==0 and idx.stdout.decode("ascii").strip()==SOURCE_BLOB,
            "R43_R28_VALIDATED_WORKFLOW_SOURCE_GIT_BLOB_CHANGED")
    original=TARGET.read_text("utf-8")
    require(original.count(BEGIN)==1 and original.count(END)==1,
        "R43_R28_HOSTED_SCENARIO_UNIQUE_ANCHORS_REQUIRED")
    area=original.split(BEGIN,1)[1].split(END,1)[0]
    preamble="        shell: powershell\n        run: |\n"
    require(area.startswith(preamble),"R43_R28_WINDOWS_POWERSHELL_HOSTED_STEP_REQUIRED")
    src=area[len(preamble):]
    lines=src.splitlines()
    require(len(lines)>260 and all(not x.strip() or x.startswith("          ") for x in lines),
        "R43_R28_HOSTED_ACCEPTANCE_SCRIPT_INDENTATION_DRIFT")
    script="\n".join(x[10:] if x.strip() else "" for x in lines)+"\n"
    old_prepare="python $script prepare"
    new_prepare="& $python (Join-Path $env:RUNNER_TEMP 'spotify-r43-integrated-prepare.py')"
    require(script.count(old_prepare)==1,"R43_ONE_OLD_PREPARE_LOCATOR_REQUIRED")
    script=script.replace(old_prepare,new_prepare,1)
    old_receipt="validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging/stage-receipt.json"
    new_receipt=COMBINED+"/stage-receipt.json"
    require(script.count(old_receipt)==1,"R43_OLD_STAGE_RECEIPT_UNIQUE")
    script=script.replace(old_receipt,new_receipt,1)
    expected_line="$expect=Get-Content -LiteralPath $output -Raw | ConvertFrom-Json"
    require(script.count(expected_line)==1,"R43_EXPECTED_SHA_ASSERTION_ANCHOR_MISSING")
    extra=(
      expected_line+"\n"
      f"    if([string]$expect.future_main_sha256 -cne '{MAIN_SHA}' -or\n"
      f"       [string]$expect.future_agent_sha256 -cne '{AGENT_SHA}'){{\n"
      "      throw 'R43_BOOTSTRAP_FIXTURE_NOT_THE_INTEGRATED_R38_PAYLOAD'\n"
      "    }\n"
      "    Write-Host 'R43_ACTUAL_R28_OWNER_CUTOVER_CONSUMES_INTEGRATED_PAYLOAD_SHA_PASS'"
    )
    script=script.replace(expected_line,extra,1)
    require(script.count("R28_ONE_OWNER_APPROVAL_THROUGH_BOOTSTRAP_AND_NEW_VBS_COMPLETE_PASS")==1 and
            script.count("R28_FINAL_NEW_AGENT_NOT_SINGLE")==1 and
            script.count("R28_OFFICIAL_JOURNAL_NOT_COMMITTED")==1 and
            script.count("FUTURE_OFFICIAL_BOOTSTRAP_HOSTED_SCRATCH_ONLY_CLEANUP_PASS")==1 and
            script.count("Stop-Process -Id $newResident.Id")==1,
            "R43_EXACT_ORIGINAL_R28_LIFECYCLE_TEST_CODE_NOT_PRESERVED")
    # Its runtime should never reference old shortcut-only stage as a source.
    require(old_receipt not in script and "python $script prepare" not in script,
            "R43_OLD_REVIEW_STAGE_STILL_ACTIVE")
    prepare=r'''from importlib import util
from pathlib import Path
root=Path.cwd()
source=root/"validation/spotify-exit-immediate-maintenance-HOLD/rehearse-localhost-bootstrap-future.py"
spec=util.spec_from_file_location("spotify_r43_original_hosted_prepare",source)
if spec is None or spec.loader is None:
    raise RuntimeError("R43_ORIGINAL_HOSTED_PREPARER_UNAVAILABLE")
module=util.module_from_spec(spec)
spec.loader.exec_module(module)
module.STAGED=root/"validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging-combined"
module.prepare()
'''
    power=dest/"spotify-r43-integrated-real-owner-cutover.ps1"
    py=dest/"spotify-r43-integrated-prepare.py"
    require(not power.exists() and not py.exists(),
        "R43_SCRATCH_TEST_SCRIPTS_ALREADY_EXIST")
    with power.open("x",encoding="utf-8",newline="\n") as f:
        f.write(script)
    with py.open("x",encoding="utf-8",newline="\n") as f:
        f.write(prepare)
    print("R43_REUSED_ACTUAL_R28_HOSTED_PROCESS_CUTOVER_SCRIPT=SOURCE_PINNED")
    print("R43_ONLY_COMBINED_STAGE_LOCATORS_AND_POSITIVE_SHA_ASSERTION_CHANGED=YES")
    print("R43_R28_SCRATCH_SCRIPT_SHA256="+hashlib.sha256(power.read_bytes()).hexdigest())
    print("R43_USER_PC_AND_PUBLIC_MAIN=UNTOUCHED")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No arguments.")
    run()
