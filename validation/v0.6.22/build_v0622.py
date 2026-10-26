from pathlib import Path
import argparse,hashlib,json,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
BASE_MAIN_SHA='f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'
BASE_MAIN_SIZE=281579
BASE_ADDON_SHA='7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
BASE_ADDON_SIZE=250616
BASE_OUT=ROOT/'validation/v0.6.21/out/bin'
OUT=ROOT/'validation/v0.6.22/out/bin'
ENGINE=ROOT/'validation/v0.6.22/addon_source_adapter_engine.ps1.inc'
REPORT=ROOT/'validation/v0.6.22/candidate-validation.json'
EXPECTED_MAIN_SHA=None
EXPECTED_MAIN_SIZE=None
EXPECTED_R11_SHA=None
EXPECTED_R11_SIZE=None

def sha(b): return hashlib.sha256(b).hexdigest()
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
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.21/build_v0621.py'),'--build'],cwd=ROOT)
    main=(BASE_OUT/'spotify-control.ps1').read_bytes(); addon=(BASE_OUT/'addon-manager.ps1').read_bytes()
    assert (len(main),sha(main))==(BASE_MAIN_SIZE,BASE_MAIN_SHA),(len(main),sha(main))
    assert (len(addon),sha(addon))==(BASE_ADDON_SIZE,BASE_ADDON_SHA),(len(addon),sha(addon))
    return main,addon

def build_main(base):
    assert base.startswith(b'\xef\xbb\xbf'); body=base[3:]; assert b'\r\n' not in body
    text=body.decode('ascii')
    text=replace_once(text,'# Spotify Control v0.6.21 Addon Registry r10\n','# Spotify Control v0.6.22 Addon Source Registry r11\n','main title')
    text=replace_once(text,'$ScriptVersion = "0.6.21"\n','$ScriptVersion = "0.6.22"\n','main version')
    return b'\xef\xbb\xbf'+text.encode('ascii')

def build_addon(base):
    bom=b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text=base[len(bom):].decode('utf-8')
    crlf=text.count('\r\n'); lf=text.count('\n'); newline='\r\n' if crlf and crlf==lf else '\n'
    if newline=='\n': assert '\r\n' not in text
    text=replace_once(text,'$Version = "0.6.5-r10"','$Version = "0.6.5-r11"','addon version')
    engine=ENGINE.read_text(encoding='utf-8').replace('\r\n','\n').rstrip('\n').replace('\n',newline)
    text=replace_once(text,'function Get-AddonInventory {',engine+newline+newline+'function Get-AddonInventory {','source adapter insertion')

    update=function_block(text,'Update-AutoApps')
    old='''    foreach ($item in @($report.items)) {\n        $authorization = Get-AddonMutationAuthorization -Item $item\n        if (-not $authorization.Allowed) {\n            if ([string]$item.policy -ceq "auto" -and $item.installed -eq $true) { Write-AddonLog "Registry denied automatic mutation for $($item.name): $($authorization.Reason)." "WARN" }\n            if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n            continue\n        }\n        if ([string]$authorization.Handler -ceq "pithaya") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","trusted-known-baseline")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -eq "exact-current") { $candidates.Add($item); continue }\n        } elseif ([string]$authorization.Handler -ceq "ivlyrics") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n        } else { throw "Registry authorized unsupported mutation handler '$($authorization.Handler)' for $($item.name)." }\n        if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n    }'''.replace('\n',newline)
    new='''    foreach ($item in @($report.items)) {\n        $sourcePlan = Get-AddonSourceAdapterPlan -Item $item\n        if (-not $sourcePlan.allowed -or -not $sourcePlan.mutation_authorized) {\n            if ([string]$item.policy -ceq "auto" -and $item.installed -eq $true) { Write-AddonLog "Source adapter denied automatic mutation for $($item.name): $($sourcePlan.authorization_reason)." "WARN" }\n            if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n            continue\n        }\n        if ([string]$sourcePlan.mutation_handler -ceq "pithaya") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","trusted-known-baseline")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -eq "exact-current") { $candidates.Add($item); continue }\n        } elseif ([string]$sourcePlan.mutation_handler -ceq "ivlyrics") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n        } else { throw "Source adapter authorized unsupported mutation handler '$($sourcePlan.mutation_handler)' for $($item.name)." }\n        if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n    }'''.replace('\n',newline)
    update=replace_once(update,old,new,'candidate source adapter gate')

    old='''            $authorization = Get-AddonMutationAuthorization -Item $item\n            if (-not $authorization.Allowed) { throw "Registry authorization changed before staging for $($item.name): $($authorization.Reason)" }\n            $before=Get-DirectoryGitSnapshot ([string]$item.install_path)\n            $state=Load-AddonState; $as=Ensure-AppState $state $item.name\n            if ([string]$authorization.Handler -ceq "pithaya") {'''.replace('\n',newline)
    new='''            $sourcePlan = Get-AddonSourceAdapterPlan -Item $item\n            if (-not $sourcePlan.allowed -or -not $sourcePlan.mutation_authorized) { throw "Source adapter authorization changed before staging for $($item.name): $($sourcePlan.authorization_reason)" }\n            $before=Get-DirectoryGitSnapshot ([string]$item.install_path)\n            $state=Load-AddonState; $as=Ensure-AppState $state $item.name\n            if ([string]$sourcePlan.mutation_handler -ceq "pithaya") {'''.replace('\n',newline)
    update=replace_once(update,old,new,'phase1 source adapter gate')
    update=replace_once(update,'            if ([string]$authorization.Handler -ceq "ivlyrics") {','            if ([string]$sourcePlan.mutation_handler -ceq "ivlyrics") {','phase1 ivlyrics adapter')
    update=replace_once(update,'            throw "Unsupported registry mutation handler for $($item.name): $($authorization.Handler)"','            throw "Unsupported source adapter mutation handler for $($item.name): $($sourcePlan.mutation_handler)"','phase1 unsupported adapter')

    old='''            $changeAuthorization = Get-AddonMutationAuthorization -Item $p.item\n            if (-not $changeAuthorization.Allowed) { throw "Registry authorization changed before transaction ledger creation for $($p.item.name): $($changeAuthorization.Reason)" }\n            $changes.Add([pscustomobject]@{\n                name=[string]$p.item.name; target=[string]$p.item.install_path; backup=$backup\n                before_fingerprint=[string]$p.before.fingerprint; before_revision=[string]$beforeState.installed_revision\n                after_revision=[string]$p.remote.revision; after_fingerprint=[string]$p.remote.fingerprint\n                remote_tree=[string]$p.remote.tree_sha; archive_sha256=[string]$p.archive_sha256; swapped=$false\n                registry_handler=[string]$changeAuthorization.Handler; registry_source=[string]$changeAuthorization.Entry.source; registry_policy=[string]$changeAuthorization.Entry.inventory_policy\n            })\n        }\n        $registrySha=Get-AddonPolicyRegistryFingerprint\n        $tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'''.replace('\n',newline)
    new='''            $changePlan = Get-AddonSourceAdapterPlan -Item $p.item\n            if (-not $changePlan.allowed -or -not $changePlan.mutation_authorized) { throw "Source adapter authorization changed before transaction ledger creation for $($p.item.name): $($changePlan.authorization_reason)" }\n            $adapterProvenance = New-AddonSourceAdapterTransactionProvenance -Plan $changePlan\n            $changes.Add([pscustomobject]@{\n                name=[string]$p.item.name; target=[string]$p.item.install_path; backup=$backup\n                before_fingerprint=[string]$p.before.fingerprint; before_revision=[string]$beforeState.installed_revision\n                after_revision=[string]$p.remote.revision; after_fingerprint=[string]$p.remote.fingerprint\n                remote_tree=[string]$p.remote.tree_sha; archive_sha256=[string]$p.archive_sha256; swapped=$false\n                registry_kind=[string]$changePlan.Entry.kind; registry_handler=[string]$changePlan.mutation_handler; registry_source=[string]$changePlan.Entry.source; registry_policy=[string]$changePlan.Entry.inventory_policy\n                source_adapter_id=[string]$adapterProvenance.source_adapter_id; source_adapter_strategy=[string]$adapterProvenance.source_adapter_strategy; source_adapter_source=[string]$adapterProvenance.source_adapter_source; source_adapter_rollback=[string]$adapterProvenance.source_adapter_rollback\n            })\n        }\n        $registrySha=Get-AddonPolicyRegistryFingerprint\n        $sourceAdapterSha=Get-AddonSourceAdapterFingerprint\n        $tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; source_adapter_schema=1; source_adapter_sha256=$sourceAdapterSha; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'''.replace('\n',newline)
    update=replace_once(update,old,new,'source adapter transaction provenance')
    text=replace_once(text,function_block(text,'Update-AutoApps'),update,'replace Update-AutoApps')

    normalize=function_block(text,'Normalize-PithayaTransaction')
    normalize=replace_once(normalize,'    foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256")) {','    foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256","source_adapter_schema","source_adapter_sha256")) {','normalize source adapter metadata')
    text=replace_once(text,function_block(text,'Normalize-PithayaTransaction'),normalize,'replace Normalize-PithayaTransaction')

    commit=function_block(text,'Commit-LastTransaction')
    old='''    $tx = Normalize-PithayaTransaction $tx\n    $registryAuthorizationMode=Assert-AddonTransactionRegistryAuthorization -Tx $tx\n    if ([string]$registryAuthorizationMode -ceq "legacy-schema2-no-registry") { Write-AddonLog "Committing legacy schema-2 addon transaction without registry fingerprint; exact-tree verification remains required." "WARN" }\n    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }'''.replace('\n',newline)
    new='''    $tx = Normalize-PithayaTransaction $tx\n    $registryAuthorizationMode=Assert-AddonTransactionRegistryAuthorization -Tx $tx\n    if ([string]$registryAuthorizationMode -ceq "legacy-schema2-no-registry") { Write-AddonLog "Committing legacy schema-2 addon transaction without registry fingerprint; exact-tree verification remains required." "WARN" }\n    $sourceAdapterAuthorizationMode=Assert-AddonSourceAdapterTransactionAuthorization -Tx $tx\n    if ([string]$sourceAdapterAuthorizationMode -ceq "legacy-r10-no-source-adapter") { Write-AddonLog "Committing pre-r11 addon transaction without source-adapter fingerprint; existing registry/exact-tree verification remains required." "WARN" }\n    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }'''.replace('\n',newline)
    commit=replace_once(commit,old,new,'CommitLast source adapter authorization')
    text=replace_once(text,function_block(text,'Commit-LastTransaction'),commit,'replace CommitLast')

    selftest=function_block(text,'Invoke-AddonSelfTest')
    old='''        Invoke-AddonPolicyRegistrySelfTest\n        Invoke-AddonTransactionRegistrySelfTest\n        Invoke-AddonRegistryCommitCycleSelfTest\n        Write-AddonLog "Addon policy registry self-test passed: deterministic fingerprint, exact current auto-authority, denied protected/unknown sources, legacy transaction compatibility, registry drift rejection, and filesystem-backed registry CommitLast."'''.replace('\n',newline)
    new='''        Invoke-AddonPolicyRegistrySelfTest\n        Invoke-AddonTransactionRegistrySelfTest\n        Invoke-AddonRegistryCommitCycleSelfTest\n        Invoke-AddonSourceAdapterSelfTest\n        Write-AddonLog "Addon policy/source registry self-test passed: deterministic registry and source-adapter fingerprints, exact current auto-authority, denied protected/unknown sources, legacy transaction compatibility, registry/source drift rejection, and filesystem-backed registry CommitLast."'''.replace('\n',newline)
    selftest=replace_once(selftest,old,new,'source adapter selftest')
    selftest=replace_once(selftest,'policy-registry authorization, Pithaya/ivLyrics transaction','policy/source-registry authorization, Pithaya/ivLyrics transaction','selftest success message')
    text=replace_once(text,function_block(text,'Invoke-AddonSelfTest'),selftest,'replace Invoke-AddonSelfTest')

    candidate=bom+text.encode('utf-8')
    update_check=function_block(candidate.decode('utf-8-sig'),'Update-AutoApps')
    if 'Get-AddonMutationAuthorization -Item $item' in update_check: raise RuntimeError('Update-AutoApps still bypasses source adapter plan')
    if '$item.source -eq "Pithaya/spicetify-apps-dist"' in update_check or '$item.source -eq "ivLis-Studio/ivLyrics"' in update_check: raise RuntimeError('Update-AutoApps still routes on literal source')
    rollback=function_block(candidate.decode('utf-8-sig'),'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback or 'source_adapter_sha256' in rollback: raise RuntimeError('RollbackLast must remain source-adapter independent')
    for forbidden in ('Invoke-WebRequest','Invoke-RestMethod','Expand-Archive','Remove-Item','Move-Item','Copy-Item','Start-Process','spicetify apply','spicetify backup','spicetify restore'):
        if forbidden.lower() in engine.lower(): raise RuntimeError(f'source adapter engine contains forbidden side effect: {forbidden}')
    return candidate,'crlf' if newline=='\r\n' else 'lf'

def build():
    main,addon=prepare_base(); candidate_main=build_main(main); candidate_addon,newline=build_addon(addon)
    OUT.mkdir(parents=True,exist_ok=True); (OUT/'spotify-control.ps1').write_bytes(candidate_main); (OUT/'addon-manager.ps1').write_bytes(candidate_addon)
    report={
        'schema':1,'version':'0.6.22','addon_version':'0.6.5-r11','base_version':'0.6.21',
        'base_main':{'size':len(main),'sha256':sha(main)},'candidate_main':{'size':len(candidate_main),'sha256':sha(candidate_main)},
        'base_addon':{'size':len(addon),'sha256':sha(addon)},'candidate_addon':{'size':len(candidate_addon),'sha256':sha(candidate_addon)},
        'adapter_engine':{'size':ENGINE.stat().st_size,'sha256':sha(ENGINE.read_bytes())},'addon_line_ending':newline,
        'authority_expanded':False,'new_auto_install_authority':False,'generic_network_fetch':False,'generic_archive_extraction':False
    }
    REPORT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    if EXPECTED_MAIN_SHA is not None and (len(candidate_main),sha(candidate_main))!=(EXPECTED_MAIN_SIZE,EXPECTED_MAIN_SHA): raise RuntimeError('Pinned v0.6.22 main identity mismatch')
    if EXPECTED_R11_SHA is not None and (len(candidate_addon),sha(candidate_addon))!=(EXPECTED_R11_SIZE,EXPECTED_R11_SHA): raise RuntimeError('Pinned r11 identity mismatch')
    print('V0622_R11_BUILD_PASS',len(candidate_main),sha(candidate_main),len(candidate_addon),sha(candidate_addon),ENGINE.stat().st_size,sha(ENGINE.read_bytes()))
    return report

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--build',action='store_true');a=ap.parse_args();build()
if __name__=='__main__': main()
