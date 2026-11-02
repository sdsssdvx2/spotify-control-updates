param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$RunnerTemp)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$parent=Join-Path $RepoRoot 'validation/custom-app-production-dual-id-bridge-aware-post-swap-apply-admission-v0.1.0/prepare_custom_app_production_dual_id_bridge_aware_post_swap_apply_admission.ps1'
if(-not(Test-Path -LiteralPath $parent -PathType Leaf)){throw 'qualified dual-ID post-swap admission preparer missing'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $parent -RepoRoot $RepoRoot -RunnerTemp $RunnerTemp
if($LASTEXITCODE){throw "qualified dual-ID post-swap admission preparer failed exit=$LASTEXITCODE"}
function Materialize-DBAXDependencyV010 {
    param([Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ExpectedBlob)
    git -C $RepoRoot cat-file -e "$Commit^{commit}" 2>$null
    if($LASTEXITCODE){git -C $RepoRoot fetch --no-tags origin $Commit | Out-Null;if($LASTEXITCODE){throw "dependency fetch failed $Commit"}}
    $out=Join-Path $RepoRoot $Path;New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent)|Out-Null
    $env:DBAX_SPEC="$Commit`:$Path";$env:DBAX_OUT=$out;$env:DBAX_REPO=$RepoRoot
    python -c "import os,subprocess,pathlib; pathlib.Path(os.environ['DBAX_OUT']).write_bytes(subprocess.check_output(['git','-C',os.environ['DBAX_REPO'],'cat-file','blob',os.environ['DBAX_SPEC']]))"
    if($LASTEXITCODE){throw "dependency materialize failed $Commit`:$Path"}
    $actual=(git -C $RepoRoot hash-object $out).Trim();if($actual-cne$ExpectedBlob){throw "dependency blob drift $Path $actual != $ExpectedBlob"}
}
Materialize-DBAXDependencyV010 -Commit 'fe07d410531ea13c8fca379b01405631a3763e84' -Path 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1' -ExpectedBlob 'f7372b069fbfe6a0f8d8a0aad45312ffd33d9f0a'
Write-Output 'DUAL_ID_BRIDGE_AWARE_SPICETIFY_APPLY_EXECUTOR_DEPENDENCIES_PASS'
