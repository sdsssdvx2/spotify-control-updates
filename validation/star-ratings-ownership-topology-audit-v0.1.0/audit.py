from __future__ import annotations

from pathlib import Path
import hashlib
import json
import re
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BASE = "25daf4a295e7737bd12e96b584467da53245e37a"
MARKETPLACE_REPO = "spicetify/marketplace"
MARKETPLACE_COMMIT = "7f357885a3514a55d426fd43edfd705d583a5cdd"
STAR_REPO = "brimell/spicetify-star-ratings"
STAR_COMMIT = "0698684b95a984b6726618e1b4541e0f830b93f2"
STAR_VERSION = "2.1.3"
STAR_DIST_SIZE = 43396
STAR_DIST_SHA256 = "198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1"
OUT = ROOT / "validation/star-ratings-ownership-topology-audit-v0.1.0/ownership-topology-audit.json"


def raw(repo: str, commit: str, path: str) -> bytes:
    url = f"https://raw.githubusercontent.com/{repo}/{commit}/{path}"
    req = urllib.request.Request(url, headers={"User-Agent": "spotify-control-validation"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(text: str, markers: list[str], label: str) -> None:
    for marker in markers:
        if marker not in text:
            raise RuntimeError(f"{label} contract marker missing: {marker}")


def function_block(text: str, name: str) -> str:
    match = re.search(rf"(?m)^export const {re.escape(name)}\s*=\s*\([^\n]*\)\s*=>\s*\{{", text)
    if not match:
        raise RuntimeError(f"function not found: {name}")
    start = match.start()
    depth = 0
    opened = False
    for index in range(match.end() - 1, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
            opened = True
        elif char == "}":
            depth -= 1
            if opened and depth == 0:
                return text[start : index + 1]
    raise RuntimeError(f"unterminated function: {name}")


def main() -> None:
    if subprocess.check_output(["git", "merge-base", BASE, "HEAD"], cwd=ROOT, text=True).strip() != BASE:
        raise RuntimeError("ownership audit is not based on exact stable v0.6.27 main")

    marketplace_card_b = raw(MARKETPLACE_REPO, MARKETPLACE_COMMIT, "src/components/Card/Card.tsx")
    marketplace_loader_b = raw(MARKETPLACE_REPO, MARKETPLACE_COMMIT, "src/extensions/extension.tsx")
    marketplace_utils_b = raw(MARKETPLACE_REPO, MARKETPLACE_COMMIT, "src/logic/Utils.ts")
    star_manifest_b = raw(STAR_REPO, STAR_COMMIT, "manifest.json")
    star_readme_b = raw(STAR_REPO, STAR_COMMIT, "README.md")
    star_dist_b = raw(STAR_REPO, STAR_COMMIT, "dist/star-ratings.js")

    marketplace_card = marketplace_card_b.decode("utf-8")
    marketplace_loader = marketplace_loader_b.decode("utf-8")
    marketplace_utils = marketplace_utils_b.decode("utf-8")
    star_manifest = json.loads(star_manifest_b.decode("utf-8"))
    star_readme = star_readme_b.decode("utf-8")

    require(
        marketplace_card,
        [
            "async refreshInstalledItem()",
            "const hasUpdate = this.state.lastUpdated !== pushed_at;",
            "await this.installExtension(recordMeta);",
            "async installExtension",
            "marketplaceStorage.mutateAsync",
            "LOCALSTORAGE_KEYS.installedExtensions",
        ],
        "Marketplace installed-extension refresh",
    )
    require(
        marketplace_loader,
        [
            "script.src = extensionManifest.extensionURL;",
            "script.src = `https://cdn.jsdelivr.${tld}/gh/${user}/${repo}@${branch}/${filePath}`;",
            "script.src = `${script.src}?time=${Date.now()}`;",
            "document.body.appendChild(script);",
            "addExtensionToSpicetifyConfig(extensionManifest.manifest?.main);",
        ],
        "Marketplace extension loader",
    )

    add_config = function_block(marketplace_utils, "addExtensionToSpicetifyConfig")
    require(add_config, ["Spicetify.Config.extensions.push(name);"], "Marketplace runtime config helper")
    for forbidden in ("marketplaceStorage", "localStorage", "fetch(", "Spicetify.Config.apply", "spicetify apply"):
        if forbidden.lower() in add_config.lower():
            raise RuntimeError(f"Marketplace runtime config helper unexpectedly gained persistence/side effect: {forbidden}")

    if star_manifest.get("main") != "dist/star-ratings.js":
        raise RuntimeError(f"Star Ratings manifest main drifted: {star_manifest.get('main')!r}")
    require(
        star_readme,
        [
            'Install "Star Ratings" from the Marketplace',
            "All ratings are stored in spotify itself",
            "designated rating playlists",
        ],
        "Star Ratings README",
    )
    if len(star_dist_b) != STAR_DIST_SIZE or sha256(star_dist_b) != STAR_DIST_SHA256:
        raise RuntimeError(
            f"Star Ratings {STAR_VERSION} dist identity drifted: {len(star_dist_b)} {sha256(star_dist_b)}"
        )

    # Public source proves that Marketplace owns a dynamic remote-script path and that the
    # Star Ratings upstream explicitly instructs Marketplace installation.  It cannot prove
    # whether a particular user's separately configured local sc-star-ratings.js is also active.
    # Therefore any new mutation authority must remain denied until a read-only runtime topology
    # check distinguishes Marketplace-only, configured-only, or dual-loaded ownership.
    report = {
        "schema": 1,
        "audit": "star-ratings-ownership-topology-audit-v0.1.0",
        "result": "AUDIT_PASS",
        "stable_base": BASE,
        "marketplace": {
            "repository": MARKETPLACE_REPO,
            "commit": MARKETPLACE_COMMIT,
            "card_sha256": sha256(marketplace_card_b),
            "loader_sha256": sha256(marketplace_loader_b),
            "utils_sha256": sha256(marketplace_utils_b),
            "installed_refresh_signal": "repository-pushed_at",
            "installed_refresh_action": "rewrite-marketplace-extension-record",
            "runtime_loader": "extensionURL -> jsdelivr @ stored branch -> DOM script",
            "config_helper": "runtime Spicetify.Config.extensions push only",
            "release_tag_pin_enforced_by_marketplace": False,
        },
        "star_ratings": {
            "repository": STAR_REPO,
            "version": STAR_VERSION,
            "commit": STAR_COMMIT,
            "manifest_main": star_manifest.get("main"),
            "dist_size": len(star_dist_b),
            "dist_sha256": sha256(star_dist_b),
            "upstream_install_owner": "Marketplace",
            "ratings_storage": "Spotify rating playlists",
        },
        "production_contract": {
            "current_policy": "source-watch-only / mutation deny / marketplace-owned",
            "safe_to_expand_mutation_authority_from_public_source_only": False,
            "reason": "public source cannot distinguish Marketplace-only, configured-local-only, or dual-loaded ownership on the user's machine",
            "next_gate": "read-only real-PC ownership topology evidence",
            "required_runtime_evidence": [
                "whether Marketplace installedExtensions contains Star Ratings",
                "stored Star Ratings extensionURL/branch without exposing unrelated Marketplace data",
                "whether Spicetify persistent config separately contains sc-star-ratings.js",
                "exact local/rescue and active xpui SHA-256 identities",
                "whether both loading paths are simultaneously active",
            ],
            "mutation_authority_change": False,
            "user_data_mutation": False,
        },
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(
        "STAR_RATINGS_OWNERSHIP_TOPOLOGY_AUDIT_PASS",
        f"marketplace={MARKETPLACE_COMMIT}",
        f"star={STAR_VERSION}:{STAR_DIST_SHA256}",
        "next_gate=read-only-real-pc-topology",
    )


if __name__ == "__main__":
    main()
