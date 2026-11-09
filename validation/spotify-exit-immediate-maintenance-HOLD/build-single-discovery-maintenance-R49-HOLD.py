"""R49 HOLD: eliminate duplicate remote maintenance discovery when the resident
AgentTick already performed an authoritative check this invocation.

Current v0.6.30 R46 full main would invoke Invoke-MaintenanceCheckPhase on
SpotifyExit, then its Maintain() callee ALWAYS repeats it. This duplicates
GitHub/Spicetify/Marketplace/Addon read operations and can lose freshness.
The existing report also declares mutation_ran before proving it entered the
mutation phase (a concurrent manual Maintain mutex can skip it).

Change only two real functions: pass the freshest in-process check result
to Maintain, re-read user authorization and health under its original
Maintenance mutex, revalidate source snapshot and Spotify closed status,
and report only actual mutation-phase admission. Manual Maintain and Launch
retain their full fresh check. No external mutations during construction.

The output is a NEW non-published v0.6.30 candidate. The previous R46
read-only held review and official stable v0.6.28 are never overwritten.
"""
from __future__ import annotations
import hashlib
from importlib import util
import json
import os
from pathlib import Path
import re
import sys

HERE=Path(__file__).resolve().parent
BASE=HERE/"out"/"integrated"/"spotify-control.ps1"
VBS=HERE/"out"/"eventdriven-r45"/"spotify-control-agent.vbs"
OUT=HERE/"out"/"single-discovery-R49"
STAGE=HERE/"out"/"release-staging-single-discovery-R49"
BASE_SHA="48714938d5ca1b40db0b1caf2fbc1e13afb69c46226e89949cfde129d643222a"
FAST_VBS="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
ADDON_SHA="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"

def sha(b:bytes)->str:
    return hashlib.sha256(b).hexdigest()

def one(src:str,old:str,new:str,label:str)->str:
    if src.count(old)!=1:
        raise RuntimeError("R49_SOURCE_ANCHOR_DRIFT_"+label)
    return src.replace(old,new,1)

def span(text:str,name:str)->tuple[int,int]:
    p="\nfunction "+name+" {"
    start=text.find(p)
    if start<0 or text.find(p,start+1)>=0:
        raise RuntimeError("R49_FUNCTION_NOT_UNIQUE_"+name)
    start+=1
    end=text.find("\nfunction ",start+2)
    if end<0: raise RuntimeError("R49_FUNCTION_END_NOT_FOUND_"+name)
    return start,end

def change_tick(chunk:str)->str:
    chunk=one(chunk,"    $checkRan = $false",
        "    $checkRan = $false\n    $freshCheck = $null",
        "TICK_FRESH_CHECK_LOCAL")
    old="[void](Invoke-MaintenanceCheckPhase -State $State)"
    if chunk.count(old)!=4:
        raise RuntimeError("R49_EXACT_FOUR_REAL_TICK_DISCOVERY_PATHS_REQUIRED")
    chunk=chunk.replace(old,"$freshCheck = Invoke-MaintenanceCheckPhase -State $State")
    chunk=one(chunk,
        """            Maintain
            $State = Ensure-StateShape (Load-State)
            $mutationRan = $true
            $decision = "maintenance-closed" """.rstrip(),
        """            $script:LastResidentMutationPhaseEntered = $false
            Maintain -FromResidentAgent -VerifiedAgentCheck $freshCheck
            $State = Ensure-StateShape (Load-State)
            $mutationRan = [bool]$script:LastResidentMutationPhaseEntered
            $checkRan = $checkRan -or [bool]$script:LastResidentDiscoveryRan
            $decision = $(if($mutationRan){"maintenance-phase-entered"}else{"maintenance-deferred-or-lease-busy"})""",
        "TICK_AMBIGUOUS_MUTATION_REPORT")
    return chunk

def change_maintain(chunk:str)->str:
    chunk=one(chunk,"function Maintain {\n",
        """function Maintain {
    param([switch]$FromResidentAgent, $VerifiedAgentCheck = $null)
    # This flag records *admission* to the real mutation phase, not whether
    # an update actually changed files or committed. Both are distinct.
    $script:LastResidentMutationPhaseEntered = $false
    $script:LastResidentDiscoveryRan = $false
""","MAINTAIN_OPTIONAL_AGENT_ARG")
    chunk=one(chunk,
        """    Save-State $State

    # Always perform discovery first. This phase is read-only with respect to
    # Spotify/Spicetify/Marketplace/CustomApp targets and is safe while Spotify runs.
    $check = Invoke-MaintenanceCheckPhase -State $State
    $State = Ensure-StateShape $check.State""",
        """    # A concurrent owner disarm or another state/health invalidation
    # between AgentTick discovery and the Maintenance mutex must not cause
    # even a second network check, much less an automatic mutation.
    if ($FromResidentAgent -and
        (-not [bool]$State.agent_mutation_enabled -or
         -not [bool]$State.pending_maintenance -or
         $State.maintenance_check_healthy -ne $true -or
         [int]$State.pending_addon_auto_ambiguous -gt 0)) {
        Write-Log "Resident maintenance deferred at mutex: owner disarmed or discovery not healthy." "WARN"
        return
    }
    Save-State $State

    # Independent manual/Launch calls always discover as before. The agent
    # can reuse only the result of its own most recent check. Any mismatch
    # forces a fresh discovery instead of trusting stale network metadata.
    $check = $null
    if ($FromResidentAgent -and $null -ne $VerifiedAgentCheck) {
        $receipt = $VerifiedAgentCheck.Report
        $snapshot = $VerifiedAgentCheck.State
        if ($null -ne $receipt -and $null -ne $snapshot -and
            [string]$receipt.phase -ceq "check-only" -and
            [bool]$receipt.healthy -and
            [bool]$State.agent_mutation_enabled -and
            [bool]$State.pending_maintenance -and
            $State.maintenance_check_healthy -eq $true -and
            [int]$State.pending_addon_auto_ambiguous -eq 0 -and
            [string]$State.last_check_only_utc -ceq [string]$snapshot.last_check_only_utc -and
            $null -ne $VerifiedAgentCheck.GuardPlan) {
            $check = $VerifiedAgentCheck
            Write-Log "Resident agent reused its completed read-only discovery (no duplicate network scan)."
        }
    }
    if ($null -eq $check) {
        $check = Invoke-MaintenanceCheckPhase -State $State
        if ($FromResidentAgent) { $script:LastResidentDiscoveryRan = $true }
    }
    $State = Ensure-StateShape $check.State

    # Recheck the current persisted owner approval and health after obtaining
    # the existing Maintenance mutex, even if they were valid in AgentTick.
    # Manual Maintain/Launch retain their independently authorized behavior.
    if ($FromResidentAgent) {
        $latest = Ensure-StateShape (Load-State)
        if (-not [bool]$latest.agent_mutation_enabled -or
            -not [bool]$latest.pending_maintenance -or
            $latest.maintenance_check_healthy -ne $true -or
            [int]$latest.pending_addon_auto_ambiguous -gt 0 -or
            [string]$latest.last_check_only_utc -cne [string]$State.last_check_only_utc) {
            Write-Log "Resident maintenance deferred: approval, fresh check or health changed under mutex." "WARN"
            return
        }
    }""",
        "MAINTAIN_USE_CHECK_RESULT_ONCE_WITH_FRESH_AUTHORITY")
    chunk=one(chunk,
       """    [void](Invoke-MaintenanceMutationPhase -State $State -GuardPlan $check.GuardPlan)""",
       """    # A lease failure or user revocation must never be reported as a
    # mutation execution. This flag is set immediately before phase entry.
    $script:LastResidentMutationPhaseEntered = $true
    [void](Invoke-MaintenanceMutationPhase -State $State -GuardPlan $check.GuardPlan)""",
       "MAINTAIN_REAL_PHASE_ADMISSION")
    return chunk

def run():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R49_GITHUB_HOSTED_WINDOWS_ONLY")
    if OUT.exists() or STAGE.exists():
        raise RuntimeError("R49_PREEXISTING_STAGE_NO_OVERWRITE")
    old=BASE.read_bytes()
    vbs=VBS.read_bytes()
    addon=(BASE.parent/"addon-manager.ps1").read_bytes()
    if (sha(old)!=BASE_SHA or sha(vbs)!=FAST_VBS or sha(addon)!=ADDON_SHA):
        raise RuntimeError("R49_PREVIOUS_RELEASE_CANDIDATE_BYTES_UNEXPECTED")
    bom=b"\xef\xbb\xbf" if old.startswith(b"\xef\xbb\xbf") else b""
    body=old[len(bom):].decode("utf-8")
    newline="\r\n" if "\r\n" in body else "\n"
    body=body.replace("\r\n","\n")
    original=body
    tick_start,tick_end=span(body,"Invoke-ResidentAgentTick")
    tick=body[tick_start:tick_end]
    edited_tick=change_tick(tick)
    body=body[:tick_start]+edited_tick+body[tick_end:]
    maintain_start,maintain_end=span(body,"Maintain")
    maintain=body[maintain_start:maintain_end]
    edited_maintain=change_maintain(maintain)
    body=body[:maintain_start]+edited_maintain+body[maintain_end:]
    t0,t1=span(body,"Invoke-ResidentAgentTick")
    m0,m1=span(body,"Maintain")
    if body[:t0]+tick+body[t1:m0]+maintain+body[m1:]!=original:
        raise RuntimeError("R49_ONLY_TWO_REAL_FUNCTIONS_EDIT_BOUNDARY_FAILED")
    if (body.count("Maintain -FromResidentAgent -VerifiedAgentCheck $freshCheck")!=1 or
        body.count("Resident agent reused its completed read-only discovery")!=1):
        raise RuntimeError("R49_SINGLE_CHECK_REUSE_NOT_INTEGRATED")
    changed=bom+body.replace("\n",newline).encode("utf-8")
    OUT.mkdir(parents=True,exist_ok=False)
    (OUT/"isolated-real-functions.ps1").write_text(edited_tick+"\n\n"+edited_maintain+"\n",encoding="utf-8",newline="\n")
    for name,data in {
       "spotify-control.ps1":changed,
       "spotify-control-agent.vbs":vbs,
       "addon-manager.ps1":addon
    }.items():
        with (OUT/name).open("xb") as f:f.write(data)
    # Reuse unchanged official R38 full-file patch producer, with explicit
    # new candidate SHA pins and an isolated, unpublished output directory.
    spec=util.spec_from_file_location("spotify_r49_original_fullfile_packer",
        HERE/"stage-combined-official-transport-R38-HOLD.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("R49_VERIFIED_FULL_FILE_PATCH_WRITER_UNAVAILABLE")
    packer=util.module_from_spec(spec)
    spec.loader.exec_module(packer)
    packer.INTEGRATED=OUT
    packer.OUTPUT=STAGE
    packer.PIN_R37_COMBINED=sha(changed)
    packer.PIN_R37_AGENT=FAST_VBS
    packer.main()
    doc=json.loads((STAGE/"manifest-UNPUBLISHABLE.json").read_text("ascii"))
    new_bytes=(STAGE/"bin"/"spotify-control.ps1").read_bytes()
    expected=changed.replace(b'$ScriptVersion = "0.6.28"',
        b'$ScriptVersion = "0.6.30"',1)
    if (new_bytes!=expected or
        doc["updates"][-1]["patches"][0]["to_sha256"]!=sha(expected) or
        len(doc["updates"][-1]["patches"])!=2 or
        doc["latest_version"]!="0.6.30" or
        doc["source_commit"]!="f"*40):
        raise RuntimeError("R49_OFFICIAL_PATCH_LOST_NEW_MUTATION_CONTROL")
    proof={
        "mode":"R49_SINGLE_DISCOVERY_AND_MUTATION_ADMISSION_HOLD",
        "main_plain_sha256":sha(changed),
        "main_published_candidate_sha256":sha(expected),
        "fast_event_resident_sha256":FAST_VBS,
        "unchanged_addon_sha256":ADDON_SHA,
        "source_edit_scope":"Invoke-ResidentAgentTick;Maintain only",
        "production_changed":False,
        "user_windows_changed":False,
        "release_authorized":False
    }
    (OUT/"attestation.json").write_text(json.dumps(proof,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R49_EXACT_NEW_MAIN_SHA256="+sha(expected))
    print("R49_ONLY_TWO_EXISTING_FUNCTIONS_CHANGED=PASS")
    print("R49_REUSE_FRESH_AGENT_CHECK_ONE_NETWORK_DISCOVERY=IMPLEMENTED")
    print("R49_OWNER_REVOCATION_AND_HEALTH_RECHECK_IN_MAINTENANCE_MUTEX=IMPLEMENTED")
    print("R49_EVENT_DRIVEN_VBS_AND_ADDON_R17_BYTE_IDENTICAL=PASS")
    print("R49_FULL_FILE_FUTURE_UPDATE_STAGE=UNPUBLISHABLE_HOLD")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("R49 no args")
    run()
