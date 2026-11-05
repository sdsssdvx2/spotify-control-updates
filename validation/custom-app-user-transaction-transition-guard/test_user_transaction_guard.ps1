param([ValidateSet('bootstrap','restart','contend')][string]$Phase='bootstrap')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $PSScriptRoot '../custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $PSScriptRoot 'user-transaction-guard.ps1')
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows') { throw 'HOSTED_WINDOWS_ONLY' }
$base=Join-Path $env:RUNNER_TEMP ('custom-user-guard-e2e-'+$env:GITHUB_RUN_ID)
$root=Join-Path $base 'AppData-Local'
$live=Join-Path $base 'Live-Tagify'
$id='a'*64;$tx='b'*64;$nonce='c'*32
function Must-Fail([scriptblock]$work,[string]$label) {
    $failed=$false
    try { & $work | Out-Null } catch { $failed=$true }
    if(-not $failed) { throw ('EXPECTED_FAIL_OPEN:'+ $label) }
}
if($Phase -eq 'bootstrap') {
    [IO.Directory]::CreateDirectory($root)|Out-Null
    [IO.Directory]::CreateDirectory($live)|Out-Null
    Must-Fail { Open-CustomAppUserTxnStoreV010 -Name '../escape' -LivePath $live -HostedCiRoot $root -Initialize } 'bad-name'
    Must-Fail { Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot 'C:\' -Initialize } 'arbitrary-root'
    Must-Fail { Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root } 'undeclared-enrollment'
    $s=Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root -Initialize
    try {
        if([long]$s.state.revision -ne 0 -or $null -ne $s.state.active) { throw 'INITIAL_STATE_INVALID' }
        if([bool]$s.production_mutation_authorized -or [bool]$s.production_execution_authorized) { throw 'PRODUCTION_AUTHORITY_ESCAPED' }
        $a=[IO.Directory]::GetAccessControl([string]$s.paths.directory)
        if(-not $a.AreAccessRulesProtected) { throw 'STORAGE_ACL_INHERITED' }
        Must-Fail { Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root } 'double-lock-same-process'
        $child=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Phase contend 2>&1 | Out-String
        if($LASTEXITCODE -ne 0 -or -not $child.Contains('CROSS_PROCESS_EXCLUSIVE_LOCK_PASS')) { throw ('CROSS_PROCESS_LOCK_NOT_PROVEN:'+ $child) }
        $illegal=($s.state|ConvertTo-Json -Depth 8|ConvertFrom-Json)
        $illegal.revision=[long]1
        $illegal.updated_utc=[DateTimeOffset]::UtcNow.ToString('o')
        $illegal.consumed=@($id)
        Must-Fail { Save-CustomAppUserTxnStoreV010 -Session $s -NextState $illegal } 'raw-ledger-injection-before-reservation'
        $illegal=($s.state|ConvertTo-Json -Depth 8|ConvertFrom-Json)
        $illegal.revision=[long]1
        $illegal.updated_utc=[DateTimeOffset]::UtcNow.ToString('o')
        $illegal.name='different-name'
        $illegal.active=[pscustomobject]@{consumption_id=$id;transaction_id=$tx;nonce=$nonce;state='reserved';created_utc=$illegal.updated_utc}
        Must-Fail { Save-CustomAppUserTxnStoreV010 -Session $s -NextState $illegal } 'raw-identity-injection-before-reservation'
        Must-Fail { Reserve-CustomAppUserTxnIdV010 -Session $s -ConsumptionId $id -TransactionId $tx -Nonce $nonce -HostedCiInterruptBeforeReplace } 'interrupted-pending-write'
        if(-not[IO.File]::Exists($s.paths.pending) -or [long](Read-CustomAppUserTxnStateV010 $s.paths).revision -ne 0) { throw 'UNCOMMITTED_PENDING_WAS_PROMOTED' }
    } finally { $s.lock_handle.Dispose() }
    $s=Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root
    try {
        if([IO.File]::Exists($s.paths.pending)) { throw 'PENDING_NOT_RECONCILED' }
        $r=Reserve-CustomAppUserTxnIdV010 -Session $s -ConsumptionId $id -TransactionId $tx -Nonce $nonce
        if(-not[bool]$r.ok -or [long]$r.revision -ne 1 -or -not[bool]$r.active) { throw 'DURABLE_RESERVATION_FAILED' }
        Must-Fail { Reserve-CustomAppUserTxnIdV010 -Session $s -ConsumptionId ('d'*64) -TransactionId $tx -Nonce $nonce } 'active-must-recover'
        $originalHash=(Get-FileHash -LiteralPath $s.paths.state -Algorithm SHA256).Hash
        $clear=($s.state|ConvertTo-Json -Depth 8|ConvertFrom-Json)
        $clear.revision=[long]$clear.revision+1
        $clear.updated_utc=[DateTimeOffset]::UtcNow.ToString('o')
        $clear.active=$null
        $clear.consumed=@($id)
        Must-Fail { Save-CustomAppUserTxnStoreV010 -Session $s -NextState $clear } 'fake-terminal-or-premature-consumption'
        $rotate=($s.state|ConvertTo-Json -Depth 8|ConvertFrom-Json)
        $rotate.revision=[long]$rotate.revision+1
        $rotate.updated_utc=[DateTimeOffset]::UtcNow.ToString('o')
        $rotate.active.consumption_id=('d'*64)
        Must-Fail { Save-CustomAppUserTxnStoreV010 -Session $s -NextState $rotate } 'replace-immutable-active-claim'
        $unchanged=(Get-FileHash -LiteralPath $s.paths.state -Algorithm SHA256).Hash
        if($originalHash -cne $unchanged -or [long](Read-CustomAppUserTxnStateV010 $s.paths).revision -ne 1) { throw 'GUARD_DENIAL_WROTE_CANONICAL_STATE' }
        Must-Fail { Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root -Initialize } 'reinitialize-cannot-bypass-lock'
        $bytes=[IO.File]::ReadAllBytes($s.paths.state)
        $utf8=[Text.Encoding]::UTF8.GetString($bytes)
        if($utf8.Contains($id) -or $utf8.Contains($tx) -or $utf8.Contains($live)) { throw 'DPAPI_STATE_LEAKED_PLAINTEXT' }
    } finally { $s.lock_handle.Dispose() }
    Write-Host 'CUSTOM_USER_GUARDED_BOOTSTRAP_PASS acl=true dpapi=true exclusive_across_processes=true interrupted_write_recovered=true active_durable=true'
    exit 0
}
if($Phase -eq 'contend') {
    Must-Fail { Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root } 'cross-process-contender'
    Write-Host 'CROSS_PROCESS_EXCLUSIVE_LOCK_PASS'
    exit 0
}
# This is a fresh PowerShell process. No cached in-memory state or previous lock.
$s=Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root
try {
    if([long]$s.state.revision -ne 1 -or [string]$s.state.active.consumption_id -cne $id -or
       [string]$s.state.active.transaction_id -cne $tx -or [string]$s.state.active.nonce -cne $nonce) { throw 'RESTART_LOST_OR_CHANGED_RESERVATION' }
    Must-Fail { Reserve-CustomAppUserTxnIdV010 -Session $s -ConsumptionId $id -TransactionId $tx -Nonce $nonce } 'same-id-replay'
    Must-Fail { Reserve-CustomAppUserTxnIdV010 -Session $s -ConsumptionId ('d'*64) -TransactionId $tx -Nonce $nonce } 'different-id-while-active'
    $premature=($s.state|ConvertTo-Json -Depth 8|ConvertFrom-Json)
    $premature.revision=[long]$premature.revision+1
    $premature.updated_utc=[DateTimeOffset]::UtcNow.ToString('o')
    $premature.active=$null
    Must-Fail { Save-CustomAppUserTxnStoreV010 -Session $s -NextState $premature } 'fresh-process-no-unverified-active-clear'
    if(Get-Command Complete-CustomAppUserTxnTerminalV010 -ErrorAction SilentlyContinue) { throw 'UNVERIFIED_TERMINAL_ERASE_IMPLEMENTED' }
    $canonical=[IO.File]::ReadAllBytes($s.paths.state)
} finally { $s.lock_handle.Dispose() }
Must-Fail { Open-CustomAppUserTxnStoreV010 -Name DifferentAlias -LivePath $live -HostedCiRoot $root } 'same-live-alias-state-binding'
$paths=Get-CustomAppUserTxnPathsV010 -Name Tagify -LivePath $live -HostedCiRoot $root
$altered=[byte[]]$canonical.Clone()
$altered[$altered.Length-1]=$altered[$altered.Length-1] -bxor 1
try {
    [IO.File]::WriteAllBytes($paths.state,$altered)
    Must-Fail { Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root } 'dpapi-bitflip-denial'
} finally { [IO.File]::WriteAllBytes($paths.state,$canonical) }
try {
    [IO.File]::Delete($paths.state)
    Must-Fail { Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root -Initialize } 'missing-canonical-no-reenrollment'
} finally { [IO.File]::WriteAllBytes($paths.state,$canonical) }
$s=Open-CustomAppUserTxnStoreV010 -Name Tagify -LivePath $live -HostedCiRoot $root
try {
    if([long]$s.state.revision -ne 1 -or [string]$s.state.active.consumption_id -cne $id) { throw 'POST_TAMPER_STATE_RECOVERY_INVALID' }
} finally { $s.lock_handle.Dispose() }
Write-Host 'CUSTOM_USER_GUARDED_FRESH_PROCESS_RESTART_PASS active_persisted=true replays_denied=true dpapi_tamper_denied=true missing_state_no_reenrollment=true manual_user_testing=none'
