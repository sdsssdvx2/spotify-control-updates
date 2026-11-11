"""R79 HOLD: audit actual official v0.6.28 and verified R70 full main
for any implicit self-update action, to avoid publishing 0.6.30 before an
owner-controlled rollout. Pure source inspection; no network/user state.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import runpy

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
PINS={
    "V0628":(284321,"af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0"),
    "R70":(294101,"b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"),
}
CHECK_TERMS=(
    r"(?i)spotify-control-self-updater",
    r"(?i)self.update",
    r"(?i)bootstrap",
    r"(?i)manifest\.json",
    r"(?i)\-Action\s+(?:Update|Check)",
    r"(?i)upgrade",
    r"(?i)auto.update",
)
FUNC=re.compile(r'(?im)^function\s+([A-Za-z0-9_-]+)\s*(?:\([^)]*\))?\s*\{')
CALL=re.compile("|".join("(?:%s)"%x for x in CHECK_TERMS))
def log(name:str,raw:bytes):
    length,digest=PINS[name]
    if (len(raw),hashlib.sha256(raw).hexdigest())!=(length,digest):
        raise RuntimeError("R79_OFFICIAL_SOURCE_PIN_MISMATCH_"+name)
    text=raw.decode("utf-8-sig").replace("\r\n","\n")
    lines=text.splitlines()
    starts=[(i+1,m.group(1)) for i,line in enumerate(lines) if (m:=FUNC.match(line))]
    found=[]
    import bisect
    points=[n for n,_ in starts]
    for n,line in enumerate(lines,1):
        if not CALL.search(line):
            continue
        i=bisect.bisect_right(points,n)-1
        function=starts[i][1] if i>=0 else "TOP_LEVEL"
        # Never output source text that could accidentally contain local data
        # because both inputs are exact public source. Still cap to 250 chars.
        found.append((n,function,line.strip()[:250]))
    print(f"R79_{name}_SHA_PIN=PASS")
    print(f"R79_{name}_TOTAL_FUNCS={len(starts)}")
    print(f"R79_{name}_SELFUPDATE_REFERENCE_LINES={len(found)}")
    for n,func,short in found[:95]:
        print(f"R79_{name}_REF_{n}={func}|{short}")
    print(f"R79_{name}_END_REFERENCES")
    # Read-only source review is not live deployment authority.
def main():
    base=runpy.run_path(str(HERE/"stage-candidate.py"))["source_from_stable"]()[0]
    cand=(HERE/"out/release-staging-boot-wmi-R70/bin/spotify-control.ps1").read_bytes()
    log("V0628",base)
    log("R70",cand)
    print("R79_AUTOMATIC_UPDATE_POLICY=SOURCE_AUDIT_ONLY_NOT_DEPLOYMENT_PROOF")
    print("R79_OWNER_PC_AND_GITHUB_PUBLIC_MAIN=UNCHANGED")
if __name__=="__main__":main()
