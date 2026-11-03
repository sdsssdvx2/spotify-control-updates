param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$RunnerTemp)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$parent=Join-Path $RepoRoot 'validation/custom-app-production-dual-id-bridge-aware-spicetify-apply-executor-v0.1.0/prepare_custom_app_production_dual_id_bridge_aware_spicetify_apply_executor.ps1'
if(-not(Test-Path -LiteralPath $parent -PathType Leaf)){throw 'qualified dual-ID apply executor preparer missing'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $parent -RepoRoot $RepoRoot -RunnerTemp $RunnerTemp
if($LASTEXITCODE){throw "qualified dual-ID apply executor preparer failed exit=$LASTEXITCODE"}
function Materialize-DBACDependencyV010 {
    param([Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ExpectedBlob)
    git -C $RepoRoot cat-file -e "$Commit^{commit}" 2>$null
    if($LASTEXITCODE){git -C $RepoRoot fetch --no-tags origin $Commit | Out-Null;if($LASTEXITCODE){throw "dependency fetch failed $Commit"}}
    $out=Join-Path $RepoRoot $Path;New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent)|Out-Null
    $env:DBAC_SPEC="$Commit`:$Path";$env:DBAC_OUT=$out;$env:DBAC_REPO=$RepoRoot
    python -c "import os,subprocess,pathlib; pathlib.Path(os.environ['DBAC_OUT']).write_bytes(subprocess.check_output(['git','-C',os.environ['DBAC_REPO'],'cat-file','blob',os.environ['DBAC_SPEC']]))"
    if($LASTEXITCODE){throw "dependency materialize failed $Commit`:$Path"}
    $actual=(git -C $RepoRoot hash-object $out).Trim();if($actual-cne$ExpectedBlob){throw "dependency blob drift $Path $actual != $ExpectedBlob"}
}
Materialize-DBACDependencyV010 -Commit '67458cbb96b5d1ed92e26c2b81debd6894044749' -Path 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1' -ExpectedBlob '3b14280d727287252f71611e4424d78e5705c2f1'
Write-Output 'DUAL_ID_BRIDGE_AWARE_POST_APPLY_COMMIT_CLEANUP_DEPENDENCIES_PASS'
