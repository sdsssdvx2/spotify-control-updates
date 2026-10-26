from pathlib import Path
import hashlib,json,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
DIR=ROOT/'validation/addon-registry-r10-v0.1.0'
BASE_BUILDER=DIR/'build_r10.py'
GUARD=DIR/'addon_transaction_registry_guard.ps1.inc'
OUT=DIR/'out/addon-manager.ps1'
META=DIR/'candidate-metadata.json'

def sha(b):return hashlib.sha256(b).hexdigest()
def function_block(text,name):
    marker=f'function {name} {{'
    start=text.find(marker)
    if start<0:raise RuntimeError(f'missing function {name}')
    nxt=text.find('\nfunction ',start+len(marker))
    if nxt<0:nxt=len(text)
    return text[start:nxt]

def replace_once(text,old,new,label):
    n=text.count(old)
    if n!=1:raise RuntimeError(f'{label}: expected exactly one match, got {n}')
    return text.replace(old,new,1)

def build():
    subprocess.check_call([sys.executable,str(BASE_BUILDER)],cwd=ROOT)
    raw=OUT.read_bytes()
    bom=b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b''
    text=raw[len(bom):].decode('utf-8')
    crlf=text.count('\r\n');lf=text.count('\n')
    newline='\r\n' if crlf and crlf==lf else '\n'
    if newline=='\n' and '\r\n' in text:raise RuntimeError('mixed candidate line endings')

    guard=GUARD.read_text(encoding='utf-8').replace('\r\n','\n').rstrip('\n').replace('\n',newline)
    text=replace_once(text,'function Get-AddonInventory {',guard+newline+newline+'function Get-AddonInventory {','transaction guard insertion')

    commit=function_block(text,'Commit-LastTransaction')
    normalize_line='    $tx = Normalize-PithayaTransaction $tx'+newline
    start=commit.find(normalize_line)
    if start<0:raise RuntimeError('CommitLast normalize marker missing')
    after=start+len(normalize_line)
    status='    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }'
    end=commit.find(status,after)
    if end<0:raise RuntimeError('CommitLast status marker missing')
    middle=commit[after:end]
    for required in ['registry_sha256','Get-AddonPolicyRegistryFingerprint','legacy schema-2 addon transaction without registry fingerprint']:
        if required not in middle:raise RuntimeError(f'base r10 inline registry guard missing expected marker: {required}')
    replacement=(
        '    $registryAuthorizationMode=Assert-AddonTransactionRegistryAuthorization -Tx $tx'+newline+
        '    if ([string]$registryAuthorizationMode -ceq "legacy-schema2-no-registry") { Write-AddonLog "Committing legacy schema-2 addon transaction without registry fingerprint; exact-tree verification remains required." "WARN" }'+newline
    )
    commit=commit[:after]+replacement+commit[end:]
    old_commit=function_block(text,'Commit-LastTransaction')
    text=replace_once(text,old_commit,commit,'replace CommitLast with pure transaction guard')

    selftest=function_block(text,'Invoke-AddonSelfTest')
    old='        Invoke-AddonPolicyRegistrySelfTest'+newline+'        Write-AddonLog "Addon policy registry self-test passed: deterministic fingerprint, exact current auto-authority, and denied protected/unknown sources."'
    new='        Invoke-AddonPolicyRegistrySelfTest'+newline+'        Invoke-AddonTransactionRegistrySelfTest'+newline+'        Write-AddonLog "Addon policy registry self-test passed: deterministic fingerprint, exact current auto-authority, denied protected/unknown sources, legacy transaction compatibility, and registry drift rejection."'
    selftest=replace_once(selftest,old,new,'transaction guard fixture integration')
    old_self=function_block(text,'Invoke-AddonSelfTest')
    text=replace_once(text,old_self,selftest,'replace selftest with transaction registry fixtures')

    candidate=bom+text.encode('utf-8')
    OUT.write_bytes(candidate)
    meta=json.loads(META.read_text(encoding='utf-8'))
    meta['candidate']='addon-registry-r10-v0.1.0-final'
    meta['candidate_addon']={'size':len(candidate),'sha256':sha(candidate)}
    meta['transaction_guard']={'size':GUARD.stat().st_size,'sha256':sha(GUARD.read_bytes())}
    META.write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')

    ctext=candidate.decode('utf-8-sig')
    if ctext.count('# BEGIN SPOTIFY CONTROL ADDON TRANSACTION REGISTRY GUARD v1 / r10')!=1:raise RuntimeError('transaction registry guard count invalid')
    if ctext.count('Invoke-AddonTransactionRegistrySelfTest')!=2:raise RuntimeError('transaction registry selftest definition/call count invalid')
    commit_check=function_block(ctext,'Commit-LastTransaction')
    if commit_check.count('Assert-AddonTransactionRegistryAuthorization -Tx $tx')!=1:raise RuntimeError('CommitLast pure registry guard call missing/ambiguous')
    if 'Get-AddonPolicyRegistryFingerprint' in commit_check:raise RuntimeError('CommitLast still contains duplicated inline registry fingerprint logic')
    rollback=function_block(ctext,'Rollback-LastTransaction')
    for forbidden in ['Assert-AddonTransactionRegistryAuthorization','Get-AddonPolicyRegistryFingerprint','registry_sha256']:
        if forbidden in rollback:raise RuntimeError(f'rollback became registry-dependent: {forbidden}')
    guard_block=function_block(ctext,'Assert-AddonTransactionRegistryAuthorization')
    for required in ['legacy-schema2-no-registry','registry-v1-authorized','registry_sha256','mutation_mode','registry_source','registry_policy','registry_handler']:
        if required not in guard_block:raise RuntimeError(f'transaction registry guard missing {required}')
    print('ADDON_REGISTRY_R10_FINAL_BUILD_PASS',len(candidate),sha(candidate),meta['wrapper']['sha256'],meta['transaction_guard']['sha256'])
    return meta

if __name__=='__main__':build()
