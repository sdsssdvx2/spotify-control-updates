"""R29: read-only verification of the REAL public Spotify Control delivery path.

Tests published GitHub main/manifest.json and raw immutable source_commit
chunks, unlike earlier localhost bootstrap transaction rehearsals. No token,
login, repository write, update, rollback, process control, or filesystem
mutation. The existing official 0.6.28 release is the known public baseline.

An unpublished next stable release is NOT considered available unless:
  * main/manifest.json SHA is externally and independently approved;
  * source_commit is independently pinned to a real 40-hex Git SHA;
  * EXACT 0.6.28 -> 0.6.30 delta, with both main and VBS patches, matches
    pre-agreed binary SHA pins, original addon preserved, no preview 0.6.29;
  * all newest-edge immutable 4KiB chunks verify and decode to target SHA.

This auditor DOES NOT approve a release, deploy R28, or publish anything.
"""
from __future__ import annotations

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import json
import re
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REPO = "sdsssdvx2/spotify-control-updates"
RAW = "https://raw.githubusercontent.com/" + REPO + "/"
BASE_MAIN_COMMIT = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
BASE_PAYLOAD_COMMIT = "bb6d90146f20b73d36fbf8cb813f1b190f403c48"
BASE_LATEST = "0.6.28"
FUTURE_LATEST = "0.6.30"
# Exact approved public R70 transport count; offline historic R30 fixture
# may override this constant only within an isolated Python module.
EXPECTED_NEXT_CHUNKS = 21
BOOTSTRAP = {
    "version": "1.0.6",
    "size": 42963,
    "sha256": "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6",
}
ORIGINAL = {
    "bin/spotify-control.ps1": (284321, "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0"),
    "bin/addon-manager.ps1": (323385, "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"),
    "bin/spotify-control-agent.vbs": (4855, "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278"),
}
FUTURE = {
    "bin/spotify-control.ps1": "b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d",
    "bin/addon-manager.ps1": ORIGINAL["bin/addon-manager.ps1"][1],
    "bin/spotify-control-agent.vbs": "e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5",
}
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
# Bounded official package pathname from Bootstrap 1.0.6.
CHUNK_RE = re.compile(
    r"^packages/v(?P<version>0\.6\.(?:28|30))/"
    r"[a-z0-9._+-]+/chunk-(?P<index>\d{3})\.txt$"
)
HEADERS = {"User-Agent": "SpotifyControl-R29-public-transport-readonly/1"}


def hash_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def download(url: str, max_size: int) -> bytes:
    if not url.startswith(RAW) or not url.startswith("https://"):
        raise RuntimeError("NON_OFFICIAL_RELEASE_URL_FORBIDDEN")
    if any(x in url for x in ("?", "#", "\\", "%", "..")):
        raise RuntimeError("AMBIGUOUS_RELEASE_URL_FORBIDDEN")
    if max_size > 200_000 or max_size < 1:
        raise RuntimeError("UNSAFE_NETWORK_READ_BOUND")
    # urllib raises instead of following a failed transaction; no retries
    # or credential injection. Follow no redirects to a different host.
    class NoForeignRedirect(__import__("urllib.request", fromlist=["HTTPRedirectHandler"]).HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            if not newurl.startswith(RAW):
                raise RuntimeError("FOREIGN_REDIRECT_REJECTED")
            return super().redirect_request(req, fp, code, msg, headers, newurl)
    opener = __import__("urllib.request", fromlist=["build_opener"]).build_opener(NoForeignRedirect)
    req = Request(url, headers=HEADERS)
    try:
        with opener.open(req, timeout=14) as res:
            if res.status != 200:
                raise RuntimeError("RELEASE_HTTP_NON_200")
            if not res.geturl().startswith(RAW):
                raise RuntimeError("RELEASE_REDIRECTED_TO_FOREIGN_HOST")
            data = res.read(max_size + 1)
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        raise RuntimeError("PUBLIC_RELEASE_READ_UNAVAILABLE") from exc
    if not data or len(data) > max_size:
        raise RuntimeError("PUBLIC_RELEASE_BODY_LENGTH_INVALID")
    return data


def parse_manifest(raw: bytes, name: str) -> dict:
    try:
        obj = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("UNPARSABLE_"+name+"_MANIFEST") from exc
    if not isinstance(obj, dict):
        raise RuntimeError("INVALID_"+name+"_MANIFEST_TYPE")
    if (obj.get("channel") != "stable" or
        obj.get("source_repository") != REPO or
        obj.get("bootstrap") != BOOTSTRAP or
        obj.get("min_bootstrap_version") != "1.0.6"):
        raise RuntimeError("UNEXPECTED_"+name+"_RELEASE_AUTHORITY")
    return obj


def newest_edge(obj: dict, expected_from: str, expected_to: str,
                expected_paths: list[str]) -> list[dict]:
    edges = obj.get("updates")
    if not isinstance(edges, list) or not edges:
        raise RuntimeError("UPDATES_NOT_PRESENT")
    edge = edges[-1]
    if edge.get("from_version") != expected_from or edge.get("to_version") != expected_to:
        raise RuntimeError("LATEST_EDGE_UNEXPECTED")
    patches = edge.get("patches")
    if not isinstance(patches, list) or [p.get("path") for p in patches] != expected_paths:
        raise RuntimeError("LATEST_EDGE_PATCH_PATHS_UNEXPECTED")
    return patches


def validate_latest(obj: dict, pins: dict[str, tuple[int, str] | str]) -> None:
    latest = obj.get("latest_files")
    if not isinstance(latest, list) or len(latest) != 3:
        raise RuntimeError("LATEST_FILE_COUNT_DRIFT")
    bypath = {}
    for row in latest:
        p = row.get("path")
        if not isinstance(p, str) or p in bypath:
            raise RuntimeError("LATEST_FILE_DUPLICATE")
        bypath[p] = row
    if set(bypath) != set(pins):
        raise RuntimeError("LATEST_FILE_PATHS_DRIFT")
    for path, expected in pins.items():
        row = bypath[path]
        if not isinstance(row.get("size"), int) or row["size"] <= 0:
            raise RuntimeError("LATEST_FILE_SIZE_NOT_VALID")
        exp_hash = expected[1] if isinstance(expected, tuple) else expected
        if row.get("sha256") != exp_hash:
            raise RuntimeError("LATEST_FILE_SHA_DRIFT")
        if isinstance(expected, tuple) and row.get("size") != expected[0]:
            raise RuntimeError("PUBLISHED_BASELINE_SIZE_DRIFT")
    canonical = "".join(
        f"{path}|{bypath[path]['size']}|{bypath[path]['sha256']}\n"
        for path in sorted(bypath)
    ).encode("ascii")
    if obj.get("payload_set_sha256") != hash_bytes(canonical):
        raise RuntimeError("PAYLOAD_SET_MISMATCH")


def validate_patch_envelope(patches: list[dict], version: str, expected_to: dict[str,str]):
    jobs = []
    for patch in patches:
        path = patch["path"]
        if (patch.get("encoding") != "gzip-base64-full-file" or
            patch.get("to_sha256") != expected_to[path]):
            raise RuntimeError("SOURCE_PATCH_TARGET_MISMATCH")
        for field in ("from_sha256", "to_sha256", "encoded_sha256", "compressed_sha256"):
            if not isinstance(patch.get(field), str) or not HEX64.fullmatch(patch[field]):
                raise RuntimeError("SOURCE_PATCH_HASH_INVALID")
        for field in ("encoded_size", "compressed_size", "target_size"):
            n = patch.get(field)
            if not isinstance(n,int) or not 1 <= n <= 200_000:
                # Target main PS1 can be >200K; only compressed data is <=200K.
                if field != "target_size" or not isinstance(n,int) or not 1 <= n <= 500_000:
                    raise RuntimeError("SOURCE_PATCH_SIZE_EXCESSIVE")
        chunks=patch.get("chunks")
        if not isinstance(chunks,list) or not (1 <= len(chunks) <= 32):
            raise RuntimeError("SOURCE_PATCH_CHUNK_COUNT_INVALID")
        for i,ch in enumerate(chunks):
            name=ch.get("path")
            match=CHUNK_RE.fullmatch(name) if isinstance(name,str) else None
            if not match or match.group("version")!=version or int(match.group("index"))!=i:
                raise RuntimeError("SOURCE_PATCH_CHUNK_PATH_NOT_CANONICAL")
            if not isinstance(ch.get("sha256"),str) or not HEX64.fullmatch(ch["sha256"]):
                raise RuntimeError("SOURCE_PATCH_CHUNK_SHA_INVALID")
            if not isinstance(ch.get("size"),int) or not 1 <= ch["size"] <= 4096:
                raise RuntimeError("SOURCE_PATCH_CHUNK_SIZE_INVALID")
            jobs.append((path,i,name,ch["size"],ch["sha256"]))
    if len(jobs)!=len(set(x[2] for x in jobs)):
        raise RuntimeError("DUPLICATE_SOURCE_CHUNK_PATH")
    return jobs


def attest_downloaded(obj: dict, expected_to: dict[str,str],
                      expected_from: dict[str,str],
                      version: str, patches: list[dict],
                      source_sha: str):
    if not HEX40.fullmatch(source_sha):
        raise RuntimeError("SOURCE_COMMIT_NOT_IMMUTABLE_SHA")
    jobs=validate_patch_envelope(patches,version,expected_to)
    if any(p["from_sha256"]!=expected_from[p["path"]] for p in patches):
        raise RuntimeError("PATCH_BEFORE_HASH_NOT_PARENT_PINNED")
    if sum(x[3] for x in jobs) > 256*1024:
        raise RuntimeError("NETWORK_TOTAL_CHUNK_CAP_EXCEEDED")
    def get(job):
        path,i,rel,length,dig=job
        data=download(RAW+source_sha+"/"+rel,4096)
        if (len(data),hash_bytes(data))!=(length,dig):
            raise RuntimeError("IMMUTABLE_CHUNK_SIZE_OR_SHA_MISMATCH")
        return (path,i,data)
    # Bounded parallelism; a request failing ends this one-shot admission.
    with ThreadPoolExecutor(max_workers=4) as pool:
        blobs=list(pool.map(get,jobs))
    decoded={}
    for patch in patches:
        path=patch["path"]
        ordered=[b for p,i,b in sorted(blobs,key=lambda x:x[1]) if p==path]
        encoded=b"".join(ordered)
        if (len(encoded),hash_bytes(encoded))!=(
            patch["encoded_size"],patch["encoded_sha256"]):
            raise RuntimeError("IMMUTABLE_ENCODED_CHUNKS_MISMATCH")
        try:
            compressed=base64.b64decode(encoded,validate=True)
            raw=gzip.decompress(compressed)
        except (ValueError, OSError) as exc:
            raise RuntimeError("IMMUTABLE_SOURCE_DECODE_FAILED") from exc
        if ((len(compressed),hash_bytes(compressed)) !=
            (patch["compressed_size"],patch["compressed_sha256"])):
            raise RuntimeError("IMMUTABLE_COMPRESSED_SHA_MISMATCH")
        if (len(raw),hash_bytes(raw))!=(
            patch["target_size"],patch["to_sha256"]):
            raise RuntimeError("IMMUTABLE_SOURCE_TARGET_BYTES_MISMATCH")
        decoded[path]=raw
    if set(decoded)!=set(expected_to):
        # For the last edge, addon may be unchanged and omitted by design.
        if not set(decoded).issubset(set(expected_to)):
            raise RuntimeError("UNEXPECTED_SOURCE_DECODED_PATHS")
    return len(jobs),decoded


def attest_future_release(
    live_raw: bytes, baseline: dict,
    approved_manifest_sha: str | None,
    approved_source_sha: str | None,
) -> dict:
    """Return a content-bound FACTUAL receipt, never release authorization.

    It is safe to pass to a separate owner-approval workflow only when that
    workflow verifies it came from this exact auditor and binds its complete
    result to a fresh unmodified public manifest. This does not execute code.
    """
    if (not approved_manifest_sha or not approved_source_sha or
        not HEX64.fullmatch(approved_manifest_sha) or
        not HEX40.fullmatch(approved_source_sha) or
        approved_source_sha in (BASE_PAYLOAD_COMMIT, "f"*40, "e"*40)):
        raise RuntimeError("NEXT_STABLE_INDEPENDENT_RELEASE_APPROVAL_PINS_REQUIRED")
    if hash_bytes(live_raw)!=approved_manifest_sha:
        raise RuntimeError("NEXT_STABLE_APPROVED_MANIFEST_SHA_MISMATCH")
    live=parse_manifest(live_raw,"LIVE")
    if (live.get("latest_version")!=FUTURE_LATEST or
        live.get("source_commit")!=approved_source_sha or
        len(live.get("updates",[]))!=19 or
        live["updates"][:-1]!=baseline["updates"] or
        live.get("bootstrap")!=baseline["bootstrap"]):
        raise RuntimeError("NEXT_STABLE_VERSION_HISTORY_OR_SOURCE_NOT_APPROVED")
    validate_latest(live,FUTURE)
    patches=newest_edge(live,BASE_LATEST,FUTURE_LATEST,
                        ["bin/spotify-control.ps1","bin/spotify-control-agent.vbs"])
    before={p:ORIGINAL[p][1] for p in
            ["bin/spotify-control.ps1","bin/spotify-control-agent.vbs"]}
    chunk_count,decoded=attest_downloaded(live,FUTURE,before,FUTURE_LATEST,patches,approved_source_sha)
    if chunk_count != EXPECTED_NEXT_CHUNKS or len(decoded)!=2:
        raise RuntimeError("NEXT_STABLE_EXPECTED_FULL_CHUNK_SET_NOT_PRESENT")
    return {
        "schema":"SPOTIFY_R30_PUBLIC_RELEASE_FACTS_V1",
        "status":"PUBLIC_SOURCE_AND_PAYLOAD_READONLY_VERIFIED_NOT_OWNER_AUTHORIZED",
        "from_version":BASE_LATEST,
        "to_version":FUTURE_LATEST,
        "manifest_sha256":hash_bytes(live_raw),
        "source_commit":approved_source_sha,
        "payload_set_sha256":live["payload_set_sha256"],
        "bootstrap_sha256":live["bootstrap"]["sha256"],
        "main_sha256":FUTURE["bin/spotify-control.ps1"],
        "agent_sha256":FUTURE["bin/spotify-control-agent.vbs"],
        "addon_sha256":FUTURE["bin/addon-manager.ps1"],
        "chunk_count":chunk_count,
        "model":"READ_ONLY_PROVENANCE_NO_EXECUTION",
    }


def run(mode: str, approved_manifest_sha: str | None, approved_source_sha: str | None) -> None:
    old_raw=download(RAW+BASE_MAIN_COMMIT+"/manifest.json",200_000)
    baseline=parse_manifest(old_raw,"ORIGINAL")
    if (baseline.get("latest_version") != BASE_LATEST or
        baseline.get("source_commit")!=BASE_PAYLOAD_COMMIT or
        len(baseline.get("updates",[]))!=18):
        raise RuntimeError("OFFICIAL_BASELINE_PIN_DRIFT")
    validate_latest(baseline,ORIGINAL)
    live_raw=download(RAW+"main/manifest.json",200_000)
    live=parse_manifest(live_raw,"LIVE")
    if mode=="baseline":
        if approved_manifest_sha is not None or approved_source_sha is not None:
            raise RuntimeError("UNEXPECTED_EXTERNAL_PINS_IN_BASELINE_MODE")
        if live_raw!=old_raw:
            raise RuntimeError("OFFICIAL_LIVE_BASELINE_DIFFERS_FROM_IMMUTABLE_MAIN")
        if live.get("source_commit")!=BASE_PAYLOAD_COMMIT or live.get("latest_version")!=BASE_LATEST:
            raise RuntimeError("OFFICIAL_STABLE_LATEST_NOT_EXACT")
        patches=newest_edge(live,"0.6.27",BASE_LATEST,
                            ["bin/spotify-control.ps1","bin/addon-manager.ps1"])
        old_pin={
            "bin/spotify-control.ps1":"9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787",
            "bin/addon-manager.ps1":"c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152",
        }
        dest={p:ORIGINAL[p][1] for p in old_pin}
        chunks,decoded=attest_downloaded(live,dest,old_pin,BASE_LATEST,patches,BASE_PAYLOAD_COMMIT)
        if chunks!=44 or len(decoded)!=2:
            raise RuntimeError("PUBLIC_BASELINE_IMMUTABLE_CHUNKS_NOT_ALL_PRESENT")
        print("PUBLIC_STABLE_V0628_MAIN_AND_IMMUTABLE_SOURCE_COMMIT=PASS")
        print("PUBLIC_STABLE_V0628_ALL_44_NEWEST_EDGE_CHUNKS=PASS")
        print("PUBLIC_STABLE_V0628_FULL_DECODED_MAIN_AND_ADDON_SHA=PASS")
        print("NEXT_STABLE_V0630=NOT_PUBLISHED_NOT_ACTIVATED")
    elif mode=="next-stable":
        receipt=attest_future_release(live_raw,baseline,approved_manifest_sha,approved_source_sha)
        print("PUBLIC_NEXT_STABLE_MANIFEST_INDEPENDENT_SHA_APPROVED=PASS")
        print("PUBLIC_NEXT_STABLE_IMMUTABLE_SOURCE_21_CHUNKS=PASS")
        print("PUBLIC_NEXT_STABLE_V0628_TO_V0630_MAIN_AND_VBS_SHA=PASS")
        print("PUBLIC_NEXT_STABLE_MANIFEST=READONLY_ADMITTED_NO_UPDATE_OR_PROCESS_CHANGE")
        return receipt
    else:
        raise RuntimeError("UNKNOWN_AUDIT_MODE")
    print("PRODUCTION_GIT_AND_WINDOWS_MUTATIONS=NONE")
    print("NETWORK=HTTPS_OFFICIAL_PUBLIC_RAW_ONLY")
    print("BOOTSTRAP_UPDATE_ROLLBACK=NOT_INVOKED")
    return None


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--mode",choices=["baseline","next-stable"],default="baseline")
    parser.add_argument("--approved-manifest-sha")
    parser.add_argument("--approved-source-sha")
    parser.add_argument("--release-facts-json",action="store_true")
    args=parser.parse_args()
    try:
        facts=run(args.mode,args.approved_manifest_sha,args.approved_source_sha)
        if args.release_facts_json:
            if args.mode != "next-stable" or facts is None:
                raise RuntimeError("RELEASE_FACTS_ONLY_FOR_VERIFIED_NEXT_STABLE")
            print("PUBLIC_RELEASE_FACTS_JSON="+json.dumps(facts,sort_keys=True,separators=(",",":")))
    except Exception as exc:
        # Do not emit raw URLs, usernames, path data, response bodies or
        # exception traces. The only runtime output is a bounded error class.
        print("PUBLIC_RELEASE_TRANSPORT=HOLD_"+type(exc).__name__.upper())
        print("REAL_PC_OR_GITHUB_WRITE=NONE")
        raise SystemExit(1)


if __name__=="__main__":
    main()
