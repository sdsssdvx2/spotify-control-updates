from pathlib import Path
import base64
import gzip
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "manifest.json"
SCHEMA_PATH = ROOT / "manifest.schema.json"

TOP_KEYS = {
    "schema", "channel", "latest_version", "min_bootstrap_version",
    "source_repository", "source_commit", "bootstrap",
    "payload_set_sha256", "latest_files", "updates",
}
LATEST_FILE_KEYS = {"path", "sha256", "size"}
EDGE_KEYS = {"from_version", "to_version", "patches"}
CHUNK_KEYS = {"path", "sha256", "size"}
LINE_PATCH_KEYS = {
    "path", "from_sha256", "to_sha256", "encoding",
    "encoded_sha256", "encoded_size", "compressed_sha256",
    "compressed_size", "json_sha256", "json_size", "chunks",
}
FULL_FILE_KEYS = {
    "path", "from_sha256", "to_sha256", "encoding",
    "encoded_sha256", "encoded_size", "compressed_sha256",
    "compressed_size", "target_size", "chunks",
}
RE_SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
RE_SHA256 = re.compile(r"^[0-9a-f]{64}$")
RE_COMMIT = re.compile(r"^[0-9a-f]{40}$")
RE_MANAGED_PATH = re.compile(r"^bin/[A-Za-z0-9._+-]+$")
RE_CHUNK_PATH = re.compile(
    r"^packages/v[0-9]+\.[0-9]+\.[0-9]+/[A-Za-z0-9._+-]+/chunk-[0-9]{3}\.txt$"
)


def fail(message):
    raise RuntimeError(message)


def require(condition, message):
    if not condition:
        fail(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def semver(value, label):
    require(isinstance(value, str), f"{label} must be a string")
    match = RE_SEMVER.fullmatch(value)
    require(match is not None, f"{label} is not strict semver: {value!r}")
    return tuple(int(x) for x in match.groups())


def require_sha(value, label):
    require(isinstance(value, str) and RE_SHA256.fullmatch(value), f"{label} is not lowercase SHA-256")


def require_int(value, low, high, label):
    require(type(value) is int and low <= value <= high, f"{label} out of range: {value!r}")


def git(*args, capture=False):
    result = subprocess.run(
        ["git", *args], cwd=ROOT,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", "replace").strip()
        fail(f"git {' '.join(args)} failed: {stderr}")
    return result.stdout if capture else b""


def git_blob(commit, path):
    return git("cat-file", "blob", f"{commit}:{path}", capture=True)


def exact_keys(obj, expected, label):
    require(isinstance(obj, dict), f"{label} must be an object")
    actual = set(obj)
    require(actual == expected, f"{label} keys differ: missing={sorted(expected-actual)} extra={sorted(actual-expected)}")


def verify_chunk(chunk, source_commit, edge_to, patch_label):
    exact_keys(chunk, CHUNK_KEYS, f"{patch_label} chunk")
    path = chunk["path"]
    require(isinstance(path, str) and RE_CHUNK_PATH.fullmatch(path), f"invalid chunk path: {path!r}")
    require(path.startswith(f"packages/v{edge_to}/"), f"chunk not scoped to edge target v{edge_to}: {path}")
    require_sha(chunk["sha256"], f"{path} sha256")
    require_int(chunk["size"], 1, 1048576, f"{path} size")

    pinned = git_blob(source_commit, path)
    require(len(pinned) == chunk["size"], f"pinned chunk size mismatch: {path}")
    require(sha256(pinned) == chunk["sha256"], f"pinned chunk SHA mismatch: {path}")

    current_path = ROOT / path
    require(current_path.is_file(), f"manifest-referenced chunk missing from current tree: {path}")
    current = current_path.read_bytes()
    require(current == pinned, f"immutable chunk drifted after source_commit: {path}")
    return pinned


def verify_patch(patch, edge, source_commit, latest_paths):
    encoding = patch.get("encoding") if isinstance(patch, dict) else None
    if encoding == "gzip-base64-chunks":
        exact_keys(patch, LINE_PATCH_KEYS, "line patch")
    elif encoding == "gzip-base64-full-file":
        exact_keys(patch, FULL_FILE_KEYS, "full-file patch")
    else:
        fail(f"unsupported patch encoding: {encoding!r}")

    path = patch["path"]
    require(isinstance(path, str) and RE_MANAGED_PATH.fullmatch(path), f"invalid managed path: {path!r}")
    require(path in latest_paths, f"patch path is not part of latest_files: {path}")
    require_sha(patch["from_sha256"], f"{path} from_sha256")
    require_sha(patch["to_sha256"], f"{path} to_sha256")
    require_sha(patch["encoded_sha256"], f"{path} encoded_sha256")
    require_sha(patch["compressed_sha256"], f"{path} compressed_sha256")
    require_int(patch["encoded_size"], 1, 4194304, f"{path} encoded_size")
    require_int(patch["compressed_size"], 1, 4194304, f"{path} compressed_size")

    chunks = patch["chunks"]
    require(isinstance(chunks, list) and 1 <= len(chunks) <= 32, f"invalid chunk list for {path}")
    chunk_paths = [c.get("path") for c in chunks if isinstance(c, dict)]
    require(len(chunk_paths) == len(set(chunk_paths)), f"duplicate chunk path inside patch: {path}")
    encoded = b"".join(
        verify_chunk(c, source_commit, edge["to_version"], f"{edge['from_version']}->{edge['to_version']} {path}")
        for c in chunks
    )
    require(len(encoded) == patch["encoded_size"], f"encoded size mismatch: {path}")
    require(sha256(encoded) == patch["encoded_sha256"], f"encoded SHA mismatch: {path}")
    try:
        compressed = base64.b64decode(encoded, validate=True)
    except Exception as exc:
        fail(f"invalid Base64 transport for {path}: {exc}")
    require(len(compressed) == patch["compressed_size"], f"compressed size mismatch: {path}")
    require(sha256(compressed) == patch["compressed_sha256"], f"compressed SHA mismatch: {path}")
    try:
        payload = gzip.decompress(compressed)
    except Exception as exc:
        fail(f"invalid gzip transport for {path}: {exc}")

    if encoding == "gzip-base64-full-file":
        require_int(patch["target_size"], 1, 20971520, f"{path} target_size")
        require(len(payload) == patch["target_size"], f"target size mismatch: {path}")
        require(sha256(payload) == patch["to_sha256"], f"full-file target SHA mismatch: {path}")
    else:
        require_sha(patch["json_sha256"], f"{path} json_sha256")
        require_int(patch["json_size"], 1, 2097152, f"{path} json_size")
        require(len(payload) == patch["json_size"], f"JSON patch size mismatch: {path}")
        require(sha256(payload) == patch["json_sha256"], f"JSON patch SHA mismatch: {path}")
        try:
            document = json.loads(payload.decode("ascii"))
        except Exception as exc:
            fail(f"invalid ASCII JSON patch for {path}: {exc}")
        require(document.get("schema") == 1, f"line patch schema mismatch: {path}")
        require(document.get("kind") == "ascii-line-patch", f"line patch kind mismatch: {path}")
        require(isinstance(document.get("operations"), list) and document["operations"], f"line patch has no operations: {path}")
        optional_contract = {
            "from_version": edge["from_version"],
            "to_version": edge["to_version"],
            "from_sha256": patch["from_sha256"],
            "to_sha256": patch["to_sha256"],
        }
        for key, expected in optional_contract.items():
            if key in document:
                require(document[key] == expected, f"line patch {key} mismatch for {path}")


def main():
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))

    exact_keys(manifest, TOP_KEYS, "manifest")
    require(schema.get("type") == "object" and schema.get("additionalProperties") is False, "manifest schema top-level contract changed")
    require(set(schema.get("required", [])) == TOP_KEYS, "manifest schema required keys diverge from stable validator")

    require(manifest["schema"] == 1, "manifest schema must be 1")
    require(manifest["channel"] == "stable", "manifest channel must be stable")
    require(manifest["source_repository"] == "sdsssdvx2/spotify-control-updates", "source_repository mismatch")
    latest_tuple = semver(manifest["latest_version"], "latest_version")
    min_bootstrap_tuple = semver(manifest["min_bootstrap_version"], "min_bootstrap_version")

    bootstrap = manifest["bootstrap"]
    exact_keys(bootstrap, {"version", "sha256", "size"}, "bootstrap")
    bootstrap_tuple = semver(bootstrap["version"], "bootstrap.version")
    require(min_bootstrap_tuple <= bootstrap_tuple, "manifest requires a bootstrap newer than the published bootstrap identity")
    require_sha(bootstrap["sha256"], "bootstrap.sha256")
    require_int(bootstrap["size"], 1, 1048576, "bootstrap.size")

    source_commit = manifest["source_commit"]
    require(isinstance(source_commit, str) and RE_COMMIT.fullmatch(source_commit), "source_commit is not a lowercase full commit SHA")
    git("cat-file", "-e", f"{source_commit}^{{commit}}")
    git("merge-base", "--is-ancestor", source_commit, "HEAD")

    latest_files = manifest["latest_files"]
    require(isinstance(latest_files, list) and 3 <= len(latest_files) <= 32, "latest_files count out of range")
    latest_by_path = {}
    for item in latest_files:
        exact_keys(item, LATEST_FILE_KEYS, "latest_files item")
        path = item["path"]
        require(isinstance(path, str) and RE_MANAGED_PATH.fullmatch(path), f"invalid latest_files path: {path!r}")
        require(path not in latest_by_path, f"duplicate latest_files path: {path}")
        require_sha(item["sha256"], f"{path} latest SHA")
        require_int(item["size"], 1, 20971520, f"{path} latest size")
        latest_by_path[path] = item
    for required_path in ("bin/spotify-control.ps1", "bin/addon-manager.ps1", "bin/spotify-control-agent.vbs"):
        require(required_path in latest_by_path, f"required managed file missing: {required_path}")

    canonical_rows = [
        f"{item['path']}|{int(item['size'])}|{item['sha256']}"
        for item in sorted(latest_files, key=lambda row: row["path"])
    ]
    canonical_payload = sha256(("\n".join(canonical_rows) + "\n").encode("ascii"))
    require_sha(manifest["payload_set_sha256"], "payload_set_sha256")
    require(canonical_payload == manifest["payload_set_sha256"], "canonical payload_set_sha256 mismatch")

    updates = manifest["updates"]
    require(isinstance(updates, list) and 1 <= len(updates) <= 64, "updates count out of range")
    outgoing = {}
    edge_pairs = set()
    incoming_targets = {}
    outgoing_sources = {}

    for edge in updates:
        exact_keys(edge, EDGE_KEYS, "update edge")
        from_tuple = semver(edge["from_version"], "from_version")
        to_tuple = semver(edge["to_version"], "to_version")
        require(from_tuple < to_tuple, f"non-forward update edge: {edge['from_version']}->{edge['to_version']}")
        require(to_tuple <= latest_tuple, f"edge targets version newer than latest: {edge['to_version']}")
        pair = (edge["from_version"], edge["to_version"])
        require(pair not in edge_pairs, f"duplicate update edge: {pair}")
        edge_pairs.add(pair)
        require(edge["from_version"] not in outgoing, f"ambiguous outgoing update edge from {edge['from_version']}")
        outgoing[edge["from_version"]] = edge

        patches = edge["patches"]
        require(isinstance(patches, list) and 1 <= len(patches) <= 16, f"patch count out of range for edge {pair}")
        patch_paths = [p.get("path") for p in patches if isinstance(p, dict)]
        require(len(patch_paths) == len(set(patch_paths)), f"duplicate patch path in edge {pair}")
        for patch in patches:
            verify_patch(patch, edge, source_commit, set(latest_by_path))
            incoming_targets.setdefault((edge["to_version"], patch["path"]), set()).add(patch["to_sha256"])
            outgoing_sources.setdefault((edge["from_version"], patch["path"]), set()).add(patch["from_sha256"])

    require(manifest["latest_version"] not in outgoing, "latest_version must not have an outgoing update edge")
    for start in outgoing:
        current = start
        seen = set()
        while current != manifest["latest_version"]:
            require(current not in seen, f"cycle in update graph starting at {start}")
            seen.add(current)
            require(current in outgoing, f"dead-end update graph from {start} at {current}")
            current = outgoing[current]["to_version"]

    for key, targets in incoming_targets.items():
        require(len(targets) == 1, f"conflicting incoming target hashes at {key}: {sorted(targets)}")
        if key in outgoing_sources:
            require(outgoing_sources[key] == targets, f"hash continuity mismatch at {key}: incoming={targets} outgoing={outgoing_sources[key]}")

    for edge in updates:
        if edge["to_version"] != manifest["latest_version"]:
            continue
        for patch in edge["patches"]:
            latest = latest_by_path[patch["path"]]
            require(patch["to_sha256"] == latest["sha256"], f"terminal patch does not match latest_files: {patch['path']}")
            if patch["encoding"] == "gzip-base64-full-file":
                require(patch["target_size"] == latest["size"], f"terminal full-file size does not match latest_files: {patch['path']}")

    print(
        "STABLE_MANIFEST_INTEGRITY_PASS",
        f"latest={manifest['latest_version']}",
        f"source={source_commit}",
        f"payload={manifest['payload_set_sha256']}",
        f"edges={len(updates)}",
        f"files={len(latest_files)}",
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"STABLE_MANIFEST_INTEGRITY_FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
