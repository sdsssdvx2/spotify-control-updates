"""R80 HOLD: independently pinned *prepublication* v0.6.30 release review.
Do NOT publish stable or change the owner's PC. This is the first reusable
admission component for an owner-first staged canary; it is NOT an installer.

Reuse the exact existing R29 source/manifest/21-chunk verifier, against an
immutable review commit rather than main, to break publication-first racing
with the still-armed v0.6.28 autonomous self-updater.
"""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
REVIEW_COMMIT="72f338297fe24ad47ae8315ce2c4bb70656f084c"
REVIEW_MANIFEST_GIT_BLOB="d858a7ea170d6df9ffe0b435a6e93dfec01549f8"
IMMUTABLE_SOURCE_COMMIT="27c3bbd2935c8568ee6d260085d8008aec5e173a"
EXPECTED_PAYLOAD_SET="fb2bf4d27991e27b67c00d1df3efcc36166369d079173f9978c35f43a6e93fb8"
EXPECTED_CHUNKS=21
EXPECTED_BOOT_SHA="d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6"

def gitblob(data:bytes)->str:
    return hashlib.sha1(b"blob "+str(len(data)).encode("ascii")+b"\x00"+data).hexdigest()

def load_verifier():
    file=HERE/"verify-public-release-transport-R29-HOLD.py"
    spec=importlib.util.spec_from_file_location("R80_VERIFIED_REUSE_R29",file)
    if spec is None or spec.loader is None:
        raise RuntimeError("R80_PREINSTALLED_RELEASE_VERIFIER_MISSING")
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def preflight(raw:bytes,verify):
    if not isinstance(raw,bytes) or len(raw)>200_000 or len(raw)<1000:
        raise RuntimeError("R80_REVIEW_MANIFEST_BYTES_NOT_BOUNDED")
    if gitblob(raw)!=REVIEW_MANIFEST_GIT_BLOB:
        raise RuntimeError("R80_EXACT_REVIEW_MANIFEST_GIT_BLOB_MISMATCH")
    doc=verify.parse_manifest(raw,"REVIEW")
    if (doc.get("latest_version")!="0.6.30" or
        doc.get("source_commit")!=IMMUTABLE_SOURCE_COMMIT or
        doc.get("payload_set_sha256")!=EXPECTED_PAYLOAD_SET or
        doc.get("bootstrap",{}).get("sha256")!=EXPECTED_BOOT_SHA or
        len(doc.get("updates",[]))!=19):
        raise RuntimeError("R80_REVIEW_MANIFEST_RELEASE_PINS_MISMATCH")
    verify.validate_latest(doc,verify.FUTURE)
    patches=verify.newest_edge(doc,"0.6.28","0.6.30",[
        "bin/spotify-control.ps1","bin/spotify-control-agent.vbs"])
    if sum(len(p["chunks"]) for p in patches)!=EXPECTED_CHUNKS:
        raise RuntimeError("R80_REVIEW_CHUNK_COUNT_CHANGED")
    return doc,patches

def run():
    verify=load_verifier()
    url=verify.RAW+REVIEW_COMMIT+"/manifest.json"
    raw=verify.download(url,200_000)
    doc,patches=preflight(raw,verify)
    # The historical stable 0.6.28 manifest remains the currently published
    # authority. Inspect and compare without writing GitHub main/ or the PC.
    base_raw=verify.download(verify.RAW+verify.BASE_MAIN_COMMIT+"/manifest.json",200_000)
    baseline=verify.parse_manifest(base_raw,"BASE")
    if (baseline.get("latest_version")!=verify.BASE_LATEST or
        baseline.get("source_commit")!=verify.BASE_PAYLOAD_COMMIT or
        len(baseline.get("updates",[]))!=18 or
        doc["updates"][:-1]!=baseline["updates"] or
        doc["bootstrap"]!=baseline["bootstrap"]):
        raise RuntimeError("R80_REVIEW_BASELINE_HISTORY_OR_TRUST_ROOT_NOT_EXACT")
    verify.validate_latest(baseline,verify.ORIGINAL)
    before={p:verify.ORIGINAL[p][1] for p in (
        "bin/spotify-control.ps1","bin/spotify-control-agent.vbs")}
    chunks,decoded=verify.attest_downloaded(doc,verify.FUTURE,before,
                                            "0.6.30",patches,IMMUTABLE_SOURCE_COMMIT)
    if chunks!=EXPECTED_CHUNKS or set(decoded)!={p["path"] for p in patches}:
        raise RuntimeError("R80_RELEASE_REVIEW_FULLFILE_NOT_PROVEN")
    target=verify.FUTURE
    for path,data in decoded.items():
        if hashlib.sha256(data).hexdigest()!=target[path]:
            raise RuntimeError("R80_MAIN_OR_VBS_OUTPUT_SHA_NOT_PINNED")
    print("R80_HELD_REVIEW_COMMIT="+REVIEW_COMMIT)
    print("R80_REVIEW_MANIFEST_SHA256="+hashlib.sha256(raw).hexdigest())
    print("R80_UNMODIFIED_OFFICIAL_BOOTSTRAP_SHA256="+EXPECTED_BOOT_SHA)
    print("R80_IMMUTABLE_21_CHUNKS_AND_TWO_FULL_FILES=PASS")
    print("R80_RELEASE_BASELINE_HISTORY_AND_ADDON_R17=PASS")
    print("R80_PUBLIC_MANIFEST_WRITE=NO;OWNER_PC_CHANGES=NO;UPDATE_INSTALL=NO")
    print("R80_RESULT=PREPUBLICATION_READONLY_TRANSPORT_ADMITTED_NOT_OWNER_CUTOVER")

def tamper_selftest():
    verify=load_verifier()
    # This public-independent negative control requires no network or owner
    # sources: no payload/manifest mutation can cross the exact Git pin.
    raw=(b'{"schema":1,"latest_version":"0.6.30"}'*50)
    try:
        preflight(raw,verify)
    except RuntimeError as exc:
        if str(exc)!="R80_EXACT_REVIEW_MANIFEST_GIT_BLOB_MISMATCH":
            raise
    else:
        raise RuntimeError("R80_TAMPERED_REVIEW_MANIFEST_ACCEPTED")
    print("R80_MUTATED_MANIFEST_GIT_PIN_REJECTED=PASS")

if __name__=="__main__":
    if sys.argv[1:]==["--tamper-selftest"]:
        tamper_selftest()
    elif not sys.argv[1:]:
        run()
    else:
        raise SystemExit("R80 supported arguments: --tamper-selftest")
