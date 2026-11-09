"""R45 HOLD: an event-driven Spotify-exit resident, with original periodic
fallback and the exact previously-accepted WScript CWD guard.

This builds a SINGLE isolated next-candidate VBS by rewriting precisely the
resident event-monitor loop in the actual R37 integrated VBS. Does not touch
the v0.6.30 review/production release, addon, account, or local Windows.

Microsoft WMI Win32_ProcessStopTrace and SWbemEventSource.NextEvent support
event-based process termination and finite (5s) timeouts. Use an explicit
60-second safety snapshot as a missed-event fallback. If event subscription
fails, retain the unchanged 60-second polling behavior; no second process.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
SOURCE=HERE/"out"/"integrated"/"spotify-control-agent.vbs"
OUTPUT=HERE/"out"/"eventdriven-r45"
PIN_ORIGINAL="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
INITIAL_DECL="Dim probeMode, wasRunning, nowRunning, nextPeriodic, lastExitTick"
INITIAL_SAMPLE="wasRunning = IsSpotifyRunning()"
START_LOOP="Do\n"
END_LOOP="\nLoop"

def sha(b:bytes)->str:
    return hashlib.sha256(b).hexdigest()

def replace_exact(data:str,before:str,after:str,reason:str)->str:
    if data.count(before)!=1:
        raise RuntimeError(reason)
    return data.replace(before,after,1)

def run():
    raw=SOURCE.read_bytes()
    if sha(raw)!=PIN_ORIGINAL:
        raise RuntimeError("R45_PREVIOUS_ACCEPTED_INTEGRATED_VBS_NOT_PINNED")
    bom=b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    text=raw[len(bom):].decode("utf-8")
    newline="\r\n" if "\r\n" in text else "\n"
    txt=text.replace("\r\n","\n")
    txt=replace_exact(txt,INITIAL_DECL,
        INITIAL_DECL+"\nDim exitSource, exitEvent, eventError, gotStopEvent, nextSafetyProbe",
        "R45_VBS_OPTION_EXPLICIT_DECLARATIONS_CHANGED")
    subscription="""' Event-driven exit trace: receives the exact Spotify.exe stop event.
' If WMI notifications are unavailable, retain original 60-second polling.
Set exitSource = Nothing
On Error Resume Next
Err.Clear
Set exitSource = wmi.ExecNotificationQuery("SELECT * FROM Win32_ProcessStopTrace WHERE ProcessName='Spotify.exe'")
If Err.Number <> 0 Then
    LogLine "WMI STOP EVENT unavailable, 60-second polling fallback."
    Set exitSource = Nothing
End If
Err.Clear
On Error GoTo 0
If Not exitSource Is Nothing Then LogLine "WMI STOP EVENT subscribed"
nextSafetyProbe = DateAdd("s", 60, Now)
"""
    txt=replace_exact(txt,INITIAL_SAMPLE,subscription+INITIAL_SAMPLE,
        "R45_INITIAL_PROCESS_STATE_ANCHOR_CHANGED")
    start=txt.index("RunTick \"Startup\"")
    start=txt.index(START_LOOP,start)
    end=txt.index(END_LOOP,start)+len(END_LOOP)
    old=txt[start:end]
    for required in [
        "WScript.Sleep POLL_MS", "nowRunning = IsSpotifyRunning()",
        'RunTick "SpotifyExit"', 'RunTick "Periodic"',
        "wasRunning = nowRunning",
        "If DateDiff(\"s\", lastExitTick, Now) >= EXIT_DEBOUNCE_SECONDS Then",
        "If Not IsSpotifyRunning() Then"
    ]:
        if required not in old:
            raise RuntimeError("R45_STABLE_VBS_LOOP_ANCHOR_DRIFT")
    replacement="""Do
    gotStopEvent = False
    If exitSource Is Nothing Then
        ' Exact original slow fallback whenever WMI event delivery failed.
        WScript.Sleep POLL_MS
    Else
        ' Block efficiently until actual process stop, or for at most 5s.
        ' NextEvent timeout is the documented wbemErrTimedOut = &H80043001.
        Set exitEvent = Nothing
        On Error Resume Next
        Err.Clear
        Set exitEvent = exitSource.NextEvent(5000)
        eventError = Err.Number
        Err.Clear
        On Error GoTo 0
        If eventError = 0 Then
            If Not exitEvent Is Nothing Then
                If LCase(CStr(exitEvent.ProcessName)) = "spotify.exe" Then
                    gotStopEvent = True
                End If
            End If
        ElseIf eventError <> &H80043001 Then
            LogLine "WMI STOP EVENT lost, 60-second polling fallback."
            Set exitSource = Nothing
        End If
    End If

    ' A trace can capture a process started after our last safe snapshot.
    ' Confirm NO Spotify process remains before any maintenance, even if
    ' the event was from a different session or an intermediate child.
    If gotStopEvent Then wasRunning = True
    If gotStopEvent Or (Now >= nextSafetyProbe) Or (exitSource Is Nothing) Then
        nowRunning = IsSpotifyRunning()

        If wasRunning And (Not nowRunning) Then
            If DateDiff("s", lastExitTick, Now) >= EXIT_DEBOUNCE_SECONDS Then
                WScript.Sleep EXIT_SETTLE_MS
                If Not IsSpotifyRunning() Then
                    lastExitTick = Now
                    LogLine "SPOTIFY EXIT confirmed"
                    RunTick "SpotifyExit"
                End If
            End If
        End If

        wasRunning = nowRunning
        nextSafetyProbe = DateAdd("s", 60, Now)
    End If

    If Now >= nextPeriodic Then
        RunTick "Periodic"
        nextPeriodic = DateAdd("h", PERIODIC_HOURS, Now)
    End If
Loop"""
    txt=txt[:start]+replacement+txt[end:]
    txt=replace_exact(txt,"Const EXIT_SETTLE_MS = 8000",
        "Const EXIT_SETTLE_MS = 2500","R45_SETTLE_ANCHOR_NOT_UNIQUE")
    compiled=bom+txt.replace("\n",newline).encode("utf-8")
    if (compiled==raw or sha(compiled)==PIN_ORIGINAL or
        compiled.count(b'RunTick "SpotifyExit"')!=1 or
        compiled.count(b'RunTick "Periodic"')!=1 or
        compiled.count(b'RunTick "Startup"')!=1 or
        compiled.count(b'shell.CurrentDirectory = rootDir')!=1 or
        compiled.count(b"Win32_ProcessStopTrace")!=1):
        raise RuntimeError("R45_SOURCE_BOUNDARY_DUPLICATE_OR_MISSING")
    OUTPUT.mkdir(parents=True,exist_ok=True)
    if (OUTPUT/"spotify-control-agent.vbs").exists():
        raise RuntimeError("R45_EVENT_CANDIDATE_ALREADY_GENERATED_NO_OVERWRITE")
    (OUTPUT/"spotify-control-agent.vbs").write_bytes(compiled)
    report={
       "mode":"R45_WMI_STOP_EVENT_HOLD_NOT_PUBLISHED",
       "previous_integrated_vbs_sha256":sha(raw),
       "new_event_driven_vbs_sha256":sha(compiled),
       "new_vbs_size":len(compiled),
       "event_class":"Win32_ProcessStopTrace",
       "finite_event_wait_ms":5000,
       "event_settle_ms":2500,
       "safety_fallback_poll_ms":60000,
       "no_extra_processes":True,
       "agent_mutation_authority_changed":False,
       "production_source_changed":False,
       "publication_authorized":False
    }
    (OUTPUT/"receipt.json").write_text(json.dumps(report,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R45_WMI_EVENT_MONITOR_CANDIDATE_SHA256="+sha(compiled))
    print("R45_WMI_EVENT_MONITOR_CANDIDATE_BYTES="+str(len(compiled)))
    print("R45_ORIGINAL_CWD_GUARD_AND_STARTUP_PERIODIC_DISPATCH=EXACT_PRESERVED")
    print("R45_STANDARD_FALLBACK_60S_POLL_MAINTAINED=YES")
    print("R45_RELEASE=HOLD;REAL_PC_AND_PUBLIC_MAIN=UNCHANGED")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No arguments")
    run()
