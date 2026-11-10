"""R66 HOLD: repair WMI service-object staleness and query-failure false exits.
Rebuild from exact native-accepted R63 agent only. No real PC, release, or
product settings are touched. Keep old Startup behavior, original cadence,
WMI event timestamps and owner's maintenance authority.
"""
from __future__ import annotations
import hashlib, json, os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
BASE=HERE/"out/selfheal-r63/spotify-control-agent.vbs"
OUT=HERE/"out/rebind-r66"
PARENT_SHA="82f4547a33149a7db2d39b24745c0e3a5a04646bed693c5a6e93d01625798acc"
PARENT_SIZE=10477

def digest(b): return hashlib.sha256(b).hexdigest()
def once(s,a,b,label):
    if s.count(a)!=1:raise RuntimeError("R66_SOURCE_ANCHOR_DRIFT_"+label)
    return s.replace(a,b,1)

def run():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R66_HOSTED_WINDOWS_ONLY")
    raw=BASE.read_bytes()
    if (len(raw),digest(raw))!=(PARENT_SIZE,PARENT_SHA):
        raise RuntimeError("R66_PARENT_R63_EXACT_SOURCE_MISMATCH")
    if OUT.exists():raise RuntimeError("R66_OUTPUT_PREEXISTS_NO_REPLACE")
    bom=b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    t=raw[len(bom):].decode("utf-8")
    nl="\r\n" if "\r\n" in t else "\n"
    t=t.replace("\r\n","\n")
    t=once(t,"Dim nextSubscriptionRecovery, retryError",
        "Dim nextSubscriptionRecovery, retryError\n"
        "Dim wmiNeedsReconnect, wmiLastQueryValid, sessionWitness\n"
        "Dim reconnectWmi, reconnectProcesses, reconnectProcess, reconnectError",
        "VARIABLES")
    t=once(t,'nextSubscriptionRecovery = DateAdd("s", 60, Now)\nlastExitStamp = CDbl(0)',
        'nextSubscriptionRecovery = DateAdd("s", 60, Now)\n'
        'wmiNeedsReconnect = False\nwmiLastQueryValid = False\n'
        'sessionWitness = False\nlastExitStamp = CDbl(0)',"INIT_STATE")
    t=once(t,"wasRunning = IsSpotifyRunning()\nlastExitTick =",
        "wasRunning = IsSpotifyRunning()\n"
        "If wmiLastQueryValid And wasRunning Then sessionWitness = True\n"
        "lastExitTick =", "INITIAL_VERIFIED_RUNNING")
    t=once(t,'ElseIf eventError <> &H80043001 Then\n'
        '            LogLine "WMI STOP EVENT lost, 60-second polling fallback."',
        'ElseIf eventError <> &H80043001 Then\n'
        '            wmiNeedsReconnect = True\n'
        '            LogLine "WMI STOP EVENT lost, 60-second polling fallback."',
        "LOST_STOP_INVALIDATES_WMI")
    t=once(t,'ElseIf startError <> 0 Then\n'
        '                LogLine "WMI START EVENT lost, original debounce retained."',
        'ElseIf startError <> 0 Then\n'
        '                wmiNeedsReconnect = True\n'
        '                LogLine "WMI START EVENT lost, original debounce retained."',
        "LOST_START_INVALIDATES_WMI")
    t=once(t,"    If gotStopEvent Then wasRunning = True\n    If gotStopEvent Or",
        "    If gotStopEvent Then\n"
        "        wasRunning = True\n"
        "        sessionWitness = True\n"
        "    End If\n    If gotStopEvent Or", "REAL_STOP_EVIDENCE")
    t=once(t,'        nowRunning = IsSpotifyRunning()\n\n'
        '        If wasRunning And (Not nowRunning) Then',
        '        nowRunning = IsSpotifyRunning()\n'
        '        If wmiLastQueryValid And nowRunning Then sessionWitness = True\n\n'
        '        If wasRunning And (Not nowRunning) And wmiLastQueryValid And sessionWitness Then',
        "BLOCK_FALSE_EXIT_WITHOUT_HEALTHY_RUNNING_WITNESS")
    t=once(t,'                If Not IsSpotifyRunning() Then',
        '                If (Not IsSpotifyRunning()) And wmiLastQueryValid Then',
        "SETTLE_WMI_HEALTH_REQUIRED")
    t=once(t,'        wasRunning = nowRunning\n        nextSafetyProbe =',
        '        If wmiLastQueryValid Then\n'
        '            wasRunning = nowRunning\n'
        '            If Not nowRunning Then sessionWitness = False\n'
        '        Else\n'
        '            wasRunning = True\n'
        '        End If\n        nextSafetyProbe =',
        "PRESERVE_WITNESS_DURING_UNKNOWN_STATUS")

    begin=t.index("    ' While running with either notification source down")
    end=t.index('    If Now >= nextPeriodic Then',begin)
    old=t[begin:end]
    if old.count("If startSource Is Nothing Then")!=1 or old.count("If exitSource Is Nothing Then")!=1:
        raise RuntimeError("R66_EXPECTED_ONE_BOUNDED_R63_RETRY_BLOCK")
    replacement='''    ' Recover from notification and service-object loss with one bounded
    ' check per minute. Never declare Spotify closed while WMI is uncertain.
    If (exitSource Is Nothing Or startSource Is Nothing Or wmiNeedsReconnect) And Now >= nextSubscriptionRecovery Then
        nextSubscriptionRecovery = DateAdd("s", 60, Now)
        If wmiNeedsReconnect Then
            Set reconnectWmi = Nothing
            Set reconnectProcesses = Nothing
            reconnectError = 1
            On Error Resume Next
            Err.Clear
            Set reconnectWmi = GetObject("winmgmts:{impersonationLevel=impersonate}!\\\\.\\root\\cimv2")
            reconnectError = Err.Number
            Err.Clear
            If reconnectError = 0 And Not reconnectWmi Is Nothing Then
                Set reconnectProcesses = reconnectWmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='Spotify.exe'")
                reconnectError = Err.Number
                Err.Clear
                If reconnectError = 0 And Not reconnectProcesses Is Nothing Then
                    For Each reconnectProcess In reconnectProcesses
                        Exit For
                    Next
                    reconnectError = Err.Number
                    Err.Clear
                Else
                    reconnectError = 1
                End If
            Else
                reconnectError = 1
            End If
            On Error GoTo 0
            If reconnectError = 0 Then
                Set wmi = reconnectWmi
                Set exitSource = Nothing
                Set startSource = Nothing
                newerSessionObserved = False
                wmiNeedsReconnect = False
                LogLine "WMI SERVICE fresh binding and process query verified"
            Else
                LogLine "WMI SERVICE binding still unavailable, keep fail-closed"
            End If
        End If
        If Not wmiNeedsReconnect Then
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
    End If

'''
    t=t[:begin]+replacement+t[end:]
    function=t[t.index("Function IsSpotifyRunning()"):]
    if function.count("End Function")!=1:raise RuntimeError("R66_WMI_QUERY_TAIL_CHANGED")
    newfunction='''Function IsSpotifyRunning()
    Dim processes, p
    IsSpotifyRunning = True
    wmiLastQueryValid = False

    On Error Resume Next
    Err.Clear
    Set processes = wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='Spotify.exe'")
    If Err.Number <> 0 Then
        wmiNeedsReconnect = True
        LogLine "WMI QUERY ERROR fail-closed-as-running err=" & CStr(Err.Number) & " " & Err.Description
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If

    IsSpotifyRunning = False
    Err.Clear
    For Each p In processes
        IsSpotifyRunning = True
        Exit For
    Next
    If Err.Number <> 0 Then
        wmiNeedsReconnect = True
        IsSpotifyRunning = True
        LogLine "WMI ENUMERATION ERROR fail-closed-as-running err=" & CStr(Err.Number)
        Err.Clear
    Else
        wmiLastQueryValid = True
    End If
    On Error GoTo 0
End Function'''
    t=t[:t.index("Function IsSpotifyRunning()")]+newfunction
    for fixed in ('Const POLL_MS = 60000','Const EXIT_SETTLE_MS = 2500',
                  'Const EXIT_DEBOUNCE_SECONDS = 60','WScript.Sleep POLL_MS',
                  'shell.CurrentDirectory = rootDir','RunTick "Startup"',
                  'RunTick "Periodic"','RunTick "SpotifyExit"'):
        if t.count(fixed)!=1:raise RuntimeError("R66_ORIGINAL_FIXED_CONTRACT_CHANGED_"+fixed)
    candidate=bom+t.replace("\n",nl).encode("utf-8")
    if digest(candidate)==PARENT_SHA:
        raise RuntimeError("R66_EXPECTED_FUNCTIONAL_CHANGE_MISSING")
    OUT.mkdir(parents=True,exist_ok=False)
    with (OUT/"spotify-control-agent.vbs").open("xb") as file:file.write(candidate)
    receipt={"mode":"R66_FRESH_WMI_SERVICE_REBIND_AND_NO_FALSE_EXIT_HOLD",
             "r63_parent_sha256":PARENT_SHA,"agent_sha256":digest(candidate),
             "agent_size":len(candidate),"retry_seconds":60,
             "release_published":False,"user_pc_modified":False}
    (OUT/"receipt.json").write_text(json.dumps(receipt,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R66_R63_PARENT_EXACT_PINNED=PASS")
    print("R66_FRESH_WMI_SERVICE_QUERY_VERIFICATION_BEFORE_USE=BUILT")
    print("R66_POLL_AND_OWNER_AUTOMATION_AUTHORITY=UNCHANGED")
    print("R66_AGENT_SHA256="+digest(candidate))
    print("R66_AGENT_SIZE="+str(len(candidate)))

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("R66 no arguments")
    run()
