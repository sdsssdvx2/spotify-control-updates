from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
ADDON_PATH = ROOT / "validation/v0.6.28/out/bin/addon-manager.ps1"
ADDON_ID = (323385, "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285")
OUT = ROOT / "validation/pithaya-provenance-audit-v0.1.0/audit-result.json"
BRANCHES = {
    "better-local-files": "dist/better-local-files",
    "eternal-jukebox": "dist/eternal-jukebox",
    "playlist-maker": "dist/playlist-maker",
}
CORE_FUNCTIONS = [
    "Get-PithayaRemote",
    "Download-PithayaPinnedStage",
    "Test-PithayaTreeAgainstRemote",
    "Get-PithayaKnownBaseline",
    "Test-PithayaLocalCurrent",
    "Invoke-PithayaPreflight",
    "Get-DirectoryGitSnapshot",
]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def api(url: str):
    headers = {"User-Agent": "spotify-control-pithaya-provenance-audit-v010", "Accept": "application/vnd.github+json"}
    token = os.environ.get("GH_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"Bearer {token}"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def blocks(text: str) -> dict[str, str]:
    hits = list(re.finditer(r"(?m)^function\s+([A-Za-z0-9_-]+)\s*\{", text))
    out = {}
    for i, hit in enumerate(hits):
        end = hits[i + 1].start() if i + 1 < len(hits) else len(text)
        out[hit.group(1)] = text[hit.start():end].rstrip()
    return out


def body_signals(body: str) -> dict:
    low = body.lower()
    return {
        "sha256": "sha256" in low,
        "get_file_hash": "get-filehash" in low,
        "tree_sha": "tree_sha" in low or "treesha" in low or "tree sha" in low,
        "fingerprint": "fingerprint" in low,
        "revision": "revision" in low,
        "git_tree_api": "/git/trees/" in low,
        "commit_api": "/commits/" in low,
        "branch_api": "/branches/" in low,
        "archive_by_revision": ("/archive/" in low or "zipball" in low or "codeload" in low) and ("revision" in low or "remote." in low),
        "zip_safety_call": "test-pithayaziparchivesafety" in low,
        "expand_archive": "expand-archive" in low,
        "directory_snapshot": "get-directorygitsnapshot" in low,
        "exact_compare": "-cne" in low or "-ceq" in low,
    }


def extract_urls(body: str) -> list[str]:
    return sorted(set(re.findall(r"https?://[^\s\"'`\)]+", body)))


def main() -> int:
    if git("merge-base", BASE, "HEAD") != BASE:
        raise SystemExit("wrong production base")
    subprocess.check_call([sys.executable, str(ROOT / "validation/v0.6.28/build_v0628.py"), "--build"], cwd=ROOT)
    raw = ADDON_PATH.read_bytes()
    if (len(raw), sha(raw)) != ADDON_ID:
        raise SystemExit(f"exact r17 identity drift: {len(raw)} {sha(raw)}")
    text = raw.decode("utf-8-sig")
    fs = blocks(text)
    missing = [name for name in CORE_FUNCTIONS if name not in fs]
    if missing:
        raise SystemExit(f"missing core functions: {missing}")

    core = {}
    for name in CORE_FUNCTIONS:
        body = fs[name]
        core[name] = {
            "chars": len(body),
            "sha256": sha(body.encode("utf-8")),
            "signals": body_signals(body),
            "urls": extract_urls(body),
            "source": body,
        }

    # Static semantic contract of the existing mutation path. These checks do not
    # authorize anything new; they describe what exact production r17 already does.
    remote = fs["Get-PithayaRemote"].lower()
    stage = fs["Download-PithayaPinnedStage"].lower()
    verify = fs["Test-PithayaTreeAgainstRemote"].lower()
    preflight = fs["Invoke-PithayaPreflight"].lower()
    static_contract = {
        "remote_has_revision": "revision" in remote,
        "remote_has_tree_identity": "tree_sha" in remote or "treesha" in remote or "fingerprint" in remote,
        "stage_uses_remote_revision": "revision" in stage and ("remote" in stage or "$revision" in stage),
        "stage_has_zip_safety": "test-pithayaziparchivesafety" in stage,
        "stage_hashes_downloaded_archive": "get-filehash" in stage and "sha256" in stage,
        "verify_compares_directory_snapshot": "get-directorygitsnapshot" in verify,
        "verify_compares_remote_identity": "remote" in verify and ("fingerprint" in verify or "tree_sha" in verify or "revision" in verify),
        "preflight_requires_remote_verification": "test-pithayatreeagainstremote" in preflight or "test-pithayalocalcurrent" in preflight,
    }

    online = {}
    for name, branch_name in BRANCHES.items():
        quoted = urllib.parse.quote(branch_name, safe="")
        branch = api(f"https://api.github.com/repos/Pithaya/spicetify-apps-dist/branches/{quoted}")
        revision = branch["commit"]["sha"]
        commit = api(f"https://api.github.com/repos/Pithaya/spicetify-apps-dist/commits/{revision}")
        tree_sha = commit["commit"]["tree"]["sha"]
        tree = api(f"https://api.github.com/repos/Pithaya/spicetify-apps-dist/git/trees/{tree_sha}?recursive=1")
        files = [x for x in tree.get("tree", []) if x.get("type") == "blob"]
        canonical = "\n".join(f"{x['path']}|{x.get('size', '')}|{x['sha']}" for x in sorted(files, key=lambda x: x["path"].lower())) + "\n"
        online[name] = {
            "branch": branch_name,
            "revision": revision,
            "commit_tree_sha": tree_sha,
            "recursive_tree_truncated": bool(tree.get("truncated")),
            "file_count": len(files),
            "api_tree_catalog_sha256": sha(canonical.encode("utf-8")),
        }

    all_static = all(static_contract.values())
    all_online = all(not x["recursive_tree_truncated"] and re.fullmatch(r"[0-9a-f]{40}", x["revision"]) and re.fullmatch(r"[0-9a-f]{40}", x["commit_tree_sha"]) for x in online.values())
    decision = {
        "existing_path_is_commit_tree_bound": all_static,
        "current_upstream_heads_resolve_to_exact_commit_and_tree": all_online,
        "production_change_justified_by_this_audit": False,
        "authority_change_recommended": False,
        "reason": (
            "exact r17 already binds Pithaya staging to a remote revision/tree identity, hashes the downloaded archive, validates ZIP structure, and compares the staged/local directory snapshot against remote identity; no provenance hardening change is justified solely by this audit"
            if all_static and all_online
            else "one or more existing commit/tree binding invariants are not proven; investigate in validation before any production mutation change"
        ),
    }

    report = {
        "schema": 1,
        "audit": "pithaya-provenance-audit-v0.1.0",
        "production_base": BASE,
        "validation_head": git("rev-parse", "HEAD"),
        "read_only": True,
        "mutation_performed": False,
        "authority_expanded": False,
        "exact_r17": {"size": len(raw), "sha256": sha(raw)},
        "static_contract": static_contract,
        "online": online,
        "decision": decision,
        "core_functions": core,
    }
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print("PITHAYA_PROVENANCE_AUDIT_STATIC", json.dumps(static_contract, sort_keys=True))
    print("PITHAYA_PROVENANCE_AUDIT_ONLINE", json.dumps(online, sort_keys=True))
    print("PITHAYA_PROVENANCE_AUDIT_DECISION", json.dumps(decision, sort_keys=True))
    for name in CORE_FUNCTIONS:
        print(f"===== BEGIN {name} =====")
        print(fs[name])
        print(f"===== END {name} =====")
    print("PITHAYA_PROVENANCE_AUDIT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
