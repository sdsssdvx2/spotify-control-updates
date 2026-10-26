from pathlib import Path
import argparse,base64,gzip,hashlib,io,json,re,shutil,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
BASE_VERSION='0.6.20'
NEW_VERSION='0.6.21'
BASE_MAIN_SHA='e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'
BASE_MAIN_SIZE=281585
BASE_ADDON_SHA='3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'
BASE_ADDON_SIZE=225044
EXPECTED_R10_SHA='7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
EXPECTED_R10_SIZE=250616
POLICY_SHA='1e982cad2c043d8715871c6cc8ecf0244b7e4592e4764257f240d20205224e06'
POLICY_SIZE=12842
GUARD_SHA='8c598f96c4b4a4c6409c531657cc4949c92ae9d362785e6186f5334043505407'
GUARD_SIZE=10408
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE=4855
BOOTSTRAP={'version':'1.0.6','sha256':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6','size':42963}
BASE_OUT=ROOT/'validation/v0.6.20/out/bin'
OUT=ROOT/'validation/v0.6.21/out/bin'
META=ROOT/'validation/v0.6.21/candidate-metadata.json'
POLICY=ROOT/'validation/v0.6.21/addon_policy_registry.ps1.inc'
GUARD=ROOT/'validation/v0.6.21/addon_transaction_registry_guard.ps1.inc'
MAIN_CHUNK_DIR=ROOT/'packages/v0.6.21/main-v0620-to-v0621'
ADDON_CHUNK_DIR=ROOT/'packages/v0.6.21/addon-v065r9-to-v065r10'
VALIDATION_HEAD='248dcd5315cd98cb798b0b711d21f50355c65d1d'
VALIDATION_PUSH_RUN='40283288327'
VALIDATION_PR_RUN='40283546439'


def sha(b): return hashlib.sha256(b).hexdigest()
def deterministic_gzip(data):
    buf=io.BytesIO()
    with gzip.GzipFile(filename='',mode='wb',fileobj=buf,compresslevel=9,mtime=0) as g:g.write(data)
    return buf.getvalue()
def clean_dir(path):
    if path.exists(): shutil.rmtree(path)
    path.mkdir(parents=True,exist_ok=True)
def write_chunks(encoded,folder,size):
    clean_dir(folder); rows=[]
    for i in range(0,len(encoded),size):
        b=encoded[i:i+size]; p=folder/f'chunk-{i//size:03d}.txt'; p.write_bytes(b)
        rows.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(b),'size':len(b)})
    assert rows
    return rows
def concat_chunks(patch,reader=lambda p:(ROOT/p).read_bytes()):
    parts=[]
    for c in patch['chunks']:
        b=reader(c['path']); assert len(b)==c['size'] and sha(b)==c['sha256'],c['path']; parts.append(b)
    encoded=b''.join(parts); assert len(encoded)==patch['encoded_size'] and sha(encoded)==patch['encoded_sha256']
    return encoded
def canonical_payload(latest):
    rows=[f"{x['path']}|{int(x['size'])}|{x['sha256']}" for x in sorted(latest,key=lambda x:x['path'])]
    return sha(('\n'.join(rows)+'\n').encode('ascii'))
def apply_ascii_line_patch(raw,doc):
    assert doc['schema']==1 and doc['kind']=='ascii-line-patch'
    bom=b'\xef\xbb\xbf' if doc.get('bom')=='utf8-bom' else b''
    if bom: assert raw.startswith(bom); body=raw[len(bom):]
    else: body=raw
    assert b'\r\n' not in body
    lines=body.decode('ascii').splitlines(keepends=True)
    for op in sorted(doc['operations'],key=lambda x:int(x['start_line']),reverse=True):
        start=int(op['start_line']); delete=int(op['delete_count']); insert=str(op.get('insert',''))
        lines[start:start+delete]=insert.splitlines(keepends=True)
    return bom+''.join(lines).encode('ascii')
def replace_once(text,old,new,label):
    n=text.count(old)
    if n!=1: raise RuntimeError(f'{label}: expected exactly one match, got {n}')
    return text.replace(old,new,1)
def function_block(text,name):
    marker=f'function {name} {{'; start=text.find(marker)
    if start<0: raise RuntimeError(f'missing function {name}')
    nxt=text.find('\nfunction ',start+len(marker))
    if nxt<0:nxt=len(text)
    return text[start:nxt]

def prepare_base():
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.20/build_v0620.py'),'--build'],cwd=ROOT)
    main=(BASE_OUT/'spotify-control.ps1').read_bytes(); addon=(BASE_OUT/'addon-manager.ps1').read_bytes()
    assert (len(main),sha(main))==(BASE_MAIN_SIZE,BASE_MAIN_SHA),(len(main),sha(main))
    assert (len(addon),sha(addon))==(BASE_ADDON_SIZE,BASE_ADDON_SHA),(len(addon),sha(addon))
    assert (POLICY.stat().st_size,sha(POLICY.read_bytes()))==(POLICY_SIZE,POLICY_SHA)
    assert (GUARD.stat().st_size,sha(GUARD.read_bytes()))==(GUARD_SIZE,GUARD_SHA)
    return main,addon

def build_main(base):
    assert base.startswith(b'\xef\xbb\xbf'); body=base[3:]; assert b'\r\n' not in body
    lines=body.decode('ascii').splitlines(keepends=True)
    assert lines[0]=='# Spotify Control v0.6.20 Star Ratings Performance\n'
    assert lines[12]=='$ScriptVersion = "0.6.20"\n'
    new=list(lines)
    new[0]='# Spotify Control v0.6.21 Addon Registry r10\n'
    new[12]='$ScriptVersion = "0.6.21"\n'
    candidate=b'\xef\xbb\xbf'+''.join(new).encode('ascii')
    doc={'schema':1,'kind':'ascii-line-patch','from_version':BASE_VERSION,'to_version':NEW_VERSION,'from_sha256':sha(base),'to_sha256':sha(candidate),'bom':'utf8-bom','line_ending':'lf','operations':[{'start_line':0,'delete_count':1,'insert':new[0]},{'start_line':12,'delete_count':1,'insert':new[12]}]}
    assert apply_ascii_line_patch(base,doc)==candidate
    assert [i for i,(a,b) in enumerate(zip(lines,new)) if a!=b]==[0,12]
    return candidate,doc

def build_addon(base):
    bom=b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text=base[len(bom):].decode('utf-8')
    crlf=text.count('\r\n'); lf=text.count('\n'); newline='\r\n' if crlf and crlf==lf else '\n'
    if newline=='\n': assert '\r\n' not in text
    text=replace_once(text,'$Version = "0.6.5-r9"','$Version = "0.6.5-r10"','version bump')

    policy=POLICY.read_text(encoding='utf-8').replace('\r\n','\n').rstrip('\n').replace('\n',newline)
    guard=GUARD.read_text(encoding='utf-8').replace('\r\n','\n').rstrip('\n').replace('\n',newline)
    text=replace_once(text,'function Get-AddonInventory {',policy+newline+newline+'function Get-AddonInventory {','policy registry insertion')

    inventory=function_block(text,'Get-AddonInventory')
    inventory=replace_once(inventory,'foreach ($name in @("better-local-files","eternal-jukebox","playlist-maker")) {','$pithayaPolicyEntries = @(Get-AddonPolicyRegistry | Where-Object { [string]$_.handler -ceq "pithaya" -and [string]$_.mutation_mode -ceq "auto" } | Sort-Object -Property name)'+newline+'    foreach ($policyEntry in $pithayaPolicyEntries) {'+newline+'        $name = [string]$policyEntry.name','Pithaya inventory registry derivation')
    inventory=replace_once(inventory,'    foreach ($item in $items) {'+newline+'        $stateKey = if ([string]$item.kind -eq \'extension\') { \'extension:\' + [string]$item.name } else { [string]$item.name }','    $registrySummary = Add-AddonPolicyRegistryMetadata -Items $items.ToArray()'+newline+'    [void](Write-AddonPolicyRegistryReport)'+newline+newline+'    foreach ($item in $items) {'+newline+'        $stateKey = if ([string]$item.kind -eq \'extension\') { \'extension:\' + [string]$item.name } else { [string]$item.name }','inventory registry metadata')
    inventory=replace_once(inventory,'        asset_resolution = $assetResolution'+newline+'        items = $items.ToArray()','        asset_resolution = $assetResolution'+newline+'        policy_registry = $registrySummary'+newline+'        items = $items.ToArray()','inventory registry summary')
    text=replace_once(text,function_block(text,'Get-AddonInventory'),inventory,'replace inventory')

    update=function_block(text,'Update-AutoApps')
    old='''    foreach ($item in @($report.items)) {\n        if ($item.policy -ne "auto" -or $item.installed -ne $true) { continue }\n        if ($item.source -eq "Pithaya/spicetify-apps-dist") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","trusted-known-baseline")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -eq "exact-current") { $candidates.Add($item); continue }\n        } elseif ($item.source -eq "ivLis-Studio/ivLyrics") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n        }\n        if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n    }'''.replace('\n',newline)
    new='''    foreach ($item in @($report.items)) {\n        $authorization = Get-AddonMutationAuthorization -Item $item\n        if (-not $authorization.Allowed) {\n            if ([string]$item.policy -ceq "auto" -and $item.installed -eq $true) { Write-AddonLog "Registry denied automatic mutation for $($item.name): $($authorization.Reason)." "WARN" }\n            if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n            continue\n        }\n        if ([string]$authorization.Handler -ceq "pithaya") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","trusted-known-baseline")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -eq "exact-current") { $candidates.Add($item); continue }\n        } elseif ([string]$authorization.Handler -ceq "ivlyrics") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n        } else { throw "Registry authorized unsupported mutation handler '$($authorization.Handler)' for $($item.name)." }\n        if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n    }'''.replace('\n',newline)
    update=replace_once(update,old,new,'candidate authorization gate')
    update=replace_once(update,'            $before=Get-DirectoryGitSnapshot ([string]$item.install_path)'+newline+'            $state=Load-AddonState; $as=Ensure-AppState $state $item.name'+newline+'            if ([string]$item.source -eq "Pithaya/spicetify-apps-dist") {','            $authorization = Get-AddonMutationAuthorization -Item $item'+newline+'            if (-not $authorization.Allowed) { throw "Registry authorization changed before staging for $($item.name): $($authorization.Reason)" }'+newline+'            $before=Get-DirectoryGitSnapshot ([string]$item.install_path)'+newline+'            $state=Load-AddonState; $as=Ensure-AppState $state $item.name'+newline+'            if ([string]$authorization.Handler -ceq "pithaya") {','phase1 Pithaya handler gate')
    update=replace_once(update,'            if ([string]$item.source -eq "ivLis-Studio/ivLyrics") {','            if ([string]$authorization.Handler -ceq "ivlyrics") {','phase1 ivLyrics handler gate')
    update=replace_once(update,'            throw "Unsupported auto-managed CustomApp source: $($item.source)"','            throw "Unsupported registry mutation handler for $($item.name): $($authorization.Handler)"','phase1 unsupported handler')
    old='''            $changes.Add([pscustomobject]@{\n                name=[string]$p.item.name; target=[string]$p.item.install_path; backup=$backup\n                before_fingerprint=[string]$p.before.fingerprint; before_revision=[string]$beforeState.installed_revision\n                after_revision=[string]$p.remote.revision; after_fingerprint=[string]$p.remote.fingerprint\n                remote_tree=[string]$p.remote.tree_sha; archive_sha256=[string]$p.archive_sha256; swapped=$false\n            })\n        }\n        $tx=[pscustomobject]@{ schema=2; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'''.replace('\n',newline)
    new='''            $changeAuthorization = Get-AddonMutationAuthorization -Item $p.item\n            if (-not $changeAuthorization.Allowed) { throw "Registry authorization changed before transaction ledger creation for $($p.item.name): $($changeAuthorization.Reason)" }\n            $changes.Add([pscustomobject]@{\n                name=[string]$p.item.name; target=[string]$p.item.install_path; backup=$backup\n                before_fingerprint=[string]$p.before.fingerprint; before_revision=[string]$beforeState.installed_revision\n                after_revision=[string]$p.remote.revision; after_fingerprint=[string]$p.remote.fingerprint\n                remote_tree=[string]$p.remote.tree_sha; archive_sha256=[string]$p.archive_sha256; swapped=$false\n                registry_handler=[string]$changeAuthorization.Handler; registry_source=[string]$changeAuthorization.Entry.source; registry_policy=[string]$changeAuthorization.Entry.inventory_policy\n            })\n        }\n        $registrySha=Get-AddonPolicyRegistryFingerprint\n        $tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'''.replace('\n',newline)
    update=replace_once(update,old,new,'transaction registry metadata')
    text=replace_once(text,function_block(text,'Update-AutoApps'),update,'replace Update-AutoApps')

    normalize=function_block(text,'Normalize-PithayaTransaction')
    normalize=replace_once(normalize,'    foreach ($optional in @("swapped_at","rolled_back_at","committed_at")) {'+newline+'        [void](Ensure-ObjectNoteProperty -Object $Tx -Name $optional -DefaultValue $null)'+newline+'    }','    foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256")) {'+newline+'        [void](Ensure-ObjectNoteProperty -Object $Tx -Name $optional -DefaultValue $null)'+newline+'    }','normalize registry metadata')
    text=replace_once(text,function_block(text,'Normalize-PithayaTransaction'),normalize,'replace Normalize-PithayaTransaction')

    text=replace_once(text,'function Get-AddonInventory {',guard+newline+newline+'function Get-AddonInventory {','transaction guard insertion')
    commit=function_block(text,'Commit-LastTransaction')
    commit=replace_once(commit,'    $tx = Normalize-PithayaTransaction $tx'+newline+'    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }','    $tx = Normalize-PithayaTransaction $tx'+newline+'    $registryAuthorizationMode=Assert-AddonTransactionRegistryAuthorization -Tx $tx'+newline+'    if ([string]$registryAuthorizationMode -ceq "legacy-schema2-no-registry") { Write-AddonLog "Committing legacy schema-2 addon transaction without registry fingerprint; exact-tree verification remains required." "WARN" }'+newline+'    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }','CommitLast registry authorization')
    text=replace_once(text,function_block(text,'Commit-LastTransaction'),commit,'replace CommitLast')

    selftest=function_block(text,'Invoke-AddonSelfTest')
    selftest=replace_once(selftest,'    if ($errors.Count -gt 0) {'+newline+'        foreach ($e in $errors) { Write-AddonLog $e "ERROR" }','    try {'+newline+'        Invoke-AddonPolicyRegistrySelfTest'+newline+'        Invoke-AddonTransactionRegistrySelfTest'+newline+'        Invoke-AddonRegistryCommitCycleSelfTest'+newline+'        Write-AddonLog "Addon policy registry self-test passed: deterministic fingerprint, exact current auto-authority, denied protected/unknown sources, legacy transaction compatibility, registry drift rejection, and filesystem-backed registry CommitLast."'+newline+'    } catch {'+newline+'        $errors.Add("Addon policy registry self-test failed: $($_.Exception.Message)")'+newline+'    }'+newline+newline+'    if ($errors.Count -gt 0) {'+newline+'        foreach ($e in $errors) { Write-AddonLog $e "ERROR" }','registry selftests')
    selftest=replace_once(selftest,'Write-AddonLog "Addon Manager read-only self-test passed, including multi-root, Pithaya/ivLyrics transaction, official-tag trust bootstrap drift rejection, unproven legacy monitor fallback, pending-aware schedule bypass, successful CommitLast pending-drain, and managed direct-extension ownership fixtures."','Write-AddonLog "Addon Manager read-only self-test passed, including multi-root, policy-registry authorization, Pithaya/ivLyrics transaction, official-tag trust bootstrap drift rejection, unproven legacy monitor fallback, pending-aware schedule bypass, successful CommitLast pending-drain, and managed direct-extension ownership fixtures."','selftest success message')
    text=replace_once(text,function_block(text,'Invoke-AddonSelfTest'),selftest,'replace Invoke-AddonSelfTest')

    candidate=bom+text.encode('utf-8')
    if (len(candidate),sha(candidate))!=(EXPECTED_R10_SIZE,EXPECTED_R10_SHA):
        raise RuntimeError(f'validated r10 byte identity mismatch: {len(candidate)}/{sha(candidate)}')
    update_check=function_block(candidate.decode('utf-8-sig'),'Update-AutoApps')
    assert '$item.source -eq "Pithaya/spicetify-apps-dist"' not in update_check
    assert '$item.source -eq "ivLis-Studio/ivLyrics"' not in update_check
    rollback=function_block(candidate.decode('utf-8-sig'),'Rollback-LastTransaction')
    assert 'registry_sha256' not in rollback and 'Assert-AddonTransactionRegistryAuthorization' not in rollback
    return candidate,'crlf' if newline=='\r\n' else 'lf'

def build():
    base_main,base_addon=prepare_base()
    candidate_main,patch_doc=build_main(base_main)
    candidate_addon,addon_newline=build_addon(base_addon)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(candidate_main); (OUT/'addon-manager.ps1').write_bytes(candidate_addon)

    patch_json=json.dumps(patch_doc,separators=(',',':'),ensure_ascii=True).encode('ascii')
    patch_gz=deterministic_gzip(patch_json); patch_b64=base64.b64encode(patch_gz)
    main_chunks=write_chunks(patch_b64,MAIN_CHUNK_DIR,1024)
    main_transport={'path':'bin/spotify-control.ps1','from_sha256':BASE_MAIN_SHA,'to_sha256':sha(candidate_main),'encoding':'gzip-base64-chunks','encoded_sha256':sha(patch_b64),'encoded_size':len(patch_b64),'compressed_sha256':sha(patch_gz),'compressed_size':len(patch_gz),'json_sha256':sha(patch_json),'json_size':len(patch_json),'chunks':main_chunks}
    addon_gz=deterministic_gzip(candidate_addon); addon_b64=base64.b64encode(addon_gz)
    addon_chunks=write_chunks(addon_b64,ADDON_CHUNK_DIR,4096)
    addon_transport={'path':'bin/addon-manager.ps1','from_sha256':BASE_ADDON_SHA,'to_sha256':sha(candidate_addon),'encoding':'gzip-base64-full-file','encoded_sha256':sha(addon_b64),'encoded_size':len(addon_b64),'compressed_sha256':sha(addon_gz),'compressed_size':len(addon_gz),'target_size':len(candidate_addon),'chunks':addon_chunks}
    latest=[{'path':'bin/spotify-control.ps1','sha256':sha(candidate_main),'size':len(candidate_main)},{'path':'bin/addon-manager.ps1','sha256':sha(candidate_addon),'size':len(candidate_addon)},{'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':AGENT_SIZE}]
    meta={'schema':1,'version':NEW_VERSION,'base_version':BASE_VERSION,'base_main':{'path':'bin/spotify-control.ps1','sha256':BASE_MAIN_SHA,'size':BASE_MAIN_SIZE},'candidate_main':latest[0],'base_addon':{'path':'bin/addon-manager.ps1','sha256':BASE_ADDON_SHA,'size':BASE_ADDON_SIZE},'candidate_addon':latest[1],'agent':latest[2],'addon_line_ending':addon_newline,'policy_registry':{'path':'validation/v0.6.21/addon_policy_registry.ps1.inc','sha256':POLICY_SHA,'size':POLICY_SIZE},'transaction_guard':{'path':'validation/v0.6.21/addon_transaction_registry_guard.ps1.inc','sha256':GUARD_SHA,'size':GUARD_SIZE},'validation_provenance':{'head':VALIDATION_HEAD,'push_run':VALIDATION_PUSH_RUN,'pr_run':VALIDATION_PR_RUN,'validated_addon_sha256':EXPECTED_R10_SHA,'validated_addon_size':EXPECTED_R10_SIZE},'main_patch':main_transport,'addon_patch':addon_transport,'payload_set_sha256':canonical_payload(latest)}
    META.parent.mkdir(parents=True,exist_ok=True); META.write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    enc=concat_chunks(main_transport); raw=gzip.decompress(base64.b64decode(enc,validate=True)); assert sha(raw)==main_transport['json_sha256']; assert apply_ascii_line_patch(base_main,json.loads(raw.decode('ascii')))==candidate_main
    enc=concat_chunks(addon_transport); assert gzip.decompress(base64.b64decode(enc,validate=True))==candidate_addon
    print('V0621_BUILD_PASS',len(candidate_main),sha(candidate_main),len(candidate_addon),sha(candidate_addon),meta['payload_set_sha256'])

def write_manifest(source_commit):
    assert re.fullmatch(r'[0-9a-f]{40}',source_commit),source_commit
    meta=json.loads(META.read_text(encoding='utf-8')); p=ROOT/'manifest.json'; m=json.loads(p.read_text(encoding='utf-8-sig'))
    assert m['bootstrap']==BOOTSTRAP
    if m['latest_version']==NEW_VERSION:
        assert m['source_commit']==source_commit; validate_published(); return
    assert m['latest_version']==BASE_VERSION,m['latest_version']
    latest={x['path']:x for x in m['latest_files']}
    assert latest['bin/spotify-control.ps1']==meta['base_main']; assert latest['bin/addon-manager.ps1']==meta['base_addon']; assert latest['bin/spotify-control-agent.vbs']==meta['agent']
    m['latest_files']=[meta['candidate_main'] if x['path']=='bin/spotify-control.ps1' else meta['candidate_addon'] if x['path']=='bin/addon-manager.ps1' else x for x in m['latest_files']]
    m['latest_version']=NEW_VERSION; m['source_commit']=source_commit; m['payload_set_sha256']=meta['payload_set_sha256']
    assert not any(e['from_version']==BASE_VERSION for e in m['updates'])
    m['updates'].append({'from_version':BASE_VERSION,'to_version':NEW_VERSION,'patches':[meta['main_patch'],meta['addon_patch']]})
    p.write_text(json.dumps(m,separators=(',',':')),encoding='utf-8',newline='')
    print('V0621_MANIFEST_WRITTEN',source_commit,meta['payload_set_sha256'])

def validate_published():
    meta=json.loads(META.read_text(encoding='utf-8')); m=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))
    assert m['latest_version']==NEW_VERSION and m['bootstrap']==BOOTSTRAP and re.fullmatch(r'[0-9a-f]{40}',m['source_commit'])
    latest={x['path']:x for x in m['latest_files']}
    assert latest['bin/spotify-control.ps1']==meta['candidate_main']; assert latest['bin/addon-manager.ps1']==meta['candidate_addon']; assert latest['bin/spotify-control-agent.vbs']==meta['agent']
    assert m['payload_set_sha256']==meta['payload_set_sha256']==canonical_payload(m['latest_files'])
    edges=[e for e in m['updates'] if e['from_version']==BASE_VERSION and e['to_version']==NEW_VERSION]; assert len(edges)==1 and len(edges[0]['patches'])==2
    patches={x['path']:x for x in edges[0]['patches']}; assert patches['bin/spotify-control.ps1']==meta['main_patch']; assert patches['bin/addon-manager.ps1']==meta['addon_patch']
    base_main,base_addon=prepare_base()
    enc=concat_chunks(meta['main_patch']); raw=gzip.decompress(base64.b64decode(enc,validate=True)); candidate_main=apply_ascii_line_patch(base_main,json.loads(raw.decode('ascii')))
    assert (len(candidate_main),sha(candidate_main))==(meta['candidate_main']['size'],meta['candidate_main']['sha256'])
    enc=concat_chunks(meta['addon_patch']); candidate_addon=gzip.decompress(base64.b64decode(enc,validate=True)); assert (len(candidate_addon),sha(candidate_addon))==(EXPECTED_R10_SIZE,EXPECTED_R10_SHA)
    print('V0621_PUBLISHED_PASS',m['source_commit'],m['payload_set_sha256'])

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--build',action='store_true'); ap.add_argument('--write-manifest',action='store_true'); ap.add_argument('--validate-published',action='store_true'); ap.add_argument('--source-commit')
    a=ap.parse_args()
    if a.build: build()
    if a.write_manifest:
        if not a.source_commit: raise SystemExit('--source-commit is required')
        write_manifest(a.source_commit)
    if a.validate_published: validate_published()
    if not (a.build or a.write_manifest or a.validate_published): build()

if __name__=='__main__': main()
