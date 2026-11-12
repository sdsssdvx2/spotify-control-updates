"""Deterministic stable v0.6.30 builder/validator for the official full-file transport.

Uses the already reviewed 21 immutable pieces and original v0.6.28 builder.
No new patch producer, API calls, live Windows mutation, or release publication.
This file lives on the v0.6.30 review branch until explicit publication.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / "out" / "bin"
SOURCE = "27c3bbd2935c8568ee6d260085d8008aec5e173a"
STABLE_MAIN = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
REVIEW_MANIFEST_BLOB = "d858a7ea170d6df9ffe0b435a6e93dfec01549f8"
PAYLOAD = "fb2bf4d27991e27b67c00d1df3efcc36166369d079173f9978c35f43a6e93fb8"
BOOT = "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6"
FILES = {
    "bin/spotify-control.ps1": (294101, "b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"),
    "bin/spotify-control-agent.vbs": (13308, "e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5"),
    "bin/addon-manager.ps1": (323385, "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"),
}
BASE = {
    "bin/spotify-control.ps1": "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0",
    "bin/spotify-control-agent.vbs": "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278",
}


def require(ok: bool, why: str) -> None:
    if not ok:
        raise RuntimeError("V0630_" + why)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(*args: str) -> bytes:
    result = subprocess.run(["git", *args], cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0, "GIT_OBJECT_OR_ANCESTRY_UNVERIFIED")
    return result.stdout


def git_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\x00" + data).hexdigest()


def validate_release() -> tuple[dict, dict[str, bytes]]:
    raw = (ROOT / "manifest.json").read_bytes()
    require(git_blob(raw) == REVIEW_MANIFEST_BLOB, "EXACT_REVIEW_MANIFEST_CHANGED")
    m = json.loads(raw)
    meta = json.loads((HERE / "release-metadata.json").read_text("utf-8"))
    require(m.get("latest_version") == meta.get("version") == "0.6.30",
            "VERSION_MISMATCH")
    require(m.get("source_commit") == meta.get("source_commit") == SOURCE,
            "IMMUTABLE_SOURCE_COMMIT_MISMATCH")
    require(m.get("payload_set_sha256") == meta.get("payload_set_sha256") == PAYLOAD,
            "PAYLOAD_SET_MISMATCH")
    require(m.get("bootstrap", {}).get("sha256") ==
            meta.get("official_bootstrap_sha256") == BOOT,
            "ORIGINAL_BOOTSTRAP_IDENTITY_CHANGED")
    require(meta.get("review_manifest_git_blob") == REVIEW_MANIFEST_BLOB,
            "METADATA_MANIFEST_MISMATCH")
    require(meta.get("publication_state") == "REVIEW_ONLY_NOT_PUBLIC_MAIN",
            "RELEASE_PROVENANCE_UNEXPECTED")
    protected = meta.get("protected_policy", {})
    for name in ("new_automatic_install_authority", "ownership_migration_authorized",
                 "direct_copy_cleanup_authorized", "disable_or_optimize_authorized",
                 "current_spotify_138_spicetify_2464_compatible"):
        require(protected.get(name) is False, "PROTECTED_POLICY_DRIFT_" + name)
    require(meta.get("from_version") == "0.6.28", "BASE_VERSION_CHANGED")
    require(meta.get("files") ==
            {p: {"size": n, "sha256": h} for p, (n, h) in FILES.items()},
            "RELEASE_FILE_PINS_CHANGED")
    require(meta.get("release_provenance", {}).get("r102_owner_private_cutover_ci") ==
            "43224292357", "PRIVATE_OWNER_CANARY_PROVENANCE_MISSING")
    # Both the baseline and immutable chunk source must remain in this history.
    git("merge-base", "--is-ancestor", SOURCE, "HEAD")
    git("merge-base", "--is-ancestor", STABLE_MAIN, "HEAD")
    baseline = json.loads(git("show", STABLE_MAIN + ":manifest.json"))
    require(baseline.get("latest_version") == "0.6.28" and
            baseline.get("bootstrap") == m.get("bootstrap") and
            baseline.get("updates") == m.get("updates", [])[:-1],
            "HISTORIC_PUBLIC_STABLE_EDGES_CHANGED")
    require(len(m.get("updates", [])) == len(baseline["updates"]) + 1 == 19,
            "HISTORICAL_GRAPH_CHANGED")
    require({x.get("path"): (x.get("size"), x.get("sha256"))
             for x in m.get("latest_files", [])} == FILES,
            "LATEST_FILES_NOT_EXACT")
    edge = m["updates"][-1]
    require(edge.get("from_version") == "0.6.28" and
            edge.get("to_version") == "0.6.30",
            "LATEST_UPDATE_EDGE_CHANGED")
    patches = edge.get("patches", [])
    require(len(patches) == 2 and
            {x.get("path") for x in patches} == set(BASE),
            "LATEST_PATCH_PATHS_CHANGED")
    targets: dict[str, bytes] = {}
    seen_chunks: set[str] = set()
    for patch in patches:
        path = patch["path"]
        require(patch.get("from_sha256") == BASE[path] and
                patch.get("to_sha256") == FILES[path][1] and
                patch.get("target_size") == FILES[path][0] and
                patch.get("encoding") == "gzip-base64-full-file",
                "EXACT_FROM_TO_OR_ENCODING_DRIFT_" + path)
        chunks = patch.get("chunks", [])
        count = 19 if path.endswith("spotify-control.ps1") else 2
        require(len(chunks) == count, "IMMUTABLE_CHUNK_COUNT_CHANGED_" + path)
        encoded = bytearray()
        for idx, chunk in enumerate(chunks):
            cpath = chunk.get("path", "")
            directory = ("main-v0628-to-v0630" if path.endswith(".ps1") else
                         "resident-v011-to-v012")
            expected = f"packages/v0.6.30/{directory}/chunk-{idx:03d}.txt"
            require(cpath == expected and cpath not in seen_chunks,
                    "IMMUTABLE_CHUNK_PATH_CHANGED")
            seen_chunks.add(cpath)
            file = ROOT / cpath
            require(file.is_file() and not file.is_symlink(), "CHUNK_MISSING_OR_SYMLINK")
            raw_piece = file.read_bytes()
            require(len(raw_piece) == chunk.get("size") and
                    sha(raw_piece) == chunk.get("sha256") and
                    raw_piece == git("show", SOURCE + ":" + cpath),
                    "SOURCE_PINNED_CHUNK_BYTES_CHANGED")
            encoded.extend(raw_piece)
        encoded_bytes = bytes(encoded)
        require(len(encoded_bytes) == patch.get("encoded_size") and
                sha(encoded_bytes) == patch.get("encoded_sha256"),
                "ENCODED_PATCH_SHA_CHANGED")
        compressed = base64.b64decode(encoded_bytes, validate=True)
        require(len(compressed) == patch.get("compressed_size") and
                sha(compressed) == patch.get("compressed_sha256"),
                "COMPRESSED_PATCH_SHA_CHANGED")
        data = gzip.decompress(compressed)
        require((len(data), sha(data)) == FILES[path],
                "RECONSTRUCTED_TARGET_SHA_CHANGED")
        regenerated = bytearray(gzip.compress(data, mtime=0))
        require(regenerated[:3] == bytes((31, 139, 8)),
                "DETERMINISTIC_GZIP_HEADER_INVALID")
        regenerated[9] = 255
        require(base64.b64encode(bytes(regenerated)) == encoded_bytes,
                "DETERMINISTIC_GZIP_CHUNKS_NOT_REPRODUCED")
        targets[path] = data
    require(len(seen_chunks) == 21 and len(targets) == 2,
            "COMPLETE_21_PIECE_DELIVERY_MISSING")
    return m, targets


def build() -> None:
    _, files = validate_release()
    parent = ROOT / "validation/v0.6.28/build_v0628.py"
    subprocess.run([sys.executable, str(parent), "--build"], cwd=ROOT,
                   check=True, stdout=subprocess.DEVNULL)
    addon = (ROOT / "validation/v0.6.28/out/bin/addon-manager.ps1").read_bytes()
    require((len(addon), sha(addon)) == FILES["bin/addon-manager.ps1"],
            "ORIGINAL_PROTECTED_ADDON_REBUILD_MISMATCH")
    files["bin/addon-manager.ps1"] = addon
    require(len(files) == 3, "MANAGED_FILE_COUNT_DRIFT")
    OUT.mkdir(parents=True, exist_ok=True)
    for path, body in files.items():
        dest = OUT / path.split("/")[-1]
        dest.write_bytes(body)
        require(dest.read_bytes() == body, "DETERMINISTIC_OUTPUT_WRITE_MISMATCH")
    print("V0630_DETERMINISTIC_IMMUTABLE_FULLFILE_BUILD=PASS")
    print("V0630_ADDON_R17_REBUILT_AND_PROTECTED=PASS")
    print("V0630_SOURCE_AND_21_CHUNKS=EXACT")


def main() -> None:
    p = argparse.ArgumentParser()
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--validate-published", action="store_true")
    group.add_argument("--build", action="store_true")
    args = p.parse_args()
    if args.build:
        build()
    else:
        validate_release()
        print("V0630_REVIEW_MANIFEST_HISTORIC_EDGE_AND_FULLFILES=PASS")
        print("V0630_AUTOMATIC_PUBLICATION=NOT_PERFORMED")


if __name__ == "__main__":
    main()
