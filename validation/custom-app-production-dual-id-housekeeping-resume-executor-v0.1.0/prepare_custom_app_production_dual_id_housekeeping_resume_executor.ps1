param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$RunnerTemp)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$parent=Join-Path $RepoRoot 'validation/custom-app-production-dual-id-bridge-aware-post-apply-commit-cleanup-v0.1.0/prepare_custom_app_production_dual_id_bridge_aware_post_apply_commit_cleanup.ps1'
if(-not(Test-Path -LiteralPath $parent -PathType Leaf)){throw 'qualified #198 cleanup preparer missing'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $parent -RepoRoot $RepoRoot -RunnerTemp $RunnerTemp
if($LASTEXITCODE){throw "qualified #198 cleanup preparer failed exit=$LASTEXITCODE"}

function Materialize-DIHRDependencyV010 {
    param([Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ExpectedBlob)
    git -C $RepoRoot cat-file -e "$Commit^{commit}" 2>$null
    if($LASTEXITCODE){git -C $RepoRoot fetch --no-tags origin $Commit | Out-Null;if($LASTEXITCODE){throw "dependency fetch failed $Commit"}}
    $out=Join-Path $RepoRoot $Path;New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent)|Out-Null
    $env:DIHR_SPEC="$Commit`:$Path";$env:DIHR_OUT=$out;$env:DIHR_REPO=$RepoRoot
    python -c "import os,subprocess,pathlib; pathlib.Path(os.environ['DIHR_OUT']).write_bytes(subprocess.check_output(['git','-C',os.environ['DIHR_REPO'],'cat-file','blob',os.environ['DIHR_SPEC']]))"
    if($LASTEXITCODE){throw "dependency materialize failed $Commit`:$Path"}
    $actual=(git -C $RepoRoot hash-object $out).Trim();if($actual-cne$ExpectedBlob){throw "dependency blob drift $Path $actual != $ExpectedBlob"}
}

$house='525c198bd1f15f26464b7f966ab7b2013f946d9a'
Materialize-DIHRDependencyV010 -Commit $house -Path 'validation/custom-app-production-recovery-housekeeping-resume-v0.1.0/custom-app-production-recovery-housekeeping-resume-contract.ps1' -ExpectedBlob '7d9f6d8543d944f5141b3282536903af98cbed6a'
Materialize-DIHRDependencyV010 -Commit $house -Path 'validation/custom-app-production-recovery-housekeeping-resume-v0.1.0/custom-app-production-recovery-housekeeping-resume-store.ps1' -ExpectedBlob 'c60b80138c8cd4189949a34795fb75a44e8e321e'
Materialize-DIHRDependencyV010 -Commit $house -Path 'validation/custom-app-production-recovery-housekeeping-resume-v0.1.0/custom-app-production-recovery-housekeeping-resume-writer.ps1' -ExpectedBlob '9ebed8dff0d8b1208103411f40192db2946a29f7'
Materialize-DIHRDependencyV010 -Commit $house -Path 'validation/custom-app-production-recovery-housekeeping-resume-v0.1.0/custom-app-production-recovery-housekeeping-resume-gate.ps1' -ExpectedBlob 'f238267779564a61b3f45e2060ecb02f63366b60'
Materialize-DIHRDependencyV010 -Commit '408e24ce7f66d1f5f23025a196b19cd8a42fcda7' -Path 'validation/custom-app-production-durable-dual-transaction-id-bridge-integration-v0.1.0/custom-app-production-durable-dual-transaction-id-bridge-integration.ps1' -ExpectedBlob 'c9a58a181d3c5f5a230fa895785c3a42a928c8cd'
Materialize-DIHRDependencyV010 -Commit '67458cbb96b5d1ed92e26c2b81debd6894044749' -Path 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1' -ExpectedBlob '3b14280d727287252f71611e4424d78e5705c2f1'

Write-Output 'DUAL_ID_HOUSEKEEPING_RESUME_EXECUTOR_DEPENDENCIES_PASS'
