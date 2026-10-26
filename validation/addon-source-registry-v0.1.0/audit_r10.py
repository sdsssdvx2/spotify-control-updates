from pathlib import Path
import argparse, hashlib, json, re, sys

ROOT=Path(__file__).resolve().parents[2]
EXPECTED_MAIN_SHA='f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'
EXPECTED_MAIN_SIZE=281579
EXPECTED_ADDON_SHA='7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
EXPECTED_ADDON_SIZE=250616
EXPECTED_AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
EXPECTED_AGENT_SIZE=4855
EXPECTED_PAYLOAD='7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55'
EXPECTED_SOURCE='9a90d5f13eb63023d8f965a004be14d309d99429'
EXPECTED_BOOT='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
EXPECTED_AUTO={'ivLyrics','better-local-files','eternal-jukebox','playlist-maker'}


def sha(p:Path): return hashlib.sha256(p.read_bytes()).hexdigest()
def need(ok,msg):
    if not ok: raise AssertionError(msg)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--report');args=ap.parse_args()
    manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))
    need(manifest['latest_version']=='0.6.21','stable latest_version drift')
    need(manifest['source_commit']==EXPECTED_SOURCE,'stable source_commit drift')
    need(manifest['payload_set_sha256']==EXPECTED_PAYLOAD,'stable payload drift')
    need(manifest['bootstrap']=={'version':'1.0.6','sha256':EXPECTED_BOOT,'size':42963},'Bootstrap identity drift')
    latest={x['path']:x for x in manifest['latest_files']}
    need((latest['bin/spotify-control.ps1']['size'],latest['bin/spotify-control.ps1']['sha256'])==(EXPECTED_MAIN_SIZE,EXPECTED_MAIN_SHA),'main identity drift')
    need((latest['bin/addon-manager.ps1']['size'],latest['bin/addon-manager.ps1']['sha256'])==(EXPECTED_ADDON_SIZE,EXPECTED_ADDON_SHA),'addon identity drift')
    need((latest['bin/spotify-control-agent.vbs']['size'],latest['bin/spotify-control-agent.vbs']['sha256'])==(EXPECTED_AGENT_SIZE,EXPECTED_AGENT_SHA),'agent identity drift')

    policy=(ROOT/'validation/v0.6.21/addon_policy_registry.ps1.inc').read_text(encoding='utf-8-sig')
    rows=re.findall(r"\[pscustomobject\]@\{ name='([^']+)'; kind='([^']+)'; source=([^;]+); inventory_policy='([^']+)'; mutation_mode='([^']+)'; handler='([^']+)'",policy)
    need(len(rows)==9,f'expected 9 policy rows, got {len(rows)}')
    names=[r[0] for r in rows];need(len(set(names))==9,'duplicate policy names')
    auto={r[0] for r in rows if r[4]=='auto'}
    need(auto==EXPECTED_AUTO,f'auto authority drift: {sorted(auto)}')
    handlers={r[5] for r in rows if r[4]=='auto'}
    need(handlers=={'pithaya','ivlyrics'},f'auto handler set drift: {sorted(handlers)}')
    for denied in ('tagify','splitify','star-ratings','sc-cover-ambience.js','sc-star-ratings.js'):
        row=next(r for r in rows if r[0]==denied);need(row[4]=='deny',f'{denied} mutation_mode drift')
    need("data_policy='protect-ratings-tags-notes'" in policy,'Tagify data protection missing')
    need("data_policy='never-disable-or-optimize'" in policy,'SC Cover Ambience protection missing')
    need("Reason='unregistered'" in policy,'unknown addon fail-closed authorization missing')
    need("Reason='source-mismatch'" in policy and "Reason='policy-mismatch'" in policy and "Reason='kind-mismatch'" in policy,'registry mismatch guards missing')
    need("Reason='not-installed'" in policy,'installed-only guard missing')
    need("$entry.handler -notin @('pithaya','ivlyrics')" in policy,'production handler allowlist drift')

    guard=(ROOT/'validation/v0.6.21/addon_transaction_registry_guard.ps1.inc').read_text(encoding='utf-8-sig')
    for marker in ('registry_schema','registry_sha256','registry_handler','registry_source','registry_policy'):
        need(marker in guard,f'transaction registry guard missing {marker}')
    need('RollbackLast' not in guard or 'registry' in guard,'unexpected transaction guard shape')

    engine=(ROOT/'validation/addon-source-registry-v0.1.0/source_adapter_engine.ps1').read_text(encoding='utf-8-sig')
    for forbidden in ('Invoke-WebRequest','Invoke-RestMethod','Expand-Archive','Remove-Item','Move-Item','Copy-Item','Start-Process','spicetify apply','spicetify backup','spicetify restore'):
        need(forbidden.lower() not in engine.lower(),f'validation generic engine gained side effect surface: {forbidden}')
    need("archive_policy='existing-handler-only'" in engine,'existing-handler archive delegation missing')
    need("archive_policy='none'" in engine,'monitor-only no-archive contract missing')
    need('Get-AddonMutationAuthorization' in engine,'generic plan does not defer authority to production registry')

    out=ROOT/'validation/v0.6.21/out/bin/addon-manager.ps1'
    need(out.exists(),'exact r10 candidate was not rebuilt before audit')
    need((out.stat().st_size,sha(out))==(EXPECTED_ADDON_SIZE,EXPECTED_ADDON_SHA),f'rebuilt r10 identity mismatch {(out.stat().st_size,sha(out))}')
    addon=out.read_text(encoding='utf-8-sig')
    need('$Version = "0.6.5-r10"' in addon,'r10 marker missing')
    need('Get-AddonMutationAuthorization -Item $item' in addon,'r10 update path does not use registry authorization')
    need('Unsupported registry mutation handler' in addon,'r10 unsupported-handler fail closed missing')
    need(addon.count('Invoke-AddonPolicyRegistrySelfTest')>=1,'registry selftest not wired')

    report={
        'result':'AUDIT_PASS','stable_version':'0.6.21','addon_sha256':EXPECTED_ADDON_SHA,
        'registry_entries':9,'auto_authority':sorted(EXPECTED_AUTO),'auto_handlers':sorted(handlers),
        'generic_engine_side_effects':False,'generic_engine_network_fetch':False,'generic_engine_archive_extraction':False,
        'authority_source':'Get-AddonMutationAuthorization','unknown_addons':'fail-closed',
        'protected':['tagify','splitify','star-ratings','sc-cover-ambience.js','sc-star-ratings.js']
    }
    if args.report:
        p=Path(args.report);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print(json.dumps(report,sort_keys=True))
    print('ADDON_SOURCE_REGISTRY_R10_AUDIT_PASS')

if __name__=='__main__':
    try: main()
    except Exception as e:
        print(f'AUDIT_FAIL: {e}',file=sys.stderr);raise
