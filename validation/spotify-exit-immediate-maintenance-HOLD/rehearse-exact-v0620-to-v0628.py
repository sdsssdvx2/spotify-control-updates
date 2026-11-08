"""Rehearse EXACT official v0.6.20/r9 => v0.6.28/r17 using released
Bootstrap 1.0.6 and the untouched stable manifest in a hosted Windows fixture.
This does not use or write any user machine profile, and never publishes a
new manifest, changes installed apps, or promotes v0.6.29.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "ci-bootstrap-v0620-to-v0628-exact-user-baseline"
BASE_MAIN = (281585, "e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18")
BASE_ADDON = (225044, "3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86")
AGENT = (4855, "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278")
BOOTSTRAP = (42963, "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6")
MAIN_URL = b"https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json"
LOCAL_URL = b"http://127.0.0.1:8765/manifest.json"

def pin(data: bytes, expected: tuple[int, str], label: str):
    actual = len(data), hashlib.sha256(data).hexdigest()
    if actual != expected:
        raise RuntimeError(label + "_SHA_OR_SIZE_MISMATCH")

def prepare():
    m = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8-sig"))
    if m.get("latest_version") != "0.6.28" or m.get("bootstrap") != {
        "version":"1.0.6", "sha256":BOOTSTRAP[1], "size":BOOTSTRAP[0]
    }:
        raise RuntimeError("STABLE_MANIFEST_IDENTITY_CHANGED")
    chain=[]
    current="0.6.20"
    while current != "0.6.28":
        edges=[x for x in m["updates"] if x["from_version"]==current]
        if len(edges)!=1:
            raise RuntimeError("STABLE_FORWARD_EDGE_MISSING_OR_AMBIGUOUS_"+current)
        nxt=edges[0]["to_version"]
        if nxt <= current or len(chain)>=12:
            raise RuntimeError("STABLE_FORWARD_EDGE_CYCLE")
        chain.append(current+"->"+nxt)
        current=nxt
    if len(chain)!=8:
        raise RuntimeError("UNEXPECTED_EXACT_USER_BASELINE_EDGE_COUNT")
    subprocess.check_call([sys.executable,str(ROOT/"validation/v0.6.20/build_v0620.py"),"--build"], cwd=ROOT)
    original=ROOT/"validation/v0.6.20/out/bin"
    main=(original/"spotify-control.ps1").read_bytes()
    addon=(original/"addon-manager.ps1").read_bytes()
    pin(main,BASE_MAIN,"USER_MAIN")
    pin(addon,BASE_ADDON,"USER_ADDON")
    # Reuse the already-accepted fixture constructor for the exact 42,963
    # byte Bootstrap, VBS, five helpers, and a neutral Marketplace tree.
    runpy.run_path(str(ROOT/"validation/bootstrap-contract-repair/build_bootstrap_fixture.py"),run_name="__main__")
    carrier=ROOT/"ci-bootstrap-fixture"
    if FOLDER.exists():
        raise RuntimeError("EXACT_BASELINE_FIXTURE_TARGET_ALREADY_EXISTS")
    shutil.copytree(carrier,FOLDER)
    bin_dir=FOLDER/"LocalAppData/SpotifyControl/bin"
    boot_dir=FOLDER/"LocalAppData/SpotifyControl/bootstrap"
    (bin_dir/"spotify-control.ps1").write_bytes(main)
    (bin_dir/"addon-manager.ps1").write_bytes(addon)
    pin((bin_dir/"spotify-control-agent.vbs").read_bytes(),AGENT,"USER_AGENT")
    bootstrap=(boot_dir/"spotify-control-self-updater.ps1").read_bytes()
    pin(bootstrap,BOOTSTRAP,"USER_BOOTSTRAP")
    if bootstrap.count(MAIN_URL)!=1 or LOCAL_URL in bootstrap:
        raise RuntimeError("BOOTSTRAP_ORIGINAL_URL_PATTERN_DRIFT")
    ci_bootstrap=bootstrap.replace(MAIN_URL,LOCAL_URL,1)
    if ci_bootstrap.replace(LOCAL_URL,MAIN_URL,1)!=bootstrap:
        raise RuntimeError("BOOTSTRAP_ONLY_LOCAL_URL_SUBSTITUTION_FAILED")
    (boot_dir/"spotify-control-self-updater-ci-local-manifest.ps1").write_bytes(ci_bootstrap)
    preview=copy.deepcopy(m)
    preview["bootstrap"]["sha256"]=hashlib.sha256(ci_bootstrap).hexdigest()
    preview["bootstrap"]["size"]=len(ci_bootstrap)
    reverted=copy.deepcopy(preview)
    reverted["bootstrap"]["sha256"]=BOOTSTRAP[1]
    reverted["bootstrap"]["size"]=BOOTSTRAP[0]
    if reverted!=m:
        raise RuntimeError("OFFICIAL_MANIFEST_CHANGED_BEYOND_BOOTSTRAP_SHA")
    manifest_dir=FOLDER/"ci-manifest"
    manifest_dir.mkdir()
    (manifest_dir/"manifest.json").write_text(json.dumps(preview,separators=(",",":")),encoding="utf-8",newline="")
    for name in ("update-state.json","update-transaction.json","rollback-state.json"):
        if (FOLDER/"LocalAppData/SpotifyControl"/name).exists():
            raise RuntimeError("EXISTING_SELF_UPDATE_TRANSACTION_NOT_ALLOWED_IN_CI")
    print("V0620_EXACT_USER_INSTALLED_BASELINE_SHA_PASS")
    print("OFFICIAL_STABLE_EIGHT_EDGE_PATH="+"|".join(chain))
    print("REAL_BOOTSTRAP_V106_AND_ORIGINAL_MANIFEST_BYTES_PRESERVED_PASS")
    return FOLDER

if __name__ == "__main__":
    prepare()
