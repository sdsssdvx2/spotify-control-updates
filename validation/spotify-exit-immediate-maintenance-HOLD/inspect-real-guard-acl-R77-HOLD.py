"""R77 HOLD read-only inventory of exact 0.6.30 full main mutation admission.
No user PC, release, keys, accounts, or runtime mutation. Emit bounded public
source excerpts so a compatibility gate can be inserted in the right place.
"""
from __future__ import annotations
import hashlib,os,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
MAIN=HERE/"out/release-staging-boot-wmi-R70/bin/spotify-control.ps1"
PIN="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
def main():
    if os.environ.get("GITHUB_ACTIONS")!="true" or os.environ.get("RUNNER_OS")!="Windows" or os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted":
        raise RuntimeError("R77_HOSTED_READONLY_ONLY")
    src=MAIN.read_bytes()
    if hashlib.sha256(src).hexdigest()!=PIN:raise RuntimeError("R77_REAL_MAIN_SHA_DRIFT")
    s=src.decode("utf-8-sig").replace("\r\n","\n")
    lines=s.splitlines()
    fns=list(re.finditer(r'(?im)^function\s+([a-zA-Z0-9_-]+)\s*\{',s))
    # Only functions directly responsible for Spotify updater ACL enforcement;
    # bounded public source output, never print owner's files or credentials.
    relevant=[]
    for i,f in enumerate(fns):
        name=f.group(1)
        b=f.start()
        e=fns[i+1].start() if i+1<len(fns) else len(s)
        body=s[b:e]
        if (("Guard" in name or "UpdateBlock" in name or "Acl" in name or "ACL" in name) and
             any(k in body.lower() for k in ("get-acl","set-acl","accessrule","updateguard","icacls","accesscontrol","updater","guard_enforced"))):
            relevant.append((name,body))
    print("R77_ACTUAL_MAIN_SHA256=PASS")
    print("R77_RELEVANT_GUARD_FUNCTIONS="+",".join(x[0] for x in relevant)[:1200])
    for name,body in relevant:
        lines=body.splitlines()
        print("R77_GUARD_FUNCTION="+name+" lines="+str(len(lines)))
        for i,line in enumerate(lines):
            if i<200 or any(k in line.lower() for k in ("get-acl","set-acl","fileaccessrule","directorysecurity","accesscontrol")):
                print("R77_SRC "+name+" "+str(i+1)+": "+line[:260])
        print("R77_GUARD_FUNCTION_END="+name)
    patterns=("Get-Acl","Set-Acl","icacls","AccessRule","DirectorySecurity",
              "ACCESS_DENIED","guard_enforced","Get-SmartUpdateGuardPlan")
    matching=[(i+1,line) for i,line in enumerate(lines if False else s.splitlines())
              if any(p.lower() in line.lower() for p in patterns)]
    print("R77_ALL_ACL_REFS="+str(len(matching)))
    for i,line in matching[:120]:
        print("R77_GLOBAL_SOURCE "+str(i)+": "+line[:260])
    print("R77_READ_ONLY_NO_PRODUCT_CHANGE=PASS")
if __name__=="__main__":main()
