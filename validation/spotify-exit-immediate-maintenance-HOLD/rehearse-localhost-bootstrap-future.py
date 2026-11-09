"""HOLD-only executable Bootstrap v1.0.6 rehearsal in hosted Windows scratch.

The *only* edits to the verified original Bootstrap script are TWO network
locator literals changed to 127.0.0.1. Its real manifest verifier, chunk
download, patch application, candidate tests, transaction, and rollback code
remain intact. This is NOT a production release, not a signed source commit,
and not identical to executing the immutable production Bootstrap binary.

Run prepare after launching serve. No server other than numeric loopback,
no edits outside RUNNER_TEMP, no user profile or production stable updates.
"""
from __future__ import annotations

import base64
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import runpy
import socket
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
REHEARSAL = Path(os.environ["RUNNER_TEMP"]).resolve() / "spotify-future-bootstrap-rehearsal"
BIN = REHEARSAL / "LocalAppData" / "SpotifyControl" / "bin"
APP = BIN.parent
SERVE = REHEARSAL / "loopback-source"
BOOTSTRAP_INPUT = Path(os.environ["RUNNER_TEMP"]).resolve() / "spotify-verified-bootstrap-v106.ps1"
FUTURE = ROOT / "validation/spotify-exit-immediate-maintenance-HOLD/out/future-safe"
CANONICAL = ROOT / "validation/v0.6.28/out/bin"
PIN = {
    "main": (284321, "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0"),
    "addon": (323385, "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"),
    "agent": (4855, "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278"),
    "bootstrap": (42963, "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6"),
}
VERSION = "0.6.30"  # NON-PUBLISHED, future scratch version; 0.6.29 preview is forbidden
COMMIT = "e" * 40  # deliberately INVALID published commit, usable only by localhost mirror
REPOSITORY = "sdsssdvx2/spotify-control-updates"

def digest(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def assert_pin(data: bytes, key: str) -> None:
    if (len(data), digest(data)) != PIN[key]:
        raise RuntimeError("OFFICIAL_SOURCE_IDENTITY_DRIFT_" + key.upper())


def paths_for_patches():
    return (
        ("bin/spotify-control.ps1", "main-v0628-to-v0630"),
        ("bin/spotify-control-agent.vbs", "resident-v011-to-v012"),
    )


def checked_write(path: Path, data: bytes) -> None:
    if not path.resolve().is_relative_to(REHEARSAL):
        raise RuntimeError("STAGING_PATH_ESCAPED_HOSTED_SCRATCH")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())


def make_patch(path: str, before: bytes, after: bytes, directory: str) -> dict:
    if digest(before) == digest(after):
        raise RuntimeError("UNCHANGED_FULL_FILE_PATCH")
    gz = gzip.compress(after, mtime=0)
    enc = base64.b64encode(gz)
    chunks = [enc[i:i+4096] for i in range(0, len(enc), 4096)]
    if not 1 <= len(chunks) <= 32:
        raise RuntimeError("BOOTSTRAP_EXACT_CHUNK_LIMIT")
    items = []
    for i, raw in enumerate(chunks):
        rel = f"packages/v{VERSION}/{directory}/chunk-{i:03}.txt"
        mirror = SERVE / REPOSITORY / COMMIT / rel
        checked_write(mirror, raw)
        items.append({"path": rel, "sha256": digest(raw), "size": len(raw)})
    if gzip.decompress(base64.b64decode(b"".join(chunks), validate=True)) != after:
        raise RuntimeError("CHUNK_ROUNDTRIP_INVALID")
    return {
        "path": path,
        "from_sha256": digest(before),
        "to_sha256": digest(after),
        "encoding": "gzip-base64-full-file",
        "encoded_sha256": digest(enc),
        "encoded_size": len(enc),
        "compressed_sha256": digest(gz),
        "compressed_size": len(gz),
        "target_size": len(after),
        "chunks": items,
    }


class LimitedMirror(BaseHTTPRequestHandler):
    def do_GET(self):
        if "?" in self.path or "#" in self.path:
            self.send_error(404)
            return
        suffix = unquote(urlsplit(self.path).path).lstrip("/")
        if not suffix or ".." in suffix or "\\" in suffix or ":" in suffix or "\x00" in suffix:
            self.send_error(404)
            return
        file = (SERVE / suffix).resolve()
        if not file.is_relative_to(SERVE) or not file.is_file() or file.is_symlink():
            self.send_error(404)
            return
        data = file.read_bytes()
        if len(data) > 500_000:
            self.send_error(413)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json" if suffix == "manifest.json" else "text/plain")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        self.send_error(405)

    def log_message(self, fmt, *args):
        return


def serve() -> None:
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_OS") != "Windows":
        raise RuntimeError("HOSTED_WINDOWS_ONLY")
    if REHEARSAL.exists():
        raise RuntimeError("SCRATCH_ALREADY_EXISTS")
    SERVE.mkdir(parents=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), LimitedMirror)
    ready = REHEARSAL / "server-port"
    with ready.open("x", encoding="ascii") as output:
        output.write(str(server.server_port))
    server.serve_forever(poll_interval=0.05)


def prepare() -> None:
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_OS") != "Windows":
        raise RuntimeError("HOSTED_WINDOWS_ONLY")
    portfile = REHEARSAL / "server-port"
    port = int(portfile.read_text(encoding="ascii"))
    if not 1 <= port <= 65535:
        raise RuntimeError("INVALID_LOOPBACK_SERVER_PORT")

    old_main = (CANONICAL / "spotify-control.ps1").read_bytes()
    old_addon = (CANONICAL / "addon-manager.ps1").read_bytes()
    old_agent = runpy.run_path(
        str(ROOT / "validation/normal-engine-shared-turnstile/audit-pinned-stable-entrypoints-v059.py")
    )["extract_verified_agent"]()
    assert_pin(old_main, "main")
    assert_pin(old_addon, "addon")
    assert_pin(old_agent, "agent")

    future_main = (FUTURE / "spotify-control.ps1").read_bytes()
    future_agent = (FUTURE / "spotify-control-agent.vbs").read_bytes()
    marker = b'$ScriptVersion = "0.6.28"'
    if future_main.count(marker) != 1:
        raise RuntimeError("RELEASE_VERSION_MARKER_NOT_EXACT")
    future_main = future_main.replace(marker, b'$ScriptVersion = "0.6.30"', 1)
    if future_main.count(b'$ScriptVersion = "0.6.30"') != 1:
        raise RuntimeError("REHEARSAL_VERSION_NOT_SET")
    if digest(future_main) == digest(old_main) or digest(future_agent) == digest(old_agent):
        raise RuntimeError("RELEASE_CANDIDATE_NOT_CHANGED")

    boot = BOOTSTRAP_INPUT.read_bytes()
    assert_pin(boot, "bootstrap")
    script = boot.decode("ascii")
    old_manifest = "'https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'"
    old_prefix = "'https://raw.githubusercontent.com/'"
    if script.count(old_manifest) != 1 or script.count(old_prefix) != 1:
        raise RuntimeError("UNEXPECTED_ORIGINAL_BOOTSTRAP_NETWORK_LOCATORS")
    script = script.replace(old_manifest, "'http://127.0.0.1:%d/manifest.json'" % port)
    script = script.replace(old_prefix, "'http://127.0.0.1:%d/'" % port)
    if "https://raw.githubusercontent.com/" in script:
        raise RuntimeError("UNREWRITTEN_PRODUCTION_NETWORK_URI")
    # Only two locator strings differ: no modification to trust checks,
    # transaction/rollback logic, candidate tests or patch decoding.
    disposable_boot = script.encode("ascii")

    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8-sig"))
    if manifest["latest_version"] != "0.6.28" or manifest["bootstrap"] != {
        "version": "1.0.6", "sha256": PIN["bootstrap"][1], "size": PIN["bootstrap"][0]
    }:
        raise RuntimeError("PUBLISHED_STABLE_SOURCE_MANIFEST_DRIFT")
    rows = {
        "bin/spotify-control.ps1": old_main,
        "bin/addon-manager.ps1": old_addon,
        "bin/spotify-control-agent.vbs": old_agent,
    }
    patches = []
    new_rows = dict(rows)
    for path, directory in paths_for_patches():
        before = rows[path]
        after = future_main if path.endswith(".ps1") else future_agent
        patches.append(make_patch(path, before, after, directory))
        new_rows[path] = after

    manifest["latest_version"] = VERSION
    manifest["source_commit"] = COMMIT
    manifest["bootstrap"] = {
        "version": "1.0.6", "size": len(disposable_boot), "sha256": digest(disposable_boot)
    }
    manifest["latest_files"] = [
        {"path": path, "size": len(data), "sha256": digest(data)}
        for path, data in sorted(new_rows.items())
    ]
    canonical = "".join(
        path + "|" + str(len(data)) + "|" + digest(data) + "\n"
        for path, data in sorted(new_rows.items())
    )
    manifest["payload_set_sha256"] = digest(canonical.encode("utf-8"))
    manifest["updates"].append({
        "from_version": "0.6.28",
        "to_version": VERSION,
        "patches": patches
    })
    if len(manifest["updates"]) != 19:
        raise RuntimeError("UPDATE_EDGE_COUNT_UNEXPECTED")
    checked_write(SERVE / "manifest.json", json.dumps(manifest,separators=(",",":")).encode("ascii"))
    checked_write(APP / "bootstrap" / "spotify-control-self-updater.ps1", disposable_boot)
    for path, data in rows.items():
        checked_write(APP / path, data)
    checked_write(APP / "state.json", b'{"schema":20,"agent_mutation_enabled":true,"ownerCustomPreserve":true}')
    checked_write(APP / "unrelated-user-preserve.txt", b"OWNER_DATA_SENTINEL_NEVER_DELETE")

    # Match the already accepted authentic current stable Bootstrap acceptance
    # fixture: long-lived optional helpers and structurally valid local apps.
    for name in (
        "collect-spotify-diagnostics.ps1", "performance-profiler.ps1",
        "health-report.ps1", "performance-ab-profiler.ps1",
        "marketplace-isolation-profiler.ps1"
    ):
        checked_write(BIN / name, b"# hosted isolated static helper fixture\n")
    (REHEARSAL / "LocalAppData" / "Spotify").mkdir(parents=True,exist_ok=True)
    market = REHEARSAL / "LocalAppData" / "spicetify" / "CustomApps" / "marketplace"
    for name,data in (
        ("index.js",b"// hosted market fixture\n"),
        ("extension.js",b"// hosted market fixture\n"),
        ("style.css",b"/* hosted market fixture */\n"),
        ("manifest.json",b'{"name":"hosted-market-fixture"}\n'),
    ):
        checked_write(market / name,data)
    roaming = REHEARSAL / "Roaming" / "spicetify"
    checked_write(roaming / "config-xpui.ini",b"[Setting]\ncurrent_theme = OwnerUnchanged\n")
    report = {
        "mode":"HOSTED_LOCALHOST_REHEARSAL_NOT_PRODUCTION",
        "version":VERSION,"fake_unpublished_source_commit":COMMIT,
        "bootstrap_original_sha256":PIN["bootstrap"][1],
        "bootstrap_locator_only_copy_sha256":digest(disposable_boot),
        "original_main_sha256":digest(old_main),
        "future_main_sha256":digest(future_main),
        "original_agent_sha256":digest(old_agent),
        "future_agent_sha256":digest(future_agent),
        "addon_sha256_unchanged":digest(old_addon),
        "future_payload_set_sha256":manifest["payload_set_sha256"],
        "patch_chunks":[len(p["chunks"]) for p in patches],
        "production_manifest_untouched":True,
    }
    checked_write(REHEARSAL / "rehearsal-report.json",
                  (json.dumps(report,indent=2)+"\n").encode("ascii"))
    print("REAL_BOOTSTRAP_REHEARSAL_FIXTURE=PREPARED")
    print("REAL_BOOTSTRAP_REHEARSAL_LOCALHOST_ONLY=YES")
    print("REAL_BOOTSTRAP_REHEARSAL_TWO_URL_LOCATOR_CHANGES=YES")
    print("REAL_BOOTSTRAP_REHEARSAL_MAIN_PATCH_CHUNKS="+str(len(patches[0]["chunks"])))
    print("REAL_BOOTSTRAP_REHEARSAL_AGENT_PATCH_CHUNKS="+str(len(patches[1]["chunks"])))
    print("REAL_BOOTSTRAP_REHEARSAL_UNPUBLISHED=YES")
    print("REAL_BOOTSTRAP_REHEARSAL_MAIN_SHA256="+digest(future_main))
    print("REAL_BOOTSTRAP_REHEARSAL_AGENT_SHA256="+digest(future_agent))


if __name__ == "__main__":
    if len(sys.argv)!=2 or sys.argv[1] not in ("prepare","serve"):
        raise SystemExit("usage: rehearse-localhost-bootstrap-future.py prepare|serve")
    if sys.argv[1]=="serve":
        serve()
    else:
        prepare()
