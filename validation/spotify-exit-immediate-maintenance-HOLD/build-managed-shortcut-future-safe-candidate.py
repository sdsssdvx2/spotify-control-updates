"""Build an offline-only future managed-shortcut safety candidate.

Source: exact official v0.6.28/r17, pinned SHA. No release or install changes.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "validation/spotify-exit-immediate-maintenance-HOLD/out/future-safe"
PIN_SIZE = 284321
PIN_SHA = "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0"

# Only replace the known original shortcut-creation loop, and never change
# a user-custom WScript link to their own VBS.
REPLACEMENT = r'''# Future managed-shortcut safety: custom owner launchers are immutable.
# A WScript shortcut targeting another VBS is not ours to change or execute.
$expectedManagedArgs = '"' + $installedVbs + '"'
foreach ($target in $managedTargets) {
    $exists = Test-Path -LiteralPath $target
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
        if ($ownedOldBin) {
            [IO.File]::Copy($target,$temp,$false)
        }
        $candidate = $shell.CreateShortcut($temp)
        $candidate.TargetPath = $wscript
        $candidate.Arguments = $expectedManagedArgs
        $candidate.WorkingDirectory = $Root
        if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") {
            $candidate.IconLocation = "$spotifyExe,0"
        }
        $candidate.Description = "Launch Spotify through Spotify Control without a console window"
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
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT / "spotify-control.ps1").write_bytes(target)
    report = {
      "schema":1,"mode":"HOLD_CANDIDATE_NO_RELEASE_OR_OPERATING_WRITE",
      "parent_sha256":sha(original),"parent_size":len(original),
      "candidate_sha256":sha(target),"candidate_size":len(target),
      "scoped_to_unique_official_managed_shortcut_loop":True,
      "published_manifest_unchanged":True,
      "installed_user_state_unchanged":True,
    }
    (OUT / "candidate-report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print("CANONICAL_V0628_R17_SOURCE_PIN=PASS")
    print("FUTURE_MANAGED_SHORTCUT_SINGLE_LOOP_REWRITE=PASS")
    print("FUTURE_SHORTCUT_CANDIDATE_SHA256="+sha(target))
    print("PRODUCTION_MANIFEST_AND_USER_INSTALL=UNCHANGED")


if __name__ == "__main__":
    build()
