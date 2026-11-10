"""R62 HOLD: prove the R58 rapid-restart resident still detects a Spotify exit
through the genuine 60-second polling path after an injected WMI subscription
loss.  Only a SHA-pinned copy of the resident VBS is modified inside hosted
Windows scratch; the released candidate, user machines, WMI service and
production repository remain untouched.

This is an injected WMI-source-loss acceptance, NOT a real Windows WMI outage
and NOT a validation of real user Spotify audio or reboot behavior.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
R44 = HERE / "accept-real-vbs-spotifyexit-event-R44-HOLD.ps1"
R44_BLOB = "1c8f9d46fcb6a3c035a5dabf2b51e043932ce9c4"
R58 = HERE / "out/rapid-restart-r58/spotify-control-agent.vbs"
R58_SHA = "8eb76416848a7da3e3ce02a7d169655f676ea109f9f9a050d94e364e48182874"
OLD_R44_VBS = "da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
SCRATCH_DIR = HERE / "out/wmi-event-loss-R62"
INJECTED_VBS = SCRATCH_DIR / "spotify-control-agent.vbs"
TEST = Path(os.environ.get("RUNNER_TEMP", "/nonexistent")) / "spotify-r62-wmi-loss-polling.ps1"

def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()

def change_one(source: str, before: str, after: str, label: str) -> str:
    if source.count(before) != 1:
        raise RuntimeError("R62_SOURCE_ANCHOR_DRIFT_" + label)
    return source.replace(before, after, 1)

def run() -> None:
    if (os.environ.get("GITHUB_ACTIONS") != "true" or
        os.environ.get("RUNNER_OS") != "Windows" or
        os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted"):
        raise RuntimeError("R62_ONLY_HOSTED_WINDOWS_SCRATCH")
    blob = subprocess.run(
        ["git", "rev-parse", ":" + R44.relative_to(ROOT).as_posix()],
        cwd=ROOT, capture_output=True, check=False, timeout=15
    )
    if blob.returncode or blob.stdout.decode("ascii").strip() != R44_BLOB:
        raise RuntimeError("R62_ORIGINAL_R44_TEST_CHANGED")
    original = R58.read_bytes()
    if sha(original) != R58_SHA or len(original) != 8905:
        raise RuntimeError("R62_NEWEST_R58_VBS_SOURCE_PIN_MISMATCH")
    bom = b"\xef\xbb\xbf" if original.startswith(b"\xef\xbb\xbf") else b""
    content = original[len(bom):].decode("utf-8")
    linebreak = "\r\n" if "\r\n" in content else "\n"
    normalized = content.replace("\r\n", "\n")
    anchor = 'If Not startSource Is Nothing Then LogLine "WMI START EVENT subscribed"'
    injected = change_one(
        normalized, anchor,
        anchor + '\n' +
        "' R62 HOSTED SCRATCH ONLY: simulate both event notification sources" + '\n' +
        "Set exitSource = Nothing" + '\n' +
        "Set startSource = Nothing" + '\n' +
        'LogLine "R62 HOSTED WMI EVENT SOURCE INJECTION"',
        "ONE_IN_MEMORY_EVENT_LOSS_INJECTION")
    if (injected == normalized or
        injected.count('RunTick "SpotifyExit"') != 1 or
        injected.count('RunTick "Startup"') != 1 or
        injected.count('RunTick "Periodic"') != 1 or
        "WScript.Sleep POLL_MS" not in injected or
        "Const POLL_MS = 60000" not in injected or
        "Const EXIT_SETTLE_MS = 2500" not in injected or
        "shell.CurrentDirectory = rootDir" not in injected):
        raise RuntimeError("R62_POLLING_OR_DISPATCH_CONTRACT_DRIFT")
    altered = bom + injected.replace("\n", linebreak).encode("utf-8")
    if SCRATCH_DIR.exists() or TEST.exists():
        raise RuntimeError("R62_SCRATCH_ALREADY_EXISTS_NO_REPLACE")
    SCRATCH_DIR.mkdir(parents=True, exist_ok=False)
    with INJECTED_VBS.open("xb") as fh:
        fh.write(altered)

    old = R44.read_text(encoding="utf-8")
    old = change_one(old, "Spotify Control R44 Actual Exit Event",
                     "Spotify Control R62 Hosted Event Loss", "SCRATCH_NAME")
    old = change_one(
        old, "validation/spotify-exit-immediate-maintenance-HOLD/out/integrated/spotify-control-agent.vbs",
        "validation/spotify-exit-immediate-maintenance-HOLD/out/wmi-event-loss-R62/spotify-control-agent.vbs",
        "USE_ONLY_TEST_OWNED_INJECTED_VBS")
    old = change_one(old, "'" + OLD_R44_VBS + "'", "'" + sha(altered) + "'",
                     "TEST_OWNED_BYTES_ONLY")
    old = change_one(
        old, "if(-not(WaitEvent 'SpotifyExit' 105)){",
        "if(-not(WaitEvent 'SpotifyExit' 105)){",
        "FULL_UNACCELERATED_POLL_WATCHDOG")
    evidence = """  # R62 is a simulated notification-source loss; require both original
  # real WMI subscriptions before the scratch-only injection, then prove
  # the unchanged 60s polling loop produced exactly one dispatch.
  $trace=@(Get-Content -LiteralPath $hostLog -ErrorAction Stop)
  foreach($fragment in @('WMI STOP EVENT subscribed',
                          'WMI START EVENT subscribed',
                          'R62 HOSTED WMI EVENT SOURCE INJECTION')){
    if(@($trace | Where-Object {$_ -like ('*'+$fragment+'*')}).Count -ne 1){
      throw 'R62_EVENT_SUBSCRIPTION_OR_SCRATCH_INJECTION_NOT_PROVEN'
    }
  }
  if((EventCount 'SpotifyExit') -ne 1){
    throw 'R62_FALLBACK_EVENT_DUPLICATE_OR_ABSENT'
  }
  Write-Host 'R62_R58_REAL_WSCRIPT_60S_POLL_FALLBACK_AFTER_INJECTED_EVENT_LOSS=PASS'
  Write-Host 'R62_INJECTION_IS_SCRATCH_ONLY_REAL_WMI_OUTAGE=NOT_PROVEN'
  Write-Host 'R62_REAL_PC_SPOTIFY_AUDIO_OR_REBOOT=NOT_TESTED'
"""
    marker = "  Write-Host 'R44_AUTHENTIC_WSCRIPT_TO_POWERSHELL_AGENTTICK_SPOTIFYEXIT=PASS'"
    old = change_one(old, marker, evidence + marker, "FALLBACK_EVIDENCE_ADMISSION")
    old = change_one(old, 
        "  Write-Host 'R44_ACTUAL_WMI_SPOTIFY_EXIT_VBS_SETTLE_AND_EVENT=PASS'",
        "  Write-Host 'R62_INJECTED_WMI_LOSS_POLL_SPOTIFY_EXIT_VBS_SETTLE=PASS'",
        "NO_FALSE_REAL_WMI_SUCCESS_LABEL")
    if OLD_R44_VBS in old or "out/integrated/spotify-control-agent.vbs" in old:
        raise RuntimeError("R62_TEST_WOULD_USE_OLDER_RESIDENT")
    with TEST.open("x", encoding="utf-8", newline="\n") as fh:
        fh.write(old)
    print("R62_LATEST_R58_VBS_PARENT_EXACT_SHA256=PASS")
    print("R62_ONLY_SCRATCH_COPY_INJECTED_WMI_EVENT_LOSS=YES")
    print("R62_REAL_60_SECOND_POLL_FALLBACK_WINDOWS_TEST_PREPARED=YES")
    print("R62_MAIN_RELEASE_OWNER_PC_WMI_SERVICE=UNCHANGED")

if __name__ == "__main__":
    if sys.argv[1:]:
        raise SystemExit("R62 no arguments")
    run()
