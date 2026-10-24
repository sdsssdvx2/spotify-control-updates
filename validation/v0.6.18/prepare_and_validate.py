from pathlib import Path
import base64,gzip,hashlib,json,os,re,subprocess

OLD_MAIN='5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'
PREVIOUS_CANDIDATE_MAIN='d848f61c318d22b3506b830d4ecc6974d3ba45853957fdd056b3f4f8f4984425'
NEW_MAIN='27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f'
NEW_MAIN_SIZE=281593
ADDON='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
ADDON_SIZE=154926
AGENT='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE=4855
PAYLOAD='ed87bf1b02a66c77137d96846dc58a3c068372abcb6deb38d335dee32243625e'
ENC_SHA='be1fd4188c17b27d6fa47e60178ffe4397a360ebe86cf948537d8911bad4dc61'
ENC_SIZE=5944
GZ_SHA='1f17fddacd39420019785e681b94435ff9bde17bf2858ff32ac9cd587be23bbe'
GZ_SIZE=4458
JSON_SHA='101cf5f1c2a2f77b43e6bb577cd3d141abc5f5990232cf76260903ce04f273ec'
JSON_SIZE=16340
CHUNKS=[
 ('packages/v0.6.18/main-v0617-to-v0618-r2/chunk-000.txt','080749e3fc1b36ce40cb3f9ff9acf08ac83b630d772b3246f1f5ea430dc835f3',1024),
 ('packages/v0.6.18/main-v0617-to-v0618-r2/chunk-001.txt','4acfae8decec577f77d0c7aa4d5bda017974dc05e222a0758bdad5b404c641e6',1024),
 ('packages/v0.6.18/main-v0617-to-v0618-r2/chunk-002.txt','24f0e1a2a7cb25ee0f400dcfcf4fc9448e8c59c83d37b68cb9960b5b7753b7cf',1024),
 ('packages/v0.6.18/main-v0617-to-v0618-r2/chunk-003.txt','d0600daa8f58f95a230d44cebe29214080b18c3161e018ead18e787398cd86d8',1024),
 ('packages/v0.6.18/main-v0617-to-v0618-r2/chunk-004.txt','33a4524f84c605881e392860067089f8617f206cd03005ce0e7f76b9d624eaaf',1024),
 ('packages/v0.6.18/main-v0617-to-v0618-r2/chunk-005.txt','0cc863dbf9b4a96730cfa09802bd53be49b88622aee3eef8c86e860d20088f1b',824),
]

def sha(b): return hashlib.sha256(b).hexdigest()
def git_bytes(ref,path): return subprocess.check_output(['git','show',f'{ref}:{path}'])

def expected_edge():
    return {'from_version':'0.6.17','to_version':'0.6.18','patches':[{
      'path':'bin/spotify-control.ps1','from_sha256':OLD_MAIN,'to_sha256':NEW_MAIN,
      'encoding':'gzip-base64-chunks','encoded_sha256':ENC_SHA,'encoded_size':ENC_SIZE,
      'compressed_sha256':GZ_SHA,'compressed_size':GZ_SIZE,'json_sha256':JSON_SHA,'json_size':JSON_SIZE,
      'chunks':[{'path':p,'sha256':h,'size':s} for p,h,s in CHUNKS]}]}

def canonical_payload(latest):
    rows=[f"{x['path']}|{int(x['size'])}|{x['sha256']}" for x in sorted(latest,key=lambda x:x['path'])]
    return sha(('\n'.join(rows)+'\n').encode('ascii'))

def validate_transport(source_commit):
    assert re.fullmatch(r'[0-9a-f]{40}',source_commit),source_commit
    parts=[]
    for i,(p,h,s) in enumerate(CHUNKS):
        assert p.endswith(f'/chunk-{i:03}.txt')
        b=git_bytes(source_commit,p); assert len(b)==s and sha(b)==h,(p,len(b),sha(b)); parts.append(b)
    enc=b''.join(parts); assert len(enc)==ENC_SIZE and sha(enc)==ENC_SHA
    comp=base64.b64decode(enc,validate=True); assert len(comp)==GZ_SIZE and sha(comp)==GZ_SHA
    raw=gzip.decompress(comp); assert len(raw)==JSON_SIZE and sha(raw)==JSON_SHA
    assert all(x<128 for x in raw)
    doc=json.loads(raw.decode('ascii'))
    assert doc['schema']==1 and doc['kind']=='ascii-line-patch'
    assert doc['from_version']=='0.6.17' and doc['to_version']=='0.6.18'
    assert doc['from_sha256']==OLD_MAIN and doc['to_sha256']==NEW_MAIN
    assert doc['bom']=='utf8-bom' and doc['line_ending']=='lf'
    ops=doc['operations']; assert 1<=len(ops)<=256
    prev=-1
    for op in ops:
        start=int(op['start_line']); delete=int(op['delete_count']); ins=str(op['insert'])
        assert start>=0 and delete>=0 and start>=prev; prev=start+delete
        assert '\r' not in ins and all(ord(c)<128 for c in ins)
    print('V0618_TRANSPORT_PASS',source_commit,len(raw),len(ops))

def validate_manifest(m):
    assert m['schema']==1 and m['channel']=='stable' and m['latest_version']=='0.6.18'
    assert m['min_bootstrap_version']=='1.0.6'
    assert m['bootstrap']=={'version':'1.0.6','sha256':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6','size':42963}
    latest={x['path']:x for x in m['latest_files']}
    assert latest['bin/spotify-control.ps1']=={'path':'bin/spotify-control.ps1','sha256':NEW_MAIN,'size':NEW_MAIN_SIZE}
    assert latest['bin/addon-manager.ps1']=={'path':'bin/addon-manager.ps1','sha256':ADDON,'size':ADDON_SIZE}
    assert latest['bin/spotify-control-agent.vbs']=={'path':'bin/spotify-control-agent.vbs','sha256':AGENT,'size':AGENT_SIZE}
    assert canonical_payload(m['latest_files'])==PAYLOAD==m['payload_set_sha256']
    rows=[e for e in m['updates'] if e['from_version']=='0.6.17']
    assert rows==[expected_edge()],rows
    validate_transport(m['source_commit'])
    print('V0618_MANIFEST_PASS',m['source_commit'],m['payload_set_sha256'])

def rewrite_to_current(m,transport):
    assert re.fullmatch(r'[0-9a-f]{40}',transport),'TRANSPORT_SHA missing/invalid'
    latest={x['path']:x for x in m['latest_files']}
    latest['bin/spotify-control.ps1']['sha256']=NEW_MAIN;latest['bin/spotify-control.ps1']['size']=NEW_MAIN_SIZE
    m['latest_version']='0.6.18';m['source_commit']=transport;m['payload_set_sha256']=PAYLOAD
    m['updates']=[e for e in m['updates'] if e['from_version']!='0.6.17']
    m['updates'].append(expected_edge())
    return m

p=Path('manifest.json'); m=json.loads(p.read_text(encoding='utf-8-sig'))
transport=os.environ.get('TRANSPORT_SHA','').strip()
if m.get('latest_version')=='0.6.17':
    assert m['source_commit']=='36b15a2ed2f9a23fffbeaf91de78b7854f6108b2'
    latest={x['path']:x for x in m['latest_files']}
    assert latest['bin/spotify-control.ps1']['sha256']==OLD_MAIN
    assert not any(e['from_version']=='0.6.17' for e in m['updates'])
    rewrite_to_current(m,transport)
    p.write_text(json.dumps(m,separators=(',',':')),encoding='utf-8',newline='')
    print('V0618_MANIFEST_PREPARED',transport)
    validate_manifest(m)
elif m.get('latest_version')=='0.6.18':
    latest={x['path']:x for x in m['latest_files']}
    if latest['bin/spotify-control.ps1']['sha256']==PREVIOUS_CANDIDATE_MAIN:
        assert transport,'TRANSPORT_SHA required to refresh previous v0.6.18 candidate'
        rewrite_to_current(m,transport)
        p.write_text(json.dumps(m,separators=(',',':')),encoding='utf-8',newline='')
        print('V0618_MANIFEST_REFRESHED',transport)
    validate_manifest(m)
else:
    raise AssertionError(f"unexpected stable latest_version={m.get('latest_version')}")
