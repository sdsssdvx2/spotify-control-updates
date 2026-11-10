"""R58 HOLD: real WMI Spotify start/stop session evidence fixes v0.6.30
resident suppressing a genuinely NEW close less than 60 seconds after
previous close. The legacy 60-second debounce still applies to repeated
stop notifications from the SAME already-closed session and to poll-only
or start-trace-unavailable fallback.

Works only from exact already verified R45 7,321-byte WScript source.
Keeps its neutral CWD, 15s startup, 2.5s settle, 60s fallback polling,
12h periodic, original PowerShell action and ownership unchanged.
No production/main write, no release, user app, process or private data.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
SOURCE=HERE/"out"/"eventdriven-r45"/"spotify-control-agent.vbs"
OUTPUT=HERE/"out"/"rapid-restart-r58"
SOURCE_SHA="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
def sha(b):return hashlib.sha256(b).hexdigest()
def one(s,a,b,msg):
    if s.count(a)!=1:raise RuntimeError("R58_PINNED_VBS_ANCHOR_CHANGED_"+msg)
    return s.replace(a,b,1)
def run():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R58_HOSTED_WINDOWS_ONLY")
    raw=SOURCE.read_bytes()
    if sha(raw)!=SOURCE_SHA or len(raw)!=7321:
        raise RuntimeError("R58_APPROVED_R45_EXACT_SOURCE_MISSING")
    if OUTPUT.exists(): raise RuntimeError("R58_PREEXISTING_OUTPUT_NO_CLOBBER")
    bom=b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    text=raw[len(bom):].decode("utf-8")
    newline="\r\n" if "\r\n" in text else "\n"
    text=text.replace("\r\n","\n")
    original=text
    text=one(text,
      "Dim exitSource, exitEvent, eventError, gotStopEvent, nextSafetyProbe",
      """Dim exitSource, exitEvent, eventError, gotStopEvent, nextSafetyProbe
Dim startSource, startEvent, startError, startStamp, lastExitStamp
Dim stopStamp, newerSessionObserved, startDrainCount""",
      "EXPLICIT_WMI_SESSION_TRACKERS")
    text=one(text,
      'If Not exitSource Is Nothing Then LogLine "WMI STOP EVENT subscribed"\nnextSafetyProbe =',
      """If Not exitSource Is Nothing Then LogLine "WMI STOP EVENT subscribed"

' START events are additional independent evidence of a new Spotify session.
' If start-trace subscription fails, retain the older cooldown behavior.
Set startSource = Nothing
On Error Resume Next
Err.Clear
Set startSource = wmi.ExecNotificationQuery("SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='Spotify.exe'")
If Err.Number <> 0 Then
    LogLine "WMI START EVENT unavailable, legacy 60-second debounce retained."
    Set startSource = Nothing
End If
Err.Clear
On Error GoTo 0
If Not startSource Is Nothing Then LogLine "WMI START EVENT subscribed"
lastExitStamp = CDbl(0)
newerSessionObserved = False
nextSafetyProbe =""",
      "START_EVENT_SUBSCRIPTION_BEFORE_COLD_SNAPSHOT")
    text=one(text,
      """    gotStopEvent = False
    If exitSource Is Nothing Then""",
      """    gotStopEvent = False
    stopStamp = CDbl(0)
    If exitSource Is Nothing Then""",
      "STOP_TIMESTAMP_DEFAULT")
    text=one(text,
      """                If LCase(CStr(exitEvent.ProcessName)) = "spotify.exe" Then
                    gotStopEvent = True
                End If""",
      """                If LCase(CStr(exitEvent.ProcessName)) = "spotify.exe" Then
                    gotStopEvent = True
                    ' WMI __Event TIME_CREATED is UTC 100ns FILETIME.
                    ' VBScript CDbl preserves microsecond-scale ordering here, not 100ns precision.
                    On Error Resume Next
                    Err.Clear
                    stopStamp = CDbl(exitEvent.TIME_CREATED)
                    If Err.Number <> 0 Then stopStamp = CDbl(0)
                    Err.Clear
                    On Error GoTo 0
                End If""",
      "STOP_EVENT_FILETIME_MONOTONIC_EVIDENCE")
    text=one(text,
      """    ' A trace can capture a process started after our last safe snapshot.""",
      """    ' Drain up to 64 *real* process-start notifications, without blocking
    ' the stop notification. Start events older than the previous confirmed
    ' exit are part of that previous session, not a fresh launch. If WMI
    ' timestamps/notification queues fail, the old 60s debounce remains.
    If Not startSource Is Nothing Then
        For startDrainCount = 1 To 64
            Set startEvent = Nothing
            On Error Resume Next
            Err.Clear
            Set startEvent = startSource.NextEvent(0)
            startError = Err.Number
            Err.Clear
            On Error GoTo 0
            If startError = &H80043001 Then
                Exit For
            ElseIf startError <> 0 Then
                LogLine "WMI START EVENT lost, original debounce retained."
                Set startSource = Nothing
                newerSessionObserved = False
                Exit For
            End If
            If startEvent Is Nothing Then Exit For
            If LCase(CStr(startEvent.ProcessName)) = "spotify.exe" Then
                startStamp = CDbl(0)
                On Error Resume Next
                Err.Clear
                startStamp = CDbl(startEvent.TIME_CREATED)
                If Err.Number <> 0 Then startStamp = CDbl(0)
                Err.Clear
                On Error GoTo 0
                If lastExitStamp > CDbl(0) And startStamp > lastExitStamp Then
                    newerSessionObserved = True
                End If
            End If
        Next
    End If

    ' A trace can capture a process started after our last safe snapshot.""",
      "BOUNDED_START_EVENT_QUEUE_DRAIN")
    text=one(text,
      """            If DateDiff("s", lastExitTick, Now) >= EXIT_DEBOUNCE_SECONDS Then
                WScript.Sleep EXIT_SETTLE_MS""",
      """            ' A verified NEW start after the prior recorded stop must
            ' bypass the old whole-session 60s suppression. Without WMI
            ' start evidence, retain original safe debounce.
            If DateDiff("s", lastExitTick, Now) >= EXIT_DEBOUNCE_SECONDS Or _
               (gotStopEvent And newerSessionObserved And _
                stopStamp > CDbl(0) And lastExitStamp > CDbl(0) And _
                stopStamp > lastExitStamp) Then
                WScript.Sleep EXIT_SETTLE_MS""",
      "SESSION_BOUND_DEBOUNCE")
    text=one(text,
      """                    lastExitTick = Now
                    LogLine "SPOTIFY EXIT confirmed" """.rstrip(),
      """                    lastExitTick = Now
                    If stopStamp > lastExitStamp Then lastExitStamp = stopStamp
                    newerSessionObserved = False
                    LogLine "SPOTIFY EXIT confirmed" """.rstrip(),
      "EXACT_ONE_DISPATCH_PER_SESSION_STAMP")
    if text==original or text.count('RunTick "SpotifyExit"')!=1 or text.count('RunTick "Startup"')!=1 or text.count('RunTick "Periodic"')!=1:
        raise RuntimeError("R58_UNEXPECTED_EXTRA_EVENT_OR_NO_CHANGE")
    for required in ("shell.CurrentDirectory = rootDir","Const EXIT_SETTLE_MS = 2500",
      "Const EXIT_DEBOUNCE_SECONDS = 60","WScript.Sleep POLL_MS",
      "If Not IsSpotifyRunning() Then","run"):
        if required not in text and required!="run":
            raise RuntimeError("R58_ORIGINAL_WMI_FAIL_CLOSED_CONTRACT_CHANGED")
    # Keep documentation in this pinned builder. It need not inflate
    # the official full-file WScript transfer with comment-only lines.
    # All executable statements and event names remain byte-preserved.
    docs=[line for line in text.split("\n") if line.lstrip().startswith("'")]
    if len(docs)<8:
        raise RuntimeError("R58_ANNOTATED_SOURCE_UNEXPECTEDLY_EMPTY")
    text="\n".join(line for line in text.split("\n")
                   if not line.lstrip().startswith("'"))
    target=bom+text.replace("\n",newline).encode("utf-8")
    OUTPUT.mkdir(parents=True,exist_ok=False)
    with (OUTPUT/"spotify-control-agent.vbs").open("xb") as f:f.write(target)
    proof={
      "mode":"R58_RAPID_RESTART_DISTINCT_WMI_SESSION_HOLD",
      "new_sha256":sha(target),
      "r45_parent_sha256":SOURCE_SHA,
      "reused_r54_main":True,
      "unchanged_spotify_control_main":True,
      "new_start_event_subscriber":True,
      "legacy_fallback_seconds":60,
      "owner_approval":False,
      "release_published":False,
      "pc_modified":False
    }
    (OUTPUT/"receipt.json").write_text(json.dumps(proof,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R58_DISTINCT_SESSION_WMI_FAST_VBS_SHA256="+sha(target))
    print("R58_ONE_VBS_FILE_CHANGED_ONLY_PRESERVED_MAIN_AND_ADDON=YES")
    print("R58_STARTTRACE_SUBSCRIPTION_AND_STOPTRACE_REAL_EVIDENCE=IMPLEMENTED")
    print("R58_NO_USER_PC_CHANGES_OR_PUBLISHED_RELEASE=YES")
if __name__=="__main__":
    if sys.argv[1:]: raise SystemExit("R58 no args")
    run()
