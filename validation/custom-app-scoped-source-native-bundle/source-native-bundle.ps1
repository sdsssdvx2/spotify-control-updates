# V020 hosted-Windows-only SOURCE+XPUI bundle experiment.
# No production dispatcher; candidate bytes are intentionally synthetic,
# not a qualified signed remote source (provenance remains NO-GO).
function Get-CustomAppScopedBundlePathsV020 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$Context)
    [void](Assert-CustomAppScopedLabHostedV017 -Path ([string]$Session.paths.root))
    $id=[string]$Context.consumption_id
    if($id -cnotmatch '^[a-f0-9]{64}$'){throw 'scoped-bundle-consumption-id-invalid'}
    $dir=[string]$Session.paths.directory
    $stem='native-bundle-'+$id
    $parent=[IO.Path]::GetDirectoryName([string]$Context.source_index)
    $parent=[IO.Path]::GetDirectoryName($parent)
    $canonicalParent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$Context.source))
    if(-not[IO.Directory]::Exists($parent) -or
       -not[IO.Path]::GetFullPath($parent).Equals($canonicalParent,[StringComparison]::OrdinalIgnoreCase)){
        throw 'scoped-bundle-source-parent-not-canonical'
    }
    $temp=Join-Path $parent ('.'+$stem+'.source.tmp')
    $restore=Join-Path $parent ('.'+$stem+'.restore.tmp')
    $paths=[pscustomobject]@{
        sealed=(Join-Path $dir ($stem+'.dpapi'))
        intent=(Join-Path $dir ($stem+'.intent'))
        recovered=(Join-Path $dir ($stem+'.recovered'))
        swap_temp=$temp
        restore_temp=$restore
        swap_backup=(Join-Path $parent ('.'+$stem+'.swap.before.bak'))
        restore_backup=(Join-Path $parent ('.'+$stem+'.restore.candidate.bak'))
    }
    foreach($v in @($paths.sealed,$paths.intent,$paths.recovered,$paths.swap_temp,$paths.restore_temp,$paths.swap_backup,$paths.restore_backup)){
        Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$v)
    }
    return $paths
}
function Get-CustomAppScopedBundleEntropyV020 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$Context)
    return [Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|ScopedSourceAndXpui|V020|'+
      [string]$Session.paths.key+'|'+[string]$Context.consumption_id))
}
function Read-CustomAppScopedBundleV020 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [Parameter(Mandatory=$true)]$Context)
    $paths=Get-CustomAppScopedBundlePathsV020 -Session $Session -Context $Context
    $path=[string]$paths.sealed
    if(-not[IO.File]::Exists($path)){throw 'scoped-bundle-beforeimage-not-enrolled'}
    $cipher=[IO.File]::ReadAllBytes($path)
    if($cipher.Length -lt 128 -or $cipher.Length -gt 10485760){
        throw 'scoped-bundle-sealed-envelope-size-invalid'
    }
    $wrapped=New-Object byte[] ($cipher.Length-32)
    [Array]::Copy($cipher,32,$wrapped,0,$wrapped.Length)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$actual=$hash.ComputeHash($wrapped)}finally{$hash.Dispose()}
    for($i=0;$i -lt 32;$i++){
        if($actual[$i] -ne $cipher[$i]){throw 'scoped-bundle-ciphertext-sha-tampered'}
    }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=$null
    try{
        $plain=[Security.Cryptography.ProtectedData]::Unprotect(
          $wrapped,(Get-CustomAppScopedBundleEntropyV020 -Session $Session -Context $Context),
          [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $snap=([Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop)
    }finally{if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)}}
    if([long]$snap.schema -ne 1 -or
       [string]$snap.target -cne [string]$Context.target -or
       [string]$snap.consumption_id -cne [string]$Context.consumption_id -or
       [string]$snap.transaction_id -cne [string]$Context.transaction_id -or
       [string]$snap.nonce -cne [string]$Context.nonce -or
       [long]$snap.state_revision -ne [long]$Context.state_revision -or
       [string]$snap.source_path -cne [string]$Context.source_index -or
       [string]$snap.exe_sha256 -cne [string]$Context.exe_sha256 -or
       [string]$snap.config_sha256 -cne [string]$Context.config_sha256 -or
       [string]$snap.prepared_journal_sha256 -cnotmatch '^[0-9a-f]{64}$'){
        throw 'scoped-bundle-dpapi-identity-invalid'
    }
    $old=[Convert]::FromBase64String([string]$snap.before_base64)
    $new=[Convert]::FromBase64String([string]$snap.candidate_base64)
    if($old.Length -lt 1 -or $old.Length -gt 2097152 -or
       $new.Length -lt 1 -or $new.Length -gt 2097152 -or
       [string]$snap.before_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$snap.candidate_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$snap.before_sha256 -ceq [string]$snap.candidate_sha256 -or
       (Get-CustomAppScopedLabShaV017 -Bytes $old) -cne [string]$snap.before_sha256 -or
       (Get-CustomAppScopedLabShaV017 -Bytes $new) -cne [string]$snap.candidate_sha256){
        throw 'scoped-bundle-source-payload-invalid'
    }
    $xpui=Read-CustomAppScopedLabSnapshotV017 -Context $Context -Session $Session
    if([string]$xpui.source_sha256 -cne [string]$snap.before_sha256){
        throw 'scoped-bundle-xpui-snapshot-source-drift'
    }
    $phase=Get-CustomAppScopedLabJournalV018 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $Context
    if([long]$phase.revision -eq 0 -and
       [string]$phase.entry_sha256 -cne [string]$snap.prepared_journal_sha256){
        throw 'scoped-bundle-prepared-journal-anchor-drift'
    }
    return [pscustomobject]@{
        snapshot=$snap;before_bytes=$old;candidate_bytes=$new
        paths=$paths;journal=$phase
        sha256=(Get-CustomAppScopedLabShaV017 -Bytes $cipher)
        production_mutation_authorized=$false;production_execution_authorized=$false
    }
}
function Save-CustomAppScopedBundleV020 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [Parameter(Mandatory=$true)][string]$CandidateIndexPath,
          [Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot)
    $ctx=Get-CustomAppScopedLabContextV017 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    $state=Get-CustomAppScopedLabJournalV018 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $ctx
    if([long]$state.revision -ne 0 -or [string]$state.phase -cne 'prepared'){
        throw 'scoped-bundle-only-prepare-before-central-mutation'
    }
    $candidate=[IO.Path]::GetFullPath($CandidateIndexPath)
    if(-not$candidate.StartsWith(([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       -not[IO.File]::Exists($candidate) -or
       $candidate.StartsWith('\\')){
        throw 'scoped-bundle-synthetic-candidate-not-from-runner'
    }
    Assert-CustomAppUserTxnNoReparseV010 -Path $candidate
    $paths=Get-CustomAppScopedBundlePathsV020 -Session $Session -Context $ctx
    foreach($p in @($paths.sealed,$paths.intent,$paths.recovered,$paths.swap_temp,$paths.restore_temp,$paths.swap_backup,$paths.restore_backup)){
        if([IO.File]::Exists([string]$p)){throw 'scoped-bundle-duplicate-or-existing-intent'}
    }
    if(-not[IO.File]::Exists([string]$ctx.sealed_path)){
        throw 'scoped-bundle-requires-existing-v017-xpui-beforeimage'
    }
    $before=[IO.File]::ReadAllBytes([string]$ctx.source_index)
    $after=[IO.File]::ReadAllBytes($candidate)
    if($before.Length -lt 1 -or $before.Length -gt 2097152 -or
       $after.Length -lt 1 -or $after.Length -gt 2097152 -or
       (Get-CustomAppScopedLabShaV017 -Bytes $before) -ceq
         (Get-CustomAppScopedLabShaV017 -Bytes $after)){
        throw 'scoped-bundle-source-before-after-identical-or-unbounded'
    }
    $original=Read-CustomAppScopedLabSnapshotV017 -Session $Session -Context $ctx
    $beforeSha=Get-CustomAppScopedLabShaV017 -Bytes $before
    if([string]$original.source_sha256 -cne $beforeSha){throw 'scoped-bundle-original-xpui-source-not-locked'}
    $body=[ordered]@{
        schema=1;target=[string]$ctx.target
        transaction_id=[string]$ctx.transaction_id
        consumption_id=[string]$ctx.consumption_id
        nonce=[string]$ctx.nonce;state_revision=[long]$ctx.state_revision
        source_path=[string]$ctx.source_index
        exe_sha256=[string]$ctx.exe_sha256
        config_sha256=[string]$ctx.config_sha256
        prepared_journal_sha256=[string]$state.entry_sha256
        before_sha256=$beforeSha
        candidate_sha256=(Get-CustomAppScopedLabShaV017 -Bytes $after)
        before_base64=[Convert]::ToBase64String($before)
        candidate_base64=[Convert]::ToBase64String($after)
        signed_source_provenance_verified=$false
    }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $raw=[Text.Encoding]::UTF8.GetBytes(($body|ConvertTo-Json -Compress -Depth 7))
    try{
        $encrypted=[Security.Cryptography.ProtectedData]::Protect(
            $raw,(Get-CustomAppScopedBundleEntropyV020 -Session $Session -Context $ctx),
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
    }finally{[Array]::Clear($raw,0,$raw.Length)}
    $sum=[Security.Cryptography.SHA256]::Create()
    try{$digest=$sum.ComputeHash($encrypted)}finally{$sum.Dispose()}
    $output=New-Object byte[] ($encrypted.Length+32)
    [Array]::Copy($digest,0,$output,0,32)
    [Array]::Copy($encrypted,0,$output,32,$encrypted.Length)
    Write-CustomAppUserTxnBytesV010 -Path ([string]$paths.sealed) -Bytes $output
    $reloaded=Read-CustomAppScopedBundleV020 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $ctx
    if([string]$reloaded.snapshot.candidate_sha256 -cne [string]$body.candidate_sha256){
        throw 'scoped-bundle-durable-source-beforeimage-not-reloaded'
    }
    return [pscustomobject]@{
        ok=$true;context=$ctx;bundle=$reloaded
        signed_source_provenance_verified=$false
        mutation_intent_written=$false
        result_is_authority=$false
        production_execution_authorized=$false
        production_mutation_authorized=$false
    }
}


# A process which cannot even start must be rejected BEFORE the durable CAS
# barrier and before any source/XPUI mutation. Win32's lpCurrentDirectory has
# a MAX_PATH limit even on hosts with some long-path support; keep margin.
function Assert-CustomAppScopedBundleNativePathBudgetV020 {
    param([Parameter(Mandatory=$true)][string]$WorkingDirectory)
    $full=[IO.Path]::GetFullPath($WorkingDirectory).TrimEnd('\','/')
    if([string]::IsNullOrWhiteSpace($full) -or $full.Length -ge 248){
        throw 'scoped-bundle-pre-cas-working-directory-too-long'
    }
    return $full
}
function Assert-CustomAppScopedBundleNativePreflightV020 {
    param([Parameter(Mandatory=$true)]$Context,
          [Parameter(Mandatory=$true)]$Bundle,
          [Parameter(Mandatory=$true)][string]$HostedCiRoot)
    [void](Assert-CustomAppScopedLabHostedV017 -Path $HostedCiRoot)
    $clone=Assert-CustomAppScopedBundleNativePathBudgetV020 -WorkingDirectory ([string]$Context.scope_root)
    [void](Assert-CustomAppScopedLabHostedV017 -Path $clone)
    $config=Join-Path $clone 'config-xpui.ini'
    $source=Join-Path $clone ('CustomApps\'+[string]$Context.target+'\index.js')
    $backup=Join-Path $clone 'Backup\xpui.spa'
    foreach($path in @($config,$source,$backup,[string]$Context.executable_path,[string]$Context.config_path)){
        Assert-CustomAppUserTxnNoReparseV010 -Path $path
        if(-not[IO.File]::Exists($path)){throw 'scoped-bundle-pre-cas-native-file-missing'}
    }
    $official=Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$Context.executable_path)
    if($official -cne [string]$Context.exe_sha256 -or
       $official -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
        throw 'scoped-bundle-pre-cas-official-exe-drift'
    }
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$Context.config_path)) -cne
          [string]$Context.config_sha256){
        throw 'scoped-bundle-pre-cas-original-config-drift'
    }
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $source) -cne
       [string]$Bundle.snapshot.candidate_sha256){
        throw 'scoped-bundle-pre-cas-private-staged-source-drift'
    }
    $conf=[IO.File]::ReadAllText($config)
    if(-not$conf.Contains(('custom_apps = '+[string]$Context.target)) -or
       -not$conf.Contains('check_spicetify_update = false')){
        throw 'scoped-bundle-pre-cas-private-config-drift'
    }
    if((Get-Item -LiteralPath $backup).Length -gt 2097152){
        throw 'scoped-bundle-pre-cas-private-backup-out-of-bound'
    }
    return [pscustomobject]@{ok=$true;working_directory=$clone
       executable_sha256=$official;staged_sha256=[string]$Bundle.snapshot.candidate_sha256
       mutation_authorized=$false;production_execution_authorized=$false}
}

function Invoke-CustomAppScopedBundleNativeV020 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot)
    $ctx=Get-CustomAppScopedLabContextV017 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    $bundle=Read-CustomAppScopedBundleV020 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $ctx
    $j=$bundle.journal
    if([long]$j.revision -ne 0 -or [string]$j.phase -cne 'prepared' -or
       [IO.File]::Exists([string]$bundle.paths.intent) -or
       [IO.File]::Exists([string]$bundle.paths.recovered) -or
       [IO.File]::Exists([string]$ctx.intent_path) -or
       [IO.File]::Exists([string]$ctx.recovered_path)){
        throw 'scoped-bundle-not-a-fresh-prepared-transaction'
    }
    $before=Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)
    if($before -cne [string]$bundle.snapshot.before_sha256){
        throw 'scoped-bundle-live-original-source-drift-before-CAS'
    }
    $xpui=Read-CustomAppScopedLabSnapshotV017 -Context $ctx -Session $Session
    [void](Assert-CustomAppScopedLabOutsideUnchangedV017 -Context $ctx -Snapshot $xpui)
    $clone=[string]$ctx.scope_root
    [void](Assert-CustomAppScopedLabHostedV017 -Path $clone)
    $clonedSource=Join-Path $clone ('CustomApps\'+[string]$ctx.target+'\index.js')
    $clonedConfig=Join-Path $clone 'config-xpui.ini'
    $clonedBackup=Join-Path $clone 'Backup\xpui.spa'
    foreach($path in @($clonedSource,$clonedConfig,$clonedBackup)){
        Assert-CustomAppUserTxnNoReparseV010 -Path $path
        if(-not[IO.File]::Exists($path)){throw 'scoped-bundle-private-clone-not-complete'}
    }
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $clonedSource) -cne $before -or
       -not[IO.File]::ReadAllText($clonedConfig).Contains(
            ('custom_apps = '+[string]$ctx.target)) -or
       (Get-Item $clonedBackup).Length -gt 2097152){
        throw 'scoped-bundle-private-clone-source-or-config-drift'
    }
    # Disposable clone is NOT a user app and is staged before the CAS phase.
    $clonedHandle=$null
    try{
        $clonedHandle=[IO.File]::Open($clonedSource,[IO.FileMode]::Open,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $clonedHandle.SetLength(0)
        $clonedHandle.Write($bundle.candidate_bytes,0,$bundle.candidate_bytes.Length)
        $clonedHandle.Flush($true)
    }finally{if($null-ne$clonedHandle){$clonedHandle.Dispose()}}
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $clonedSource) -cne
       [string]$bundle.snapshot.candidate_sha256){
        throw 'scoped-bundle-candidate-private-clone-drift'
    }
    # Launch feasibility and exact official/private bytes are checked before
    # journal CAS, durable intent creation, or any live app source mutation.
    $preflight=Assert-CustomAppScopedBundleNativePreflightV020 -Context $ctx -Bundle $bundle -HostedCiRoot $HostedCiRoot
    if(-not[bool]$preflight.ok){throw 'scoped-bundle-pre-cas-native-preflight-denied'}
    Write-Host 'NATIVE_BUNDLE_V020_NATIVE_START_PREFLIGHT_BEFORE_CAS_PASS'
    if([IO.File]::Exists([string]$bundle.paths.swap_temp) -or
       [IO.File]::Exists([string]$bundle.paths.restore_temp) -or
       [IO.File]::Exists([string]$bundle.paths.swap_backup) -or
       [IO.File]::Exists([string]$bundle.paths.restore_backup)){
        throw 'scoped-bundle-temp-path-reused-before-mutation'
    }
    # The stage temp is in the SOURCE'S PARENT (same volume) so the following
    # File.Replace can change only the enrolled index.js atomically.
    $handle=$null
    try{
        $handle=[IO.File]::Open([string]$bundle.paths.swap_temp,
             [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $handle.Write($bundle.candidate_bytes,0,$bundle.candidate_bytes.Length)
        $handle.Flush($true)
    }finally{if($null-ne$handle){$handle.Dispose()}}
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$bundle.paths.swap_temp)) -cne
       [string]$bundle.snapshot.candidate_sha256){
        throw 'scoped-bundle-staged-source-sha-drift'
    }
    # All admissible effects must appear AFTER this journal CAS barrier.
    $started=Move-CustomAppScopedLabJournalV018 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $ctx -NextPhase 'atomic-mutation-starting'
    $nativeBefore=[IO.File]::ReadAllBytes([string]$ctx.sealed_path)
    $nativeSha=Get-CustomAppScopedLabShaV017 -Bytes $nativeBefore
    $marker=[Text.Encoding]::ASCII.GetBytes(('V018_INTENT_SHA256='+$nativeSha+'|FIRST_JOURNAL_SHA256='+[string]$started.entry_sha256+[Environment]::NewLine))
    Write-CustomAppUserTxnBytesV010 -Path ([string]$ctx.intent_path) -Bytes $marker
    $bundleIntent=[Text.Encoding]::ASCII.GetBytes(('V020_BUNDLE_INTENT_SHA256='+[string]$bundle.sha256+'|FIRST_JOURNAL_SHA256='+[string]$started.entry_sha256+[Environment]::NewLine))
    Write-CustomAppUserTxnBytesV010 -Path ([string]$bundle.paths.intent) -Bytes $bundleIntent
    # Crash after the journal CAS but before either intent is ambiguous:
    # worker MUST reject missing markers without changing source or XPUI.
    [IO.File]::Replace([string]$bundle.paths.swap_temp,[string]$ctx.source_index,[string]$bundle.paths.swap_backup)
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$bundle.paths.swap_backup)) -cne [string]$bundle.snapshot.before_sha256){
        throw 'scoped-bundle-atomic-original-source-backup-drift'
    }
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)) -cne
       [string]$bundle.snapshot.candidate_sha256){
        throw 'scoped-bundle-atomic-live-source-swap-not-verified'
    }
    Write-Host 'NATIVE_BUNDLE_V020_ATOMIC_SOURCE_SWAPPED_AFTER_DURABLE_V010_CAS_PASS'
    # Genuine pinned vendor execution (never through user system, all hosted).
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=[string]$ctx.executable_path
    $psi.Arguments='--bypass-admin -n -a refresh'
    $psi.WorkingDirectory=$clone
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$false
    $psi.RedirectStandardError=$false
    $psi.EnvironmentVariables['SPICETIFY_CONFIG']=$clone
    $psi.EnvironmentVariables['SPICETIFY_STATE']=$clone
    $psi.EnvironmentVariables['APPDATA']=[string]$HostedCiAppDataRoot
    $psi.EnvironmentVariables['LOCALAPPDATA']=[string]$HostedCiLocalAppDataRoot
    $child=New-Object Diagnostics.Process
    try{
        $child.StartInfo=$psi
        if(-not$child.Start()){throw 'scoped-bundle-vendor-process-start-failed'}
        if(-not$child.WaitForExit(60000)){
            $child.Kill();[void]$child.WaitForExit()
            throw 'scoped-bundle-vendor-execution-timeout-recovery-required'
        }
        $code=[int]$child.ExitCode
    }finally{$child.Dispose()}
    if($code -ne 0){throw ('scoped-bundle-vendor-exit-nonzero-'+$code)}
    [void](Assert-CustomAppScopedLabOutsideUnchangedV017 -Context $ctx -Snapshot $xpui)
    $expectedOutput=Join-Path ([string]$ctx.xpui) ('spicetify-routes-'+[string]$ctx.target+'.js')
    if(-not[IO.File]::Exists($expectedOutput) -or
       -not[IO.File]::ReadAllText($expectedOutput).Contains(
            [Text.Encoding]::UTF8.GetString($bundle.candidate_bytes)) -or
       (Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)) -cne
            [string]$bundle.snapshot.candidate_sha256){
        throw 'scoped-bundle-vendor-zero-without-exact-source-and-output'
    }
    $final=Get-CustomAppScopedLabJournalV018 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $ctx
    if([string]$final.phase -cne 'atomic-mutation-starting' -or [long]$final.revision -ne 1){
        throw 'scoped-bundle-native-effect-with-incorrect-journal-phase'
    }
    Write-Host 'NATIVE_BUNDLE_V020_REAL_OFFICIAL_XPUI_AND_SOURCE_BOTH_CHANGED_PASS'
    return [pscustomobject]@{
        ok=$true;source_changed=$true;xpui_changed=$true
        recovery_required=$true;journal_phase=[string]$final.phase
        signed_source_provenance_verified=$false
        result_is_authority=$false;production_execution_authorized=$false
        production_mutation_authorized=$false
    }
}


function Restore-CustomAppScopedBundleV020 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot,
          [switch]$HostedCiExitAfterSourceRestore)
    $ctx=Get-CustomAppScopedLabContextV017 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    $bundle=Read-CustomAppScopedBundleV020 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $ctx
    $xpui=Read-CustomAppScopedLabSnapshotV017 -Context $ctx -Session $Session
    [void](Assert-CustomAppScopedLabOutsideUnchangedV017 -Context $ctx -Snapshot $xpui)
    $phase=$bundle.journal
    if([long]$phase.revision -notin @(1,2,3) -or
       [string]$phase.phase -notin @('atomic-mutation-starting','rollback-required','rollback-complete')){
        throw 'scoped-bundle-journal-not-eligible-for-independent-recovery'
    }
    $first=Get-CustomAppScopedLabFirstMutationEntryV018 -Journal $phase
    if(-not[IO.File]::Exists([string]$bundle.paths.intent) -or
       -not[IO.File]::Exists([string]$ctx.intent_path)){
        throw 'scoped-bundle-source-or-XPUI-intent-missing-after-CAS'
    }
    $bundleIntent='V020_BUNDLE_INTENT_SHA256='+[string]$bundle.sha256+'|FIRST_JOURNAL_SHA256='+$first+[Environment]::NewLine
    $actualBundle=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes([string]$bundle.paths.intent))
    $v017Seal=[IO.File]::ReadAllBytes([string]$ctx.sealed_path)
    $nativeIntent='V018_INTENT_SHA256='+(Get-CustomAppScopedLabShaV017 -Bytes $v017Seal)+'|FIRST_JOURNAL_SHA256='+$first+[Environment]::NewLine
    $actualNative=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes([string]$ctx.intent_path))
    if($actualBundle -cne $bundleIntent -or $actualNative -cne $nativeIntent){
        throw 'scoped-bundle-intent-not-bound-to-two-durable-preimages-and-journal'
    }
    $now=Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)
    if($now -cne [string]$bundle.snapshot.before_sha256 -and
       $now -cne [string]$bundle.snapshot.candidate_sha256){
        throw 'scoped-bundle-live-source-unexpected-unowned-change'
    }
    if([string]$phase.phase -ceq 'rollback-complete' -and
       $now -cne [string]$bundle.snapshot.before_sha256){
        throw 'scoped-bundle-source-not-restored-while-journal-terminal'
    }
    if([IO.File]::Exists([string]$bundle.paths.recovered) -and
       [string]$phase.phase -cne 'rollback-complete'){
        throw 'scoped-bundle-early-terminal-marker-before-journal-complete'
    }
    if([string]$phase.phase -ceq 'atomic-mutation-starting'){
        # This journal CAS MUST be durable before source or XPUI rollback effects.
        $phase=Move-CustomAppScopedLabJournalV018 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $ctx -NextPhase 'rollback-required'
    }
    if([string]$phase.phase -ceq 'rollback-required' -and
       $now -ceq [string]$bundle.snapshot.candidate_sha256){
        # Repeated recovery is safe across crashes: a verified old-source
        # temporary file is either completed or rewritten in this exact
        # private transaction-pinned sibling path.
        Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$bundle.paths.restore_temp)
        $f=$null
        try{
            $f=[IO.File]::Open([string]$bundle.paths.restore_temp,
                [IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $f.SetLength(0)
            $f.Write($bundle.before_bytes,0,$bundle.before_bytes.Length)
            $f.Flush($true)
        }finally{if($null-ne$f){$f.Dispose()}}
        if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$bundle.paths.restore_temp)) -cne
           [string]$bundle.snapshot.before_sha256){
            throw 'scoped-bundle-old-source-recovery-file-sha-invalid'
        }
        [IO.File]::Replace([string]$bundle.paths.restore_temp,[string]$ctx.source_index,[string]$bundle.paths.restore_backup)
        if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$bundle.paths.restore_backup)) -cne [string]$bundle.snapshot.candidate_sha256){
            throw 'scoped-bundle-candidate-before-rollback-backup-drift'
        }
        $now=Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)
        if($now -cne [string]$bundle.snapshot.before_sha256){
            throw 'scoped-bundle-source-rollback-not-byte-exact'
        }
        Write-Host 'NATIVE_BUNDLE_V020_ORIGINAL_SOURCE_BYTE_EXACT_RECOVERED_PASS'
        if($HostedCiExitAfterSourceRestore){
            # Inject actual process kill AFTER source rollback, BEFORE XPUI rollback.
            [Environment]::Exit(74)
        }
    }
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)) -cne
       [string]$bundle.snapshot.before_sha256){
        throw 'scoped-bundle-source-beforeimage-not-restored-before-native-recovery'
    }
    # V018 is now safely reusable; it validates every protected XPUI file and
    # persists rollback-complete through the existing V010 journal CAS.
    $native=Restore-CustomAppScopedLabNativeV017 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    if(-not[bool]$native.ok -or
       [bool]$native.production_mutation_authorized){
        throw 'scoped-bundle-native-rollback-not-complete'
    }
    $final=Get-CustomAppScopedLabJournalV018 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -Context $ctx
    if([string]$final.phase -cne 'rollback-complete' -or [long]$final.revision -ne 3 -or
       (Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)) -cne
         [string]$bundle.snapshot.before_sha256){
        throw 'scoped-bundle-source-and-xpui-not-durably-reconciled'
    }
    # Exact transaction-owned backup files, verified before cleanup. This is
    # safe and repeatable even if this worker crashes before terminal receipt.
    foreach($record in @(
        [pscustomobject]@{path=[string]$bundle.paths.swap_backup;sha=[string]$bundle.snapshot.before_sha256},
        [pscustomobject]@{path=[string]$bundle.paths.restore_backup;sha=[string]$bundle.snapshot.candidate_sha256}
    )){
        Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$record.path)
        if([IO.File]::Exists([string]$record.path)){
            if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$record.path)) -cne [string]$record.sha){
                throw 'scoped-bundle-private-source-swap-backup-not-authentic'
            }
            [IO.File]::Delete([string]$record.path)
        }
    }
    $receipt='V020_SOURCE_AND_XPUI_RECOVERED='+[string]$ctx.transaction_id+'|JOURNAL_SHA256='+[string]$final.entry_sha256+[Environment]::NewLine
    $repeated=[IO.File]::Exists([string]$bundle.paths.recovered)
    if($repeated){
        if([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes([string]$bundle.paths.recovered)) -cne
           $receipt){throw 'scoped-bundle-terminal-receipt-corrupted'}
    }else{
        Write-CustomAppUserTxnBytesV010 -Path ([string]$bundle.paths.recovered) -Bytes ([Text.Encoding]::ASCII.GetBytes($receipt))
    }
    Write-Host 'NATIVE_BUNDLE_V020_JOURNALED_SOURCE_AND_XPUI_RECOVERY_COMPLETE_PASS'
    return [pscustomobject]@{
        ok=$true;source_restored_exact=$true;xpui_restored_exact=$true
        journal_phase='rollback-complete';replay_idempotent=$repeated
        signed_source_provenance_verified=$false;result_is_authority=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Invoke-CustomAppScopedBundleIndependentRecoveryV020 {
    param([Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot,
          [switch]$HostedCiExitAfterSourceRestore)
    [void](Assert-CustomAppScopedLabHostedV017 -Path $HostedCiRoot)
    $global=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $HostedCiRoot
    try{
        $audit=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $HostedCiRoot -HeldCrossEngineSession $global
        if(-not[bool]$audit.ok -or [int]$audit.inspected_count -ne 1 -or
           [int]$audit.active_count -ne 1 -or @($audit.items).Count -ne 1){
            throw 'scoped-bundle-restart-ambiguous-DPAPI-active-source'
        }
        $src=$audit.items[0].source
        $name=[string]$src.name;$live=[string]$src.live
        $paths=if([IO.Directory]::Exists($live)){
            Get-CustomAppUserTxnPathsV010 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
        }else{
            Get-CustomAppUserTxnMissingLivePathsV011 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
        }
        $held=$null
        try{
            Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$paths.lock)
            if(-not[IO.File]::Exists([string]$paths.lock)){
                throw 'scoped-bundle-restart-existing-per-app-lock-required'
            }
            $held=[IO.File]::Open([string]$paths.lock,[IO.FileMode]::Open,
                [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            $state=Read-CustomAppUserTxnStateV010 -Paths $paths
            if($null-eq$state.active -or
               [string]$state.active.consumption_id -cne [string]$src.consumption_id -or
               [string]$state.active.transaction_id -cne [string]$src.transaction_id -or
               [string]$state.active.nonce -cne [string]$src.nonce -or
               [long]$state.revision -ne [long]$src.state_revision){
                throw 'scoped-bundle-restart-current-state-identity-drift'
            }
            $session=[pscustomobject]@{
                ok=$true;paths=$paths;state=$state;lock_handle=$held
                production_execution_authorized=$false;production_mutation_authorized=$false
            }
            return Restore-CustomAppScopedBundleV020 -Session $session -HeldCrossEngineSession $global -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot -HostedCiExitAfterSourceRestore:$HostedCiExitAfterSourceRestore
        }finally{if($null-ne$held){$held.Dispose()}}
    }finally{
        if($null-ne$global -and $null-ne$global.lock_handle){$global.lock_handle.Dispose()}
    }
}
function Test-CustomAppScopedBundleSelfTestV020 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'scoped-bundle-must-not-enable-fullchain'
    }
    foreach($name in @('Get-CustomAppScopedBundlePathsV020',
      'Read-CustomAppScopedBundleV020','Save-CustomAppScopedBundleV020',
      'Invoke-CustomAppScopedBundleNativeV020','Restore-CustomAppScopedBundleV020',
      'Invoke-CustomAppScopedBundleIndependentRecoveryV020')){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('scoped-bundle-missing-inert-function-'+$name)
        }
    }
    Write-Host 'NATIVE_BUNDLE_V020_EXPERIMENT_SELFTEST_PASS hosted_only=true unsigned_candidate_not_accepted_in_production=true'
}
