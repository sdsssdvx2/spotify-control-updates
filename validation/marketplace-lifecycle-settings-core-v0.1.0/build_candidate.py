from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, subprocess, sys

ROOT=Path(__file__).resolve().parents[2]
BASE_OUT=ROOT/'validation/v0.6.28/out/bin'
HERE=ROOT/'validation/marketplace-lifecycle-settings-core-v0.1.0'
OUT=HERE/'out/bin'
REPORT=HERE/'candidate-report.json'
CORE=HERE/'lifecycle-settings-core.ps1'
BASE_MAIN_SIZE=284321
BASE_MAIN_SHA='af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
BASE_ADDON_SIZE=323385
BASE_ADDON_SHA='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
AUTHORIZED=['better-local-files','eternal-jukebox','ivLyrics','playlist-maker']

def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def bounds(t,n):
 m=re.search(rf'(?m)^function {re.escape(n)} \{{',t)
 if not m: raise RuntimeError(f'missing function {n}')
 nxt=re.search(r'(?m)^function [A-Za-z0-9_-]+ \{',t[m.end():]); e=m.end()+nxt.start() if nxt else len(t)
 return m.start(),e
def block(t,n):a,b=bounds(t,n);return t[a:b].rstrip()
def replace_func(t,n,new):a,b=bounds(t,n);return t[:a]+new.rstrip()+'\n\n'+t[b:].lstrip('\n')

def build_base():
 subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.28/build_v0628.py'),'--build'],cwd=ROOT)
 main=(BASE_OUT/'spotify-control.ps1').read_bytes(); addon=(BASE_OUT/'addon-manager.ps1').read_bytes()
 if (len(main),sha(main))!=(BASE_MAIN_SIZE,BASE_MAIN_SHA):raise RuntimeError('stable main rebuild drift')
 if (len(addon),sha(addon))!=(BASE_ADDON_SIZE,BASE_ADDON_SHA):raise RuntimeError('stable addon rebuild drift')
 return main,addon

def patch_addon(base:bytes)->bytes:
 bom=b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''; t=base[len(bom):].decode('utf-8')
 normalize=r'''function Normalize-AddonStateObject {
    param($State)
    if ($null -eq $State) { $State = [pscustomobject]@{} }
    [void](Ensure-ObjectNoteProperty -Object $State -Name "schema" -DefaultValue 2)
    if ([int]$State.schema -lt 2) { Set-ObjectNoteProperty -Object $State -Name "schema" -Value 2 }
    if ([int]$State.schema -gt 2) { throw "Unsupported future addon state schema: $($State.schema)" }
    [void](Ensure-ObjectNoteProperty -Object $State -Name "last_check" -DefaultValue $null)
    [void](Ensure-ObjectNoteProperty -Object $State -Name "last_backup" -DefaultValue $null)
    [void](Ensure-ObjectNoteProperty -Object $State -Name "last_update" -DefaultValue $null)
    [void](Ensure-ObjectNoteProperty -Object $State -Name "apps" -DefaultValue ([pscustomobject]@{}))
    [void](Ensure-ObjectNoteProperty -Object $State -Name "lifecycle" -DefaultValue ([pscustomobject]@{}))
    if ($null -eq $State.apps) { Set-ObjectNoteProperty -Object $State -Name "apps" -Value ([pscustomobject]@{}) }
    if ($null -eq $State.lifecycle) { Set-ObjectNoteProperty -Object $State -Name "lifecycle" -Value ([pscustomobject]@{}) }
    return $State
}'''
 t=replace_func(t,'Normalize-AddonStateObject',normalize)
 core=CORE.read_text(encoding='utf-8').strip()+'\n\n'
 anchor='function Test-Due {'
 if t.count(anchor)!=1:raise RuntimeError('core insertion anchor drift')
 t=t.replace(anchor,core+anchor,1)
 inv=block(t,'Get-AddonInventory')
 a='    $registrySummary = Add-AddonPolicyRegistryMetadata -Items $items.ToArray()'
 b="""    $dynamicObservations=@(Get-DynamicSpicetifyAssetObservations -CustomAppRoots $customAppRoots)
    $lifecycleSummary=Update-AddonLifecycleObservations -State $state -Observations $dynamicObservations -ObservedAt $now

    $registrySummary = Add-AddonPolicyRegistryMetadata -Items $items.ToArray()"""
 if inv.count(a)!=1:raise RuntimeError('inventory lifecycle anchor drift')
 inv=inv.replace(a,b,1)
 a='        policy_registry = $registrySummary\n        items = $items.ToArray()'
 b='        policy_registry = $registrySummary\n        dynamic_lifecycle = $lifecycleSummary\n        dynamic_observations = $dynamicObservations\n        items = $items.ToArray()'
 if inv.count(a)!=1:raise RuntimeError('inventory report anchor drift')
 inv=inv.replace(a,b,1);t=replace_func(t,'Get-AddonInventory',inv)
 ntx=block(t,'Normalize-PithayaTransaction')
 a='foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256","source_adapter_schema","source_adapter_sha256"))'
 b='foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256","source_adapter_schema","source_adapter_sha256","persistence_guard_schema","persistence_backup_path","persistence_before_fingerprint"))'
 if ntx.count(a)!=1:raise RuntimeError('transaction normalization anchor drift')
 ntx=ntx.replace(a,b,1);t=replace_func(t,'Normalize-PithayaTransaction',ntx)
 upd=block(t,'Update-AutoApps'); phase='    # Phase 1: pin and validate every remote payload before touching any live app.'
 if upd.count(phase)!=1:raise RuntimeError('update phase anchor drift')
 upd=upd.replace(phase,"    $persistenceGuard=New-RequiredSpotifyPersistenceBackup\n    Write-AddonLog (\"Created required exact persistence guard for managed update: {0}\" -f [string]$persistenceGuard.path)\n\n"+phase,1)
 old='$tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; source_adapter_schema=1; source_adapter_sha256=$sourceAdapterSha; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'
 new='$tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; source_adapter_schema=1; source_adapter_sha256=$sourceAdapterSha; persistence_guard_schema=1; persistence_backup_path=[string]$persistenceGuard.path; persistence_before_fingerprint=[string]$persistenceGuard.fingerprint; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'
 if upd.count(old)!=1:raise RuntimeError('transaction creation anchor drift')
 upd=upd.replace(old,new,1);t=replace_func(t,'Update-AutoApps',upd)
 rb=block(t,'Rollback-LastTransaction'); a='    $tx.status="rolled-back"; Set-ObjectNoteProperty -Object $tx -Name "rolled_back_at" -Value ((Get-Date).ToString("o"))'
 b="""    if([int]$tx.persistence_guard_schema -eq 1){
        if([string]::IsNullOrWhiteSpace([string]$tx.persistence_backup_path) -or [string]::IsNullOrWhiteSpace([string]$tx.persistence_before_fingerprint)){throw 'Persistence guard metadata is incomplete; retaining transaction for manual-safe recovery.'}
        $restored=Restore-SpotifyPersistenceBackup -BackupPath ([string]$tx.persistence_backup_path)
        if([string]$restored.fingerprint -cne [string]$tx.persistence_before_fingerprint){throw 'Rollback restored app trees but protected persistence fingerprint did not return to the pre-update identity.'}
        Write-AddonLog 'Rollback restored and verified protected Spotify/Spicetify persistence.' 'WARN'
    }
"""+a
 if rb.count(a)!=1:raise RuntimeError('rollback persistence anchor drift')
 rb=rb.replace(a,b,1);t=replace_func(t,'Rollback-LastTransaction',rb)
 cm=block(t,'Commit-LastTransaction');a='    $state=Load-AddonState'
 b="""    if([int]$tx.persistence_guard_schema -eq 1){
        $currentPersistence=Get-SpotifyPersistenceSnapshot
        if([string]$currentPersistence.fingerprint -cne [string]$tx.persistence_before_fingerprint){
            Write-AddonLog 'Protected Spotify/Spicetify persistence changed during managed update; rolling back code and persistence instead of committing.' 'ERROR'
            Rollback-LastTransaction
            throw 'Managed addon update was rolled back because protected persistence changed.'
        }
    }
"""+a
 if cm.count(a)!=1:raise RuntimeError('commit persistence anchor drift')
 cm=cm.replace(a,b,1);t=replace_func(t,'Commit-LastTransaction',cm)
 st=block(t,'Invoke-AddonSelfTest');a='    if ($errors.Count -gt 0) {'
 b="""    try { Invoke-LifecycleSettingsCoreSelfTest } catch { $errors.Add(\"Settings-preserving lifecycle core self-test failed: $($_.Exception.Message)\") }

"""+a
 if st.count(a)!=1:raise RuntimeError('selftest anchor drift')
 st=st.replace(a,b,1);t=replace_func(t,'Invoke-AddonSelfTest',st)
 return bom+t.encode('utf-8')

def validate(base:bytes,cand:bytes):
 b=base.decode('utf-8-sig').replace('\r\n','\n'); c=cand.decode('utf-8-sig').replace('\r\n','\n')
 reg=block(c,'Get-AddonPolicyRegistry'); auto=re.findall(r"name='([^']+)'.*?mutation_mode='auto'",reg,re.I)
 if sorted(x.lower() for x in auto)!=sorted(x.lower() for x in AUTHORIZED):raise RuntimeError(f'auto authority drift: {auto}')
 if block(b,'Get-AddonPolicyRegistry')!=reg:raise RuntimeError('policy registry changed')
 if block(b,'Get-AddonSourceAdapterCatalog')!=block(c,'Get-AddonSourceAdapterCatalog'):raise RuntimeError('source adapter catalog changed')
 for required in ('Get-DynamicSpicetifyAssetObservations','Update-AddonLifecycleObservations','Test-AddonLifecycleAutoInstallAllowed','New-RequiredSpotifyPersistenceBackup','Restore-SpotifyPersistenceBackup','persistence_before_fingerprint','dynamic_lifecycle'):
  if required not in c:raise RuntimeError('missing lifecycle/settings contract: '+required)
 for protected in ("name='tagify'","mutation_mode='deny'","protect-ratings-tags-notes","name='splitify'","name='star-ratings'","playlist-backed-ratings-preserve","name='sc-cover-ambience.js'","never-disable-or-optimize"):
  if protected.lower() not in reg.lower():raise RuntimeError('protected policy missing: '+protected)
 if 'New-RequiredSpotifyPersistenceBackup' not in block(c,'Update-AutoApps'):raise RuntimeError('required persistence guard not integrated into update')
 if 'Restore-SpotifyPersistenceBackup' not in block(c,'Rollback-LastTransaction'):raise RuntimeError('persistence restore not integrated into rollback')
 if 'Get-SpotifyPersistenceSnapshot' not in block(c,'Commit-LastTransaction'):raise RuntimeError('commit persistence guard missing')

def build():
 main,addon=build_base();cand=patch_addon(addon);validate(addon,cand);OUT.mkdir(parents=True,exist_ok=True)
 (OUT/'spotify-control.ps1').write_bytes(main);(OUT/'addon-manager.ps1').write_bytes(cand)
 report={'schema':1,'production_base':'d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2','stable_version':'0.6.28','stable_addon_version':'0.6.5-r17','base_main':{'size':len(main),'sha256':sha(main)},'base_addon':{'size':len(addon),'sha256':sha(addon)},'candidate_addon':{'size':len(cand),'sha256':sha(cand)},'authority_expanded':False,'auto_authority':AUTHORIZED,'features':['dynamic-spicetify-first-seen-delete-tombstone-reinstall-lifecycle','unknown-assets-default-mutation-deny','exact-protected-persistence-transaction-backup','commit-persistence-drift-fail-closed','rollback-code-plus-persistence-exact-restore'],'production_manifest_changed':False}
 REPORT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
 print('MARKETPLACE_LIFECYCLE_SETTINGS_CORE_BUILD_PASS',len(cand),sha(cand))

def main():
 p=argparse.ArgumentParser();p.add_argument('--build',action='store_true');a=p.parse_args()
 if not a.build:p.error('use --build')
 build()
if __name__=='__main__':main()
