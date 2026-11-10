"""R63 HOLD: bounded self-healing WMI notification subscriptions.

Build from the exact R58 native-accepted resident; never change its
60-second fallback, 2.5-second settle, session timestamps, or owner
maintenance authority. When one WMI subscription is lost, attempt a
re-subscription at most once every 60 seconds while the live resident
continues polling. This does not prove recovery from a full WMI service
crash (the previously obtained SWbemServices connection could be stale).

No published code, installed Spotify, user PC or release is changed.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
BASE=HERE/"out/rapid-restart-r58/spotify-control-agent.vbs"
OUT=HERE/"out/selfheal-r63"
PARENT_SHA="8eb76416848a7da3e3ce02a7d169655f676ea109f9f9a050d94e364e48182874"
PARENT_SIZE=8905

def digest(data: bytes)->str:
    return hashlib.sha256(data).hexdigest()

def once(text: str, old: str, new: str, label: str)->str:
    if text.count(old)!=1:
        raise RuntimeError("R63_SOURCE_ANCHOR_DRIFT_"+label)
    return text.replace(old,new,1)

def build()->None:
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R63_HOSTED_WINDOWS_ONLY")
    src=BASE.read_bytes()
    if (len(src),digest(src))!=(PARENT_SIZE,PARENT_SHA):
        raise RuntimeError("R63_EXACT_R58_PROVENANCE_MISMATCH")
    if OUT.exists():
        raise RuntimeError("R63_OUTPUT_PREEXISTS_NO_REPLACE")
    bom=b"\xef\xbb\xbf" if src.startswith(b"\xef\xbb\xbf") else b""
    val=src[len(bom):].decode("utf-8")
    nl="\r\n" if "\r\n" in val else "\n"
    val=val.replace("\r\n","\n")
    val=once(val,
       "Dim stopStamp, newerSessionObserved, startDrainCount",
       "Dim stopStamp, newerSessionObserved, startDrainCount\nDim nextSubscriptionRecovery, retryError",
       "EXACT_OPTION_EXPLICIT_DECLARATION")
    val=once(val,
       'If Not startSource Is Nothing Then LogLine "WMI START EVENT subscribed"\nlastExitStamp = CDbl(0)',
       'If Not startSource Is Nothing Then LogLine "WMI START EVENT subscribed"\n'
       'nextSubscriptionRecovery = DateAdd("s", 60, Now)\nlastExitStamp = CDbl(0)',
       "RECOVERY_CADENCE_INITIALIZED_AFTER_BOTH_SUBSCRIPTIONS")
    recovery='''    ' While running with either notification source down, keep the original
    ' safe polling or stop trace. Attempt at most once per minute. If the
    ' WMI service connection is stale, all errors are swallowed and the
    ' polling fallback continues; do not create additional resident hosts.
    If (exitSource Is Nothing Or startSource Is Nothing) And Now >= nextSubscriptionRecovery Then
        nextSubscriptionRecovery = DateAdd("s", 60, Now)
        If exitSource Is Nothing Then
            On Error Resume Next
            Err.Clear
            Set exitSource = wmi.ExecNotificationQuery("SELECT * FROM Win32_ProcessStopTrace WHERE ProcessName='Spotify.exe'")
            retryError = Err.Number
            Err.Clear
            On Error GoTo 0
            If retryError <> 0 Then Set exitSource = Nothing
            If Not exitSource Is Nothing Then LogLine "WMI STOP EVENT resubscribed"
        End If
        If startSource Is Nothing Then
            On Error Resume Next
            Err.Clear
            Set startSource = wmi.ExecNotificationQuery("SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='Spotify.exe'")
            retryError = Err.Number
            Err.Clear
            On Error GoTo 0
            If retryError <> 0 Then Set startSource = Nothing
            If Not startSource Is Nothing Then
                newerSessionObserved = False
                LogLine "WMI START EVENT resubscribed"
            End If
        End If
    End If

'''
    # This is the existing loop's end, after exit snapshots, before the
    # existing 12-hour periodic dispatch.
    val=once(val,
       '    If Now >= nextPeriodic Then\n        RunTick "Periodic"',
       recovery+'    If Now >= nextPeriodic Then\n        RunTick "Periodic"',
       "ONLY_ONCE_IN_EXISTING_LOOP")
    for item in ('Const POLL_MS = 60000','Const EXIT_SETTLE_MS = 2500',
                 'Const EXIT_DEBOUNCE_SECONDS = 60','WScript.Sleep POLL_MS',
                 'shell.CurrentDirectory = rootDir',
                 'Win32_ProcessStartTrace','Win32_ProcessStopTrace'):
        if item not in val:raise RuntimeError("R63_REQUIRED_UNCHANGED_CONTRACT_"+item)
    for event in ("Startup","SpotifyExit","Periodic"):
        if val.count('RunTick "'+event+'"')!=1:
            raise RuntimeError("R63_UNEXPECTED_RUN_TICK_"+event)
    agent=bom+val.replace("\n",nl).encode("utf-8")
    if agent==src:
        raise RuntimeError("R63_NO_FUNCTIONAL_DELTA")
    OUT.mkdir(parents=True,exist_ok=False)
    with (OUT/"spotify-control-agent.vbs").open("xb") as f:f.write(agent)
    meta={
      "mode":"R63_BOUND_WMI_EVENT_RESUBSCRIBE_ONCE_PER_60_SECONDS_HOLD",
      "r58_parent_sha256":PARENT_SHA,
      "agent_sha256":digest(agent),
      "agent_size":len(agent),
      "retry_seconds":60,
      "stop_and_start_both_recovered":True,
      "fallback_poll_unchanged":True,
      "user_pc_modified":False,"release_published":False
    }
    (OUT/"receipt.json").write_text(json.dumps(meta,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R63_VERIFIED_R58_PARENT=PASS")
    print("R63_SELF_HEAL_BOUNDED_RETRY_SECONDS=60")
    print("R63_NEW_WMI_RESIDENT_SHA256="+digest(agent))
    print("R63_NEW_WMI_RESIDENT_SIZE="+str(len(agent)))
    print("R63_OFFICIAL_STABLE_AND_REVIEW_BRANCHES=UNCHANGED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No arguments")
    build()
