# V044 focused extension+asset manifest acceptance using the V043 pinned
# official CLI/fallback fixture. No original Addon Manager rebuild required.
param([Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\approved-installed-xpui-readonly\test-official-fallback-refresh-v043.ps1') -OfficialExecutable $OfficialExecutable
. (Join-Path $PSScriptRoot 'manifest-owned-xpui-v044.ps1')
function Assert-V044([bool]$ok,[string]$why){if(-not$ok){throw ('V044_TEST_'+$why)}}
function Denied-V044([scriptblock]$Callback){
 try{& $Callback|Out-Null;return $false}catch{return $true}
}
$selected=Join-Path $cliApps $targetName
$aux=Join-Path $selected 'runtime'
$ext=Join-Path $selected 'extensions'
$img=Join-Path $selected 'assets\images'
$icons=Join-Path $img 'icons'
$assetDir=Join-Path $selected 'assets'
foreach($p in @($aux,$ext,$img,$icons)){[IO.Directory]::CreateDirectory($p)|Out-Null}
$helper=Join-Path $aux 'extra.js'
$extensionSource=Join-Path $ext 'dedicated.js'
$logo=Join-Path $img 'logo.svg'
$icon=Join-Path $icons 'icon.svg'
$identity=Join-Path $assetDir 'identity.txt'
[IO.File]::WriteAllText($helper,'const V044_BUNDLED_AUX_HELPER=true;')
[IO.File]::WriteAllText($extensionSource,'const V044_EXTENSION_PRIVATE_OWNER=true;')
[IO.File]::WriteAllText($logo,'<svg id="V044_LOGO"/>')
[IO.File]::WriteAllText($icon,'<svg id="V044_ICON"/>')
[IO.File]::WriteAllText($identity,'V044_IDENTITY_ASSET')
$manifestPath=Join-Path $selected 'manifest.json'
$manifest='{"name":"better-local-files","subfiles":["runtime/extra.js"],"subfiles_extension":["extensions/dedicated.js"],"assets":["assets/images/*","assets/identity.txt"]}'
[IO.File]::WriteAllText($manifestPath,$manifest,[Text.UTF8Encoding]::new($false))
$nativeBefore=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$scoped=Get-ApprovedNativeManifestOwnedScopeV044 -Name $targetName -SourceAppPath $selected
Assert-V044 ($scoped.output_scope_determined_by_official_2464_manifest -and
 @($scoped.owned_files).Count -eq 7 -and
 [int]$scoped.declared_extensions -eq 1 -and
 [int]$scoped.declared_asset_files -eq 3 -and
 [string]$scoped.manifest_sha256 -cmatch '^[a-f0-9]{64}$') 'SOURCE_MANIFEST_SCOPE_NOT_DERIVED_FROM_REAL_FIELDS'
$pin=[string]$scoped.source_tree_sha256
$foreignFiles=@($foreign|ForEach-Object{Join-Path $xpui $_})
$foreignDigest=@{}
foreach($f in @($foreignFiles)){$foreignDigest[$f]=(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash}
$unknownSource=Join-Path $cliApps 'some-unmanaged-app\index.js'
$unknownSourceHash=(Get-FileHash $unknownSource -Algorithm SHA256).Hash
$parentConfigHash=(Get-FileHash $config -Algorithm SHA256).Hash
$prefsHash=(Get-FileHash $prefs -Algorithm SHA256).Hash
$proc2=New-Object Diagnostics.Process
try{
 $proc2.StartInfo=$psi
 if(-not$proc2.Start()){throw 'V044_OFFICIAL_VENDOR_NOT_STARTED'}
 if(-not$proc2.WaitForExit(60000)){
   $proc2.Kill();[void]$proc2.WaitForExit()
   throw 'V044_OFFICIAL_VENDOR_TIMEOUT'
 }
 if($proc2.ExitCode -ne 0){throw ('V044_PINNED_VENDOR_EXIT_'+$proc2.ExitCode)}
}finally{$proc2.Dispose()}
$nativeAfter=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$proof=Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $nativeBefore -After $nativeAfter -Name $targetName -SourceAppPath $selected -ExpectedSourceTreeSha256 $pin
Assert-V044 ($proof.ok -and $proof.foreign_xpui_preserved -and
 $proof.scoped_file_count -eq 7 -and $proof.scoped_extension_files -eq 1 -and
 $proof.scoped_asset_files -eq 3 -and -not[bool]$proof.production_mutation_authorized) 'OFFICIAL_EXTRA_FILES_NOT_CORRECTLY_CONSTRAINED'
$owned=@(
 @{output=('spicetify-routes-'+$targetName+'.json');source=$manifestPath},
 @{output=('extensions/'+$targetName+'/dedicated.js');source=$extensionSource},
 @{output=('assets/'+$targetName+'/assets/images/logo.svg');source=$logo},
 @{output=('assets/'+$targetName+'/assets/images/icons/icon.svg');source=$icon},
 @{output=('assets/'+$targetName+'/assets/identity.txt');source=$identity}
)
foreach($pair in $owned){
 $xpuiFile=Join-Path $xpui (($pair.output).Replace('/','\'))
 Assert-V044 ([IO.File]::Exists($xpuiFile) -and
  (Get-FileHash -LiteralPath $xpuiFile -Algorithm SHA256).Hash -ceq
  (Get-FileHash -LiteralPath $pair.source -Algorithm SHA256).Hash) 'REAL_OFFICIAL_COPIED_ASSET_OR_EXTENSION_BYTES_NOT_EQUAL'
}
$js=Join-Path $xpui ('spicetify-routes-'+$targetName+'.js')
Assert-V044 ([IO.File]::ReadAllText($js).Contains('V044_BUNDLED_AUX_HELPER')) 'EXTRA_JS_SUBFILE_NOT_BUNDLED'
foreach($f in @($foreignFiles)){
 Assert-V044 ((Get-FileHash $f -Algorithm SHA256).Hash -ceq [string]$foreignDigest[$f]) 'FOREIGN_APPROVED_OR_UNMANAGED_XPUI_CHANGED'
}
Assert-V044 ((Get-FileHash $unknownSource -Algorithm SHA256).Hash -ceq $unknownSourceHash -and
 (Get-FileHash $config -Algorithm SHA256).Hash -ceq $parentConfigHash -and
 (Get-FileHash $prefs -Algorithm SHA256).Hash -ceq $prefsHash) 'UNMANAGED_SOURCE_OR_ORIGINAL_CONFIG_PREFS_CHANGED'
Assert-V044 (Denied-V044 {Test-ApprovedNativeXpuiOnlyOwnedTargetChangedV035 -Before $nativeBefore -After $nativeAfter -Name $targetName}) 'OLD_FIXED_FOUR_FILE_GUARD_MISCLAIMED_ASSET_OUTPUT'
Write-Host 'V044_PINNED_OFFICIAL_CLI_MANIFEST_SUBFILES_EXTENSION_AND_ASSETS_PASS'
Write-Host 'V044_NESTED_GLOB_ASSET_AND_EXTENSION_BYTES_EXACTLY_COPIED_PASS'
Write-Host 'V044_UNMANAGED_APP_AND_OTHER_APPROVED_XPUI_UNCHANGED_PASS'
Write-Host 'V044_V035_OLD_FIXED_OUTPUT_GUARD_NOT_SILENTLY_PROMOTED_PASS'
# Negative 1: an unexpected file in XPUI outside exact manifest ownership
# must fail even though the requested app's generated files all exist.
$foreignExtra=Join-Path $xpui 'assets\some-unmanaged-app\intrusion.dat'
[IO.Directory]::CreateDirectory((Split-Path -Parent $foreignExtra))|Out-Null
[IO.File]::WriteAllText($foreignExtra,'V044_FOREIGN_INTRUSION')
$bad=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
Assert-V044 (Denied-V044 {Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $nativeBefore -After $bad -Name $targetName -SourceAppPath $selected -ExpectedSourceTreeSha256 $pin}) 'UNDECLARED_FOREIGN_XPUI_OUTPUT_ALLOWED'
[IO.Directory]::Delete((Split-Path -Parent $foreignExtra),$true)
# Negative 2: even an allowed copied asset whose bytes differ from the
# manifest-approved source must fail before it can be sealed as official.
$assetOut=Join-Path $xpui ('assets\'+$targetName+'\assets\identity.txt')
$assetOld=[IO.File]::ReadAllBytes($assetOut)
[IO.File]::AppendAllText($assetOut,'V044_TAMPER')
$bad=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
Assert-V044 (Denied-V044 {Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $nativeBefore -After $bad -Name $targetName -SourceAppPath $selected -ExpectedSourceTreeSha256 $pin}) 'COPIED_ASSET_BYTES_NOT_AUTHENTICATED'
[IO.File]::WriteAllBytes($assetOut,$assetOld)
# Negative 3: manifest or source changed AFTER preflight, while XPUI bytes
# remain same, must refuse; we never re-bless a changed staged source.
$helperOld=[IO.File]::ReadAllBytes($helper)
[IO.File]::AppendAllText($helper,'V044_AFTER_PREFLIGHT_CHANGED')
Assert-V044 (Denied-V044 {Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $nativeBefore -After $nativeAfter -Name $targetName -SourceAppPath $selected -ExpectedSourceTreeSha256 $pin}) 'CHANGED_STAGED_SOURCE_PASSED_ADMISSION'
[IO.File]::WriteAllBytes($helper,$helperOld)
# Negative 4: reject manifest traversal before evaluating any glob.
$oldManifest=[IO.File]::ReadAllBytes($manifestPath)
[IO.File]::WriteAllText($manifestPath,'{"subfiles":["../private.js"],"subfiles_extension":[],"assets":[]}')
Assert-V044 (Denied-V044 {Get-ApprovedNativeManifestOwnedScopeV044 -Name $targetName -SourceAppPath $selected}) 'MANIFEST_TRAVERSAL_ALLOWED'
[IO.File]::WriteAllText($manifestPath,'{"subfiles":[],"subfiles_extension":["extensions/../dedicated.js"],"assets":[]}')
Assert-V044 (Denied-V044 {Get-ApprovedNativeManifestOwnedScopeV044 -Name $targetName -SourceAppPath $selected}) 'EXTENSION_TRAVERSAL_ALLOWED'
[IO.File]::WriteAllText($manifestPath,'{"subfiles":[],"subfiles_extension":[],"assets":["assets/images/**/*.svg"]}')
Assert-V044 (Denied-V044 {Get-ApprovedNativeManifestOwnedScopeV044 -Name $targetName -SourceAppPath $selected}) 'UNBOUNDED_ASSET_GLOB_ALLOWED'
[IO.File]::WriteAllBytes($manifestPath,$oldManifest)
# Negative 5: basename-colliding extension sources cannot both claim one
# generated destination, even when both source files really exist.
[IO.Directory]::CreateDirectory((Join-Path $selected 'other'))|Out-Null
[IO.File]::WriteAllText((Join-Path $selected 'other\dedicated.js'),'DUPLICATE_TARGET')
[IO.File]::WriteAllText($manifestPath,'{"subfiles":[],"subfiles_extension":["extensions/dedicated.js","other/dedicated.js"],"assets":[]}')
Assert-V044 (Denied-V044 {Get-ApprovedNativeManifestOwnedScopeV044 -Name $targetName -SourceAppPath $selected}) 'EXTENSION_BASENAME_COLLISION_ACCEPTED'
[IO.File]::WriteAllBytes($manifestPath,$oldManifest)
Assert-V044 (Denied-V044 {Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $nativeBefore -After (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui) -Name $targetName -SourceAppPath $selected -ExpectedSourceTreeSha256 $pin}) 'EXTRA_SOURCE_FILE_NOT_DENIED_AFTER_RESTORED_MANIFEST'
# Remove only this disposable fixture directory to re-establish source pin.
[IO.Directory]::Delete((Join-Path $selected 'other'),$true)
$restored=Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $nativeBefore -After (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui) -Name $targetName -SourceAppPath $selected -ExpectedSourceTreeSha256 $pin
Assert-V044 ([bool]$restored.ok -and [string]$restored.source_tree_sha256 -ceq $pin) 'CLEAN_SOURCE_AND_NATIVE_SCOPE_CANNOT_REVERIFY'
Write-Host 'V044_TRAVERSAL_GLOB_COLLISION_SOURCE_RACE_AND_FOREIGN_OUTPUT_DENIED_PASS'
Write-Host 'V044_MANIFEST_SCOPED_OUTPUT_FRESH_READBACK_IDEMPOTENT_PASS'
Write-Host 'V044_NO_USER_SPOTIFY_NO_PRODUCTION_AUTHORITY_NO_BACKUP_DELETION_PASS'
