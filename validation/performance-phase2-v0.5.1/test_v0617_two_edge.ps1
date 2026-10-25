Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$Root=(Resolve-Path '.\ci-bootstrap-fixture\LocalAppData\SpotifyControl').Path
$Bin=Join-Path $Root 'bin'
$Boot=Join-Path $Root 'bootstrap\spotify-control-self-updater.ps1'
$Main17='5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'
$AddonR7='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
$Main19='45795b9622953a10c6eca2ee2f5a19fc4467c5143d5bdf7a9f2ad64841b9416f'
$AddonR8='df17018bdb5f62f55624070d047933387f62c049dae73cf5cefcc541bc412afa'
$Agent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
$Bootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
function Get-TestHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Invoke-TestBootstrap([string]$Action){
    $out=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Boot -Action $Action -Json 2>&1)
    $code=$LASTEXITCODE
    $out|ForEach-Object{Write-Host $_}
    if($code-ne0){throw "Bootstrap $Action failed: $code"}
    $json=@($out|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1
    if(-not$json){throw "Bootstrap $Action emitted no JSON"}
    return ($json|ConvertFrom-Json)
}
$MainPath=Join-Path $Bin 'spotify-control.ps1';$AddonPath=Join-Path $Bin 'addon-manager.ps1';$AgentPath=Join-Path $Bin 'spotify-control-agent.vbs'
if((Get-TestHash $MainPath)-ne$Main17 -or (Get-TestHash $AddonPath)-ne$AddonR7 -or (Get-TestHash $AgentPath)-ne$Agent -or (Get-TestHash $Boot)-ne$Bootstrap){throw 'v0.6.17 fixture identity mismatch.'}
$env:LOCALAPPDATA=(Resolve-Path '.\ci-bootstrap-fixture\LocalAppData').Path
$env:APPDATA=Join-Path (Resolve-Path '.\ci-bootstrap-fixture').Path 'Roaming'
New-Item -ItemType Directory -Force -Path $env:APPDATA|Out-Null
$check=Invoke-TestBootstrap 'Check'
if(-not$check.success -or [string]$check.installed_version-ne'0.6.17' -or [int]$check.result.edge_count-ne2){throw 'Check did not prove exact two-edge path.'}
$rb=Invoke-TestBootstrap 'RollbackTest'
if(-not$rb.success -or [string]$rb.transaction_status-ne'rolled-back'){throw 'Two-edge RollbackTest did not roll back.'}
if((Get-TestHash $MainPath)-ne$Main17 -or (Get-TestHash $AddonPath)-ne$AddonR7){throw 'Two-edge rollback did not restore exact v0.6.17/r7.'}
$up=Invoke-TestBootstrap 'Update'
if(-not$up.success -or [string]$up.transaction_status-ne'committed'){throw 'Two-edge Update did not commit.'}
if((Get-TestHash $MainPath)-ne$Main19 -or (Get-TestHash $AddonPath)-ne$AddonR8 -or (Get-TestHash $AgentPath)-ne$Agent -or (Get-TestHash $Boot)-ne$Bootstrap){throw 'Two-edge final v0.6.19/r8 identity mismatch.'}
$tokens=$null;$errors=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($MainPath,[ref]$tokens,[ref]$errors);if($errors.Count){throw 'Updated v0.6.19 main failed PS5.1 parse.'}
$tokens=$null;$errors=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($AddonPath,[ref]$tokens,[ref]$errors);if($errors.Count){throw 'Updated r8 addon failed PS5.1 parse.'}
$post=Invoke-TestBootstrap 'Check'
if(-not$post.success -or [string]$post.installed_version-ne'0.6.19' -or $post.result.already_current-ne$true -or [int]$post.result.edge_count-ne0){throw 'Two-edge post-update state is not already-current.'}
Write-Host 'V051_BOOTSTRAP_V0617_TO_V0619_TWO_EDGE_E2E_PASS'
