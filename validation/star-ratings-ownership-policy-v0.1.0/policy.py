from __future__ import annotations

from dataclasses import dataclass, asdict
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
BASE = "25daf4a295e7737bd12e96b584467da53245e37a"
POLICY_ID = "star-ratings-ownership-policy-v0.1.0"
ORIGINAL = "198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1"
TRANSFORMED = "6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3"
PERF_ID = "star-ratings-observer-debounce-v1"
CURRENT_AUTOMATIC_MUTATION_ALLOWLIST = (
    "better-local-files",
    "eternal-jukebox",
    "ivLyrics",
    "playlist-maker",
)
OUT = ROOT / "validation/star-ratings-ownership-policy-v0.1.0/report.json"


@dataclass(frozen=True)
class Evidence:
    marketplace_installed: bool | None
    marketplace_complete: bool
    marketplace_stable: bool
    configured_active: bool | None
    local_sha256: str | None
    active_sha256: str | None
    performance_state_exists: bool
    performance_contract_valid: bool


def decide(e: Evidence) -> dict:
    risks: list[str] = []
    complete = (
        e.marketplace_installed is not None
        and e.configured_active is not None
        and e.marketplace_complete
        and e.marketplace_stable
    )
    if not complete:
        topology = "inconclusive"
        risks.append("incomplete-or-unstable-ownership-evidence")
    elif e.marketplace_installed and e.configured_active:
        topology = "dual-owned-risk"
        risks.append("marketplace-and-persistent-config-coexist")
    elif e.marketplace_installed:
        topology = "marketplace-only-likely"
    elif e.configured_active:
        topology = "configured-only-likely"
    else:
        topology = "absent"

    known = {ORIGINAL, TRANSFORMED}
    if e.configured_active:
        if e.local_sha256 not in known:
            risks.append("unknown-local-source-bytes")
        if e.active_sha256 not in known:
            risks.append("unknown-active-bytes")
    if e.performance_state_exists and not e.performance_contract_valid:
        risks.append("invalid-performance-state-contract")

    if e.marketplace_installed:
        owner_candidate = "marketplace"
    elif e.configured_active:
        owner_candidate = "configured-local"
    else:
        owner_candidate = "none"

    # v0.1.0 is intentionally decision-only. It never authorizes migration or
    # mutation, even for a clean single-owner topology. A future release must
    # separately validate an exact transactional migration/update mechanism.
    return {
        "policy": POLICY_ID,
        "topology": topology,
        "canonical_owner_candidate": owner_candidate,
        "risk_flags": sorted(set(risks)),
        "monitoring_allowed": True,
        "mutation_authorized": False,
        "migration_authorized": False,
        "migration_action": "none",
        "delete_local_file": False,
        "edit_spicetify_config": False,
        "edit_marketplace_storage": False,
        "run_spicetify_apply": False,
        "restart_spotify": False,
        "playlist_contract": "playlist-backed-ratings-preserve",
        "performance_contract": PERF_ID,
        "safe_to_expand_mutation_authority": False,
    }


def case(name: str, evidence: Evidence, topology: str, owner: str, required_risks: tuple[str, ...] = ()) -> dict:
    result = decide(evidence)
    assert result["topology"] == topology, (name, result)
    assert result["canonical_owner_candidate"] == owner, (name, result)
    for risk in required_risks:
        assert risk in result["risk_flags"], (name, risk, result)
    for key in (
        "mutation_authorized",
        "migration_authorized",
        "delete_local_file",
        "edit_spicetify_config",
        "edit_marketplace_storage",
        "run_spicetify_apply",
        "restart_spotify",
        "safe_to_expand_mutation_authority",
    ):
        assert result[key] is False, (name, key, result)
    assert result["migration_action"] == "none"
    assert result["playlist_contract"] == "playlist-backed-ratings-preserve"
    assert result["performance_contract"] == PERF_ID
    return {"name": name, "evidence": asdict(evidence), "decision": result}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    target_path = ROOT / "performance/star-ratings/target.json"
    patch_path = ROOT / "performance/star-ratings/apply-star-ratings-patch.ps1"
    target = json.loads(target_path.read_text(encoding="utf-8"))["target"]
    assert target["id"] == PERF_ID
    assert target["expected_size"] == 43396
    assert target["expected_sha256"] == ORIGINAL
    assert target["transformed_sha256"] == TRANSFORMED

    patch = patch_path.read_text(encoding="utf-8")
    for marker in (
        "status = 'already-applied'",
        "state-conflict-newer-or-unknown-active-bytes",
        "conflict-newer-or-unknown-active-bytes",
        "already-original",
        "restored-exact-original",
    ):
        assert marker in patch, marker

    cases = [
        case(
            "real-pc-shaped-dual-known-original-valid-performance-state",
            Evidence(True, True, True, True, ORIGINAL, ORIGINAL, True, True),
            "dual-owned-risk",
            "marketplace",
            ("marketplace-and-persistent-config-coexist",),
        ),
        case(
            "marketplace-only",
            Evidence(True, True, True, False, None, None, False, False),
            "marketplace-only-likely",
            "marketplace",
        ),
        case(
            "configured-only-known-original",
            Evidence(False, True, True, True, ORIGINAL, ORIGINAL, True, True),
            "configured-only-likely",
            "configured-local",
        ),
        case(
            "dual-version-drift",
            Evidence(True, True, True, True, ORIGINAL, "0" * 64, True, True),
            "dual-owned-risk",
            "marketplace",
            ("marketplace-and-persistent-config-coexist", "unknown-active-bytes"),
        ),
        case(
            "configured-unknown-local-bytes",
            Evidence(False, True, True, True, "f" * 64, "f" * 64, False, False),
            "configured-only-likely",
            "configured-local",
            ("unknown-local-source-bytes", "unknown-active-bytes"),
        ),
        case(
            "dual-known-transformed-active",
            Evidence(True, True, True, True, ORIGINAL, TRANSFORMED, True, True),
            "dual-owned-risk",
            "marketplace",
            ("marketplace-and-persistent-config-coexist",),
        ),
        case(
            "invalid-performance-state",
            Evidence(True, True, True, True, ORIGINAL, ORIGINAL, True, False),
            "dual-owned-risk",
            "marketplace",
            ("invalid-performance-state-contract",),
        ),
        case(
            "unstable-marketplace-evidence",
            Evidence(True, True, False, True, ORIGINAL, ORIGINAL, True, True),
            "inconclusive",
            "marketplace",
            ("incomplete-or-unstable-ownership-evidence",),
        ),
        case(
            "unknown-marketplace-state",
            Evidence(None, False, False, True, ORIGINAL, ORIGINAL, True, True),
            "inconclusive",
            "configured-local",
            ("incomplete-or-unstable-ownership-evidence",),
        ),
        case(
            "absent",
            Evidence(False, True, True, False, None, None, False, False),
            "absent",
            "none",
        ),
    ]

    # The policy itself cannot add Star Ratings to automatic mutation authority.
    assert "star-ratings" not in CURRENT_AUTOMATIC_MUTATION_ALLOWLIST
    assert CURRENT_AUTOMATIC_MUTATION_ALLOWLIST == (
        "better-local-files", "eternal-jukebox", "ivLyrics", "playlist-maker"
    )

    report = {
        "schema": 1,
        "policy": POLICY_ID,
        "result": "POLICY_MATRIX_PASS",
        "stable_base": BASE,
        "real_pc_gate_result": "dual-owned-risk",
        "production_decision": "do-not-expand-star-ratings-mutation-authority",
        "canonical_owner_candidate": "marketplace",
        "migration_authorized": False,
        "mutation_authority_change": False,
        "user_data_mutation": False,
        "playlist_contract": "playlist-backed-ratings-preserve",
        "performance_contract": {
            "id": PERF_ID,
            "target_sha256": sha256(target_path),
            "patch_sha256": sha256(patch_path),
            "original_sha256": ORIGINAL,
            "transformed_sha256": TRANSFORMED,
        },
        "automatic_mutation_allowlist_expected_unchanged": list(CURRENT_AUTOMATIC_MUTATION_ALLOWLIST),
        "cases": cases,
        "next_gate": "separate-transactional-ownership-migration-validation-before-any-real-pc-change",
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print("STAR_RATINGS_OWNERSHIP_POLICY_MATRIX_PASS", f"cases={len(cases)}", "decision=deny-mutation")


if __name__ == "__main__":
    main()
