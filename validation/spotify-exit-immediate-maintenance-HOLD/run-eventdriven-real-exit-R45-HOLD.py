"""R45: replay the immutable R44 real WScript / WMI fake-Spotify acceptance
with an event-driven VBS candidate and a bounded (<12s) exit budget.

Only the source VBS locator, exact SHA pin, test-owned scratch directory,
exit timeout and timing observation change from the already-passing R44 test.
No installation, user data or production code modification.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
EXISTING=HERE/"accept-real-vbs-spotifyexit-event-R44-HOLD.ps1"
PIN_R44_BLOB="1c8f9d46fcb6a3c035a5dabf2b51e043932ce9c4"
ORIGINAL_PIN="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
CANDIDATE=HERE/"out"/"eventdriven-r45"/"spotify-control-agent.vbs"
SRC_OLD="validation/spotify-exit-immediate-maintenance-HOLD/out/integrated/spotify-control-agent.vbs"
SRC_NEW="validation/spotify-exit-immediate-maintenance-HOLD/out/eventdriven-r45/spotify-control-agent.vbs"

def change(source,before,after,code):
    if source.count(before)!=1:
        raise RuntimeError(code)
    return source.replace(before,after,1)

def run():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R45_GITHUB_HOSTED_WINDOWS_ONLY")
    check=subprocess.run(["git","rev-parse",
        ":"+EXISTING.relative_to(ROOT).as_posix()],cwd=ROOT,
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
    if check.returncode or check.stdout.decode("ascii").strip()!=PIN_R44_BLOB:
        raise RuntimeError("R45_R44_SUCCESSFUL_SOURCE_BLOB_CHANGED")
    receipt=json.loads((CANDIDATE.parent/"receipt.json").read_text("utf-8"))
    bytes_=CANDIDATE.read_bytes()
    candidate_sha=hashlib.sha256(bytes_).hexdigest()
    if (receipt["new_event_driven_vbs_sha256"]!=candidate_sha or
        receipt["previous_integrated_vbs_sha256"]!=ORIGINAL_PIN or
        receipt["mode"]!="R45_WMI_STOP_EVENT_HOLD_NOT_PUBLISHED"):
        raise RuntimeError("R45_EVENT_CANDIDATE_SHA_NOT_ACCEPTED")
    script=EXISTING.read_text("utf-8")
    script=change(script,SRC_OLD,SRC_NEW,"R45_SOURCE_LOCATOR_NOT_UNIQUE")
    script=change(script,"'"+ORIGINAL_PIN+"'","'"+candidate_sha+"'",
                  "R45_VBS_SHA_PIN_NOT_UNIQUE")
    script=change(script,
        "Spotify Control R44 Actual Exit Event",
        "Spotify Control R45 EventDriven Real Exit",
        "R45_SCRATCH_ROOT_NOT_UNIQUE")
    script=change(script,
        "  Stop-Process -Id $fake.Id -Force -ErrorAction Stop",
        "  Stop-Process -Id $fake.Id -Force -ErrorAction Stop",
        "R45_STOP_PROCESS_IDENTITY_ANCHOR_NOT_UNIQUE")
    script=change(script,
        "  if(-not(WaitEvent 'SpotifyExit' 105)){",
        "  $exitTimer=[Diagnostics.Stopwatch]::StartNew()\n"
        "  if(-not(WaitEvent 'SpotifyExit' 18)){",
        "R45_REAL_EXIT_WAIT_ANCHOR_MISSING")
    script=change(script,
        "  if((EventCount 'SpotifyExit') -ne 1){",
        "  $exitTimer.Stop()\n"
        "  if($exitTimer.Elapsed.TotalSeconds -gt 12){"
        "throw 'R45_EVENT_DRIVEN_EXIT_TOO_SLOW_OVER_12_SECONDS'}\n"
        "  Write-Host ('R45_REAL_WMI_STOP_EVENT_DISPATCH_SECONDS='+"
        "[Math]::Round($exitTimer.Elapsed.TotalSeconds,2))\n"
        "  if((EventCount 'SpotifyExit') -ne 1){",
        "R45_EXIT_TIME_PROOF_ANCHOR_CHANGED")
    if "WaitEvent 'SpotifyExit' 105" in script or ORIGINAL_PIN in script:
        raise RuntimeError("R45_STALE_R44_PAYLOAD_OR_DELAY")
    target=Path(os.environ["RUNNER_TEMP"]).resolve()/(
       "spotify-r45-eventdriven-real-exit.ps1")
    if target.exists() or not target.parent.is_dir():
        raise RuntimeError("R45_TEST_SCRIPT_ALREADY_EXISTS")
    with target.open("x",encoding="utf-8",newline="\n") as f:
        f.write(script)
    print("R45_REUSED_PROVEN_R44_REAL_PROCESS_TEST=SOURCE_PINNED")
    print("R45_EVENT_MONITOR_NEW_SHA256="+candidate_sha)
    print("R45_SCRIPT_EXIT_DISPATCH_DEADLINE_SECONDS=12")
    print("R45_RUNNER_SCRATCH_VBS_ONLY_NO_USER_APP=YES")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No arguments")
    run()
