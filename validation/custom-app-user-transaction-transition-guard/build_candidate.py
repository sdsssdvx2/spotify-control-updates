from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / "out" / "bin"
PARENT = "440b3d695c15c6dddbaa3c71461432d33cc534ad"
PARENT_BUILDER = "validation/custom-app-user-transaction-store-bundle/build_candidate.py"
PARENT_BUILDER_BLOB = "4c9b75f9e2b4a7d96f9c01ca18db671640c6e9fa"
PARENT_ADDON = (1431151, "0758928dfc46191bac941775cc64b613d9657c6098494a602851360af8a76c1f")
PARENT_SPOTIFY = (284327, "69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99")
MODULE = "validation/custom-app-user-transaction-transition-guard/user-transaction-guard.ps1"
MODULE_BLOB = "554a792fb6eb7ca0a0d44b23a758a2ddf21548a2"
TEST = "validation/custom-app-user-transaction-transition-guard/test_user_transaction_guard.ps1"
TEST_BLOB = "018dfca2a3dc9c74683ce3320c59d66ec5dd15ce"
PREVIOUS_HOOK = '    try { Test-CustomAppUserTxnBundleSelfTestV010 } catch { $errors.Add("Custom App private user transaction store bundle self-test failed: $($_.Exception.Message)") }'
NEW_HOOK = PREVIOUS_HOOK + '\n    try { Test-CustomAppUserTxnGuardBundleSelfTestV010 } catch { $errors.Add("Custom App private user transaction guard bundle self-test failed: $($_.Exception.Message)") }'
SELFTEST = r"""function Test-CustomAppUserTxnGuardBundleSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'Guard unexpectedly enabled production pipeline'}
    foreach($name in @('Test-CustomAppUserTxnPermitOnlyTransitionV010','Save-CustomAppUserTxnStoreV010')){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('Missing guard '+$name)}
    }
    if(Get-Command Complete-CustomAppUserTxnTerminalV010 -ErrorAction SilentlyContinue){throw 'Unverified terminal clearance exposed'}
    Write-Host 'CUSTOM_USER_TXN_GUARD_BUNDLE_SELFTEST_PASS only_reserve_transition=true terminal_retirement_disabled=true'
}"""

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(["git", "rev-parse", f"{commit}:{path}"], cwd=ROOT, text=True).strip()

def once(value: str, old: str, new: str, label: str) -> str:
    if value.count(old) != 1:
        raise RuntimeError(f"qualified {label} anchor drift: {value.count(old)}")
    return value.replace(old, new, 1)

def names(value: str) -> list[str]:
    return re.findall(r"(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{", value)

def block(value: str, name: str) -> str:
    p = re.search(r"(?im)^[ \t]*function\s+" + re.escape(name) + r"\s*\{", value)
    if not p:
        raise RuntimeError("missing qualified function " + name)
    end = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", value[p.end():])
    return value[p.start():(p.end() + end.start() if end else len(value))]

def main() -> None:
    if git_blob(PARENT, PARENT_BUILDER) != PARENT_BUILDER_BLOB:
        raise RuntimeError("parent source builder drift")
    if git_blob("HEAD", MODULE) != MODULE_BLOB or git_blob("HEAD", TEST) != TEST_BLOB:
        raise RuntimeError("guard source or protected regression test drift")
    subprocess.check_call(["python", str(ROOT / PARENT_BUILDER)], cwd=ROOT)
    d = ROOT / "validation/custom-app-user-transaction-store-bundle/out/bin"
    originals = {key: (d / key).read_bytes() for key in (
        "addon-manager.ps1", "spotify-control.ps1", "Collect-Marketplace-Records.ps1", "LevelDbReadOnly.cs")}
    addon = originals["addon-manager.ps1"]
    spotify = originals["spotify-control.ps1"]
    if (len(addon), sha(addon)) != PARENT_ADDON or (len(spotify), sha(spotify)) != PARENT_SPOTIFY:
        raise RuntimeError("qualified prior hard-disabled candidate bytes drift")
    bom = b"\xef\xbb\xbf" if addon.startswith(b"\xef\xbb\xbf") else b""
    original = addon[len(bom):].decode("utf-8").replace("\r\n", "\n")
    extension = (ROOT / MODULE).read_text("utf-8-sig").replace("\r\n", "\n").strip()
    before = set(names(original))
    added = names(extension)
    if sorted(added) != ["Save-CustomAppUserTxnStoreV010", "Test-CustomAppUserTxnPermitOnlyTransitionV010"]:
        raise RuntimeError("unexpected exposed functions in transition-only guard")
    if set(added) & before != {"Save-CustomAppUserTxnStoreV010"}:
        raise RuntimeError("unexpected original function override")
    if "Test-CustomAppUserTxnPermitOnlyTransitionV010 -Current $current -Next $NextState -Paths $p" not in extension:
        raise RuntimeError("guard not invoked from canonical saved-state mutation")
    if any(marker in extension for marker in (
        "Complete-CustomAppUserTxnTerminalV010", "Invoke-CustomAppProductionFullChainV010",
        "Invoke-CustomAppProductionExactSpicetifyApplyProcessV010",
        "$script:CustomAppProductionPipelineEnabled = $true")):
        raise RuntimeError("guard attempted broader operating authority")
    payload = extension + "\n\n" + SELFTEST + "\n\n"
    candidate = once(original, "function Test-Due {", payload + "function Test-Due {", "guard injection")
    candidate = once(candidate, PREVIOUS_HOOK, NEW_HOOK, "guard SelfTest hook")
    if block(original, "Invoke-CustomAppProductionFullChainV010") != block(candidate, "Invoke-CustomAppProductionFullChainV010"):
        raise RuntimeError("hard-disabled production FullChain changed")
    if "Custom App production full-chain execution is intentionally unavailable in integration-only candidate." not in block(candidate, "Invoke-CustomAppProductionFullChainV010"):
        raise RuntimeError("required hard-disabled FullChain throw missing")
    if candidate.count("$script:CustomAppProductionPipelineEnabled = $true") != original.count("$script:CustomAppProductionPipelineEnabled = $true"):
        raise RuntimeError("production enablement changed")
    if names(candidate).count("Save-CustomAppUserTxnStoreV010") != names(original).count("Save-CustomAppUserTxnStoreV010") + 1:
        raise RuntimeError("transition guard did not override the precise Save function")
    for n in before:
        if n in ("Invoke-AddonSelfTest", "Test-CustomAppUserTxnBundleSelfTestV010"):
            # The preceding function lexical boundary shifts at insertion;
            # exact reverse below still proves all original bytes unchanged.
            continue
        if block(candidate, n) != block(original, n):
            raise RuntimeError(f"pre-existing function drift: {n}")
    reverse = once(once(candidate, NEW_HOOK, PREVIOUS_HOOK, "guard inverse SelfTest"),
                   payload, "", "guard inverse injection")
    if reverse != original:
        raise RuntimeError("guard candidate is not exactly reversible to frozen previous bundle")
    output = bom + candidate.replace("\n", "\r\n").encode("utf-8")
    originals["addon-manager.ps1"] = output
    OUT.mkdir(parents=True, exist_ok=True)
    for name, value in originals.items():
        (OUT / name).write_bytes(value)
    report = {
        "schema": 1, "parent": PARENT, "parent_addon_sha256": sha(addon),
        "candidate_addon_sha256": sha(output), "candidate_addon_bytes": len(output),
        "main_spotify_sha256": sha(spotify), "guard_blob": MODULE_BLOB,
        "e2e_test_blob": TEST_BLOB, "exact_parent_inverse": True,
        "preexisting_full_chain_unchanged": True,
        "intentional_override": ["Save-CustomAppUserTxnStoreV010"],
        "one_legal_reservation_transition": True, "active_cannot_be_cleared_by_save": True,
        "consumed_ledger_cannot_be_modified_by_save": True,
        "terminal_retirement_implemented": False, "normal_auto_update_wired": False,
        "production_mutation_authorized": False, "real_spicetify_executed": False,
        "operating_main_changed": False
    }
    (HERE / "candidate-validation.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CUSTOM_USER_TXN_GUARD_CANDIDATE_BUILT", len(output), sha(output),
          "full_chain_disabled=true unverified_terminal_retirement_disabled=true")

if __name__ == "__main__":
    main()
