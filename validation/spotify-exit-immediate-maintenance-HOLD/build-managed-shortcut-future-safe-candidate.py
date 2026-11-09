"""Build an offline-only future managed-shortcut safety candidate.

Source: exact official v0.6.28/r17, pinned SHA. No release or install changes.
"""
from __future__ import annotations
import hashlib
import json
import runpy
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "validation/spotify-exit-immediate-maintenance-HOLD/out/future-safe"
PIN_SIZE = 284321
PIN_SHA = "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0"
PIN_AGENT_SIZE = 4855
PIN_AGENT_SHA = "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278"
AGENT_CWD_GUARD = """' Always release the installed bin directory before running any resident tick.
' Shell.CurrentDirectory changes the actual WScript host process CWD, and
' is independent of the owner-controlled shortcut / invoking wrapper CWD.
On Error Resume Next
Err.Clear
shell.CurrentDirectory = rootDir
If Err.Number <> 0 Then WScript.Quit 10
Err.Clear
On Error GoTo 0
If StrComp(shell.CurrentDirectory, rootDir, vbTextCompare) <> 0 Then
    WScript.Quit 10
End If
"""

# Only replace the known original shortcut-creation loop, and never change
# a user-custom WScript link to their own VBS.
REPLACEMENT = r'''# Future managed-shortcut safety: custom owner launchers are immutable.
# A WScript shortcut targeting another VBS is not ours to change or execute.
$expectedManagedArgs = '"' + $installedVbs + '"'
# If the owner has kept only one of the default locations, never recreate
# the deliberately absent Desktop or Start Menu shortcut on maintenance.
# For a genuinely fresh install with neither link, create both as before.
$managedLinkAlreadyPresent = @($managedTargets | Where-Object {
    Test-Path -LiteralPath $_
}).Count -gt 0
foreach ($target in $managedTargets) {
    $exists = Test-Path -LiteralPath $target
    if (-not $exists -and $managedLinkAlreadyPresent) { continue }
    $ownedOldBin = $false
    $skip = $false
    if ($exists) {
        try {
            $file = Get-Item -LiteralPath $target -Force -ErrorAction Stop
            if ($file.PSIsContainer -or
                ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $skip = $true
            } else {
                $entry = $shell.CreateShortcut($target)
                $official = [string]::Equals([string]$entry.TargetPath,
                    [string]$wscript,[StringComparison]::OrdinalIgnoreCase) -and
                    ([string]$entry.Arguments -ceq $expectedManagedArgs)
                if (-not $official) {
                    $skip = $true
                } elseif ([string]::Equals([string]$entry.WorkingDirectory,
                        [string]$Root,[StringComparison]::OrdinalIgnoreCase)) {
                    $skip = $true
                } elseif ([string]::Equals([string]$entry.WorkingDirectory,
                        [string]$installedBin,[StringComparison]::OrdinalIgnoreCase)) {
                    $ownedOldBin = $true
                } else {
                    # Owner-custom working directory is not ours.
                    $skip = $true
                }
            }
        } catch {
            $skip = $true
        }
    }
    if ($skip) { continue }

    $temp = Join-Path (Split-Path -Parent $target) (
        ".spotify-control-managed-cwd-" + [guid]::NewGuid().ToString("N") + ".lnk")
    try {
        $sourceHash = $null
        if ($ownedOldBin) {
            $sourceHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            [IO.File]::Copy($target,$temp,$false)
            # Do not change the owner's description, icon, hotkeys or other
            # metadata on an already-owned official launcher. Only its CWD.
            $candidate = $shell.CreateShortcut($temp)
            $candidate.WorkingDirectory = $Root
        } else {
            $candidate = $shell.CreateShortcut($temp)
            $candidate.TargetPath = $wscript
            $candidate.Arguments = $expectedManagedArgs
            $candidate.WorkingDirectory = $Root
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") {
                $candidate.IconLocation = "$spotifyExe,0"
            }
            $candidate.Description = "Launch Spotify through Spotify Control without a console window"
        }
        $candidate.Save()

        $check = $shell.CreateShortcut($temp)
        if (-not [string]::Equals([string]$check.TargetPath,
                [string]$wscript,[StringComparison]::OrdinalIgnoreCase) -or
            [string]$check.Arguments -cne $expectedManagedArgs -or
            -not [string]::Equals([string]$check.WorkingDirectory,
                [string]$Root,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Staged managed link identity mismatch"
        }
        if ($ownedOldBin) {
            $again = $shell.CreateShortcut($target)
            if (-not [string]::Equals([string]$again.TargetPath,
                    [string]$wscript,[StringComparison]::OrdinalIgnoreCase) -or
                [string]$again.Arguments -cne $expectedManagedArgs -or
                -not [string]::Equals([string]$again.WorkingDirectory,
                    [string]$installedBin,[StringComparison]::OrdinalIgnoreCase)) {
                throw "Original managed link changed while staging"
            }
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $sourceHash) {
                throw "Original managed link bytes changed during staging"
            }
            # Adjacent immutable original backup: same-volume atomic replace.
            $saved = Join-Path (Split-Path -Parent $target) (
                ".spotify-control-managed-before-neutral-" +
                [guid]::NewGuid().ToString("N") + ".lnk")
            [IO.File]::Replace($temp,$target,$saved,$true)
        } else {
            # Atomic create-no-replace; a raced custom link remains untouched.
            [IO.File]::Move($temp,$target)
        }
    } catch {
        Write-Log "Managed shortcut neutral workdir deferred; original preserved." "WARN"
    } finally {
        if (Test-Path -LiteralPath $temp) {
            try { [IO.File]::Delete($temp) } catch {}
        }
    }
}'''


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def build():
    subprocess.check_call(
        [sys.executable, str(ROOT / "validation/v0.6.28/build_v0628.py"), "--build"],
        cwd=ROOT,
    )
    original = (ROOT / "validation/v0.6.28/out/bin/spotify-control.ps1").read_bytes()
    if (len(original), sha(original)) != (PIN_SIZE, PIN_SHA):
        raise RuntimeError("CANONICAL_SOURCE_SHA_OR_SIZE_DRIFT")
    text = original.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"
    normalized = text.replace("\r\n", "\n")
    first = "foreach ($target in $managedTargets) {"
    if normalized.count(first) != 1:
        raise RuntimeError("ORIGINAL_SHORTCUT_LOOP_COUNT_NOT_ONE")
    start = normalized.index(first)
    end = normalized.find("\n    }\n",start)
    if end < start:
        raise RuntimeError("ORIGINAL_SHORTCUT_LOOP_NOT_CLOSED")
    end += len("\n    }")
    old = normalized[start:end]
    anchors = [
        "$shortcut = $shell.CreateShortcut($target)",
        "$shortcut.TargetPath = $wscript",
        "$shortcut.Arguments = ",
        "$shortcut.WorkingDirectory = $installedBin",
        "$shortcut.IconLocation = ",
        "$shortcut.Description = ",
        "$shortcut.Save()",
    ]
    if not all(old.count(a) == 1 for a in anchors):
        raise RuntimeError("ORIGINAL_SHORTCUT_LOOP_ANCHOR_DRIFT")
    if not (7 <= len(old.splitlines()) <= 14):
        print("CANONICAL_OFFICIAL_SHORTCUT_LOOP_LINE_COUNT",len(old.splitlines()))
        for idx,line in enumerate(old.splitlines(),1):
            if idx <= 40: print("CANONICAL_SHORTCUT_LOOP_LINE",idx,repr(line[:200]))
        raise RuntimeError("ORIGINAL_SHORTCUT_LOOP_UNKNOWN_CODE")
    changed = normalized[:start] + REPLACEMENT + normalized[end:]
    if changed.count(first) != 1:
        raise RuntimeError("FUTURE_SHORTCUT_LOOP_DUPLICATED")
    target = ((b"\xef\xbb\xbf" if original.startswith(b"\xef\xbb\xbf") else b"")
              + changed.replace("\n",newline).encode("utf-8"))
    if (len(target),sha(target)) == (len(original),sha(original)):
        raise RuntimeError("NO_ACTUAL_CHANGE")
    # Recover the exact publicly pinned official VBS from the historical
    # delivery archive; never infer content or use an unrelated newer VBS.
    auditor = runpy.run_path(str(ROOT / "validation/normal-engine-shared-turnstile/audit-pinned-stable-entrypoints-v059.py"))
    agent = auditor["extract_verified_agent"]()
    if (len(agent),sha(agent)) != (PIN_AGENT_SIZE,PIN_AGENT_SHA):
        raise RuntimeError("CANONICAL_AGENT_SOURCE_SHA_OR_SIZE_DRIFT")
    agent_text = agent.decode("utf-8-sig")
    agent_line = "rootDir = fso.GetParentFolderName(scriptDir)"
    if agent_text.count(agent_line) != 1 or "shell.CurrentDirectory" in agent_text:
        raise RuntimeError("CANONICAL_AGENT_INIT_ANCHOR_DRIFT")
    agent_nl = "\r\n" if "\r\n" in agent_text else "\n"
    agent_norm = agent_text.replace("\r\n","\n")
    agent_target = agent_norm.replace(agent_line+"\n",agent_line+"\n"+AGENT_CWD_GUARD,1)
    if agent_target == agent_norm or agent_target.count("shell.CurrentDirectory") != 2:
        raise RuntimeError("AGENT_CWD_GUARD_NOT_EXACT_ONCE")
    future_agent = (b"\xef\xbb\xbf" if agent.startswith(b"\xef\xbb\xbf") else b"") + agent_target.replace("\n",agent_nl).encode("utf-8")
    if sha(future_agent) == sha(agent):
        raise RuntimeError("FUTURE_AGENT_UNCHANGED")
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT / "spotify-control.ps1").write_bytes(target)
    (OUT / "spotify-control-agent.vbs").write_bytes(future_agent)
    report = {
      "schema":1,"mode":"HOLD_CANDIDATE_NO_RELEASE_OR_OPERATING_WRITE",
      "parent_sha256":sha(original),"parent_size":len(original),
      "original_resident_sha256":sha(agent),
      "original_resident_size":len(agent),
      "future_resident_sha256":sha(future_agent),
      "future_resident_size":len(future_agent),
      "resident_sets_process_cwd_to_app_root_before_any_tick":True,
      "candidate_sha256":sha(target),"candidate_size":len(target),
      "scoped_to_unique_official_managed_shortcut_loop":True,
      "absent_link_preserved_if_other_managed_location_exists":True,
      "published_manifest_unchanged":True,
      "installed_user_state_unchanged":True,
    }
    (OUT / "candidate-report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print("CANONICAL_V0628_R17_SOURCE_PIN=PASS")
    print("FUTURE_MANAGED_SHORTCUT_SINGLE_LOOP_REWRITE=PASS")
    print("FUTURE_SHORTCUT_CANDIDATE_SHA256="+sha(target))
    print("FUTURE_RESIDENT_CWD_GUARD_SHA256="+sha(future_agent))
    print("PRODUCTION_MANIFEST_AND_USER_INSTALL=UNCHANGED")


if __name__ == "__main__":
    build()
