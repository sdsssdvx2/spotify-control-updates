"""R54 HOLD: serialize read-only resident discovery against a separately
running manual Maintenance using the SAME existing per-user Windows mutex.

Prior R50 AgentTick held only Local/SpotifyControl-AgentTick-{SID}, while
manual Maintain held Local/SpotifyControl-Maintenance-{SID}. They could
concurrently read/write state. Acquire Maintenance inside the existing
AgentTick lease (non-blocking); nested Maintain re-enters same named mutex
on the SAME PowerShell thread, then releases once. On manual busy, skip
entire tick without discovery or state writes.

Change ONLY Invoke-ResidentAgentTick. Preserve the exact R50 Maintain
single-discovery function, fast WMI VBS and r17 Addon bytes. The official
full-file transport must be staged under a separate HOLD output.
"""
from __future__ import annotations
from importlib import util
import hashlib
import json
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
BASE=HERE/"out"/"single-discovery-R49"/"spotify-control.ps1"
ATTEST=HERE/"out"/"single-discovery-R49"/"attestation.json"
VBS=HERE/"out"/"eventdriven-r45"/"spotify-control-agent.vbs"
ADDON=HERE/"out"/"single-discovery-R49"/"addon-manager.ps1"
OUT=HERE/"out"/"shared-maintenance-R54"
STAGE=HERE/"out"/"release-staging-shared-maintenance-R54"
EXPECTED_PUBLISHED_PARENT="4ec5bc6c6612ab15fc297d474b193d228b9dab8eb5b79cd7b14042af5b72c93c"
EXPECTED_AGENT="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
EXPECTED_ADDON="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"

def sha(b:bytes):
    return hashlib.sha256(b).hexdigest()

def span(text:str,name:str):
    token="\nfunction "+name+" {"
    start=text.find(token)
    if start<0 or text.find(token,start+1)>=0:
        raise RuntimeError("R54_FUNCTION_SOURCE_NOT_UNIQUE_"+name)
    start+=1
    end=text.find("\nfunction ",start+2)
    if end<0:
        raise RuntimeError("R54_FUNCTION_END_NOT_FOUND_"+name)
    return start,end

def exactly(text:str,old:str,new:str,reason:str):
    if text.count(old)!=1:
        raise RuntimeError("R54_SOURCE_ANCHOR_DRIFT_"+reason)
    return text.replace(old,new,1)

def module(name:str,file:Path):
    spec=util.spec_from_file_location(name,file)
    if spec is None or spec.loader is None:
        raise RuntimeError("R54_FULL_FILE_TRANSPORT_UNAVAILABLE")
    m=util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def run():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R54_HOSTED_WINDOWS_ONLY")
    if OUT.exists() or STAGE.exists():
        raise RuntimeError("R54_STAGE_ALREADY_EXISTS_NO_CLOBBER")
    report=json.loads(ATTEST.read_text("utf-8"))
    old=BASE.read_bytes()
    vbs=VBS.read_bytes()
    addon=ADDON.read_bytes()
    version_bumped=old.replace(b'$ScriptVersion = "0.6.28"',
                              b'$ScriptVersion = "0.6.30"',1)
    if (sha(old)!=report["main_plain_sha256"] or
        sha(version_bumped)!=EXPECTED_PUBLISHED_PARENT or
        old.count(b'$ScriptVersion = "0.6.28"')!=1 or
        sha(vbs)!=EXPECTED_AGENT or sha(addon)!=EXPECTED_ADDON):
        raise RuntimeError("R54_PREVIOUS_SINGLE_CHECK_BYTES_NOT_PINNED")
    bom=b"\xef\xbb\xbf" if old.startswith(b"\xef\xbb\xbf") else b""
    src=old[len(bom):].decode("utf-8")
    nl="\r\n" if "\r\n" in src else "\n"
    norm=src.replace("\r\n","\n")
    start,end=span(norm,"Invoke-ResidentAgentTick")
    fn=norm[start:end]
    orig_fn=fn
    fn=exactly(fn,"    try {\n    $State = Ensure-StateShape (Load-State)",
       """    $maintenanceLease = $null
    try {
    # Cross-process manual Maintain must serialize with resident DISCOVERY,
    # not just the later mutation. Nonblocking avoids delaying Spotify.
    $maintenanceLease = Enter-SpotifyControlMutex -Purpose "Maintenance"
    if ($null -eq $maintenanceLease) {
        Write-Log "Resident tick deferred: another Maintenance owner holds the exclusive lease."
        return
    }
    $State = Ensure-StateShape (Load-State)""",
       "SHARED_MANUAL_MAINTENANCE_MUTEX_BEFORE_AGENT_DISCOVERY")
    fn=exactly(fn,
       """    } finally {
        Exit-SpotifyControlMutex -Mutex $lease
    }""",
       """    } finally {
        Exit-SpotifyControlMutex -Mutex $maintenanceLease
        Exit-SpotifyControlMutex -Mutex $lease
    }""",
       "RELEASE_BOTH_MUTEXES_ON_ALL_PATHS")
    if (fn.count('Enter-SpotifyControlMutex -Purpose "AgentTick"')!=1 or
        fn.count('Enter-SpotifyControlMutex -Purpose "Maintenance"')!=1 or
        fn.count('Exit-SpotifyControlMutex -Mutex $maintenanceLease')!=1 or
        fn.count('Maintain -FromResidentAgent -VerifiedAgentCheck $freshCheck')!=1):
        raise RuntimeError("R54_EXISTING_AGENT_AUTHORITY_OR_NESTED_UPDATE_DRIFT")
    changed=norm[:start]+fn+norm[end:]
    if changed.replace(fn,orig_fn,1)!=norm:
        raise RuntimeError("R54_NOT_EXACTLY_ONE_FUNCTION_SOURCE_CHANGE")
    new=bom+changed.replace("\n",nl).encode("utf-8")
    if sha(new)==sha(old):
        raise RuntimeError("R54_NEW_CONCURRENCY_CHANGE_MISSING")
    OUT.mkdir(parents=True,exist_ok=False)
    for filename,data in {
      "spotify-control.ps1":new,
      "spotify-control-agent.vbs":vbs,
      "addon-manager.ps1":addon
    }.items():
        with (OUT/filename).open("xb") as f:
            f.write(data)
    parts=[]
    for name in ["Enter-SpotifyControlMutex","Exit-SpotifyControlMutex",
                 "Invoke-ResidentAgentTick","Maintain"]:
        a,b=span(changed,name)
        parts.append(changed[a:b])
    (OUT/"real-mutex-and-maintenance.ps1").write_text(
        "\n\n".join(parts)+"\n",encoding="utf-8",newline="\n")
    packer=module("spotify_r54_unmodified_fullfile",
                  HERE/"stage-combined-official-transport-R38-HOLD.py")
    packer.INTEGRATED=OUT
    packer.OUTPUT=STAGE
    packer.PIN_R37_COMBINED=sha(new)
    packer.PIN_R37_AGENT=EXPECTED_AGENT
    packer.main()
    doc=json.loads((STAGE/"manifest-UNPUBLISHABLE.json").read_text("ascii"))
    new_release=(STAGE/"bin"/"spotify-control.ps1").read_bytes()
    expected=new.replace(b'$ScriptVersion = "0.6.28"',
                         b'$ScriptVersion = "0.6.30"',1)
    if (new_release!=expected or
        doc["latest_version"]!="0.6.30" or
        doc["source_commit"]!="f"*40 or
        sum(len(p["chunks"]) for p in doc["updates"][-1]["patches"])!=20):
        raise RuntimeError("R54_VERIFIED_FULL_FILE_STAGE_CHANGED")
    proof={
      "mode":"R54_SERIALIZED_AGENT_AND_MANUAL_MAINTENANCE_HOLD",
      "main_plain_sha256":sha(new),
      "main_release_sha256":sha(expected),
      "fast_vbs_sha256":EXPECTED_AGENT,
      "addon_r17_sha256":EXPECTED_ADDON,
      "source_function_changes":["Invoke-ResidentAgentTick"],
      "production_main_changed":False,
      "user_pc_changed":False,
      "release_owner_approval":False
    }
    (OUT/"attestation.json").write_text(json.dumps(proof,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R54_NEW_PUBLISHED_FORM_MAIN_SHA256="+sha(expected))
    print("R54_ONLY_AGENTTICK_REENTRANT_MAINTENANCE_LEASE_ADDED=PASS")
    print("R54_REAL_WINDOWS_MUTEX_SOURCE_AND_UNCHANGED_MAINTAIN_EXTRACTED=PASS")
    print("R54_FAST_WMI_RESIDENT_AND_ADDON_R17_EXACT_BYTES=UNCHANGED")
    print("R54_PUBLIC_RELEASE=HOLD;OWNER_PC=UNCHANGED")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("R54 has no arguments.")
    run()
