from pathlib import Path
import argparse,base64,gzip,hashlib,importlib.util,sys

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
RAW_SHA='2cf31fb02c337b3c52197d744432bc77a7b5393419c095046a64213cdf593004'
PATCHED_RAW_SIZE=36710
PATCHED_RAW_SHA='807ae0d78777304d0242f8c436d3bc14ec26f48d2e215510a5be3714e43b9a6b'
BROKEN_RECOVERY="if($BackupReady -and ((Get-TreeFingerprint $Bin)-cne $BaselineBinFingerprint){"
FIXED_RECOVERY="if($BackupReady -and ((Get-TreeFingerprint $Bin)-cne $BaselineBinFingerprint)){"

def sha(b):return hashlib.sha256(b).hexdigest()

def load_builder():
    spec=importlib.util.spec_from_file_location('v0621_acceptance_builder',BUILDER)
    if spec is None or spec.loader is None: raise RuntimeError('Unable to load acceptance builder module.')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    original=mod.validator_text
    def repaired_validator_text():
        text=original()
        broken="write_text(json.dumps(o,indent=2)+'\n');"
        correct="write_text(json.dumps(o,indent=2)+'\\n');"
        if broken in text:
            if text.count(broken)!=1: raise RuntimeError('Generated-validator newline repair target is ambiguous.')
            text=text.replace(broken,correct,1)
        elif correct not in text:
            raise RuntimeError('Generated-validator newline contract changed unexpectedly.')
        compile(text,'<generated-acceptance-validator>','exec')
        return text
    mod.validator_text=repaired_validator_text
    return mod

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
    text=raw.decode('utf-8-sig')
    if text.count(BROKEN_RECOVERY)!=1: raise RuntimeError('Runtime recovery syntax repair target is missing or ambiguous.')
    text=text.replace(BROKEN_RECOVERY,FIXED_RECOVERY,1)
    patched=text.encode('utf-8-sig')
    assert len(patched)==PATCHED_RAW_SIZE,(len(patched),PATCHED_RAW_SIZE)
    assert sha(patched)==PATCHED_RAW_SHA,(sha(patched),PATCHED_RAW_SHA)
    patched_encoded=base64.b64encode(gzip.compress(patched,compresslevel=9,mtime=0))
    template=a.out_dir/'_assembled-runtime-template.gz.b64'
    template.write_bytes(patched_encoded)
    builder=load_builder()
    builder.build(a.stage14_artifact,a.bootstrap_artifact,a.release_manifest,template,a.out_dir)
    print('V0621_RUNTIME_TEMPLATE_ASSEMBLY_PASS',len(encoded),sha(encoded),len(raw),sha(raw),len(patched),sha(patched))

if __name__=='__main__':main()
