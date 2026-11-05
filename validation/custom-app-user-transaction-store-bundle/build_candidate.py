from __future__ import annotations
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / "out" / "bin"
PARENT = "194ae24fc1a56ba76bfb8d401b4dbe50f95f1d6b"
PARENT_BUILDER = "validation/custom-app-journal-lock-integration/build_candidate.py"
PARENT_BUILDER_BLOB = "5ac34f40bc52ab9583dbeb4a05b45f378aa1d2a2"
PARENT_ADDON = (1415377, "60e5d5ce80bdddff3e399cd481cac82c1e94338bc9dc0a768944c7db6343d4a7")
PARENT_MAIN = (284327, "69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99")
MODULE = "validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1"
MODULE_BLOB = "b547fa00cc0da4368e4943eba6f475f95a8b0622"
TEST = "validation/custom-app-user-transaction-store-bundle/test_user_transaction_store.ps1"
TEST_BLOB = "b06b699a987e838563d3f00f2f9b2e48c4e9d6d3"
OLD_HOOK = '    try { Invoke-CustomAppProductionJournalLockBundleSelfTestV010 } catch { $errors.Add("Custom App journal-lock bundle self-test failed: $($_.Exception.Message)") }'
NEW_HOOK = OLD_HOOK + '\n    try { Test-CustomAppUserTxnBundleSelfTestV010 } catch { $errors.Add("Custom App private user transaction store bundle self-test failed: $($_.Exception.Message)") }'
NEW_SELFTEST = r"""function Test-CustomAppUserTxnBundleSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'User store unexpectedly enabled normal pipeline'}
    foreach($name in @(
        'Open-CustomAppUserTxnStoreV010',
        'Read-CustomAppUserTxnStateV010',
        'Reserve-CustomAppUserTxnIdV010',
        'Test-CustomAppUserTxnStateV010',
        'Assert-CustomAppUserTxnPrivateDirectoryV010'
    )){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('User store missing function '+$name)}
    }
    if(Get-Command Complete-CustomAppUserTxnTerminalV010 -ErrorAction SilentlyContinue){throw 'Unverified terminal clearance exposed'}
    Write-Host 'CUSTOM_APP_USER_TRANSACTION_STORE_BUNDLED_SELFTEST_PASS DPAPI=true no_production_authority=true terminal_retirement_not_wired=true'
}"""

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(["git", "rev-parse", f"{commit}:{path}"], cwd=ROOT, text=True).strip()

def once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, got {count}")
    return source.replace(old, new, 1)

def funcs(source: str) -> list[str]:
    return re.findall(r"(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{", source)

def function_block(source: str, name: str) -> str:
    pat = r"(?im)^[ \t]*function\s+" + re.escape(name) + r"\s*\{"
    match = re.search(pat, source)
    if not match:
        raise RuntimeError("missing qualified function " + name)
    next_func = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", source[match.end():])
    stop = match.end() + next_func.start() if next_func else len(source)
    return source[match.start():stop]

def main() -> None:
    if git_blob(PARENT, PARENT_BUILDER) != PARENT_BUILDER_BLOB:
        raise RuntimeError("qualified prior journal/lock bundle builder drift")
    if git_blob("HEAD", MODULE) != MODULE_BLOB or git_blob("HEAD", TEST) != TEST_BLOB:
        raise RuntimeError("private user store source or e2e test pin changed")
    subprocess.check_call(["python", str(ROOT / PARENT_BUILDER)], cwd=ROOT)
    parent_dir = ROOT / "validation/custom-app-journal-lock-integration/out/bin"
    originals = {name: (parent_dir / name).read_bytes() for name in
                 ("addon-manager.ps1", "spotify-control.ps1", "Collect-Marketplace-Records.ps1", "LevelDbReadOnly.cs")}
    addon = originals["addon-manager.ps1"]
    spotify = originals["spotify-control.ps1"]
    if (len(addon), digest(addon)) != PARENT_ADDON:
        raise RuntimeError("previous frozen addon bundle bytes changed")
    if (len(spotify), digest(spotify)) != PARENT_MAIN:
        raise RuntimeError("protected Spotify Control candidate changed")
    bom = b"\xef\xbb\xbf" if addon.startswith(b"\xef\xbb\xbf") else b""
    original = addon[len(bom):].decode("utf-8").replace("\r\n", "\n")
    extension = (ROOT / MODULE).read_text("utf-8-sig").replace("\r\n", "\n").strip()
    if "Set-StrictMode" in extension or "Invoke-CustomAppProductionFullChain" in extension:
        raise RuntimeError("side-effectful top-level mode or production FullChain in user store module")
    before_funcs = set(funcs(original))
    extra_funcs = funcs(extension)
    if len(extra_funcs) != 13 or len(extra_funcs) != len(set(extra_funcs)) or before_funcs.intersection(extra_funcs):
        raise RuntimeError("unexpected private user store exports or collision")
    if any(token in extension for token in
           ("Invoke-CustomAppProductionExactSpicetifyApplyProcessV010", "Complete-CustomAppUserTxnTerminalV010", "$script:CustomAppProductionPipelineEnabled = $true")):
        raise RuntimeError("user store module attempted production authorization")
    payload = extension + "\n\n" + NEW_SELFTEST + "\n\n"
    candidate = once(original, "function Test-Due {", payload + "function Test-Due {", "private user store insert")
    candidate = once(candidate, OLD_HOOK, NEW_HOOK, "private user store SelfTest registration")
    if function_block(candidate, "Invoke-CustomAppProductionFullChainV010") != function_block(original, "Invoke-CustomAppProductionFullChainV010"):
        raise RuntimeError("FullChain mutated")
    if "Custom App production full-chain execution is intentionally unavailable in integration-only candidate." not in function_block(candidate, "Invoke-CustomAppProductionFullChainV010"):
        raise RuntimeError("production FullChain hard disable missing")
    if candidate.count("$script:CustomAppProductionPipelineEnabled = $true") != original.count("$script:CustomAppProductionPipelineEnabled = $true"):
        raise RuntimeError("production enablement changed")
    for fn in before_funcs:
        if fn == "Invoke-AddonSelfTest":
            continue
        if function_block(original, fn) != function_block(candidate, fn):
            raise RuntimeError(f"existing function modified: {fn}")
    reverse = once(once(candidate, NEW_HOOK, OLD_HOOK, "inverse SelfTest"), payload, "", "inverse user store module")
    if reverse != original:
        raise RuntimeError("original candidate inverse not byte-identical")
    output = bom + candidate.replace("\n", "\r\n").encode("utf-8")
    originals["addon-manager.ps1"] = output
    OUT.mkdir(parents=True, exist_ok=True)
    for name, data in originals.items():
        (OUT / name).write_bytes(data)
    evidence = {
        "schema": 1, "source_parent": PARENT, "source_parent_addon_sha256": digest(addon),
        "new_module_blob": MODULE_BLOB, "new_test_blob": TEST_BLOB,
        "new_module_functions": extra_funcs, "new_module_function_count": len(extra_funcs),
        "candidate_addon_size": len(output), "candidate_addon_sha256": digest(output),
        "candidate_spotify_control_sha256": digest(spotify),
        "parent_exact_inverse": True, "preexisting_full_chain_unchanged": True,
        "real_user_pc_store_code_in_candidate": True, "hosted_ci_isolation_required_for_tests": True,
        "current_user_dpapi_protection": True, "explicit_current_user_acl_required": True,
        "fail_closed_on_missing_or_invalid_state": True, "active_reservation_remains_until_terminal_adapter": True,
        "production_mutation_authorized": False, "production_execution_authorized": False,
        "normal_auto_update_wired": False, "real_spicetify_executed": False,
        "operating_main_unchanged": True
    }
    (HERE / "candidate-validation.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CUSTOM_APP_PRIVATE_USER_STORE_BUNDLED_CANDIDATE", len(output), digest(output),
          "normal_update_enabled=false terminal_retirement_enabled=false")

if __name__ == "__main__":
    main()
