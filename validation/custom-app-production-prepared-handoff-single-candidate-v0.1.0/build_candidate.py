"""Build one hard-disabled Addon Manager integrating the qualified new-Permit,
real ZIP handoff, standard stage-executor bridge and pre-permit backups.

This builds only a candidate in validation/out; it never edits production
manifests, installed Spotify/Spicetify, source profiles, startup or network.
"""
from __future__ import annotations

from pathlib import Path
import hashlib
import importlib.util
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / "out" / "bin"
REPORT = HERE / "candidate-validation.json"

FROZEN_PRODUCTION_MAIN = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
PARENT_VALIDATED = "02242daa6258fe552ac19e395612df000ddf779f"
PARENT_BUILDER = "validation/custom-app-production-new-permit-integration-v0.1.0/build_candidate.py"
PARENT_BUILDER_BLOB = "1b69372cbe0bd3b3eb58fa2e242ad470d200dbf4"
MODULES = [
    (
        "byte-real ZIP handoff",
        "validation/custom-app-production-byte-real-prepared-stage-handoff-v0.1.0/custom-app-production-byte-real-prepared-stage-handoff.ps1",
        "c53eead027e8f48f9777e5c70ae2f011016bb851",
    ),
    (
        "existing stage-executor bridge",
        "validation/custom-app-production-prepared-stage-executor-bridge-v0.1.0/custom-app-production-prepared-stage-executor-bridge.ps1",
        "04226ed6595049a2fcb3ac355150e9cd62940b58",
    ),
    (
        "pre-permit app and persistence backups",
        "validation/custom-app-production-pre-permit-backups-bridge-v0.1.0/custom-app-production-pre-permit-backups-bridge.ps1",
        "2b91297b72d1b223fffe2428b75ed4de8771b8eb",
    ),
]
HOOK_ORIGINAL = (
    '    try { Invoke-CustomAppProductionNewPermitHardDisabledSelfTestV010 } catch '
    '{ $errors.Add("Custom App production new permit hard-disabled integration '
    'self-test failed: $($_.Exception.Message)") }'
)
HOOK_EXTRA = (
    '    try { Invoke-CustomAppProductionPreparedHandoffHardDisabledSelfTestV010 } catch '
    '{ $errors.Add("Custom App prepared handoff hard-disabled integration '
    'self-test failed: $($_.Exception.Message)") }'
)
SELFTEST = r"""function Invoke-CustomAppProductionPreparedHandoffHardDisabledSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'Prepared handoff candidate unexpectedly enabled production mutation.'
    }
    foreach($fn in @(
        'Test-CustomAppProductionByteRealPreparedStageHandoffV010',
        'Invoke-CustomAppProductionPreparedStageExecutorBridgeV010',
        'Invoke-CustomAppProductionPrePermitBackupPreparationV010',
        'Invoke-CustomAppProductionPrePermitBackupsHandoffV010',
        'Test-CustomAppPrePermitBackupsBridgeReceiptV010',
        'Test-CustomAppPrePermitBackupTargetAncestorsV010'
    )){
        if(-not(Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('Prepared handoff qualified dependency missing: '+$fn)
        }
    }
    $noReceipt=Test-CustomAppPrePermitBackupsBridgeReceiptV010 -Receipt $null
    if($null-eq$noReceipt -or [bool]$noReceipt.ok){
        throw 'Null backup preparation receipt unexpectedly trusted.'
    }
    $noAuthority=New-CustomAppPrePermitBackupsBridgeDeniedV010 -Reason 'selftest-hard-deny'
    if([bool]$noAuthority.ok -or [bool]$noAuthority.apply_authorized -or
       [bool]$noAuthority.production_mutation_authorized){
        throw 'Pre-permit backup negative result became mutation authority.'
    }
    $badHandoff=New-CustomAppPreparedStageBridgeDeniedV010 -Reason 'selftest-hard-deny'
    if([bool]$badHandoff.ok -or [bool]$badHandoff.production_mutation_authorized){
        throw 'Prepared stage negative result became mutation authority.'
    }
    Write-Host 'CUSTOM_APP_PRODUCTION_PREPARED_HANDOFF_HARD_DISABLED_SELFTEST_PASS'
}"""

FUNCTION_DEF = re.compile(r"(?im)^[ \t]*function[ \t]+([a-zA-Z0-9_-]+)[ \t]*\{")
AUTORUN = re.compile(r"(?im)^[ \t]*\$script:CustomAppProductionPipelineEnabled[ \t]*=[ \t]*\$true[ \t]*$")

def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()

def git_blob(ref: str, path: str) -> str:
    return subprocess.check_output(["git", "rev-parse", f"{ref}:{path}"], cwd=ROOT, text=True).strip()

def load_qualified_parent():
    if git_blob("HEAD", PARENT_BUILDER) != PARENT_BUILDER_BLOB:
        raise RuntimeError("qualified parent Addon Manager candidate-builder blob drift")
    spec = importlib.util.spec_from_file_location("qualified_new_permit_builder", ROOT / PARENT_BUILDER)
    if spec is None or spec.loader is None:
        raise RuntimeError("qualified parent builder import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def build() -> None:
    parent = load_qualified_parent()
    main_bytes, base_addon, collector, reader = parent.build_parent()
    new_permit_addon, new_permit_evidence = parent.integrate(base_addon)
    if new_permit_evidence.get("pipeline_enabled") is not False:
        raise RuntimeError("new permit parent unexpectedly enabled")
    if new_permit_evidence.get("new_permit_normal_path_wiring_added") is not False:
        raise RuntimeError("new permit parent normal path unexpectedly wired")
    if new_permit_evidence.get("new_permit_external_dependencies_fully_resolved") is not True:
        raise RuntimeError("qualified new permit source dependencies unresolved")
    if not new_permit_addon:
        raise RuntimeError("parent compiled empty Addon Manager")

    bom = b"\xef\xbb\xbf" if new_permit_addon.startswith(b"\xef\xbb\xbf") else b""
    prev = new_permit_addon[len(bom):].decode("utf-8").replace("\r\n", "\n")
    old_defs = [m.group(1) for m in FUNCTION_DEF.finditer(prev)]
    existing = set(old_defs)
    all_new = set()
    imported = []
    chunks = []
    for label, path, blob in MODULES:
        if git_blob(PARENT_VALIDATED, path) != blob or git_blob("HEAD", path) != blob:
            raise RuntimeError(f"qualified module source blob drift: {label}")
        raw = subprocess.check_output(["git", "cat-file", "blob", blob], cwd=ROOT)
        content = raw.decode("utf-8-sig").replace("\r\n", "\n").strip()
        defs = [m.group(1) for m in FUNCTION_DEF.finditer(content)]
        if not defs or len(defs) != len(set(defs)):
            raise RuntimeError(f"{label} has missing or duplicate functions")
        collisions = existing.intersection(defs) | all_new.intersection(defs)
        if collisions:
            raise RuntimeError(f"{label} would override earlier validated APIs: {sorted(collisions)}")
        if "CustomAppProductionPipelineEnabled" in content or AUTORUN.search(content):
            raise RuntimeError(f"{label} attempted pipeline configuration: forbidden")
        all_new.update(defs)
        chunks.append(content)
        imported.append({"name": label, "path": path, "blob": blob, "exports": defs})
    if "Invoke-CustomAppProductionPreparedHandoffHardDisabledSelfTestV010" in existing | all_new:
        raise RuntimeError("hard-disabled selftest name collision")
    payload = "\n\n".join(chunks + [SELFTEST]) + "\n\n"
    first = FUNCTION_DEF.search(prev)
    if first is None:
        raise RuntimeError("compiled base candidate does not define functions")
    integrated = prev[: first.start()] + payload + prev[first.start() :]
    if integrated.count(HOOK_ORIGINAL) != 1:
        raise RuntimeError("parent new-Permit SelfTest injection point moved")
    integrated = integrated.replace(HOOK_ORIGINAL, HOOK_ORIGINAL + "\n" + HOOK_EXTRA, 1)

    # Reversibility is a byte-level scope proof: deleting just our three
    # modules, one canary and one selftest hook must recover the EXACT parent.
    reverse = integrated.replace(HOOK_ORIGINAL + "\n" + HOOK_EXTRA, HOOK_ORIGINAL, 1)
    if reverse.count(payload) != 1:
        raise RuntimeError("prepared-handoff insertion not uniquely reversible")
    reverse = reverse.replace(payload, "", 1)
    if reverse != prev:
        raise RuntimeError("candidate would alter frozen parent beyond approved additive surfaces")
    if integrated.count("$script:CustomAppProductionPipelineEnabled = $false") != 1:
        raise RuntimeError("hard-disabled global sentinel changed")
    if AUTORUN.findall(integrated) != AUTORUN.findall(prev):
        raise RuntimeError("force-enable canary changed")
    if "Invoke-CustomAppProductionFullChainV010" not in existing:
        raise RuntimeError("frozen parent full-chain entrypoint missing")
    if parent.function_block(integrated, "Invoke-CustomAppProductionFullChainV010") != parent.function_block(prev, "Invoke-CustomAppProductionFullChainV010"):
        raise RuntimeError("normal production full-chain implementation changed")
    if not all(fn in integrated for fn in ("Invoke-CustomAppProductionNewPermitHardDisabledSelfTestV010", "Invoke-CustomAppProductionPreparedHandoffHardDisabledSelfTestV010")):
        raise RuntimeError("one hard-disabled selftest not reachable in candidate")

    reachable = set(m.group(1) for m in FUNCTION_DEF.finditer(integrated))
    external_re = re.compile(r"\b((?:Get|Test|New|Resolve|Invoke|Open|Read|Save|Write|Repair|Assert|ConvertFrom|ConvertTo|Restore|Remove|Initialize)-[a-zA-Z][a-zA-Z0-9-]+V0\d\d)\b")
    unresolved = set()
    for s in chunks:
        for function_name in external_re.findall(s):
            if function_name not in reachable:
                unresolved.add(function_name)
    if unresolved:
        raise RuntimeError(f"new prepared handoff has unresolved required function dependency: {sorted(unresolved)}")

    candidate = bom + integrated.encode("utf-8")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "spotify-control.ps1").write_bytes(main_bytes)
    (OUT / "addon-manager.ps1").write_bytes(candidate)
    (OUT / "Collect-Marketplace-Records.ps1").write_bytes(collector)
    (OUT / "LevelDbReadOnly.cs").write_bytes(reader)

    report = {
        "schema": 1,
        "production_main_frozen": FROZEN_PRODUCTION_MAIN,
        "validated_parent": PARENT_VALIDATED,
        "validated_parent_builder_blob": PARENT_BUILDER_BLOB,
        "new_modules": imported,
        "new_function_count": len(all_new),
        "pre_existing_export_override_count": 0,
        "normal_full_chain_unmodified": True,
        "exact_source_reversibility": True,
        "unresolved_new_function_dependencies": [],
        "pipeline_enabled": False,
        "new_production_execution_path_wired": False,
        "app_or_persistence_live_mutated": False,
        "actual_atomic_swap_tested_by_this_builder": False,
        "addon_sha256": sha(candidate),
        "addon_size": len(candidate),
        "spotify_control_sha256": sha(main_bytes),
        "spotify_control_size": len(main_bytes),
        "addon_has_hard_disabled_selftest": True,
        "base_new_permit": {
            "pipeline_enabled": new_permit_evidence.get("pipeline_enabled"),
            "new_permit_normal_path_wiring_added": new_permit_evidence.get("new_permit_normal_path_wiring_added"),
            "new_permit_module_count": new_permit_evidence.get("new_permit_module_count"),
        },
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"PREPARED_HANDOFF_SINGLE_CANDIDATE_BUILD_PASS addon={len(candidate)} sha={sha(candidate)} extra_modules={len(imported)} pipeline=false")

if __name__ == "__main__":
    build()
