from __future__ import annotations

from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "validation/v0.6.28/out/bin"
REPORT = ROOT / "validation/settings-preserving-marketplace-lifecycle-v0.1.0/report.json"

EXPECTED_ADDON_SIZE = 323385
EXPECTED_ADDON_SHA256 = "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"
EXPECTED_MAIN_SIZE = 284321
EXPECTED_MAIN_SHA256 = "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0"
EXPECTED_AUTO = ["better-local-files", "eternal-jukebox", "ivLyrics", "playlist-maker"]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def function_map(text: str) -> dict[str, str]:
    matches = list(re.finditer(r"(?m)^function ([A-Za-z0-9_-]+) \{", text))
    result: dict[str, str] = {}
    for idx, match in enumerate(matches):
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        result[match.group(1)] = text[match.start():end].rstrip()
    return result


def functions_containing(funcs: dict[str, str], terms: list[str]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for name, block in funcs.items():
        lower = block.lower()
        hits = sorted({term for term in terms if term.lower() in lower}, key=str.lower)
        if hits:
            out[name] = hits
    return dict(sorted(out.items()))


def main() -> None:
    subprocess.check_call([sys.executable, str(ROOT / "validation/v0.6.28/build_v0628.py"), "--build"], cwd=ROOT)

    main_bytes = (OUT / "spotify-control.ps1").read_bytes()
    addon_bytes = (OUT / "addon-manager.ps1").read_bytes()
    require((len(main_bytes), sha256(main_bytes)) == (EXPECTED_MAIN_SIZE, EXPECTED_MAIN_SHA256), "exact v0.6.28 main reconstruction drifted")
    require((len(addon_bytes), sha256(addon_bytes)) == (EXPECTED_ADDON_SIZE, EXPECTED_ADDON_SHA256), "exact r17 addon reconstruction drifted")

    text = addon_bytes.decode("utf-8-sig").replace("\r\n", "\n")
    funcs = function_map(text)
    require(len(funcs) >= 25, f"unexpectedly small function surface: {len(funcs)}")

    required_functions = ["Get-AddonPolicyRegistry", "Get-AddonInventory", "Update-AutoApps", "Rollback-LastTransaction"]
    for name in required_functions:
        require(name in funcs, f"required function missing: {name}")

    registry = funcs["Get-AddonPolicyRegistry"]
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    require(sorted(x.lower() for x in auto) == sorted(x.lower() for x in EXPECTED_AUTO), f"automatic mutation authority drifted: {auto}")

    protected_markers = {
        "tagify": ["name='tagify'", "mutation_mode='deny'", "protect-ratings-tags-notes"],
        "splitify": ["name='splitify'", "mutation_mode='deny'", "preserve-installed-content"],
        "star-ratings": ["name='star-ratings'", "mutation_mode='deny'", "playlist-backed-ratings-preserve"],
        "sc-cover-ambience": ["name='sc-cover-ambience.js'", "mutation_mode='deny'", "never-disable-or-optimize"],
    }
    for addon, markers in protected_markers.items():
        for marker in markers:
            require(marker.lower() in registry.lower(), f"protected registry contract missing for {addon}: {marker}")

    update = funcs["Update-AutoApps"]
    for forbidden in ("tagify", "splitify", "star-ratings", "sc-cover-ambience"):
        require(forbidden not in update.lower(), f"unexpected protected addon mutation route already exists: {forbidden}")

    rollback = funcs["Rollback-LastTransaction"]
    require("Assert-AddonSourceAdapterTransactionAuthorization" not in rollback, "RollbackLast became source-adapter-dependent")

    persistence_terms = [
        "IndexedDB", "localStorage", "Local Storage", "Browser", "Default", "preferences", "prefs",
        "settings", "storage", "database", "state.json", "config-xpui", "marketplace"
    ]
    lifecycle_terms = [
        "backup", "snapshot", "restore", "rollback", "transaction", "staging", "journal", "commit"
    ]
    ownership_terms = [
        "marketplace-owned", "recovery-owned", "external-owner", "owner-cleanup-only", "installed-only",
        "extension", "custom app", "custom_apps", "customapps"
    ]
    mutation_terms = [
        "Remove-Item", "Copy-Item", "Move-Item", "Set-Content", "Add-Content", "Rename-Item",
        "spicetify apply", "spicetify config"
    ]

    persistence_hits = functions_containing(funcs, persistence_terms)
    lifecycle_hits = functions_containing(funcs, lifecycle_terms)
    ownership_hits = functions_containing(funcs, ownership_terms)
    mutation_hits = functions_containing(funcs, mutation_terms)

    # A true generic settings-preservation layer must be explicit enough to be auditable: it must
    # combine persistence/data semantics with backup/snapshot/restore/transaction semantics in one helper.
    generic_persistence_helpers: list[str] = []
    for name, block in funcs.items():
        lower = block.lower()
        has_persistence = any(term.lower() in lower for term in persistence_terms)
        has_lifecycle = any(term.lower() in lower for term in ("backup", "snapshot", "restore", "rollback", "transaction"))
        if has_persistence and has_lifecycle:
            generic_persistence_helpers.append(name)
    generic_persistence_helpers.sort()

    # Inventory must already be dynamic enough to enumerate installed extension/app surfaces; this is
    # prerequisite evidence only, not permission to mutate newly discovered addons.
    inventory = funcs["Get-AddonInventory"]
    inventory_lower = inventory.lower()
    dynamic_inventory_signals = {
        "extensions": "extension" in inventory_lower,
        "custom_apps": ("custom_apps" in inventory_lower or "customapps" in inventory_lower or "custom app" in inventory_lower),
        "marketplace": "marketplace" in inventory_lower,
        "registry_enrichment": "add-addonpolicyregistrymetadata" in inventory_lower,
    }

    # Current r17 is intentionally not the final requested lifecycle: protected addons remain denied and
    # unknown/new sources fail closed. Record this as an evidence-backed gap rather than changing production.
    final_goal_gaps = {
        "tagify_settings_preserving_auto_update": True,
        "splitify_settings_preserving_auto_update": True,
        "star_ratings_settings_preserving_auto_update": True,
        "sc_cover_ambience_settings_preserving_auto_update": True,
        "generic_new_marketplace_addon_auto_onboarding": True,
        "user_uninstall_tombstone_or_intent_tracking": True,
        "generic_persistence_snapshot_contract": len(generic_persistence_helpers) == 0,
    }

    report = {
        "schema": 1,
        "base_commit": "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2",
        "stable": {"main_version": "0.6.28", "addon_version": "0.6.5-r17"},
        "exact_reconstruction": {
            "main": {"size": len(main_bytes), "sha256": sha256(main_bytes)},
            "addon": {"size": len(addon_bytes), "sha256": sha256(addon_bytes)},
        },
        "function_count": len(funcs),
        "function_names": sorted(funcs),
        "automatic_mutation_authority": auto,
        "protected_mutation_denied": sorted(protected_markers),
        "dynamic_inventory_signals": dynamic_inventory_signals,
        "persistence_surface_functions": persistence_hits,
        "transaction_lifecycle_functions": lifecycle_hits,
        "ownership_surface_functions": ownership_hits,
        "mutation_surface_functions": mutation_hits,
        "generic_persistence_helpers": generic_persistence_helpers,
        "final_goal_gaps": final_goal_gaps,
        "production_change_made": False,
        "authority_expanded": False,
        "next_design_target": "settings-preserving marketplace/custom-app lifecycle layer with uninstall-intent tracking and fail-closed onboarding",
    }

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")

    print("SETTINGS_PRESERVING_MARKETPLACE_LIFECYCLE_AUDIT_PASS")
    print("EXACT_R17", len(addon_bytes), sha256(addon_bytes))
    print("AUTO_AUTHORITY=" + "|".join(auto))
    print("GENERIC_PERSISTENCE_HELPERS=" + "|".join(generic_persistence_helpers))
    print("DYNAMIC_INVENTORY=" + json.dumps(dynamic_inventory_signals, sort_keys=True))
    print("FINAL_GOAL_GAPS=" + json.dumps(final_goal_gaps, sort_keys=True))
    print("PRODUCTION_CHANGE_MADE=false")
    print("AUTHORITY_EXPANDED=false")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"SETTINGS_PRESERVING_MARKETPLACE_LIFECYCLE_AUDIT_FAIL: {exc}", file=sys.stderr)
        raise
