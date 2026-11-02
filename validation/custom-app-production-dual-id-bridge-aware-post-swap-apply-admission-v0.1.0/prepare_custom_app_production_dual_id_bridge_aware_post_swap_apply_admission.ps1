param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$RunnerTemp
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$parent=Join-Path $RepoRoot 'validation/custom-app-production-dual-id-bridge-aware-finalization-v0.1.0/prepare_custom_app_production_dual_id_bridge_aware_finalization.ps1'
if(-not(Test-Path -LiteralPath $parent -PathType Leaf)){throw 'qualified finalization preparer missing'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $parent -RepoRoot $RepoRoot -RunnerTemp $RunnerTemp
if($LASTEXITCODE){throw "qualified finalization preparer failed exit=$LASTEXITCODE"}

function Materialize-DBAPDependencyV010 {
    param([Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ExpectedBlob)
    git -C $RepoRoot cat-file -e "$Commit^{commit}" 2>$null
    if($LASTEXITCODE){git -C $RepoRoot fetch --no-tags origin $Commit | Out-Null;if($LASTEXITCODE){throw "dependency fetch failed $Commit"}}
    $out=Join-Path $RepoRoot $Path
    New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent)|Out-Null
    $env:DBAP_SPEC="$Commit`:$Path";$env:DBAP_OUT=$out;$env:DBAP_REPO=$RepoRoot
    python -c "import os,subprocess,pathlib; pathlib.Path(os.environ['DBAP_OUT']).write_bytes(subprocess.check_output(['git','-C',os.environ['DBAP_REPO'],'cat-file','blob',os.environ['DBAP_SPEC']]))"
    if($LASTEXITCODE){throw "dependency materialize failed $Commit`:$Path"}
    $actual=(git -C $RepoRoot hash-object $out).Trim()
    if($actual-cne$ExpectedBlob){throw "dependency blob drift $Path $actual != $ExpectedBlob"}
}

Materialize-DBAPDependencyV010 -Commit 'a4f6d4772afb895dd253a4c82a21643711ac0829' -Path 'validation/custom-app-production-post-swap-apply-admission-v0.1.0/custom-app-production-post-swap-apply-admission.ps1' -ExpectedBlob '190382903e23d7abc59b525829c5ecd5c76f7ff1'
Materialize-DBAPDependencyV010 -Commit 'da3bf726c2c888bd6ac8c4aaee8fd13660a9235f' -Path 'validation/custom-app-remote-binding-observer-v0.4.0/custom-app-remote-binding-state.ps1' -ExpectedBlob 'bd19cbb3da2087e68b2452fe62471d4eca2cd990'
Write-Output 'DUAL_ID_BRIDGE_AWARE_POST_SWAP_APPLY_ADMISSION_DEPENDENCIES_PASS'