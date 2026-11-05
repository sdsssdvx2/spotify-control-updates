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
# Frozen ancestors supplying four missing new-cycle entry points. These are
# imported only for symbols absent from the exact pinned parent, never as
# overrides of any existing function.
SUPPORT_MODULES = [
    ("durable-housekeeping", "0948a31cd46aedc3f0af5262feff37e07c6855a0", "validation/custom-app-production-dual-id-housekeeping-resume-executor-v0.1.0/custom-app-production-dual-id-housekeeping-resume-executor.ps1", "6cf870e37b2ad4afc6b4d7eec0538afda595ddb1"),
    ("historical-consumption-reader", "0948a31cd46aedc3f0af5262feff37e07c6855a0", "validation/custom-app-production-recovery-aware-permit-consumption-persistence-v0.1.0/custom-app-production-recovery-aware-permit-consumption-persistence.ps1", "5712edc5a5c8720d3254d9f3a9f151042e8c5187"),
    ("promotion-eligibility", "6bc69d2c8b12d074fa68f3d2ed7688e0846cd23c", "validation/custom-app-production-promotion-gate-v0.1.0/custom-app-production-promotion-gate.ps1", "1164c197405eac2295f789256e2886068611dd94"),
    ("dual-transaction-id-bridge", "408e24ce7f66d1f5f23025a196b19cd8a42fcda7", "validation/custom-app-production-dual-transaction-id-bridge-v0.1.0/custom-app-production-dual-transaction-id-bridge.ps1", "ce018db8c13d569036ca378bbe3b4a2a84ab3bcd"),
    ("durable-transaction-id-bridge", "408e24ce7f66d1f5f23025a196b19cd8a42fcda7", "validation/custom-app-production-durable-dual-transaction-id-bridge-integration-v0.1.0/custom-app-production-durable-dual-transaction-id-bridge-integration.ps1", "c9a58a181d3c5f5a230fa895785c3a42a928c8cd"),
]
REQUIRED_SUPPORT_EXPORTS = [
    "Get-CustomAppProductionDualIdHousekeepingResumeDurableIdentityV010",
    "Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedTargetV010",
    "Resolve-CustomAppProductionPromotionEligibilityV010",
    "Test-CustomAppProductionDualIdHousekeepingResumeResultV010",
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
    $canary=[pscustomobject]@{mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$true}
    $strict=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $canary -Label 'promotion-canary'
    if($null-eq$strict-or[bool]$strict.ok){throw 'Inherited promotion helper accepted forbidden canary execution authority.'}
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
    # Historical hard-disabled integration parent may intentionally retain duplicate
    # function declarations. Its exact bytes are SHA pinned and proven reversible;
    # never shadow any of those names from a newly inserted module.
    inherited_duplicates = sorted(n for n in baseline if parent_functions.count(n) > 1)
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
    support_parts = []
    support_exports: set[str] = set()
    support_records = []
    support_overlap_body_differences = []
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
    # Build the smallest exact source-verified support closure required by the
    # four new-cycle external entry points. The full ancestor modules contain
    # unrelated recovery executors: importing them wholesale would reintroduce
    # dead code and false-positive dependency obligations. Follow only
    # statically named calls reachable from the declared support roots.
    source_defs = {}
    source_headers = {}
    source_original_order = {}
    for label, lineage, path, expected in SUPPORT_MODULES:
        if git_blob(lineage, path) != expected:
            raise RuntimeError(f"qualified support module lineage drift: {label}")
        if lineage == QUALIFIED_NEW_PERMIT_HEAD and git_blob("HEAD", path) != expected:
            raise RuntimeError(f"qualified support module current blob drift: {label}")
        src = git_bytes(expected).decode("utf-8-sig").replace("\r\n", "\n").strip()
        if "$script:CustomAppProductionPipelineEnabled" in src or PIPELINE_TRUE_PATTERN.search(src):
            raise RuntimeError(f"support module attempted pipeline assignment: {label}")
        nms = functions(src)
        if not nms or len(nms) != len(set(nms)):
            raise RuntimeError(f"support module malformed function inventory: {label}")
        fn_start = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", src)
        if not fn_start:
            raise RuntimeError(f"support module has no function definition: {label}")
        source_headers[label] = src[:fn_start.start()].strip()
        source_original_order[label] = nms
        for nm in nms:
            if nm in source_defs:
                raise RuntimeError(f"two support modules define same function: {nm}")
            source_defs[nm] = (label, function_block(src, nm).strip())

    closure_seen = set()
    closure_queue = list(REQUIRED_SUPPORT_EXPORTS)
    # A historical promotion gate invokes a generic strict-deny helper whose
    # name is already defined in the exact parent. Prove the inherited helper
    # is exactly the qualified historical helper OR an exact stricter extension
    # which additionally rejects canary execution authority. Do not override it.
    helper_name = "Test-CustomAppPromotionStrictDeniedAuthorityV010"
    historical_helper = source_defs[helper_name][1]
    generic_promotion_source = "validation/custom-app-promotion-eligibility-gate-v0.1.0/custom-app-promotion-eligibility.ps1"
    generic_promotion_blob = "94c1b0ba8f2454078252a723f89ccc0327cbc181"
    if git_blob("HEAD", generic_promotion_source) != generic_promotion_blob:
        raise RuntimeError("inherited generic promotion strict-deny source blob drift")
    stricter_source = git_bytes(generic_promotion_blob).decode("utf-8-sig").replace("\r\n", "\n")
    stricter_helper = function_block(stricter_source, helper_name).strip()
    extra_deny = "    if($Object.PSObject.Properties['canary_execution_authorized'] -and [bool]$Object.canary_execution_authorized){return [pscustomobject]@{ok=$false;reason=($Label+'-canary-authority-true')}}"
    if stricter_helper.count(extra_deny) != 1 or stricter_helper.replace(extra_deny + "\n", "") != historical_helper:
        raise RuntimeError("inherited generic promotion helper is not exact stricter extension")
    parent_function_headers = list(re.finditer(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", parent))
    inherited_helper_bodies = [
        parent[m.start():(parent_function_headers[i + 1].start() if i + 1 < len(parent_function_headers) else len(parent))].strip()
        for i, m in enumerate(parent_function_headers)
        if m.group(0).split()[1] == helper_name
    ]
    if not inherited_helper_bodies or any(body not in (historical_helper, stricter_helper) for body in inherited_helper_bodies):
        raise RuntimeError("inherited promotion strict-deny helper differs from both qualified safe bodies")
    source_selected = {label: set() for label, _, _, _ in SUPPORT_MODULES}
    unresolved_reachable = set()
    while closure_queue:
        nm = closure_queue.pop(0)
        if nm in closure_seen:
            continue
        closure_seen.add(nm)
        if nm in seen_new:
            continue
        if nm in baseline:
            if nm in source_defs:
                label, body = source_defs[nm]
                if function_block(parent, nm).strip() != body:
                    support_overlap_body_differences.append(f"{label}:{nm}")
            continue
        if nm not in source_defs:
            unresolved_reachable.add(nm)
            continue
        label, body = source_defs[nm]
        source_selected[label].add(nm)
        closure_queue.extend(EXTERNAL_EXPORT_PATTERN.findall(body))

    for label, lineage, path, expected in SUPPORT_MODULES:
        selected = source_selected[label]
        retained = [nm for nm in source_original_order[label] if nm in selected]
        chunks = [source_headers[label]] if selected and source_headers[label] else []
        for nm in retained:
            chunks.append(source_defs[nm][1])
            support_exports.add(nm)
        if chunks:
            filtered = "\n\n".join(chunks).rstrip()
            support_parts.append(filtered)
            module_source.append(filtered)
        overlapping = [
            nm for nm in source_original_order[label]
            if nm in baseline and nm in closure_seen
        ]
        support_records.append({
            "label": label, "lineage": lineage, "path": path, "git_blob": expected,
            "imported_exports": retained, "inherited_exports_preserved": overlapping,
        })
    for nm in REQUIRED_SUPPORT_EXPORTS:
        if nm not in (baseline | seen_new | support_exports):
            raise RuntimeError(f"qualified support function missing: {nm}")
    for name in REQUIRED_EXPORTS:
        if name not in seen_new:
            raise RuntimeError(f"required new permit export missing: {name}")
    if len(seen_new) != 74:
        raise RuntimeError(f"new permit function inventory drift: {len(seen_new)}")
    first = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", parent)
    if not first:
        raise RuntimeError("frozen parent function boundary missing")
    payload = "\n\n".join(support_parts + payloads) + "\n\n" + SELFTEST.rstrip() + "\n\n"
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
        "support_module_count": len(SUPPORT_MODULES),
        "support_added_export_count": len(support_exports),
        "support_modules": support_records,
        "support_overlapping_parent_function_bodies_different": sorted(support_overlap_body_differences),
        "inherited_promotion_helper_strict_superset_proven": True,
        "support_source_closure_unresolved": sorted(unresolved_reachable),
        "new_permit_external_function_dependencies_unresolved": missing,
        "new_permit_external_dependencies_fully_resolved": not bool(missing),
        "preexisting_functions_changed": changed,
        "preexisting_parent_duplicate_exports_preserved": inherited_duplicates,
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
