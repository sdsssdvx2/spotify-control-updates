from __future__ import annotations

from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / "out" / "bin"
REPORT = HERE / "candidate-validation.json"

PRODUCTION_MAIN = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
QUALIFIED_NEW_PERMIT_HEAD = "0948a31cd46aedc3f0af5262feff37e07c6855a0"
PARENT_BUILDER = "validation/custom-app-production-bounded-recovery-stack-hard-disabled-integration-v0.1.0/build_candidate.py"
PARENT_BUILDER_BLOB = "1440d16fd55b268efbf1fdd4efe714cd80c35e39"
PARENT_OUTPUT_DIR = ROOT / "validation/custom-app-production-bounded-recovery-stack-hard-disabled-integration-v0.1.0/out/bin"
PARENT_MAIN = (284327, "69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99")
PARENT_ADDON = (1307828, "d0bce3c8c4684838cd19cb2bd8bf70a44f8cbba323a853893e5497a854e96afc")

MODULES = [
    ("readiness", "validation/custom-app-production-dual-id-new-permit-readiness-v0.1.0/custom-app-production-dual-id-new-permit-readiness.ps1", "a6734b92b3c529fe81ab9c0f947956b425833998"),
    ("issuance-admission", "validation/custom-app-production-dual-id-new-permit-issuance-admission-v0.1.0/custom-app-production-dual-id-new-permit-issuance-admission.ps1", "731c6d096298199b784d3da8b3a9610ff880cd98"),
    ("issuer", "validation/custom-app-production-dual-id-new-permit-issuer-v0.1.0/custom-app-production-dual-id-new-permit-issuer.ps1", "c3a79490d569798775696626d10f73485275c4bc"),
    ("reservation", "validation/custom-app-production-dual-id-new-permit-reservation-v0.1.0/custom-app-production-dual-id-new-permit-reservation.ps1", "32af654e5cb3e70293824fa8ca8920114cc3f865"),
    ("reservation-persistence", "validation/custom-app-production-dual-id-new-permit-reservation-persistence-v0.1.0/custom-app-production-dual-id-new-permit-reservation-persistence.ps1", "629c09384ac13d2fe148566deffcc413f91cdc5d"),
    ("consumption", "validation/custom-app-production-dual-id-new-permit-consumption-v0.1.0/custom-app-production-dual-id-new-permit-consumption.ps1", "048fdda7bf8b03810cec18803e6ab094e56e831e"),
    ("consumption-persistence", "validation/custom-app-production-dual-id-new-permit-consumption-persistence-v0.1.0/custom-app-production-dual-id-new-permit-consumption-persistence.ps1", "65799d084ea7fb18ac735c08c2f6b09abe7fd0ee"),
    ("executor-start", "validation/custom-app-production-dual-id-new-permit-executor-start-gate-v0.1.0/custom-app-production-dual-id-new-permit-executor-start-gate.ps1", "23ddf1bb5a922791bb0f20fee07dc99d0de44629"),
]
REQUIRED_EXPORTS = [
    "Resolve-CustomAppProductionDualIdNewPermitReadinessV010",
    "Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010",
    "Invoke-CustomAppProductionDualIdNewPermitIssuerV010",
    "Invoke-CustomAppProductionDualIdNewPermitReservationV010",
    "Invoke-CustomAppProductionDualIdNewPermitReservationPersistenceV010",
    "Invoke-CustomAppProductionDualIdNewPermitConsumptionV010",
    "Invoke-DualIdNewConsumptionPersistenceV010",
    "Resolve-DualIdNewExecutorStartGateV010",
    "Test-DualIdNewExecutorStartReceiptV010",
]
EXTERNAL_EXPORT_PATTERN = re.compile(
    r"\b((?:Get|Test|New|Resolve|Invoke|Open|Read|Save|Write|Repair|Assert|ConvertFrom|ConvertTo|Restore|Remove|Initialize)-[A-Za-z][A-Za-z0-9-]+V0\d\d)\b"
)
PIPELINE_TRUE_PATTERN = re.compile(r"(?im)^[ \t]*\$script:CustomAppProductionPipelineEnabled[ \t]*=[ \t]*\$true[ \t]*$")

SELFTEST = r'''function Invoke-CustomAppProductionNewPermitHardDisabledSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'New permit stack unexpectedly enabled production pipeline.'}
    foreach($name in @(
        'Resolve-CustomAppProductionDualIdNewPermitReadinessV010',
        'Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010',
        'Invoke-CustomAppProductionDualIdNewPermitIssuerV010',
        'Invoke-CustomAppProductionDualIdNewPermitReservationV010',
        'Invoke-CustomAppProductionDualIdNewPermitReservationPersistenceV010',
        'Invoke-CustomAppProductionDualIdNewPermitConsumptionV010',
        'Invoke-DualIdNewConsumptionPersistenceV010',
        'Resolve-DualIdNewExecutorStartGateV010',
        'Test-DualIdNewExecutorStartReceiptV010'
    )){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('New permit integrated export missing: '+$name)}
    }
    if([string]$DualIdNewExecutorStartQualifiedPersistenceHead -cne '33100251692a2486313456643842095a163267d6'){throw 'New permit executor start qualified parent drift.'}
    if([string]$CustomAppProductionDualIdNewPermitIssuerPermitTtlMinutes -cne '1'){throw 'New permit TTL drift.'}
    if([int]$CustomAppProductionDualIdNewPermitIssuerReservationWindowSeconds -ne 5){throw 'New permit reservation window drift.'}
    $negative=Test-DualIdNewExecutorStartReceiptV010 -Receipt $null
    if($null -eq $negative -or [bool]$negative.ok){throw 'New permit null receipt unexpectedly accepted.'}
    Write-Host 'CUSTOM_APP_PRODUCTION_NEW_PERMIT_HARD_DISABLED_SELFTEST_PASS loaded-but-unreachable'
}
'''

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def git_blob(revision: str, path: str) -> str:
    return subprocess.check_output(["git", "rev-parse", f"{revision}:{path}"], cwd=ROOT, text=True).strip()

def git_bytes(blob: str) -> bytes:
    return subprocess.check_output(["git", "cat-file", "blob", blob], cwd=ROOT)

def functions(text: str) -> list[str]:
    return re.findall(r"(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{", text)

def function_bounds(text: str, name: str) -> tuple[int, int]:
    start = re.search(rf"(?im)^[ \t]*function\s+{re.escape(name)}\s*\{{", text)
    if not start:
        raise RuntimeError(f"function missing from candidate: {name}")
    nxt = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", text[start.end():])
    return start.start(), (start.end() + nxt.start() if nxt else len(text))

def function_block(text: str, name: str) -> str:
    a, b = function_bounds(text, name)
    return text[a:b]

def replace_function(text: str, name: str, replacement: str) -> str:
    a, b = function_bounds(text, name)
    return text[:a] + replacement.rstrip() + "\n\n" + text[b:].lstrip("\n")

def replace_once(text: str, original: str, replacement: str, label: str) -> str:
    count = text.count(original)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact anchor, found {count}")
    return text.replace(original, replacement, 1)

def build_parent() -> tuple[bytes, bytes, bytes, bytes]:
    if git_blob("HEAD", PARENT_BUILDER) != PARENT_BUILDER_BLOB:
        raise RuntimeError("frozen bounded-recovery builder blob drift")
    subprocess.check_call(["python", str(ROOT / PARENT_BUILDER)], cwd=ROOT)
    main = (PARENT_OUTPUT_DIR / "spotify-control.ps1").read_bytes()
    addon = (PARENT_OUTPUT_DIR / "addon-manager.ps1").read_bytes()
    collector = (PARENT_OUTPUT_DIR / "Collect-Marketplace-Records.ps1").read_bytes()
    reader = (PARENT_OUTPUT_DIR / "LevelDbReadOnly.cs").read_bytes()
    if (len(main), sha(main)) != PARENT_MAIN:
        raise RuntimeError("frozen parent Spotify Control payload drift")
    if (len(addon), sha(addon)) != PARENT_ADDON:
        raise RuntimeError("frozen bounded recovery Addon Manager payload drift")
    return main, addon, collector, reader

def integrate(parent_addon: bytes) -> tuple[bytes, dict]:
    bom = b"\xef\xbb\xbf" if parent_addon.startswith(b"\xef\xbb\xbf") else b""
    parent = parent_addon[len(bom):].decode("utf-8").replace("\r\n", "\n")
    parent_functions = functions(parent)
    baseline = set(parent_functions)
    if len(parent_functions) != len(baseline):
        raise RuntimeError("frozen parent has duplicate function names")
    if "$script:CustomAppProductionPipelineEnabled = $false" not in parent:
        raise RuntimeError("parent hard-disable sentinel missing")
    if len(PIPELINE_TRUE_PATTERN.findall(parent)) != 1:
        raise RuntimeError("parent forced-enable selftest sentinel drift")
    if "CUSTOM_APP_PRODUCTION_BOUNDED_RECOVERY_STACK_HARD_DISABLED_SELFTEST_V010_PASS" not in parent:
        raise RuntimeError("bounded recovery parent selftest missing")
    payloads = []
    seen_new: set[str] = set()
    module_records = []
    module_source = []
    for label, path, expected in MODULES:
        if git_blob(QUALIFIED_NEW_PERMIT_HEAD, path) != expected or git_blob("HEAD", path) != expected:
            raise RuntimeError(f"{label} frozen source Git blob mismatch")
        raw = git_bytes(expected)
        text = raw.decode("utf-8-sig").replace("\r\n", "\n").strip()
        names = functions(text)
        if not names or len(names) != len(set(names)):
            raise RuntimeError(f"{label} has no unique exports")
        duplicate = (set(names) & (baseline | seen_new))
        if duplicate:
            raise RuntimeError(f"{label} would override existing functions: {sorted(duplicate)}")
        if "$script:CustomAppProductionPipelineEnabled" in text or PIPELINE_TRUE_PATTERN.search(text):
            raise RuntimeError(f"{label} attempts to manipulate production pipeline")
        seen_new.update(names)
        module_source.append(text)
        payloads.append(text)
        module_records.append({"label": label, "path": path, "git_blob": expected, "export_count": len(names)})
    for name in REQUIRED_EXPORTS:
        if name not in seen_new:
            raise RuntimeError(f"required new permit export missing: {name}")
    if len(seen_new) != 74:
        raise RuntimeError(f"new permit function inventory drift: {len(seen_new)}")
    first = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", parent)
    if not first:
        raise RuntimeError("frozen parent function boundary missing")
    payload = "\n\n".join(payloads) + "\n\n" + SELFTEST.rstrip() + "\n\n"
    candidate = parent[:first.start()] + payload + parent[first.start():]
    original_hook = (
        '    try { Invoke-CustomAppProductionBoundedRecoveryStackHardDisabledSelfTestV010 } '
        'catch { $errors.Add("Custom App production bounded recovery stack hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    )
    added_hook = '    try { Invoke-CustomAppProductionNewPermitHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production new permit hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    old_selftest = function_block(candidate, "Invoke-AddonSelfTest")
    new_selftest = replace_once(old_selftest, original_hook, original_hook + "\n" + added_hook, "new permit SelfTest hook")
    candidate = replace_function(candidate, "Invoke-AddonSelfTest", new_selftest)

    # No pre-existing implementation may be changed apart from this exact SelfTest insertion.
    changed = [
        name for name in parent_functions if name != "Invoke-AddonSelfTest"
        and function_block(candidate, name) != function_block(parent, name)
    ]
    if changed:
        raise RuntimeError(f"pre-existing implementation changed: {changed}")
    if function_block(candidate, "Invoke-CustomAppProductionFullChainV010") != function_block(parent, "Invoke-CustomAppProductionFullChainV010"):
        raise RuntimeError("full-chain production flow changed")
    reduced = replace_once(candidate, payload, "", "new permit module removal proof")
    reduced = replace_once(reduced, original_hook + "\n" + added_hook, original_hook, "new permit selftest hook removal proof")
    if reduced != parent:
        raise RuntimeError("candidate differs beyond explicit insertion and one SelfTest hook")
    if len(PIPELINE_TRUE_PATTERN.findall(candidate)) != 1 or "$script:CustomAppProductionPipelineEnabled = $false" not in candidate:
        raise RuntimeError("candidate production guard drift")

    available = set(functions(candidate))
    uses: set[str] = set()
    for src in module_source:
        uses.update(EXTERNAL_EXPORT_PATTERN.findall(src))
    missing = sorted(x for x in uses if x not in available)
    candidate_bytes = bom + candidate.replace("\n", "\r\n").encode("utf-8")
    return candidate_bytes, {
        "schema": 1,
        "parent_addon": {"size": len(parent_addon), "sha256": sha(parent_addon)},
        "new_permit_qualified_head": QUALIFIED_NEW_PERMIT_HEAD,
        "new_permit_module_count": len(MODULES),
        "new_permit_export_count": len(seen_new),
        "modules": module_records,
        "new_permit_external_function_dependencies_unresolved": missing,
        "new_permit_external_dependencies_fully_resolved": not bool(missing),
        "preexisting_functions_changed": changed,
        "candidate_reduces_exactly_to_parent": True,
        "full_chain_implementation_unchanged": True,
        "pipeline_enabled": False,
        "pipeline_enablement_implemented": False,
        "new_permit_normal_path_wiring_added": False,
        "production_main_changed": False,
        "candidate_addon": {"size": len(candidate_bytes), "sha256": sha(candidate_bytes)},
    }

def main() -> None:
    main_bytes, addon, collector, reader = build_parent()
    candidate, evidence = integrate(addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "spotify-control.ps1").write_bytes(main_bytes)
    (OUT / "addon-manager.ps1").write_bytes(candidate)
    (OUT / "Collect-Marketplace-Records.ps1").write_bytes(collector)
    (OUT / "LevelDbReadOnly.cs").write_bytes(reader)
    REPORT.write_text(json.dumps(evidence, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "CUSTOM_APP_PRODUCTION_NEW_PERMIT_HARD_DISABLED_BUILD_PASS",
        "modules=", evidence["new_permit_module_count"],
        "exports=", evidence["new_permit_export_count"],
        "unresolved-dependency-count=", len(evidence["new_permit_external_function_dependencies_unresolved"]),
        "candidate-addon-size=", len(candidate),
        "candidate-addon-sha256=", sha(candidate),
        "pipeline-enabled=false",
    )

if __name__ == "__main__":
    main()
