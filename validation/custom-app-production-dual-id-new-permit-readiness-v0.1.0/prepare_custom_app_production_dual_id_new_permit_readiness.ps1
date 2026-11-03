param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$RunnerTemp)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$parent=Join-Path $RepoRoot 'validation/custom-app-production-dual-id-housekeeping-resume-executor-v0.1.0/prepare_custom_app_production_dual_id_housekeeping_resume_executor.ps1'
if(-not(Test-Path -LiteralPath $parent -PathType Leaf)){throw 'qualified #199 housekeeping preparer missing'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $parent -RepoRoot $RepoRoot -RunnerTemp $RunnerTemp
if($LASTEXITCODE){throw "qualified #199 housekeeping preparer failed exit=$LASTEXITCODE"}

function Materialize-DINPDependencyV010 {
    param([Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ExpectedBlob)
    git -C $RepoRoot cat-file -e "$Commit^{commit}" 2>$null
    if($LASTEXITCODE){git -C $RepoRoot fetch --no-tags origin $Commit | Out-Null;if($LASTEXITCODE){throw "dependency fetch failed $Commit"}}
    $out=Join-Path $RepoRoot $Path;New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent)|Out-Null
    $env:DINP_SPEC="$Commit`:$Path";$env:DINP_OUT=$out;$env:DINP_REPO=$RepoRoot
    python -c "import os,subprocess,pathlib; pathlib.Path(os.environ['DINP_OUT']).write_bytes(subprocess.check_output(['git','-C',os.environ['DINP_REPO'],'cat-file','blob',os.environ['DINP_SPEC']]))"
    if($LASTEXITCODE){throw "dependency materialize failed $Commit`:$Path"}
    $actual=(git -C $RepoRoot hash-object $out).Trim();if($actual-cne$ExpectedBlob){throw "dependency blob drift $Path $actual != $ExpectedBlob"}
}

$promotion='6bc69d2c8b12d074fa68f3d2ed7688e0846cd23c'
Materialize-DINPDependencyV010 -Commit $promotion -Path 'validation/custom-app-production-promotion-gate-v0.1.0/custom-app-production-promotion-gate.ps1' -ExpectedBlob '1164c197405eac2295f789256e2886068611dd94'
Materialize-DINPDependencyV010 -Commit $promotion -Path 'validation/custom-app-production-promotion-gate-v0.1.0/test_custom_app_production_promotion_gate.ps1' -ExpectedBlob '80b27015fa05951fe2c0f706eb60d212dac17d24'
Write-Output 'DUAL_ID_NEW_PERMIT_READINESS_DEPENDENCIES_PASS'
