from pathlib import Path
from io import BytesIO
from collections import Counter
import base64, gzip, hashlib, json, shutil, subprocess, sys, zipfile

BASE_MAIN = "966b0105b6a2560c24907ea08fe100ad8e2277be"
OLD_MAIN_SHA = "4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f"
OLD_ADDON_SHA = "56185d3b23c4b0df455673ad3f601d67c7980b7428f1d15b3e0465d1a7859022"
MAIN16_SHA = "6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad"
R6_SHA = "fb2bd974ee795bb697a0e5b534e03477be77b655e60353d82064b1e751bdc686"
PAYLOAD16_SHA = "fbeffb5f594c3feeb621f50e391246bb035dd0fffce5300a575aa74883a7acfb"
R6_PATCH_ENC_SHA = "36b20a04c3bd425472dd1a616a042edcda81cbd0c20824803acc6c619536371c"
R6_PATCH_RAW_SHA = "372cf3d2b19e797cb63b3d6b65c38114f77be12b9a92474c9899692ac2729235"
AGENT_SHA = "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278"
BOOTSTRAP_SHA = "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6"

def sha(b): return hashlib.sha256(b).hexdigest()
def git_bytes(ref, path): return subprocess.check_output(["git","show",f"{ref}:{path}"])
def load_manifest(ref=None):
    raw = Path("manifest.json").read_bytes() if ref is None else git_bytes(ref,"manifest.json")
    return json.loads(raw.decode("utf-8-sig"))

def reconstruct_payload(manifest, edge_from, edge_to, path):
    edge=next(e for e in manifest["updates"] if e["from_version"]==edge_from and e["to_version"]==edge_to)
    p=next(x for x in edge["patches"] if x["path"]==path)
    source=manifest["source_commit"]
    parts=[]
    for i,c in enumerate(p["chunks"]):
        q=c["path"].replace("\\","/")
        assert q.endswith(f"/chunk-{i:03}.txt"), q
        data=git_bytes(source,q)
        assert len(data)==int(c["size"]) and sha(data)==c["sha256"], q
        parts.append(data)
    enc=b"".join(parts)
    assert len(enc)==int(p["encoded_size"]) and sha(enc)==p["encoded_sha256"]
    comp=base64.b64decode(enc,validate=True)
    assert len(comp)==int(p["compressed_size"]) and sha(comp)==p["compressed_sha256"]
    return p,gzip.decompress(comp)

def reconstruct_main_0615(manifest):
    enc=b"".join(Path(f"packages/v0.6.11/chunks/chunk-{i:03}.txt").read_bytes() for i in range(8))
    with zipfile.ZipFile(BytesIO(base64.b64decode(b"".join(enc.split()),validate=True))) as z:
        cur=z.read("bin/spotify-control.ps1")
    assert sha(cur)=="045ed3fa898453ce6563a057a31412d254f5958b75286589e8d5cc95c6782a39"
    ver="0.6.11"
    for to in ("0.6.13","0.6.14","0.6.15"):
        edge=next(e for e in manifest["updates"] if e["from_version"]==ver and e["to_version"]==to)
        p=next(x for x in edge["patches"] if x["path"]=="bin/spotify-control.ps1")
        parts=[]
        for c in p["chunks"]:
            data=Path(c["path"]).read_bytes()
            assert len(data)==int(c["size"]) and sha(data)==c["sha256"]
            parts.append(data)
        encoded=b"".join(parts)
        assert len(encoded)==int(p["encoded_size"]) and sha(encoded)==p["encoded_sha256"]
        comp=base64.b64decode(encoded,validate=True)
        assert len(comp)==int(p["compressed_size"]) and sha(comp)==p["compressed_sha256"]
        raw=gzip.decompress(comp); assert sha(raw)==p["json_sha256"]
        doc=json.loads(raw.decode("ascii"))
        assert sha(cur)==p["from_sha256"]
        lines=cur.decode("utf-8-sig").splitlines(keepends=True)
        for op in sorted(doc["operations"],key=lambda x:int(x["start_line"]),reverse=True):
            start=int(op["start_line"]); delete=int(op["delete_count"])
            lines[start:start+delete]=str(op.get("insert","")).splitlines(keepends=True)
        cur=b"\xef\xbb\xbf"+"".join(lines).encode("utf-8")
        assert sha(cur)==p["to_sha256"]
        ver=to
    assert len(cur)==266313 and sha(cur)==OLD_MAIN_SHA
    return cur

def derive_r6(manifest):
    _,r5=reconstruct_payload(manifest,"0.6.14","0.6.15","bin/addon-manager.ps1")
    assert len(r5)==128714 and sha(r5)==OLD_ADDON_SHA
    enc=Path("validation/v0.6.16/r5-to-r6.patch.json.gz.b64").read_bytes()
    assert len(enc)==8768 and sha(enc)==R6_PATCH_ENC_SHA
    raw=gzip.decompress(base64.b64decode(enc,validate=True))
    assert len(raw)==26823 and sha(raw)==R6_PATCH_RAW_SHA
    doc=json.loads(raw); assert doc["from_sha256"]==OLD_ADDON_SHA and doc["to_sha256"]==R6_SHA
    lines=r5.decode("utf-8-sig").splitlines(keepends=True)
    for op in sorted(doc["operations"],key=lambda x:int(x["start_line"]),reverse=True):
        s=int(op["start_line"]); d=int(op["delete_count"])
        lines[s:s+d]=str(op.get("insert","")).splitlines(keepends=True)
    r6=b"\xef\xbb\xbf"+"".join(lines).encode("utf-8")
    assert len(r6)==152481 and sha(r6)==R6_SHA
    return r5,r6

def derive_main16(main):
    doc={"kind":"ascii-line-patch","from_version":"0.6.15","to_version":"0.6.16",
         "from_sha256":OLD_MAIN_SHA,"to_sha256":"",
         "operations":[
           {"start_line":0,"delete_count":1,"insert":"# Spotify Control v0.6.16 ivLyrics Historical-Tag Trust Bootstrap\n"},
           {"start_line":12,"delete_count":1,"insert":"$ScriptVersion = \"0.6.16\"\n"}]}
    lines=main.decode("utf-8-sig").splitlines(keepends=True)
    for op in sorted(doc["operations"],key=lambda x:int(x["start_line"]),reverse=True):
        s=int(op["start_line"]); d=int(op["delete_count"])
        lines[s:s+d]=op["insert"].splitlines(keepends=True)
    out=b"\xef\xbb\xbf"+"".join(lines).encode("utf-8")
    doc["to_sha256"]=sha(out)
    assert len(out)==266321 and sha(out)==MAIN16_SHA
    return doc,out

def write_chunks(root,data):
    root.mkdir(parents=True,exist_ok=True); rows=[]
    for off in range(0,len(data),4096):
        part=data[off:off+4096]; name=f"chunk-{off//4096:03}.txt"; (root/name).write_bytes(part)
        rows.append({"path":str((root/name)).replace("\\","/"),"sha256":sha(part),"size":len(part)})
    return rows

def build_prepare(manifest):
    base=load_manifest(BASE_MAIN)
    assert manifest["latest_version"]=="0.6.15"
    assert manifest["updates"]==base["updates"]
    main=reconstruct_main_0615(manifest); r5,r6=derive_r6(manifest); doc,main16=derive_main16(main)
    out=Path("publication-v0.6.16"); shutil.rmtree(out,ignore_errors=True); out.mkdir()
    (out/"candidate-main-v0.6.16.ps1").write_bytes(main16)
    (out/"candidate-addon-v0.6.5-r6.ps1").write_bytes(r6)
    pkg=out/"packages/v0.6.16"
    main_json=json.dumps(doc,separators=(",",":"),ensure_ascii=True).encode("ascii")
    main_gz=gzip.compress(main_json,compresslevel=9,mtime=0); main_b64=base64.b64encode(main_gz)
    addon_gz=gzip.compress(r6,compresslevel=9,mtime=0); addon_b64=base64.b64encode(addon_gz)
    mc=write_chunks(pkg/"main-v0615-to-v0616",main_b64)
    ac=write_chunks(pkg/"addon-v065r5-to-v065r6",addon_b64)
    for row in mc+ac: row["path"]=row["path"].removeprefix("publication-v0.6.16/")
    mp={"path":"bin/spotify-control.ps1","from_sha256":OLD_MAIN_SHA,"to_sha256":MAIN16_SHA,
        "encoding":"gzip-base64-chunks","encoded_sha256":sha(main_b64),"encoded_size":len(main_b64),
        "compressed_sha256":sha(main_gz),"compressed_size":len(main_gz),
        "json_sha256":sha(main_json),"json_size":len(main_json),"chunks":mc}
    ap={"path":"bin/addon-manager.ps1","from_sha256":OLD_ADDON_SHA,"to_sha256":R6_SHA,
        "encoding":"gzip-base64-full-file","encoded_sha256":sha(addon_b64),"encoded_size":len(addon_b64),
        "compressed_sha256":sha(addon_gz),"compressed_size":len(addon_gz),"target_size":len(r6),"chunks":ac}
    latest=[{"path":"bin/spotify-control.ps1","sha256":MAIN16_SHA,"size":len(main16)},
            {"path":"bin/addon-manager.ps1","sha256":R6_SHA,"size":len(r6)},
            {"path":"bin/spotify-control-agent.vbs","sha256":AGENT_SHA,"size":4855}]
    rows=[f"{x['path']}|{x['size']}|{x['sha256']}" for x in latest]
    assert sha(("\n".join(sorted(rows))+"\n").encode())==PAYLOAD16_SHA
    nxt=json.loads(json.dumps(manifest)); nxt["latest_version"]="0.6.16"; nxt["source_commit"]="__SOURCE_COMMIT__"
    nxt["payload_set_sha256"]=PAYLOAD16_SHA; nxt["latest_files"]=latest
    nxt["updates"]=list(manifest["updates"])+[{"from_version":"0.6.15","to_version":"0.6.16","patches":[mp,ap]}]
    (out/"manifest-template.json").write_text(json.dumps(nxt,separators=(",",":")),encoding="utf-8",newline="\n")
    print("PREPARE_OK",MAIN16_SHA,R6_SHA,PAYLOAD16_SHA)

def final_validate(manifest):
    assert manifest["latest_version"]=="0.6.16"
    assert manifest["payload_set_sha256"]==PAYLOAD16_SHA
    assert manifest["bootstrap"]["sha256"]==BOOTSTRAP_SHA and manifest["bootstrap"]["size"]==42963
    base=load_manifest(BASE_MAIN)
    assert manifest["updates"][:-1]==base["updates"]
    edge=manifest["updates"][-1]; assert edge["from_version"]=="0.6.15" and edge["to_version"]=="0.6.16"
    froms=[e["from_version"] for e in manifest["updates"]]; assert len(froms)==len(set(froms))
    source=manifest["source_commit"]; subprocess.check_call(["git","merge-base","--is-ancestor",source,"HEAD"])
    patches={p["path"]:p for p in edge["patches"]}
    assert set(patches)=={"bin/spotify-control.ps1","bin/addon-manager.ps1"}
    main=reconstruct_main_0615(base)
    out=Path("publication-v0.6.16"); shutil.rmtree(out,ignore_errors=True); out.mkdir()
    for path,target,size in [("bin/spotify-control.ps1",MAIN16_SHA,266321),("bin/addon-manager.ps1",R6_SHA,152481)]:
        p=patches[path]; parts=[]
        for i,c in enumerate(p["chunks"]):
            q=c["path"].replace("\\","/"); assert q.endswith(f"/chunk-{i:03}.txt")
            data=git_bytes(source,q); assert len(data)==int(c["size"]) and sha(data)==c["sha256"]; parts.append(data)
        enc=b"".join(parts); assert len(enc)==int(p["encoded_size"]) and sha(enc)==p["encoded_sha256"]
        comp=base64.b64decode(enc,validate=True); assert len(comp)==int(p["compressed_size"]) and sha(comp)==p["compressed_sha256"]
        raw=gzip.decompress(comp)
        if path.endswith("spotify-control.ps1"):
            assert sha(raw)==p["json_sha256"]; doc=json.loads(raw.decode("ascii"))
            lines=main.decode("utf-8-sig").splitlines(keepends=True)
            for op in sorted(doc["operations"],key=lambda x:int(x["start_line"]),reverse=True):
                s=int(op["start_line"]); d=int(op["delete_count"]); lines[s:s+d]=str(op["insert"]).splitlines(keepends=True)
            payload=b"\xef\xbb\xbf"+"".join(lines).encode("utf-8")
        else: payload=raw
        assert len(payload)==size and sha(payload)==target and p["to_sha256"]==target
        (out/("candidate-main-v0.6.16.ps1" if path.endswith("spotify-control.ps1") else "candidate-addon-v0.6.5-r6.ps1")).write_bytes(payload)
    latest={x["path"]:(int(x["size"]),x["sha256"]) for x in manifest["latest_files"]}
    assert latest=={"bin/spotify-control.ps1":(266321,MAIN16_SHA),"bin/addon-manager.ps1":(152481,R6_SHA),"bin/spotify-control-agent.vbs":(4855,AGENT_SHA)}
    rows=[f"{p}|{s}|{h}" for p,(s,h) in latest.items()]; assert sha(("\n".join(sorted(rows))+"\n").encode())==PAYLOAD16_SHA
    print("FINAL_VALIDATE_OK",source,MAIN16_SHA,R6_SHA,PAYLOAD16_SHA)

m=load_manifest()
if m["latest_version"]=="0.6.15":
    build_prepare(m)
elif m["latest_version"]=="0.6.16":
    final_validate(m)
else:
    raise SystemExit(f"Unexpected stable latest_version {m['latest_version']}")
