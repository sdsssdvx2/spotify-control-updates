from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / "out" / "bin"
REPORT = HERE / "candidate-validation.json"

PRODUCTION_MAIN = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
PARENT_HEAD = "07ca418a6356a4966783480c5200aab123836987"
PARENT_BUILDER = "validation/custom-app-production-bounded-recovery-stack-hard-disabled-integration-v0.1.0/build_candidate.py"
PARENT_BUILDER_BLOB = "1440d16fd55b268efbf1fdd4efe714cd80c35e39"
PARENT_ADDON = (1307828, "d0bce3c8c4684838cd19cb2bd8bf70a44f8cbba323a853893e5497a854e96afc")
PARENT_MAIN = (284327, "69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99")
QUALIFIED_RESTORE_ADMISSION_BLOB = "0273d7e28a56759b1d0ec9cbf037483b04d98d63"
QUALIFIED_RESTORE_ADMISSION_PATH = "validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1"
NEW_MODULE = "validation/custom-app-production-retained-old-live-compat-v0.1.1/custom-app-production-retained-old-live-compat.ps1"
PIPELINE_TRUE_RE = r"(?im)^[ \t]*\$script:CustomAppProductionPipelineEnabled[ \t]*=[ \t]*\$true[ \t]*$"

OLD_CALL = "$mapping=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 -Phase $phase -Live $live -Transaction $txn"
NEW_CALL = "$mapping=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV011 -Phase $phase -Live $live -Transaction $txn"
ORIGINAL_HOOK = '    try { Invoke-CustomAppProductionBoundedRecoveryStackHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production bounded recovery stack hard-disabled integration self-test failed: $($_.Exception.Message)") }'
NEW_HOOK = ORIGINAL_HOOK + '\n    try { Test-CustomAppProductionRetainedOldLiveCompatibilitySelfTestV011 } catch { $errors.Add("Custom App retained old-live compatibility self-test failed: $($_.Exception.Message)") }'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(["git", "rev-parse", f"{commit}:{path}"], cwd=ROOT, text=True).strip()


def git_data(blob: str) -> bytes:
    return subprocess.check_output(["git", "cat-file", "blob", blob], cwd=ROOT)


def replace_once(source: str, old: str, new: str, label: str) -> str:
    n = source.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, got {n}")
    return source.replace(old, new, 1)


def function_bounds(source: str, name: str) -> tuple[int, int]:
    pat = re.compile(r"(?im)^[ \t]*function\s+" + re.escape(name) + r"\s*\{")
    match = pat.search(source)
    if not match:
        raise RuntimeError(f"missing function {name}")
    after = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", source[match.end():])
    return (match.start(), match.end() + after.start() if after else len(source))


def function_block(source: str, name: str) -> str:
    a, b = function_bounds(source, name)
    return source[a:b]


def replace_function(source: str, name: str, replacement: str) -> str:
    a, b = function_bounds(source, name)
    return source[:a] + replacement.rstrip() + "\n\n" + source[b:].lstrip("\n")


def functions(source: str) -> list[str]:
    return re.findall(r"(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{", source)


def build_parent() -> tuple[bytes, bytes, bytes, bytes, dict]:
    actual = git_blob(PARENT_HEAD, PARENT_BUILDER)
    if actual != PARENT_BUILDER_BLOB:
        raise RuntimeError(f"bounded production candidate builder hash drift {actual}")
    subprocess.check_call(["python", str(ROOT / PARENT_BUILDER)], cwd=ROOT)
    d = ROOT / "validation/custom-app-production-bounded-recovery-stack-hard-disabled-integration-v0.1.0/out/bin"
    main, addon, collector, reader = (
        (d / "spotify-control.ps1").read_bytes(),
        (d / "addon-manager.ps1").read_bytes(),
        (d / "Collect-Marketplace-Records.ps1").read_bytes(),
        (d / "LevelDbReadOnly.cs").read_bytes()
    )
    report = json.loads((ROOT / "validation/custom-app-production-bounded-recovery-stack-hard-disabled-integration-v0.1.0/candidate-validation.json").read_text("utf-8"))
    if (len(main), sha(main)) != PARENT_MAIN:
        raise RuntimeError("parent Spotify Control main drift")
    if (len(addon), sha(addon)) != PARENT_ADDON:
        raise RuntimeError("parent addon exact bytes drift")
    for flag in ("pipeline_enabled", "pipeline_enablement_implemented",
                 "recovery_normal_path_wiring_added", "bounded_recovery_normal_path_wiring_added",
                 "generic_auto_authority_expanded", "production_main_changed"):
        if bool(report.get(flag)):
            raise RuntimeError(f"unexpected parent authority: {flag}")
    return main, addon, collector, reader, report


def integrate(addon: bytes, module_bytes: bytes, qualified_bytes: bytes) -> tuple[bytes, dict]:
    bom = b"\xef\xbb\xbf" if addon.startswith(b"\xef\xbb\xbf") else b""
    parent = addon[len(bom):].decode("utf-8").replace("\r\n", "\n")
    extension = module_bytes.decode("utf-8-sig").replace("\r\n", "\n").strip()
    original = qualified_bytes.decode("utf-8-sig").replace("\r\n", "\n")

    parent_functions = functions(parent)
    if len(parent_functions) != len(set(parent_functions)):
        raise RuntimeError("preexisting parent function duplication")
    if "$script:CustomAppProductionPipelineEnabled = $false" not in parent:
        raise RuntimeError("production hard-disable missing")
    if "Custom App production full-chain execution is intentionally unavailable in integration-only candidate." not in function_block(parent, "Invoke-CustomAppProductionFullChainV010"):
        raise RuntimeError("the hard-disabled full-chain throw changed")
    if len(re.findall(PIPELINE_TRUE_RE, parent)) != 1:
        raise RuntimeError("parent forced-enable selftest assignment drift")
    if "CUSTOM_APP_PRODUCTION_BOUNDED_RECOVERY_STACK_HARD_DISABLED_SELFTEST_V010_PASS" not in parent:
        raise RuntimeError("parent bounded recovery integration drift")
    legacy_name = "Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010"
    resolver_name = "Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010"
    if function_block(parent, legacy_name).rstrip() != function_block(original, legacy_name).rstrip():
        raise RuntimeError("qualified legacy v010 mapping byte text differs from parent")
    if OLD_CALL not in function_block(parent, resolver_name):
        raise RuntimeError("qualified original resolve mapping call missing")
    if "Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV011" in parent:
        raise RuntimeError("parent already has a v011 bridge")
    new_functions = functions(extension)
    expected_exports = (
        "Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV011",
        "Test-CustomAppProductionRetainedOldLiveCompatibilitySelfTestV011",
    )
    if sorted(new_functions) != sorted(expected_exports):
        raise RuntimeError(f"extension unexpected function exports: {new_functions}")
    if set(new_functions) & set(parent_functions):
        raise RuntimeError("new compatibility bridge collided with original code")
    if ("Open-CustomAppProduction" in extension or "Invoke-CustomAppProductionExactSpicetifyApplyProcessV010" in extension):
        raise RuntimeError("compatibility mapping must not launch executable")

    # This source is inserted before the first existing function so it is
    # loaded as part of the candidate, but only called by an explicit
    # one-line change in the existing restore-resume admission.
    first = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", parent)
    if first is None:
        raise RuntimeError("parent first function missing")
    inserted = extension + "\n\n"
    text = parent[:first.start()] + inserted + parent[first.start():]
    old_resolver = function_block(text, resolver_name)
    new_resolver = replace_once(old_resolver, OLD_CALL, NEW_CALL, "one compatibility decision call")
    text = replace_function(text, resolver_name, new_resolver)
    old_selftest = function_block(text, "Invoke-AddonSelfTest")
    new_selftest = replace_once(old_selftest, ORIGINAL_HOOK, NEW_HOOK, "only Addon SelfTest hook")
    text = replace_function(text, "Invoke-AddonSelfTest", new_selftest)

    changed = []
    for fn in parent_functions:
        if fn in ("Invoke-AddonSelfTest", resolver_name):
            continue
        if function_block(parent, fn) != function_block(text, fn):
            changed.append(fn)
    if changed:
        raise RuntimeError(f"pre-existing execution function changed: {changed}")
    if function_block(parent, "Invoke-CustomAppProductionFullChainV010") != function_block(text, "Invoke-CustomAppProductionFullChainV010"):
        raise RuntimeError("full-chain function changed or enabled")
    if len(re.findall(PIPELINE_TRUE_RE, text)) != 1:
        raise RuntimeError("pipeline forced-enable assignment added")
    if sorted(set(functions(text)) - set(parent_functions)) != sorted(expected_exports):
        raise RuntimeError("candidate unexpected extra function")

    # Inverse transformation is deterministic: the candidate must reduce
    # byte-for-byte to the exact original hard-disabled parent.
    reverse = replace_once(text, NEW_HOOK, ORIGINAL_HOOK, "inverse new selftest hook")
    resolver = function_block(reverse, resolver_name)
    reverse = replace_function(reverse, resolver_name, replace_once(resolver, NEW_CALL, OLD_CALL, "inverse narrow mapping call"))
    reverse = replace_once(reverse, inserted, "", "inverse extension module")
    if reverse != parent:
        raise RuntimeError("candidate does not reduce byte-for-byte to parent")
    candidate = bom + text.replace("\n", "\r\n").encode("utf-8")
    return candidate, {
        "schema": 1,
        "production_main": PRODUCTION_MAIN,
        "parent_builder_head": PARENT_HEAD,
        "parent_builder_blob": PARENT_BUILDER_BLOB,
        "qualified_legacy_restore_admission_blob": QUALIFIED_RESTORE_ADMISSION_BLOB,
        "parent_addon_size": len(addon),
        "parent_addon_sha256": sha(addon),
        "new_mapping_function_count": len(new_functions),
        "new_mapper_called_only_by_restore_resume_admission": True,
        "preexisting_parent_functions_changed": changed,
        "preexisting_restore_resume_admission_single_call_replaced": True,
        "full_chain_function_unchanged": True,
        "candidate_reduces_exactly_to_parent": True,
        "pipeline_true_assignment_count": 1,
        "pipeline_true_assignment_inherited_selftest_only": True,
        "pipeline_enabled": False,
        "pipeline_enablement_implemented": False,
        "normal_update_path_wiring_added": False,
        "generic_auto_authority_expanded": False,
        "production_main_changed": False,
        "candidate_addon_size": len(candidate),
        "candidate_addon_sha256": sha(candidate),
        "module_sha256": sha(module_bytes)
    }


def main() -> None:
    main_bytes, addon_bytes, collector, reader, _ = build_parent()
    if git_blob(PARENT_HEAD, QUALIFIED_RESTORE_ADMISSION_PATH) != QUALIFIED_RESTORE_ADMISSION_BLOB:
        raise RuntimeError("qualified original restore admission blob drift")
    module_path = ROOT / NEW_MODULE
    if not module_path.is_file():
        raise RuntimeError("compatibility module not found")
    extension = module_path.read_bytes()
    candidate, report = integrate(addon_bytes, extension, git_data(QUALIFIED_RESTORE_ADMISSION_BLOB))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "spotify-control.ps1").write_bytes(main_bytes)
    (OUT / "addon-manager.ps1").write_bytes(candidate)
    (OUT / "Collect-Marketplace-Records.ps1").write_bytes(collector)
    (OUT / "LevelDbReadOnly.cs").write_bytes(reader)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"RETAINED_OLD_LIVE_HARD_DISABLED_BUNDLE_BUILT size={len(candidate)} sha256={sha(candidate)} no_production_authority=true")


if __name__ == "__main__":
    main()
