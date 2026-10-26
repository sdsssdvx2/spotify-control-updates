from pathlib import Path
import hashlib,json,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
BASE='29d6c52c6a79559e513b367ec57edcccebae5fd0'
BASE_ADDON_SIZE=225044
BASE_ADDON_SHA='3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'
BASE_MAIN_SIZE=281585
BASE_MAIN_SHA='e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'
WRAPPER=ROOT/'validation/addon-registry-r10-v0.1.0/addon_policy_registry.ps1.inc'
OUT=ROOT/'validation/addon-registry-r10-v0.1.0/out'
META=ROOT/'validation/addon-registry-r10-v0.1.0/candidate-metadata.json'

def sha(b):return hashlib.sha256(b).hexdigest()
def replace_once(text,old,new,label):
    n=text.count(old)
    if n!=1:raise RuntimeError(f'{label}: expected exactly one match, got {n}')
    return text.replace(old,new,1)

def function_block(text,name):
    marker=f'function {name} {{'
    start=text.find(marker)
    if start<0:raise RuntimeError(f'missing function {name}')
    nxt=text.find('\nfunction ',start+len(marker))
    if nxt<0:nxt=len(text)
    return text[start:nxt]

def build():
    if subprocess.check_output(['git','merge-base',BASE,'HEAD'],text=True).strip()!=BASE:
        raise RuntimeError('r10 validation branch is not based on exact production main')
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.20/build_v0620.py'),'--build'],cwd=ROOT)
    base_main=(ROOT/'validation/v0.6.20/out/bin/spotify-control.ps1').read_bytes()
    base_addon=(ROOT/'validation/v0.6.20/out/bin/addon-manager.ps1').read_bytes()
    if (len(base_main),sha(base_main))!=(BASE_MAIN_SIZE,BASE_MAIN_SHA):raise RuntimeError('production main identity drift')
    if (len(base_addon),sha(base_addon))!=(BASE_ADDON_SIZE,BASE_ADDON_SHA):raise RuntimeError('production addon identity drift')
    bom=b'\xef\xbb\xbf' if base_addon.startswith(b'\xef\xbb\xbf') else b''
    text=base_addon[len(bom):].decode('utf-8')
    crlf=text.count('\r\n');lf=text.count('\n')
    newline='\r\n' if crlf and crlf==lf else '\n'
    if newline=='\n' and '\r\n' in text:raise RuntimeError('mixed addon line endings')

    text=replace_once(text,'$Version = "0.6.5-r9"','$Version = "0.6.5-r10"','version bump')

    wrapper=WRAPPER.read_text(encoding='utf-8').replace('\r\n','\n').rstrip('\n').replace('\n',newline)
    text=replace_once(text,'function Get-AddonInventory {',wrapper+newline+newline+'function Get-AddonInventory {','registry wrapper insertion')

    inventory=function_block(text,'Get-AddonInventory')
    old='foreach ($name in @("better-local-files","eternal-jukebox","playlist-maker")) {'
    new='$pithayaPolicyEntries = @(Get-AddonPolicyRegistry | Where-Object { [string]$_.handler -ceq "pithaya" -and [string]$_.mutation_mode -ceq "auto" } | Sort-Object -Property name)'+newline+'    foreach ($policyEntry in $pithayaPolicyEntries) {'+newline+'        $name = [string]$policyEntry.name'
    inventory=replace_once(inventory,old,new,'Pithaya inventory registry derivation')
    old='    foreach ($item in $items) {'+newline+'        $stateKey = if ([string]$item.kind -eq \'extension\') { \'extension:\' + [string]$item.name } else { [string]$item.name }'
    new='    $registrySummary = Add-AddonPolicyRegistryMetadata -Items $items.ToArray()'+newline+'    [void](Write-AddonPolicyRegistryReport)'+newline+newline+'    foreach ($item in $items) {'+newline+'        $stateKey = if ([string]$item.kind -eq \'extension\') { \'extension:\' + [string]$item.name } else { [string]$item.name }'
    inventory=replace_once(inventory,old,new,'inventory registry metadata insertion')
    old='        asset_resolution = $assetResolution'+newline+'        items = $items.ToArray()'
    new='        asset_resolution = $assetResolution'+newline+'        policy_registry = $registrySummary'+newline+'        items = $items.ToArray()'
    inventory=replace_once(inventory,old,new,'inventory report registry summary')
    old_block=function_block(text,'Get-AddonInventory')
    text=replace_once(text,old_block,inventory,'replace Get-AddonInventory')

    update=function_block(text,'Update-AutoApps')
    old='''    foreach ($item in @($report.items)) {\n        if ($item.policy -ne "auto" -or $item.installed -ne $true) { continue }\n        if ($item.source -eq "Pithaya/spicetify-apps-dist") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","trusted-known-baseline")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -eq "exact-current") { $candidates.Add($item); continue }\n        } elseif ($item.source -eq "ivLis-Studio/ivLyrics") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n        }\n        if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n    }'''.replace('\n',newline)
    new='''    foreach ($item in @($report.items)) {\n        $authorization = Get-AddonMutationAuthorization -Item $item\n        if (-not $authorization.Allowed) {\n            if ([string]$item.policy -ceq "auto" -and $item.installed -eq $true) { Write-AddonLog "Registry denied automatic mutation for $($item.name): $($authorization.Reason)." "WARN" }\n            if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n            continue\n        }\n        if ([string]$authorization.Handler -ceq "pithaya") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","trusted-known-baseline")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -eq "exact-current") { $candidates.Add($item); continue }\n        } elseif ([string]$authorization.Handler -ceq "ivlyrics") {\n            if ($item.status -eq "update-available" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n            if ($Force -and $item.status -eq "current" -and $item.local_safety -in @("trusted-baseline","release-proof-required")) { $candidates.Add($item); continue }\n        } else { throw "Registry authorized unsupported mutation handler '$($authorization.Handler)' for $($item.name)." }\n        if ($item.status -like "update-blocked-*") { Write-AddonLog "Fail-closed: $($item.name) is $($item.status); Force does not override local divergence." "WARN" }\n    }'''.replace('\n',newline)
    update=replace_once(update,old,new,'candidate authorization gate')

    old='''            $before=Get-DirectoryGitSnapshot ([string]$item.install_path)\n            $state=Load-AddonState; $as=Ensure-AppState $state $item.name\n            if ([string]$item.source -eq "Pithaya/spicetify-apps-dist") {'''.replace('\n',newline)
    new='''            $authorization = Get-AddonMutationAuthorization -Item $item\n            if (-not $authorization.Allowed) { throw "Registry authorization changed before staging for $($item.name): $($authorization.Reason)" }\n            $before=Get-DirectoryGitSnapshot ([string]$item.install_path)\n            $state=Load-AddonState; $as=Ensure-AppState $state $item.name\n            if ([string]$authorization.Handler -ceq "pithaya") {'''.replace('\n',newline)
    update=replace_once(update,old,new,'phase1 pithaya handler gate')
    update=replace_once(update,'            if ([string]$item.source -eq "ivLis-Studio/ivLyrics") {','            if ([string]$authorization.Handler -ceq "ivlyrics") {','phase1 ivlyrics handler gate')
    update=replace_once(update,'            throw "Unsupported auto-managed source for $($item.name): $($item.source)"','            throw "Unsupported registry mutation handler for $($item.name): $($authorization.Handler)"','phase1 unsupported handler')

    old='''            $changes.Add([pscustomobject]@{\n                name=[string]$p.item.name; target=[string]$p.item.install_path; backup=$backup\n                before_fingerprint=[string]$p.before.fingerprint; before_revision=[string]$beforeState.installed_revision\n                after_revision=[string]$p.remote.revision; after_fingerprint=[string]$p.remote.fingerprint\n                remote_tree=[string]$p.remote.tree_sha; archive_sha256=[string]$p.archive_sha256; swapped=$false\n            })\n        }\n        $tx=[pscustomobject]@{ schema=2; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'''.replace('\n',newline)
    new='''            $changeAuthorization = Get-AddonMutationAuthorization -Item $p.item\n            if (-not $changeAuthorization.Allowed) { throw "Registry authorization changed before transaction ledger creation for $($p.item.name): $($changeAuthorization.Reason)" }\n            $changes.Add([pscustomobject]@{\n                name=[string]$p.item.name; target=[string]$p.item.install_path; backup=$backup\n                before_fingerprint=[string]$p.before.fingerprint; before_revision=[string]$beforeState.installed_revision\n                after_revision=[string]$p.remote.revision; after_fingerprint=[string]$p.remote.fingerprint\n                remote_tree=[string]$p.remote.tree_sha; archive_sha256=[string]$p.archive_sha256; swapped=$false\n                registry_handler=[string]$changeAuthorization.Handler; registry_source=[string]$changeAuthorization.Entry.source; registry_policy=[string]$changeAuthorization.Entry.inventory_policy\n            })\n        }\n        $registrySha=Get-AddonPolicyRegistryFingerprint\n        $tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'''.replace('\n',newline)
    update=replace_once(update,old,new,'transaction registry metadata')
    text=replace_once(text,function_block(text,'Update-AutoApps'),update,'replace Update-AutoApps')

    normalize=function_block(text,'Normalize-PithayaTransaction')
    old='''    foreach ($optional in @("swapped_at","rolled_back_at","committed_at")) {\n        [void](Ensure-ObjectNoteProperty -Object $Tx -Name $optional -DefaultValue $null)\n    }'''.replace('\n',newline)
    new='''    foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256")) {\n        [void](Ensure-ObjectNoteProperty -Object $Tx -Name $optional -DefaultValue $null)\n    }'''.replace('\n',newline)
    normalize=replace_once(normalize,old,new,'normalize optional registry metadata')
    text=replace_once(text,function_block(text,'Normalize-PithayaTransaction'),normalize,'replace Normalize-PithayaTransaction')

    commit=function_block(text,'Commit-LastTransaction')
    old='''    $tx = Normalize-PithayaTransaction $tx\n    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }'''.replace('\n',newline)
    new='''    $tx = Normalize-PithayaTransaction $tx\n    if (-not [string]::IsNullOrWhiteSpace([string]$tx.registry_sha256)) {\n        if ([int]$tx.registry_schema -ne 1) { throw "Addon transaction registry schema is unsupported: $($tx.registry_schema)" }\n        $currentRegistrySha=Get-AddonPolicyRegistryFingerprint\n        if ([string]$tx.registry_sha256 -cne [string]$currentRegistrySha) { throw "Addon policy registry changed since transaction preparation; refusing commit. transaction=$($tx.registry_sha256) current=$currentRegistrySha" }\n        foreach($change in @($tx.changes)) {\n            $entry=Get-AddonPolicyRegistryEntry -Name ([string]$change.name)\n            if($null -eq $entry -or [string]$entry.mutation_mode -cne "auto"){throw "Addon policy registry no longer authorizes committed change $($change.name)."}\n            if($change.PSObject.Properties["registry_source"] -and [string]$change.registry_source -cne [string]$entry.source){throw "Addon transaction source policy changed for $($change.name)."}\n            if($change.PSObject.Properties["registry_policy"] -and [string]$change.registry_policy -cne [string]$entry.inventory_policy){throw "Addon transaction inventory policy changed for $($change.name)."}\n            if($change.PSObject.Properties["registry_handler"] -and [string]$change.registry_handler -cne [string]$entry.handler){throw "Addon transaction handler policy changed for $($change.name)."}\n        }\n    } else {\n        Write-AddonLog "Committing legacy schema-2 addon transaction without registry fingerprint; exact-tree verification remains required." "WARN"\n    }\n    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }'''.replace('\n',newline)
    commit=replace_once(commit,old,new,'commit registry drift gate')
    text=replace_once(text,function_block(text,'Commit-LastTransaction'),commit,'replace Commit-LastTransaction')

    selftest=function_block(text,'Invoke-AddonSelfTest')
    old='''    if ($errors.Count -gt 0) {\n        foreach ($e in $errors) { Write-AddonLog $e "ERROR" }'''.replace('\n',newline)
    new='''    try {\n        Invoke-AddonPolicyRegistrySelfTest\n        Write-AddonLog "Addon policy registry self-test passed: deterministic fingerprint, exact current auto-authority, and denied protected/unknown sources."\n    } catch {\n        $errors.Add("Addon policy registry self-test failed: $($_.Exception.Message)")\n    }\n\n    if ($errors.Count -gt 0) {\n        foreach ($e in $errors) { Write-AddonLog $e "ERROR" }'''.replace('\n',newline)
    selftest=replace_once(selftest,old,new,'registry selftest insertion')
    old='Write-AddonLog "Addon Manager read-only self-test passed, including multi-root, Pithaya/ivLyrics transaction, official-tag trust bootstrap drift rejection, unproven legacy monitor fallback, pending-aware schedule bypass, successful CommitLast pending-drain, and managed direct-extension ownership fixtures."'
    new='Write-AddonLog "Addon Manager read-only self-test passed, including multi-root, policy-registry authorization, Pithaya/ivLyrics transaction, official-tag trust bootstrap drift rejection, unproven legacy monitor fallback, pending-aware schedule bypass, successful CommitLast pending-drain, and managed direct-extension ownership fixtures."'
    selftest=replace_once(selftest,old,new,'selftest success message')
    text=replace_once(text,function_block(text,'Invoke-AddonSelfTest'),selftest,'replace Invoke-AddonSelfTest')

    candidate=bom+text.encode('utf-8')
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'addon-manager.ps1').write_bytes(candidate)
    (OUT/'spotify-control.ps1').write_bytes(base_main)
    meta={
        'schema':1,'candidate':'addon-registry-r10-v0.1.0','production_base':BASE,
        'base_main':{'size':len(base_main),'sha256':sha(base_main)},
        'base_addon':{'size':len(base_addon),'sha256':sha(base_addon)},
        'candidate_addon':{'size':len(candidate),'sha256':sha(candidate)},
        'wrapper':{'size':WRAPPER.stat().st_size,'sha256':sha(WRAPPER.read_bytes())},
        'line_ending':'crlf' if newline=='\r\n' else 'lf',
    }
    META.write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')

    ctext=candidate.decode('utf-8-sig')
    if ctext.count('$Version = "0.6.5-r10"')!=1:raise RuntimeError('candidate version marker invalid')
    if ctext.count('# BEGIN SPOTIFY CONTROL ADDON POLICY REGISTRY v1 / r10')!=1:raise RuntimeError('registry wrapper count invalid')
    update_check=function_block(ctext,'Update-AutoApps')
    if '$item.source -eq "Pithaya/spicetify-apps-dist"' in update_check or '$item.source -eq "ivLis-Studio/ivLyrics"' in update_check:
        raise RuntimeError('hard-coded source mutation branch remains in Update-AutoApps')
    if 'Get-AddonMutationAuthorization' not in update_check or 'registry_sha256=$registrySha' not in update_check:
        raise RuntimeError('registry authorization/transaction fingerprint missing')
    rollback=function_block(ctext,'Rollback-LastTransaction')
    if 'Get-AddonPolicyRegistryFingerprint' in rollback or 'registry_sha256' in rollback:
        raise RuntimeError('rollback must remain independent of current registry')
    commit_check=function_block(ctext,'Commit-LastTransaction')
    if 'legacy schema-2 addon transaction without registry fingerprint' not in commit_check:
        raise RuntimeError('legacy transaction commit compatibility missing')
    print('ADDON_REGISTRY_R10_BUILD_PASS',len(candidate),sha(candidate),meta['wrapper']['sha256'])
    return meta

if __name__=='__main__':build()
