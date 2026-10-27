from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE_MAIN = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
EXPECTED_ADDON_SIZE = 323385
EXPECTED_ADDON_SHA = "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"
EXPECTED_REGISTRY_SHA = "0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8"
EXPECTED_SOURCE_ADAPTER_SHA = "c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d"
EXPECTED_AUTO = ["better-local-files", "eternal-jukebox", "ivLyrics", "playlist-maker"]
OUT = ROOT / "validation/auto-authority-provenance-gap-audit-v0.1.0/audit-result.json"
ADDON = ROOT / "validation/v0.6.28/out/bin/addon-manager.ps1"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def function_blocks(text: str) -> dict[str, str]:
    hits = list(re.finditer(r"(?m)^function\s+([A-Za-z0-9_-]+)\s*\{", text))
    out: dict[str, str] = {}
    for i, hit in enumerate(hits):
        end = hits[i + 1].start() if i + 1 < len(hits) else len(text)
        out[hit.group(1)] = text[hit.start():end]
    return out


def relevant_functions(blocks: dict[str, str], needles: tuple[str, ...]) -> list[str]:
    lowered = tuple(n.lower() for n in needles)
    return sorted(
        name for name, block in blocks.items()
        if any(n in block.lower() or n in name.lower() for n in lowered)
    )


def signal(text: str, token: str) -> bool:
    return token.lower() in text.lower()


def api_json(url: str):
    headers = {"User-Agent": "spotify-control-auto-authority-gap-audit-v010", "Accept": "application/vnd.github+json"}
    token = os.environ.get("GH_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"Bearer {token}"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def subset(blocks: dict[str, str], names: list[str]) -> str:
    return "\n".join(blocks[n] for n in names)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--online", action="store_true")
    args = parser.parse_args()

    head = git("rev-parse", "HEAD")
    if git("merge-base", BASE_MAIN, "HEAD") != BASE_MAIN:
        raise SystemExit(f"audit branch no longer descends from exact production base {BASE_MAIN}")

    subprocess.check_call([sys.executable, str(ROOT / "validation/v0.6.28/build_v0628.py"), "--build"], cwd=ROOT)
    raw = ADDON.read_bytes()
    if (len(raw), sha256(raw)) != (EXPECTED_ADDON_SIZE, EXPECTED_ADDON_SHA):
        raise SystemExit(f"r17 identity drift: {len(raw)} {sha256(raw)}")
    text = raw.decode("utf-8-sig")
    if '$Version = "0.6.5-r17"' not in text:
        raise SystemExit("r17 version marker missing")

    blocks = function_blocks(text)
    pithaya_names = relevant_functions(blocks, ("pithaya", "spicetify-apps-dist"))
    iv_names = relevant_functions(blocks, ("ivlyrics", "ivLis-Studio/ivLyrics"))
    registry = blocks.get("Get-AddonPolicyRegistry", "")
    adapter = blocks.get("Get-AddonSourceAdapterCatalog", "")
    if not registry or not adapter:
        raise SystemExit("policy/source adapter registry not found in exact r17")

    auto = sorted(re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, flags=re.I))
    if auto != sorted(EXPECTED_AUTO):
        raise SystemExit(f"automatic mutation authority drift: {auto}")
    for required in (
        "name='tagify'", "name='splitify'", "name='star-ratings'",
        "name='sc-cover-ambience.js'", "name='sc-star-ratings.js'",
        "never-disable-or-optimize", "playlist-backed-ratings-preserve", "protect-ratings-tags-notes",
    ):
        if required.lower() not in registry.lower():
            raise SystemExit(f"protected registry contract missing: {required}")

    ptext = subset(blocks, pithaya_names)
    itext = subset(blocks, iv_names)

    static = {
        "exact_r17": {"size": len(raw), "sha256": sha256(raw)},
        "function_count": len(blocks),
        "automatic_authority": auto,
        "pithaya_functions": pithaya_names,
        "ivlyrics_functions": iv_names,
        "pithaya_signals": {
            "zip_safety": "Test-PithayaZipArchiveSafety" in blocks,
            "pinned_stage": "Download-PithayaPinnedStage" in blocks,
            "directory_git_snapshot_reference": signal(ptext, "Get-DirectoryGitSnapshot"),
            "tree_sha_reference": signal(ptext, "tree_sha") or signal(ptext, "tree sha"),
            "archive_sha256_reference": signal(ptext, "archive_sha256") or signal(ptext, "Get-FileHash"),
            "commit_archive_url_reference": signal(ptext, "archive/refs") or signal(ptext, "zipball") or signal(ptext, "/zip/") or signal(ptext, "codeload"),
            "expand_archive_reference": signal(ptext, "Expand-Archive"),
            "branch_names_present": sorted(set(re.findall(r"dist/(?:better-local-files|eternal-jukebox|playlist-maker)", ptext, flags=re.I))),
        },
        "ivlyrics_signals": {
            "zip_safety": "Test-IvLyricsZipArchiveSafety" in blocks,
            "official_tag_proof_selftest": "Invoke-IvLyricsOfficialTagProofOnlineSelfTest" in blocks,
            "directory_git_snapshot_reference": signal(itext, "Get-DirectoryGitSnapshot"),
            "release_asset_reference": signal(itext, "assets") or signal(itext, "browser_download_url"),
            "github_asset_digest_reference": signal(itext, ".digest") or signal(itext, "digest"),
            "sha256_sidecar_reference": signal(itext, ".sha256"),
            "archive_sha256_reference": signal(itext, "archive_sha256") or signal(itext, "Get-FileHash"),
            "tag_commit_reference": signal(itext, "tag") and (signal(itext, "commit") or signal(itext, "refs/tags")),
            "expand_archive_reference": signal(itext, "Expand-Archive"),
        },
        "registry_fingerprint_expected": EXPECTED_REGISTRY_SHA,
        "source_adapter_fingerprint_expected": EXPECTED_SOURCE_ADAPTER_SHA,
    }

    online = None
    if args.online:
        p_branches = api_json("https://api.github.com/repos/Pithaya/spicetify-apps-dist/branches?per_page=100")
        p_manifest = api_json("https://api.github.com/repos/Pithaya/spicetify-apps-dist/contents/manifest.json?ref=main")
        iv_latest = api_json("https://api.github.com/repos/ivLis-Studio/ivLyrics/releases/latest")
        p_map = {x["name"]: x["commit"]["sha"] for x in p_branches if x["name"].startswith("dist/")}
        iv_assets = [
            {
                "name": x.get("name"),
                "size": x.get("size"),
                "digest": x.get("digest"),
                "content_type": x.get("content_type"),
            }
            for x in iv_latest.get("assets", [])
        ]
        online = {
            "pithaya": {
                "dist_branch_heads": dict(sorted(p_map.items())),
                "main_manifest_blob_sha": p_manifest.get("sha"),
                "main_manifest_size": p_manifest.get("size"),
            },
            "ivlyrics": {
                "latest_tag": iv_latest.get("tag_name"),
                "published_at": iv_latest.get("published_at"),
                "prerelease": iv_latest.get("prerelease"),
                "draft": iv_latest.get("draft"),
                "assets": iv_assets,
                "has_zip_asset": any(x.get("name") == "ivLyrics.zip" for x in iv_assets),
                "has_sha256_sidecar": any(x.get("name") == "ivLyrics.zip.sha256" for x in iv_assets),
                "zip_has_github_digest": any(x.get("name") == "ivLyrics.zip" and str(x.get("digest", "")).startswith("sha256:") for x in iv_assets),
            },
        }

    # This is a prioritization result, not a mutation authorization decision.
    # Prefer a defense-in-depth audit where upstream exposes a stronger immutable checksum
    # than the current exact-r17 implementation visibly consumes.
    recommendation = {
        "target": None,
        "reason": None,
        "authority_change_recommended": False,
        "production_mutation_change_recommended": False,
    }
    if online:
        iv = online["ivlyrics"]
        ivs = static["ivlyrics_signals"]
        if iv["zip_has_github_digest"] and not ivs["github_asset_digest_reference"]:
            recommendation["target"] = "ivLyrics"
            recommendation["reason"] = "latest official release exposes a GitHub SHA-256 asset digest that exact r17 does not visibly consume; audit digest pinning as defense-in-depth while preserving existing exact-tree/tag proof"
        elif iv["has_sha256_sidecar"] and not ivs["sha256_sidecar_reference"]:
            recommendation["target"] = "ivLyrics"
            recommendation["reason"] = "latest official release exposes a SHA-256 sidecar not visibly consumed by exact r17; audit checksum consumption as defense-in-depth"
        else:
            recommendation["target"] = "Pithaya"
            recommendation["reason"] = "ivLyrics already consumes available release checksum evidence; next compare Pithaya mutable dist-branch head anchoring against exact commit/tree staging"

    report = {
        "schema": 1,
        "audit": "auto-authority-provenance-gap-v0.1.0",
        "production_base": BASE_MAIN,
        "validation_head": head,
        "read_only": True,
        "mutation_performed": False,
        "authority_expanded": False,
        "static": static,
        "online": online,
        "recommendation": recommendation,
    }
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print("AUTO_AUTHORITY_PROVENANCE_GAP_AUDIT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
