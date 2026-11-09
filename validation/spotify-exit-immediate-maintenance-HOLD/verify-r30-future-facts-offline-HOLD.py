"""R30 non-network attestation contract acceptance.

Uses exactly the same 20 staged future release chunks as native Bootstrap
E2E, but replaces HTTP with a fully pinned in-memory Git/raw transport.
This is a synthetic proof of R29 future mode, NOT public publication or
authorization. It never writes to user files or starts programs.
"""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "validation/spotify-exit-immediate-maintenance-HOLD"
STAGE = SUB / "out/release-staging"
R29 = SUB / "verify-public-release-transport-R29-HOLD.py"
SOURCE = "1" * 40  # not an approved or claimed public commit


def sha(b):
    return hashlib.sha256(b).hexdigest()


def reject(call, needle):
    try:
        call()
    except RuntimeError as ex:
        if needle not in str(ex):
            raise RuntimeError("WRONG_R30_REJECTION_CLASS_"+str(ex)) from ex
    else:
        raise RuntimeError("R30_NEGATIVE_WAS_ACCEPTED_"+needle)


def main():
    before = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8-sig"))
    staged = json.loads((STAGE / "manifest-UNPUBLISHABLE.json").read_text(encoding="ascii"))
    if before["latest_version"] != "0.6.28" or before["source_commit"] != "bb6d90146f20b73d36fbf8cb813f1b190f403c48":
        raise RuntimeError("ORIGINAL_OFFICIAL_RELEASE_DRIFT")
    if staged["source_commit"] != "f"*40 or len(staged["updates"]) != 19:
        raise RuntimeError("FUTURE_STAGE_NOT_UNPUBLISHABLE")
    future = copy.deepcopy(staged)
    future["source_commit"] = SOURCE
    manifest_bytes = json.dumps(future,ensure_ascii=True,sort_keys=True,separators=(",",":")).encode("ascii")
    manifest_sha = sha(manifest_bytes)
    module=runpy.run_path(str(R29))
    function=module["attest_future_release"]
    namespace=function.__globals__
    # Historical R30 scenario attests the immutable shortcut-only fixture.
    # The real R29 public admission now correctly targets the integrated R38.
    namespace["FUTURE"]=dict(namespace["FUTURE"])
    namespace["FUTURE"]["bin/spotify-control.ps1"]="37eda0638c428ed3474a06812c067ca10f5771216ae509d3cd4ce10fdafbd3ec"
    namespace["FUTURE"]["bin/spotify-control-agent.vbs"]="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
    raw_url=namespace["RAW"]
    allowed={}
    patches=future["updates"][-1]["patches"]
    for patch in patches:
        for chunk in patch["chunks"]:
            rel=chunk["path"]
            b=(STAGE / rel).read_bytes()
            if (len(b),sha(b)) != (chunk["size"],chunk["sha256"]):
                raise RuntimeError("STAGED_IMMUTABLE_CHUNK_SHA_CHANGED")
            allowed[raw_url+SOURCE+"/"+rel]=b
    if len(allowed)!=20:
        raise RuntimeError("R30_STAGED_TRANSPORT_NOT_20_CHUNKS")
    tampered={}
    def exact_get(url,limit):
        b=tampered.get(url, allowed.get(url))
        if b is None or len(b)>limit:
            raise RuntimeError("UNKNOWN_PUBLIC_SOURCE_OR_UNBOUNDED_CHUNK")
        return b
    namespace["download"]=exact_get
    receipt=function(manifest_bytes,before,manifest_sha,SOURCE)
    expected={
        "schema":"SPOTIFY_R30_PUBLIC_RELEASE_FACTS_V1",
        "status":"PUBLIC_SOURCE_AND_PAYLOAD_READONLY_VERIFIED_NOT_OWNER_AUTHORIZED",
        "from_version":"0.6.28",
        "to_version":"0.6.30",
        "manifest_sha256":manifest_sha,
        "source_commit":SOURCE,
        "payload_set_sha256":staged["payload_set_sha256"],
        "bootstrap_sha256":staged["bootstrap"]["sha256"],
        "main_sha256":"37eda0638c428ed3474a06812c067ca10f5771216ae509d3cd4ce10fdafbd3ec",
        "agent_sha256":"da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d",
        "addon_sha256":"5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285",
        "chunk_count":20,
        "model":"READ_ONLY_PROVENANCE_NO_EXECUTION",
    }
    if receipt!=expected:
        raise RuntimeError("R30_FACTUAL_RECEIPT_NOT_EXACT")
    print("R30_SYNTHETIC_FUTURE_20_SOURCE_CHUNKS_RECEIPT=PASS")

    reject(lambda: function(manifest_bytes,before,"0"*64,SOURCE),
           "NEXT_STABLE_APPROVED_MANIFEST_SHA_MISMATCH")
    reject(lambda: function(manifest_bytes,before,manifest_sha,"f"*40),
           "NEXT_STABLE_INDEPENDENT_RELEASE_APPROVAL_PINS_REQUIRED")
    reject(lambda: function(manifest_bytes,before,manifest_sha,"0"*40),
           "NEXT_STABLE_VERSION_HISTORY_OR_SOURCE_NOT_APPROVED")
    invalid=copy.deepcopy(future)
    invalid["updates"][2]["to_version"]="0.0.0"
    invalid_bytes=json.dumps(invalid,sort_keys=True,separators=(",",":")).encode("ascii")
    reject(lambda: function(invalid_bytes,before,sha(invalid_bytes),SOURCE),
           "NEXT_STABLE_VERSION_HISTORY_OR_SOURCE_NOT_APPROVED")
    # Actual corruption of ONE content-addressed chunk should fail before
    # a factual receipt can be issued.
    first=next(iter(allowed))
    raw=allowed[first]
    tampered[first]=(b"B" if raw[:1]!=b"B" else b"C")+raw[1:]
    reject(lambda: function(manifest_bytes,before,manifest_sha,SOURCE),
           "IMMUTABLE_CHUNK_SIZE_OR_SHA_MISMATCH")
    tampered.clear()
    print("R30_INVALID_MANIFEST_SOURCE_HISTORY_AND_CHUNK_REJECTED=PASS")
    print("R30_OWNER_APPROVAL=NOT_GRANTED;PUBLIC_NEXT_RELEASE=NOT_PUBLISHED")
    print("R30_OPERATING_SOURCES_AND_EXTERNAL_NETWORK=UNCHANGED")


if __name__=="__main__":
    main()
