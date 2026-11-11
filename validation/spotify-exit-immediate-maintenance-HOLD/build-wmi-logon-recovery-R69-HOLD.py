"""R69 HOLD: allow the resident to survive unavailable WMI at Windows logon.

From exact R66 13,069-byte candidate, preserve its fail-closed Spotify state,
real WMI session evidence and 60-second retry. The original initial WMI
GetObject call is now bounded by the existing VBScript Err mechanism. Failure
must not kill WScript, fake a SpotifyExit, or authorize any maintenance.
Do NOT publish, install, change any Windows service, or touch user files.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import sys

HERE=Path(__file__).resolve().parent
PARENT=HERE/"out/rebind-r66/spotify-control-agent.vbs"
OUTPUT=HERE/"out/boot-wmi-r69"
EXPECTED_PARENT_SHA="4eb5940bd68bfbde412db5deba3e9c37cecb19632c66d6ec61dc0791bf838eab"
EXPECTED_PARENT_SIZE=13069

def sha(x:bytes)->str:
    return hashlib.sha256(x).hexdigest()

def replace_once(s:str,old:str,new:str,label:str)->str:
    if s.count(old)!=1:raise RuntimeError("R69_SOURCE_ANCHOR_"+label)
    return s.replace(old,new,1)

def run()->None:
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R69_GITHUB_HOSTED_WINDOWS_ONLY")
    raw=PARENT.read_bytes()
    if (len(raw),sha(raw))!=(EXPECTED_PARENT_SIZE,EXPECTED_PARENT_SHA):
        raise RuntimeError("R69_R66_EXACT_PARENT_NOT_VERIFIED")
    if OUTPUT.exists():raise RuntimeError("R69_OUTPUT_PREEXISTS_NO_OVERWRITE")
    bom=b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    s=raw[len(bom):].decode("utf-8")
    newline="\r\n" if "\r\n" in s else "\n"
    s=s.replace("\r\n","\n")
    pattern=r"(?m)^[ \t]*Set[ \t]+wmi[ \t]*=[ \t]*GetObject\([^\r\n]*\)[ \t]*$"
    matches=list(re.finditer(pattern,s))
    if len(matches)!=1:raise RuntimeError("R69_ORIGINAL_BOOT_GETOBJECT_NOT_EXACT_ONCE")
    original=matches[0].group(0)
    if "winmgmts:" not in original.lower() or "cimv2" not in original.lower():
        raise RuntimeError("R69_LOCAL_WMI_OBJECT_SCOPE_CHANGED")
    # Preserve the exact old GetObject moniker and only guard its startup
    # failure. Do not change WMI service permissions or run as admin.
    guarded=('Set wmi = Nothing\n'
             'On Error Resume Next\n'
             'Err.Clear\n'
             +original+'\n'
             'If Err.Number <> 0 Then\n'
             '    Err.Clear\n'
             '    Set wmi = Nothing\n'
             '    LogLine "WMI STARTUP COM binding unavailable, polling and bounded recovery"\n'
             'End If\n'
             'On Error GoTo 0')
    s=replace_once(s,original,guarded,"INITIAL_MONIKER_WRAP")
    # Existing pre-R69 startup used a separate fail-fast gate for absent
    # WMI, even if GetObject itself was handled. Modify exactly that gate,
    # not unrelated initialization/file/owner failures.
    needle="WMI connect returned no service object."
    if s.count(needle)!=1:
        raise RuntimeError("R69_ORIGINAL_FATAL_NO_SERVICE_MESSAGE_NOT_UNIQUE")
    old_guard=re.search(
        r'(?im)^[ \t]*If[ \t]+wmi[ \t]+Is[ \t]+Nothing[ \t]+Then[ \t]*
    s=replace_once(s,
        'wmiNeedsReconnect = False\nwmiLastQueryValid = False\nsessionWitness = False',
        'wmiNeedsReconnect = (wmi Is Nothing)\n'
        'wmiLastQueryValid = False\nsessionWitness = False',
        "INITIAL_MISSING_OBJECT_ENABLES_EXISTING_R66_RECOVERY")
    # Set all three behaviors from the previously accepted R66; no
    # duplicate loop, second process, alternate updater or per-app settings.
    for unchanged in (
        'Const POLL_MS = 60000',
        'Const EXIT_SETTLE_MS = 2500',
        'Const EXIT_DEBOUNCE_SECONDS = 60',
        'RunTick "Startup"',
        'RunTick "SpotifyExit"',
        'RunTick "Periodic"',
        'WScript.Sleep POLL_MS',
        'shell.CurrentDirectory = rootDir',
        'WMI SERVICE fresh binding and process query verified',
        'WMI QUERY ERROR fail-closed-as-running',
    ):
        if s.count(unchanged)!=1:
            raise RuntimeError("R69_UNEXPECTED_EXISTING_CONTRACT_"+unchanged)
    agent=bom+s.replace("\n",newline).encode("utf-8")
    if agent==raw:raise RuntimeError("R69_NO_FUNCTIONAL_CHANGE")
    OUTPUT.mkdir(parents=True,exist_ok=False)
    with (OUTPUT/"spotify-control-agent.vbs").open("xb") as f:f.write(agent)
    receipt={
      "mode":"R69_WMI_UNAVAILABLE_AT_LOGON_HOLD",
      "r66_parent_sha256":EXPECTED_PARENT_SHA,
      "agent_sha256":sha(agent),
      "agent_size":len(agent),
      "boot_missing_wmi_fails_closed":True,
      "retry_seconds":60,
      "main_sha256":"b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d",
      "user_pc_modified":False,"release_published":False
    }
    (OUTPUT/"receipt.json").write_text(
        json.dumps(receipt,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R69_EXACT_R66_PARENT_SHA256=PASS")
    print("R69_INITIAL_WMI_COM_FAILURE_RECOVERABLE=BUILT")
    print("R69_AGENT_SHA256="+sha(agent))
    print("R69_AGENT_SIZE="+str(len(agent)))
    print("R69_USER_PC_WMI_SERVICE_PUBLIC_MAIN=UNTOUCHED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("R69 no CLI options")
    run()
,
        s)
    if old_guard:
        begin=old_guard.start()
        end_marker=re.search(r'(?m)^End If[ \t]*
    s=replace_once(s,
        'wmiNeedsReconnect = False\nwmiLastQueryValid = False\nsessionWitness = False',
        'wmiNeedsReconnect = (wmi Is Nothing)\n'
        'wmiLastQueryValid = False\nsessionWitness = False',
        "INITIAL_MISSING_OBJECT_ENABLES_EXISTING_R66_RECOVERY")
    # Set all three behaviors from the previously accepted R66; no
    # duplicate loop, second process, alternate updater or per-app settings.
    for unchanged in (
        'Const POLL_MS = 60000',
        'Const EXIT_SETTLE_MS = 2500',
        'Const EXIT_DEBOUNCE_SECONDS = 60',
        'RunTick "Startup"',
        'RunTick "SpotifyExit"',
        'RunTick "Periodic"',
        'WScript.Sleep POLL_MS',
        'shell.CurrentDirectory = rootDir',
        'WMI SERVICE fresh binding and process query verified',
        'WMI QUERY ERROR fail-closed-as-running',
    ):
        if s.count(unchanged)!=1:
            raise RuntimeError("R69_UNEXPECTED_EXISTING_CONTRACT_"+unchanged)
    agent=bom+s.replace("\n",newline).encode("utf-8")
    if agent==raw:raise RuntimeError("R69_NO_FUNCTIONAL_CHANGE")
    OUTPUT.mkdir(parents=True,exist_ok=False)
    with (OUTPUT/"spotify-control-agent.vbs").open("xb") as f:f.write(agent)
    receipt={
      "mode":"R69_WMI_UNAVAILABLE_AT_LOGON_HOLD",
      "r66_parent_sha256":EXPECTED_PARENT_SHA,
      "agent_sha256":sha(agent),
      "agent_size":len(agent),
      "boot_missing_wmi_fails_closed":True,
      "retry_seconds":60,
      "main_sha256":"b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d",
      "user_pc_modified":False,"release_published":False
    }
    (OUTPUT/"receipt.json").write_text(
        json.dumps(receipt,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R69_EXACT_R66_PARENT_SHA256=PASS")
    print("R69_INITIAL_WMI_COM_FAILURE_RECOVERABLE=BUILT")
    print("R69_AGENT_SHA256="+sha(agent))
    print("R69_AGENT_SIZE="+str(len(agent)))
    print("R69_USER_PC_WMI_SERVICE_PUBLIC_MAIN=UNTOUCHED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("R69 no CLI options")
    run()
,s[old_guard.end():])
        if end_marker is None:
            raise RuntimeError("R69_ORIGINAL_WMI_ONLY_FATAL_GATE_UNCLOSED")
        end=old_guard.end()+end_marker.end()
        original_block=s[begin:end]
        if needle not in original_block:
            raise RuntimeError("R69_ORIGINAL_NULL_WMI_GATE_NOT_THE_FATAL_GATE")
        lines=[z.strip() for z in original_block.splitlines()]
        if any(z.startswith("If ") and not z.startswith("If wmi Is Nothing Then") for z in lines):
            raise RuntimeError("R69_STARTUP_FATAL_GATE_HAS_ADDITIONAL_NESTED_LOGIC")
        # Replace just the fatal WMI-unavailable gate by an explicit
        # bounded recovery marker. All other host-fatal rules are preserved.
        s=s[:begin] + ('If wmi Is Nothing Then\n'
             '    LogLine "WMI BOOTSTRAP missing service; existing 60s reconnect active"\n'
             'End If') + s[end:]
    else:
        idx=s.index(needle)
        print("R69_ORIGINAL_ONLY_BOOT_WMI_FATAL_CONTEXT="+
              repr(s[max(0,idx-240):idx+240]))
        raise RuntimeError("R69_ORIGINAL_WMI_FATAL_GATE_SHAPE_UNKNOWN")

    s=replace_once(s,
        'wmiNeedsReconnect = False\nwmiLastQueryValid = False\nsessionWitness = False',
        'wmiNeedsReconnect = (wmi Is Nothing)\n'
        'wmiLastQueryValid = False\nsessionWitness = False',
        "INITIAL_MISSING_OBJECT_ENABLES_EXISTING_R66_RECOVERY")
    # Set all three behaviors from the previously accepted R66; no
    # duplicate loop, second process, alternate updater or per-app settings.
    for unchanged in (
        'Const POLL_MS = 60000',
        'Const EXIT_SETTLE_MS = 2500',
        'Const EXIT_DEBOUNCE_SECONDS = 60',
        'RunTick "Startup"',
        'RunTick "SpotifyExit"',
        'RunTick "Periodic"',
        'WScript.Sleep POLL_MS',
        'shell.CurrentDirectory = rootDir',
        'WMI SERVICE fresh binding and process query verified',
        'WMI QUERY ERROR fail-closed-as-running',
    ):
        if s.count(unchanged)!=1:
            raise RuntimeError("R69_UNEXPECTED_EXISTING_CONTRACT_"+unchanged)
    agent=bom+s.replace("\n",newline).encode("utf-8")
    if agent==raw:raise RuntimeError("R69_NO_FUNCTIONAL_CHANGE")
    OUTPUT.mkdir(parents=True,exist_ok=False)
    with (OUTPUT/"spotify-control-agent.vbs").open("xb") as f:f.write(agent)
    receipt={
      "mode":"R69_WMI_UNAVAILABLE_AT_LOGON_HOLD",
      "r66_parent_sha256":EXPECTED_PARENT_SHA,
      "agent_sha256":sha(agent),
      "agent_size":len(agent),
      "boot_missing_wmi_fails_closed":True,
      "retry_seconds":60,
      "main_sha256":"b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d",
      "user_pc_modified":False,"release_published":False
    }
    (OUTPUT/"receipt.json").write_text(
        json.dumps(receipt,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R69_EXACT_R66_PARENT_SHA256=PASS")
    print("R69_INITIAL_WMI_COM_FAILURE_RECOVERABLE=BUILT")
    print("R69_AGENT_SHA256="+sha(agent))
    print("R69_AGENT_SIZE="+str(len(agent)))
    print("R69_USER_PC_WMI_SERVICE_PUBLIC_MAIN=UNTOUCHED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("R69 no CLI options")
    run()
