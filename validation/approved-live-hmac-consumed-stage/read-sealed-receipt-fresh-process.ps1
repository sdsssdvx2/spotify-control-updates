# Separate Windows process: deliberately has no original HMAC session key,
# source archive, network/issuer or user Spotify credentials. It only reads
# this one already-consumed DPAPI-encrypted stage record.
param([Parameter(Mandatory=$true)][string]$Store,
      [Parameter(Mandatory=$true)][string]$TokenId,
      [Parameter(Mandatory=$true)][string]$ExpectedTreeSha256)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'approved-live-hmac-stage.ps1')
$read=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $Store -TokenId $TokenId
if(-not[bool]$read.ok -or -not[bool]$read.single_use_consumed -or
   [bool]$read.production_mutation_authorized -or
   [string]$read.runtime_tree_sha256 -cne $ExpectedTreeSha256){
    throw ('V029_FRESH_PROCESS_UNSEALED_OR_CHANGED_RECORD:'+ [string]$read.reason)
}
Write-Host 'V029_FRESH_PROCESS_CURRENTUSER_DPAPI_CONSUMED_NO_HMAC_KEY_PASS'
