from pathlib import Path
import argparse,base64,gzip,hashlib,subprocess,sys

HERE=Path(__file__).resolve().parent
BUILDER=HERE/'build_acceptance.py'
CHUNKS=[
    ('runtime-template.part-000.b64',3400,'4b8fe7e9d1e467288eef7e524b95d3124925420211e156e07bc3883a06850232'),
    ('runtime-template.part-001.b64',3400,'b4b5ec637de85ca821a1942a219e2d6cfc95ac84db7db3aea4d1302e9b42f1e6'),
    ('runtime-template.part-002.b64',3400,'6b5c3031dab4dd07fe18990105a94468ae3e29e3504a42bcccf34a751780670e'),
    ('runtime-template.part-003.b64',3344,'fa3a086647c8ddc0e27cf4cbd364b806962ea980d83dd59d05d3de5c80f72dc4'),
]
ENCODED_SIZE=13544
ENCODED_SHA='51bba07c6e67bdc93c884391ed4b993e4af0cac85ebea3b2886a9c79c967076c'
RAW_SIZE=36709
RAW_SHA='2cf31add068df056d02f80261881ec683807be2027a10bd8f784109fa9c4bc72'

def sha(b):return hashlib.sha256(b).hexdigest()

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--stage14-artifact',type=Path,required=True)
    p.add_argument('--bootstrap-artifact',type=Path,required=True)
    p.add_argument('--release-manifest',type=Path,required=True)
    p.add_argument('--out-dir',type=Path,required=True)
    a=p.parse_args();a.out_dir.mkdir(parents=True,exist_ok=True)
    parts=[]
    for name,size,digest in CHUNKS:
        b=(HERE/name).read_bytes()
        assert len(b)==size,(name,len(b),size)
        assert sha(b)==digest,(name,sha(b),digest)
        parts.append(b)
    encoded=b''.join(parts)
    assert len(encoded)==ENCODED_SIZE,(len(encoded),ENCODED_SIZE)
    assert sha(encoded)==ENCODED_SHA,(sha(encoded),ENCODED_SHA)
    raw=gzip.decompress(base64.b64decode(encoded,validate=True))
    assert len(raw)==RAW_SIZE,(len(raw),RAW_SIZE)
    assert sha(raw)==RAW_SHA,(sha(raw),RAW_SHA)
    template=a.out_dir/'_assembled-runtime-template.gz.b64'
    template.write_bytes(encoded)
    cmd=[sys.executable,str(BUILDER),'--stage14-artifact',str(a.stage14_artifact),'--bootstrap-artifact',str(a.bootstrap_artifact),'--release-manifest',str(a.release_manifest),'--runtime-template',str(template),'--out-dir',str(a.out_dir)]
    subprocess.check_call(cmd)
    print('V0621_RUNTIME_TEMPLATE_ASSEMBLY_PASS',len(encoded),sha(encoded),len(raw),sha(raw))

if __name__=='__main__':main()
