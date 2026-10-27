from __future__ import annotations
import argparse, json, shutil, struct
from pathlib import Path

MAGIC=0xDB4775248B80FB57
DB_NAME='spicetify-marketplace'; STORE_NAME='settings'; ORIGIN='https://xpui.app'; DB_ID=7; STORE_ID=3
MIGRATION='internal:local-storage-migrated'
LIST_EXT='marketplace:installed-extensions'; LIST_THEME='marketplace:installed-themes'; LIST_SNIP='marketplace:installed-snippets'
EXT='marketplace:installed:alice/ext-repo/dist/ext.js'
THEME='marketplace:installed:bob/theme-repo/user.css'
SNIP='marketplace:installed:snippet:My-Snippet'
ORPHAN='marketplace:installed:carol/orphan-repo/orphan.js'

def varint(v:int)->bytes:
 out=bytearray()
 while v>=0x80: out.append((v&0x7f)|0x80); v>>=7
 out.append(v); return bytes(out)
def fixed32(v:int)->bytes:return struct.pack('<I',v)
def fixed64(v:int)->bytes:return struct.pack('<Q',v)
def prefix(db:int,store:int,index:int)->bytes:
 def enc(v,m):
  w=max(1,(v.bit_length()+7)//8)
  if w>m: raise ValueError('id too wide')
  return w,v.to_bytes(w,'little')
 dw,d=enc(db,8);sw,s=enc(store,8);iw,i=enc(index,4)
 return bytes([((dw-1)<<5)|((sw-1)<<2)|(iw-1)])+d+s+i
def s16(text:str)->bytes:
 b=text.encode('utf-16-be');return varint(len(b)//2)+b
def dbkey()->bytes:return prefix(0,0,0)+bytes([201])+s16(ORIGIN)+s16(DB_NAME)
def storekey()->bytes:return prefix(DB_ID,0,0)+bytes([50])+varint(STORE_ID)+b'\x00'
def datakey(primary:str)->bytes:return prefix(DB_ID,STORE_ID,1)+b'\x01'+s16(primary)
def value(payload:bytes)->bytes:return varint(1)+payload
def ikey(user:bytes,seq:int,typ:int=1)->bytes:return user+fixed64((seq<<8)|typ)
def block(entries:list[tuple[bytes,bytes]])->bytes:
 body=bytearray();restarts=[]
 for k,v in entries:
  restarts.append(len(body));body+=varint(0)+varint(len(k))+varint(len(v))+k+v
 if not entries:restarts=[0]
 for x in restarts:body+=fixed32(x)
 body+=fixed32(len(restarts));return bytes(body)
def snappy_literal(raw:bytes)->bytes:
 out=bytearray(varint(len(raw)));n=len(raw)-1
 if len(raw)<=60:out.append(n<<2)
 else:
  w=max(1,(n.bit_length()+7)//8);out.append((59+w)<<2);out+=n.to_bytes(w,'little')
 out+=raw;return bytes(out)
def append_block(buf:bytearray,raw:bytes,compression:int):
 off=len(buf);stored=raw if compression==0 else snappy_literal(raw);buf+=stored+bytes([compression])+b'\0\0\0\0';return off,len(stored)
def handle(off:int,size:int)->bytes:return varint(off)+varint(size)
def table(path:Path,records:list[tuple[bytes,bytes,int,int]],snappy=False):
 path.parent.mkdir(parents=True,exist_ok=True)
 entries=sorted((ikey(k,seq,typ),v if typ==1 else b'') for k,v,seq,typ in records)
 buf=bytearray();do,ds=append_block(buf,block(entries),1 if snappy else 0);mo,ms=append_block(buf,block([]),0)
 sep=entries[-1][0] if entries else b'\0';io,is_=append_block(buf,block([(sep,handle(do,ds))]),0)
 hs=handle(mo,ms)+handle(io,is_);buf+=hs+b'\0'*(40-len(hs))+fixed64(MAGIC);path.write_bytes(buf)
def batch(seq:int,ops:list[tuple[str,bytes,bytes|None]])->bytes:
 out=bytearray(fixed64(seq)+fixed32(len(ops)))
 for kind,k,v in ops:
  if kind=='put':out.append(1);out+=varint(len(k))+k+varint(len(v or b''))+(v or b'')
  else:out.append(0);out+=varint(len(k))+k
 return bytes(out)
def log(path:Path,b:bytes):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'\0\0\0\0'+struct.pack('<H',len(b))+b'\x01'+b)
def idb(local:Path,profile='Browser')->Path:return local/'Spotify'/profile/'IndexedDB'/'https_xpui.app_0.indexeddb.leveldb'
def ls(local:Path,profile='Browser')->Path:return local/'Spotify'/profile/'Local Storage'/'leveldb'
def base_records(include_orphan=False):
 rows=[(dbkey(),fixed64(DB_ID),100,1),(storekey(),STORE_NAME.encode('utf-16-be'),101,1),(datakey(MIGRATION),value(b'1'),102,1),
       (datakey(LIST_EXT),value(json.dumps([EXT]).encode()),103,1),(datakey(LIST_THEME),value(json.dumps([THEME]).encode()),104,1),(datakey(LIST_SNIP),value(json.dumps([SNIP]).encode()),105,1),
       (datakey(EXT),value(b'{"type":"extension","user":"alice","repo":"ext-repo"}'),106,1),(datakey(THEME),value(b'{"type":"theme","user":"bob","repo":"theme-repo"}'),107,1),(datakey(SNIP),value(b'{"type":"snippet"}'),108,1)]
 if include_orphan:rows.append((datakey(ORPHAN),value(b'{"type":"extension","user":"carol","repo":"orphan-repo"}'),109,1))
 return rows
def legacy_records():
 pairs={LIST_EXT:json.dumps([EXT]),LIST_THEME:json.dumps([THEME]),LIST_SNIP:json.dumps([SNIP]),EXT:'{"type":"extension"}',THEME:'{"type":"theme"}',SNIP:'{"type":"snippet"}'}
 return [(b'ls:'+k.encode(),v.encode(),100+i,1) for i,(k,v) in enumerate(pairs.items())]
def build(root:Path,kind:str):
 local=root/'localappdata';local.mkdir(parents=True,exist_ok=True)
 if kind=='indexeddb': table(idb(local)/'000001.ldb',base_records(),snappy=True)
 elif kind=='orphan': table(idb(local)/'000001.ldb',base_records(True))
 elif kind=='wal-tombstone':
  d=idb(local);table(d/'000001.ldb',base_records());log(d/'000002.log',batch(300,[('delete',datakey(THEME),None)]))
 elif kind=='corrupt':
  d=idb(local);table(d/'000001.ldb',base_records());(d/'000099.ldb').write_bytes(b'deliberately-corrupt')
 elif kind=='localstorage':table(ls(local)/'000001.ldb',legacy_records(),snappy=True)
 elif kind=='dual-profiles':
  table(idb(local,'Browser')/'000001.ldb',base_records());table(idb(local,'Default')/'000001.ldb',base_records())
 else:raise ValueError(kind)
def main():
 p=argparse.ArgumentParser();p.add_argument('--out',required=True,type=Path);a=p.parse_args()
 if a.out.exists():shutil.rmtree(a.out)
 a.out.mkdir(parents=True)
 kinds=['indexeddb','orphan','wal-tombstone','corrupt','localstorage','dual-profiles']
 for k in kinds:build(a.out/k,k)
 expected={
  'indexeddb':{'status':'ok','count':3,'kinds':['extension','snippet','theme']},
  'orphan':{'status':'ok','count':4,'has_unlisted':True},
  'wal-tombstone':{'status':'ok','count':2,'keys':[EXT,SNIP]},
  'corrupt':{'status':'inconclusive'},
  'localstorage':{'status':'ok','count':3},
  'dual-profiles':{'status':'ok','count':3,'profiles_each':2},
 }
 (a.out/'expected.json').write_text(json.dumps(expected,indent=2,sort_keys=True)+'\n',encoding='utf-8')
 print('MARKETPLACE_RECORD_FIXTURES_BUILT',a.out)
if __name__=='__main__':main()
