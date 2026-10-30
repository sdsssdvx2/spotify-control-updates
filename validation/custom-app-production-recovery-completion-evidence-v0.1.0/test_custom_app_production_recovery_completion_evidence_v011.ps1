$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$source=Join-Path $PSScriptRoot 'test_custom_app_production_recovery_completion_evidence.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false))
$old="Assert-CETrue ([string]`$r.reason -like 'recovery-completion-evidence-journal-*') ('journal corruption reason drifted: '+[string]`$r.reason)"
$new="Assert-CETrue ([string]`$r.reason -like 'recovery-completion-evidence-read-failed:*journal JSON invalid*') ('journal corruption reason drifted: '+[string]`$r.reason)"
$first=$text.IndexOf($old,[StringComparison]::Ordinal)
if($first-lt0){throw 'completion v011 expected journal assertion not found'}
if($text.IndexOf($old,$first+$old.Length,[StringComparison]::Ordinal)-ge0){throw 'completion v011 journal assertion replacement not unique'}
$patched=$text.Replace($old,$new)
$temp=Join-Path $PSScriptRoot ('test_custom_app_production_recovery_completion_evidence_v011_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try{
    [IO.File]::WriteAllText($temp,$patched,[Text.UTF8Encoding]::new($false))
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "completion evidence v011 patched matrix failed exit=$LASTEXITCODE"}
}finally{
    if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}
}
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_COMPLETION_EVIDENCE_V011_MATRIX_PASS'
