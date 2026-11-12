"""R74 HOLD read-only inventory of exact 0.6.30 full main mutation admission.
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
        raise RuntimeError("R74_HOSTED_READONLY_ONLY")
    src=MAIN.read_bytes()
    if hashlib.sha256(src).hexdigest()!=PIN:raise RuntimeError("R74_REAL_MAIN_SHA_DRIFT")
    s=src.decode("utf-8-sig").replace("\r\n","\n")
    lines=s.splitlines()
    fns=list(re.finditer(r'(?im)^function\s+([a-zA-Z0-9_-]+)\s*\{',s))
    keywords=("SelfUpdate","Self-Updater","Test-DueHours","Spicetify","SpotifyVersion","Spotify-Version","VersionSpotify","Backup","Invoke-MaintenanceMutationPhase","Invoke-MaintenanceCheckPhase","Update-AutoApps","AgentTick","GuardPlan","spotify_path","prefs_path")
    candidates=[(f.group(1),f.start(),f.end(),fns[i+1].start() if i+1<len(fns) else len(s)) for i,f in enumerate(fns) if any(k.lower() in f.group(1).lower() for k in keywords)]
    print("R74_MAIN_SHA256=PASS")
    print("R74_FUNCTIONS_TOTAL="+str(len(fns)))
    print("R74_SOURCE_KEYWORD_FUNCTIONS="+",".join(x[0] for x in candidates)[:3000])
    selected=["Get-SelfUpdateCheckResult","Invoke-SelfUpdaterJsonAction","Get-SpicetifyLatestReleaseInfo","Invoke-MaintenanceCheckPhase","Repair-SpicetifyBackupMetadataIfTrusted","Test-SpicetifyBackupMetadataRepairEligibility","Invoke-SpicetifyTransactionalMaintenance","Invoke-MaintenanceMutationPhase","Maintain","Invoke-ResidentAgentTick","Update-AutoApps"]
    for n,b,_,e in candidates:
        if n in selected:
            fragment=s[b:e].splitlines()
            print("R74_FUNCTION_BEGIN="+n+" lines="+str(len(fragment)))
            if len(fragment)<210:
                for i,line in enumerate(fragment):
                    print("R74_FUNC "+n+" "+str(i+1)+": "+line[:330])
            else:
                for i,line in enumerate(fragment):
                    if i<27 or i>len(fragment)-14 or any(k in line.lower() for k in ("spicetify","spotifyversion","version","guard","apply","compat","addon","mutation","update-autoapps")):
                        print("R74_FUNC "+n+" "+str(i+1)+": "+line[:330])
            print("R74_FUNCTION_END="+n)
    # Other functions and relevant clauses only, bounded.
    pattern=re.compile(r'(?i)spotify.*version|version.*spotify|spicetify.*apply|spicetify.*backup|spicetify.*version|spicetify.*refresh|unsupported|compatib|guardplan|invoke-maintenance(?:mutation|check)phase')
    matches=[(i+1,line.strip()[:320]) for i,line in enumerate(lines) if pattern.search(line)]
    print("R74_RELEVANT_LINES_TOTAL="+str(len(matches)))
    for i,line in matches[:180]:print("R74_SOURCE_LINE "+str(i)+": "+line)
    print("R74_READ_ONLY_NO_PRODUCT_CHANGE=PASS")
if __name__=="__main__":main()
