from pathlib import Path
import json, os

MAIN_FROM='5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'
MAIN_TO='1f279a46b4fe3b6ffed4aa5484b3bbe54b7f05cda0a6e8953e078378ac7abdbf'
MAIN_SIZE=283348
ADDON_SHA='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
PAYLOAD_SET='d39de4ff47f60f6534fb4ff6fdf9a1b939a066e12bd5b3536af40e1f490b068a'
ENC_SHA='9f2fbad19cc3b9af2d1ec3b899a930706d26d91f1d12d3591f6b84062281cf8c'
ENC_SIZE=73144
COMP_SHA='8829b6d33b110b0837b2ea60a322d66cf39e0f0f1495219b6fa0065e990be780'
COMP_SIZE=54857
CHUNK_META=[
 ('6b15659c13742ca5fc0d75c4bb4c578f2ccce5374b1b7c94063c7b77b3e9e5e8',8192),
 ('a341d7ded6f7ad51fc9e5d17d4fea102947b87abf4c854658527be825a726ac0',64952),
]
source=os.environ['TRANSPORT_SHA'].strip().lower()
assert len(source)==40 and all(c in '0123456789abcdef' for c in source)
p=Path('manifest.json')
m=json.loads(p.read_text(encoding='utf-8-sig'))
if m['latest_version']=='0.6.18':
    assert m['source_commit']==source or os.environ.get('ALLOW_EXISTING_SOURCE')=='1'
    print('MANIFEST_ALREADY_V0618',m['source_commit'])
    raise SystemExit(0)
assert m['latest_version']=='0.6.17',m['latest_version']
assert m['bootstrap']['version']=='1.0.6'
assert next(x for x in m['latest_files'] if x['path']=='bin/spotify-control.ps1')['sha256']==MAIN_FROM
assert not any(x['from_version']=='0.6.17' for x in m['updates'])
chunks=[{'path':f'packages/v0.6.18/main-v0617-to-v0618/chunk-{i:03d}.txt','sha256':h,'size':n} for i,(h,n) in enumerate(CHUNK_META)]
edge={'from_version':'0.6.17','to_version':'0.6.18','patches':[{
    'path':'bin/spotify-control.ps1','from_sha256':MAIN_FROM,'to_sha256':MAIN_TO,
    'encoding':'gzip-base64-full-file','encoded_sha256':ENC_SHA,'encoded_size':ENC_SIZE,
    'compressed_sha256':COMP_SHA,'compressed_size':COMP_SIZE,'target_size':MAIN_SIZE,'chunks':chunks
}]}
m['latest_version']='0.6.18';m['source_commit']=source;m['payload_set_sha256']=PAYLOAD_SET
for f in m['latest_files']:
    if f['path']=='bin/spotify-control.ps1': f['sha256']=MAIN_TO;f['size']=MAIN_SIZE
assert next(x for x in m['latest_files'] if x['path']=='bin/addon-manager.ps1')['sha256']==ADDON_SHA
assert next(x for x in m['latest_files'] if x['path']=='bin/spotify-control-agent.vbs')['sha256']==AGENT_SHA
m['updates'].append(edge)
p.write_text(json.dumps(m,separators=(',',':')),encoding='utf-8',newline='\n')
print('MANIFEST_V0618_PREPARED',source,PAYLOAD_SET)
