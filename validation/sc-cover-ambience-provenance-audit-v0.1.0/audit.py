from __future__ import annotations

from collections import OrderedDict
from pathlib import Path
import hashlib
import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BASE = "25daf4a295e7737bd12e96b584467da53245e37a"
UPSTREAM = "Theblockbuster1/spicetify-extensions"
SOURCE_PATH = "CoverAmbience/CoverAmbience.js"
MANIFEST_PATH = "manifest.json"
OUT = ROOT / "validation/sc-cover-ambience-provenance-audit-v0.1.0/catalog.json"
USER_AGENT = "spotify-control-sc-cover-ambience-provenance-audit"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def request(url: str) -> bytes:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=45) as response:
        return response.read()


def api_json(url: str):
    return json.loads(request(url).decode("utf-8"))


def raw(commit: str, path: str) -> bytes:
    quoted = "/".join(urllib.parse.quote(part, safe="") for part in path.split("/"))
    url = f"https://raw.githubusercontent.com/{UPSTREAM}/{urllib.parse.quote(commit, safe='')}/{quoted}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise FileNotFoundError(f"{UPSTREAM}@{commit}:{path}") from exc
        raise


def list_path_commits() -> list[dict]:
    commits: list[dict] = []
    page = 1
    encoded_path = urllib.parse.quote(SOURCE_PATH, safe="")
    while True:
        url = (
            f"https://api.github.com/repos/{UPSTREAM}/commits"
            f"?path={encoded_path}&per_page=100&page={page}"
        )
        batch = api_json(url)
        if not isinstance(batch, list):
            raise RuntimeError("GitHub path commit response was not a list")
        commits.extend(batch)
        if len(batch) < 100:
            break
        page += 1
        if page > 20:
            raise RuntimeError("unexpectedly large Cover Ambience path history")
    if not commits:
        raise RuntimeError("no Cover Ambience path commits found")
    return commits


def main() -> None:
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    merge_base = subprocess.check_output(["git", "merge-base", BASE, "HEAD"], cwd=ROOT, text=True).strip()
    if merge_base != BASE:
        raise RuntimeError(f"audit is not based on exact stable v0.6.27 main: {merge_base}")

    repo = api_json(f"https://api.github.com/repos/{UPSTREAM}")
    if repo.get("full_name") != UPSTREAM or repo.get("archived") or repo.get("disabled"):
        raise RuntimeError("upstream repository identity/state drifted")
    default_branch = str(repo.get("default_branch") or "")
    if default_branch != "main":
        raise RuntimeError(f"unexpected upstream default branch: {default_branch!r}")

    releases = api_json(f"https://api.github.com/repos/{UPSTREAM}/releases?per_page=100")
    tags = api_json(f"https://api.github.com/repos/{UPSTREAM}/tags?per_page=100")
    if not isinstance(releases, list) or not isinstance(tags, list):
        raise RuntimeError("upstream release/tag response shape drifted")

    manifest_bytes = raw(default_branch, MANIFEST_PATH)
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    cover_entries = [
        row for row in manifest
        if isinstance(row, dict) and row.get("name") == "Cover Ambience"
    ]
    if len(cover_entries) != 1:
        raise RuntimeError(f"Cover Ambience manifest entry count drifted: {len(cover_entries)}")
    cover = cover_entries[0]
    if cover.get("main") != SOURCE_PATH:
        raise RuntimeError(f"Cover Ambience manifest main drifted: {cover.get('main')!r}")

    commits = list_path_commits()
    groups: OrderedDict[tuple[int, str], dict] = OrderedDict()
    missing_at_commit: list[str] = []
    for index, commit in enumerate(commits):
        commit_sha = str(commit.get("sha") or "")
        if len(commit_sha) != 40:
            raise RuntimeError(f"invalid path commit SHA at index {index}: {commit_sha!r}")
        try:
            data = raw(commit_sha, SOURCE_PATH)
        except FileNotFoundError:
            # Keep deletion/path-transition commits visible but never treat them as provenance.
            missing_at_commit.append(commit_sha)
            continue
        key = (len(data), sha256(data))
        c = commit.get("commit") or {}
        author = c.get("author") or {}
        meta = {
            "commit": commit_sha,
            "date": author.get("date"),
            "message": str(c.get("message") or "").splitlines()[0],
            "verified": bool(((c.get("verification") or {}).get("verified"))),
        }
        if key not in groups:
            groups[key] = {
                "size": key[0],
                "sha256": key[1],
                "commits": [],
            }
        groups[key]["commits"].append(meta)

    if not groups:
        raise RuntimeError("no hashable official Cover Ambience snapshots found")

    current = raw(default_branch, SOURCE_PATH)
    current_key = (len(current), sha256(current))
    current_group = groups.get(current_key)
    if current_group is None:
        raise RuntimeError("current main Cover Ambience bytes are absent from path history catalog")

    latest_path_commit = str(commits[0].get("sha") or "")
    latest_commit_bytes = raw(latest_path_commit, SOURCE_PATH)
    if latest_commit_bytes != current:
        raise RuntimeError(
            "current default-branch Cover Ambience bytes differ from latest path commit bytes"
        )

    snapshots = []
    for ordinal, row in enumerate(groups.values(), start=1):
        commits_for_bytes = row["commits"]
        snapshots.append(
            {
                "snapshot": ordinal,
                "size": row["size"],
                "sha256": row["sha256"],
                "latest_commit": commits_for_bytes[0]["commit"],
                "latest_date": commits_for_bytes[0]["date"],
                "commit_count": len(commits_for_bytes),
                "commits": commits_for_bytes,
                "is_current": (row["size"], row["sha256"]) == current_key,
            }
        )

    # Hash the canonical provenance payload itself so a later candidate can pin the exact audit catalog.
    catalog_payload = {
        "repository": UPSTREAM,
        "path": SOURCE_PATH,
        "default_branch": default_branch,
        "snapshots": snapshots,
    }
    catalog_bytes = (
        json.dumps(catalog_payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
    ).encode("utf-8")
    catalog_sha = sha256(catalog_bytes)

    report = {
        "schema": 1,
        "audit": "sc-cover-ambience-provenance-audit-v0.1.0",
        "result": "AUDIT_PASS",
        "stable_base": BASE,
        "validation_head": actual,
        "upstream": {
            "repository": UPSTREAM,
            "repository_id": repo.get("id"),
            "default_branch": default_branch,
            "archived": bool(repo.get("archived")),
            "disabled": bool(repo.get("disabled")),
            "license": ((repo.get("license") or {}).get("spdx_id")),
            "release_count": len(releases),
            "tag_count": len(tags),
            "manifest_sha256": sha256(manifest_bytes),
            "manifest_entry": cover,
            "source_path": SOURCE_PATH,
            "path_commit_count": len(commits),
            "path_missing_commit_count": len(missing_at_commit),
            "path_missing_commits": missing_at_commit,
            "snapshot_count": len(snapshots),
            "current": {
                "size": len(current),
                "sha256": sha256(current),
                "latest_path_commit": latest_path_commit,
                "latest_path_commit_date": (commits[0].get("commit") or {}).get("author", {}).get("date"),
                "latest_path_commit_message": str((commits[0].get("commit") or {}).get("message") or "").splitlines()[0],
            },
            "snapshots": snapshots,
            "catalog_payload_sha256": catalog_sha,
            "all_commits_unique_by_bytes": all(row["commit_count"] == 1 for row in snapshots),
        },
        "provenance_model": {
            "kind": "official-git-file-snapshot",
            "exact_local_match_inputs": ["size", "sha256"],
            "version_label": "commit-snapshot",
            "can_prove_official_bytes": True,
            "can_always_prove_unique_commit_from_bytes": all(row["commit_count"] == 1 for row in snapshots),
            "current_snapshot_detection": "exact size+sha256 equals default-branch source bytes",
            "historical_snapshot_detection": "exact size+sha256 equals a frozen official path-history snapshot",
            "unknown_or_modified_bytes": "unproven",
        },
        "production_contract": {
            "current_policy": "rescue-copy-cleanup-only / mutation deny / recovery-owned / never-disable-or-optimize",
            "recommended_next_policy": "ownership-gated read-only commit-snapshot provenance; keep mutation deny and never-disable-or-optimize",
            "safe_for_read_only_provenance": True,
            "safe_to_expand_mutation_authority": False,
            "safe_to_auto_remove_direct_copy_without_runtime_ownership_evidence": False,
            "next_gate": "read-only real-PC Cover Ambience ownership topology evidence",
            "mutation_authority_change": False,
            "auto_install_authority_change": False,
            "user_data_mutation": False,
            "disable_or_optimize": False,
        },
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(
        "SC_COVER_AMBIENCE_PROVENANCE_AUDIT_PASS",
        f"commits={len(commits)}",
        f"snapshots={len(snapshots)}",
        f"current={len(current)}:{sha256(current)}",
        f"catalog={catalog_sha}",
        f"releases={len(releases)}",
        f"tags={len(tags)}",
    )


if __name__ == "__main__":
    main()
