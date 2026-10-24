from pathlib import Path
import base64,gzip,hashlib,json,os,re,subprocess

OLD_MAIN='5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'
NEW_MAIN='d848f61c318d22b3506b830d4ecc6974d3ba45853957fdd056b3f4f8f4984425'
NEW_MAIN_SIZE=281551
ADDON='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
ADDON_SIZE=154926
AGENT='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE=4855
PAYLOAD='7c5e03a89b8d0d4209bb55485a0e32de56267c56d97a0c97cbb661823bd84d5f'
ENC_SHA='42ba557900d8d603d2aafdffdffb8f5cf814930b4e4a6fd536a148e3a36bff8e'
ENC_SIZE=5928
GZ_SHA='3fe57e3ad9f589381bd5b78026e03a3363f00ddfd1eedcf36feaf5d71b4a5423'
GZ_SIZE=4444
JSON_SHA='7ee26d4cfdfaba691096e0d813dba7636d7c03e793485993d540afa2721a1f7d'
JSON_SIZE=16295
CHUNKS=[
 ('packages/v0.6.18/main-v0617-to-v0618/chunk-000.txt','08eb5aa27d29e3ee9b3a8bb857b9bc6f3b83586d462776dbf1df7cf9f07c722b',4096),
 ('packages/v0.6.18/main-v0617-to-v0618/chunk-001.txt','75048499ea1b9754a61966c029e6864bb902db401b2f9f5b219533e641d50d2c',1832),
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
        assert p.endswith(f'/chunk-{i:03d}.txt')
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

p=Path('manifest.json'); m=json.loads(p.read_text(encoding='utf-8-sig'))
if m.get('latest_version')=='0.6.17':
    transport=os.environ.get('TRANSPORT_SHA','').strip()
    assert re.fullmatch(r'[0-9a-f]{40}',transport),'TRANSPORT_SHA missing/invalid'
    assert m['source_commit']=='36b15a2ed2f9a23fffbeaf91de78b7854f6108b2'
    latest={x['path']:x for x in m['latest_files']}
    assert latest['bin/spotify-control.ps1']['sha256']==OLD_MAIN
    assert not any(e['from_version']=='0.6.17' for e in m['updates'])
    m['latest_version']='0.6.18';m['source_commit']=transport;m['payload_set_sha256']=PAYLOAD
    latest['bin/spotify-control.ps1']['sha256']=NEW_MAIN;latest['bin/spotify-control.ps1']['size']=NEW_MAIN_SIZE
    m['updates'].append(expected_edge())
    p.write_text(json.dumps(m,separators=(',',':')),encoding='utf-8',newline='')
    print('V0618_MANIFEST_PREPARED',transport)
    validate_manifest(m)
elif m.get('latest_version')=='0.6.18':
    validate_manifest(m)
else:
    raise AssertionError(f"unexpected stable latest_version={m.get('latest_version')}")
