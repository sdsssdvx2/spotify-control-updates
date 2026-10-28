$ErrorActionPreference='Stop'
$validationRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $validationRoot 'custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1')
. (Join-Path $validationRoot 'custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1')
. (Join-Path $PSScriptRoot 'custom-app-local-runtime-baseline.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

function Assert-Throws {
    param([scriptblock]$Action,[string]$Label)
    $failed=$false
    try{& $Action}catch{$failed=$true}
    if(-not $failed){throw "Expected failure did not occur: $Label"}
}

function New-FixtureApp {
    param([string]$Root,[string]$Manifest='{"name":"Fixture App","description":"test"}')
    New-Item -ItemType Directory -Force -Path $Root,(Join-Path $Root 'assets'),(Join-Path $Root '.GIT')|Out-Null
    [IO.File]::WriteAllText((Join-Path $Root 'index.js'),'console.log("fixture");',[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $Root 'manifest.json'),$Manifest,[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $Root 'assets/data.txt'),'runtime-data',[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $Root '.GIT/config'),'[remote "origin"]',[Text.Encoding]::UTF8)
}

$root=Join-Path $env:RUNNER_TEMP ('local-runtime-baseline-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root|Out-Null
try{
    $app=Join-Path $root 'app';New-FixtureApp $app
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name 'fixture-app' -AppPath $app
    if(-not [bool]$baseline.safe -or -not [bool]$baseline.installable -or [string]$baseline.reason -cne 'safe-ready-local-runtime-root'){throw 'Ready local runtime was not accepted.'}
    if([string]$baseline.manifest_name -cne 'Fixture App' -or -not [bool]$baseline.manifest_valid -or [int]$baseline.app_root_count -ne 1 -or [string]$baseline.layout_root -cne '.'){throw 'Ready local runtime manifest/layout identity drift.'}
    if(-not [bool]$baseline.vcs_metadata_excluded -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $baseline)){throw 'Local baseline VCS exclusion/authority drift.'}
    if(@($baseline.files|Where-Object{([string]$_.path).StartsWith('.git',[StringComparison]::OrdinalIgnoreCase)}).Count -ne 0){throw '.git metadata leaked into runtime file set.'}
    if(-not (Test-CustomAppRemoteSha256 ([string]$baseline.tree_sha256))){throw 'Local runtime tree hash is invalid.'}

    # The exact same runtime files in a ZIP must produce the exact same tree fingerprint.
    $clean=Join-Path $root 'clean';New-Item -ItemType Directory -Force -Path $clean,(Join-Path $clean 'assets')|Out-Null
    foreach($relative in @('index.js','manifest.json','assets/data.txt')){
        $dest=Join-Path $clean ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar));$parent=Split-Path -Parent $dest
        New-Item -ItemType Directory -Force -Path $parent|Out-Null;[IO.File]::Copy((Join-Path $app ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))),$dest,$true)
    }
    $zip=Join-Path $root 'clean.zip';[IO.Compression.ZipFile]::CreateFromDirectory($clean,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
    $remote=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode none
    if([string]$remote.tree_sha256 -cne [string]$baseline.tree_sha256){throw "Local/remote tree formula mismatch: $($baseline.tree_sha256) != $($remote.tree_sha256)"}
    if([string]$remote.manifest_name -cne [string]$baseline.manifest_name -or [int]$remote.file_count -ne [int]$baseline.file_count){throw 'Local/remote manifest or file-count equivalence drift.'}
    $contractFiles=Test-CustomAppRemoteRuntimeFileSet -Observation $baseline
    if(-not [bool]$contractFiles.safe -or -not [bool]$contractFiles.installable -or [string]$contractFiles.tree_sha256 -cne [string]$baseline.tree_sha256){throw 'Local baseline is not directly compatible with remote runtime file-set validation.'}

    # VCS metadata changes must not change runtime identity.
    $treeBefore=[string]$baseline.tree_sha256
    [IO.File]::WriteAllText((Join-Path $app '.GIT/config'),'changed-vcs-metadata',[Text.Encoding]::UTF8)
    $afterGit=Get-CustomAppLocalRuntimeBaseline -Name 'fixture-app' -AppPath $app
    if([string]$afterGit.tree_sha256 -cne $treeBefore){throw 'VCS metadata changed runtime tree identity.'}

    # Any unknown runtime file is visible and changes the exact tree; it is never silently ignored.
    [IO.File]::WriteAllText((Join-Path $app 'unknown-user-or-runtime-state.bin'),'x',[Text.Encoding]::UTF8)
    $withExtra=Get-CustomAppLocalRuntimeBaseline -Name 'fixture-app' -AppPath $app
    if([string]$withExtra.tree_sha256 -ceq $treeBefore){throw 'Unknown local file was silently excluded from runtime tree.'}
    Remove-Item -LiteralPath (Join-Path $app 'unknown-user-or-runtime-state.bin') -Force

    Assert-Throws {Get-CustomAppLocalRuntimeBaseline -Name 'fixture-app' -AppPath $app -MaxFiles 2|Out-Null} 'file-count limit'
    Assert-Throws {Get-CustomAppLocalRuntimeBaseline -Name 'fixture-app' -AppPath $app -MaxFileBytes 4|Out-Null} 'per-file byte limit'
    Assert-Throws {Get-CustomAppLocalRuntimeBaseline -Name 'fixture-app' -AppPath $app -MaxTotalBytes 10|Out-Null} 'total byte limit'
    Assert-Throws {Get-CustomAppLocalRuntimeBaseline -Name 'fixture-app' -AppPath (Join-Path $root 'missing')|Out-Null} 'missing root'

    $badManifest=Join-Path $root 'bad-manifest';New-FixtureApp $badManifest '{"description":"missing name"}'
    $bad=Get-CustomAppLocalRuntimeBaseline -Name 'bad-manifest' -AppPath $badManifest
    if([bool]$bad.installable -or [bool]$bad.manifest_valid -or [string]$bad.reason -cne 'root-manifest-invalid'){throw 'Invalid manifest did not fail closed.'}

    $noIndex=Join-Path $root 'no-index';New-FixtureApp $noIndex;Remove-Item -LiteralPath (Join-Path $noIndex 'index.js') -Force
    $missingIndex=Get-CustomAppLocalRuntimeBaseline -Name 'no-index' -AppPath $noIndex
    if([bool]$missingIndex.installable -or [string]$missingIndex.reason -cne 'root-index-js-missing-or-duplicate'){throw 'Missing root index.js did not fail closed.'}

    $onlyGit=Join-Path $root 'only-git';New-Item -ItemType Directory -Force -Path (Join-Path $onlyGit '.git')|Out-Null
    [IO.File]::WriteAllText((Join-Path $onlyGit '.git/config'),'metadata',[Text.Encoding]::UTF8)
    Assert-Throws {Get-CustomAppLocalRuntimeBaseline -Name 'only-git' -AppPath $onlyGit|Out-Null} 'VCS-only root'

    # Nested junctions/reparse points are denied rather than traversed.
    $external=Join-Path $root 'external';New-Item -ItemType Directory -Force -Path $external|Out-Null
    [IO.File]::WriteAllText((Join-Path $external 'outside.txt'),'outside',[Text.Encoding]::UTF8)
    $junction=Join-Path $app 'unsafe-link'
    New-Item -ItemType Junction -Path $junction -Target $external -ErrorAction Stop|Out-Null
    Assert-Throws {Get-CustomAppLocalRuntimeBaseline -Name 'fixture-app' -AppPath $app|Out-Null} 'nested reparse point'
    Remove-Item -LiteralPath $junction -Force

    # A reparse-point root itself is also denied.
    $rootJunction=Join-Path $root 'root-junction';New-Item -ItemType Junction -Path $rootJunction -Target $clean -ErrorAction Stop|Out-Null
    Assert-Throws {Get-CustomAppLocalRuntimeBaseline -Name 'root-junction' -AppPath $rootJunction|Out-Null} 'root reparse point'
    Remove-Item -LiteralPath $rootJunction -Force

    Write-Host "CUSTOM_APP_LOCAL_RUNTIME_BASELINE_V010_PASS tree=$treeBefore files=$($baseline.file_count) bytes=$($baseline.total_bytes) manifest=$($baseline.manifest_name)"
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
