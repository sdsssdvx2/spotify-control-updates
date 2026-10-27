$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'custom-app-remote-observer.ps1')

function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-False([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual='$Actual' expected='$Expected'"}}
function Assert-Throws([scriptblock]$Action,[string]$Contains,[string]$Message){$threw=$false;try{& $Action}catch{$threw=$true;if(-not [string]::IsNullOrWhiteSpace($Contains) -and $_.Exception.Message.IndexOf($Contains,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "$Message wrong error: $($_.Exception.Message)"}};if(-not $threw){throw "$Message did not throw"}}

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
$root=Join-Path ([IO.Path]::GetTempPath()) ('custom-app-remote-observer-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)

function New-TestZip {
    param([string]$Path,[object[]]$Entries)
    if(Test-Path -LiteralPath $Path){Remove-Item -LiteralPath $Path -Force}
    $archive=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
    try{
        foreach($item in $Entries){
            $entry=$archive.CreateEntry([string]$item.path,[IO.Compression.CompressionLevel]::Optimal)
            if($item.PSObject.Properties['external_attributes']){$entry.ExternalAttributes=[int]$item.external_attributes}
            if(-not ([string]$item.path).EndsWith('/')){
                $stream=$entry.Open();$writer=$null
                try{$writer=New-Object IO.StreamWriter($stream,[Text.Encoding]::UTF8,4096,$true);$writer.Write([string]$item.content);$writer.Flush()}
                finally{if($null -ne $writer){$writer.Dispose()};$stream.Dispose()}
            }
        }
    }finally{$archive.Dispose()}
}
function E([string]$Path,[string]$Content){[pscustomobject]@{path=$Path;content=$Content}}
function SymlinkAttributes {
    $bytes=[BitConverter]::GetBytes([uint32]0xA1FF0000)
    return [BitConverter]::ToInt32($bytes,0)
}

try{
    # 1. Canonical source normalization accepts exact GitHub identities and secure URLs only.
    Assert-Eq (ConvertTo-CustomAppObserverSourceIdentity 'Example/App') 'example/app' 'Canonical source normalization failed.'
    Assert-Eq (ConvertTo-CustomAppObserverSourceIdentity 'https://github.com/Example/App.git') 'example/app' 'HTTPS source normalization failed.'
    Assert-Eq (ConvertTo-CustomAppObserverSourceIdentity 'git@github.com:Example/App.git') 'example/app' 'SSH source normalization failed.'
    Assert-True ($null -eq (ConvertTo-CustomAppObserverSourceIdentity 'https://gitlab.com/example/app')) 'Non-GitHub source was accepted.'

    # 2. Ready root runtime ZIP is observed with valid manifest/package provenance.
    $zip=Join-Path $root 'root.zip'
    New-TestZip $zip @(
        (E 'manifest.json' '{"name":"Fixture App"}'),
        (E 'index.js' 'console.log("fixture");'),
        (E 'package.json' '{"repository":"https://github.com/example/app.git"}'),
        (E 'assets/a.txt' 'a')
    )
    $z=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode none
    Assert-False $z.build_required 'Ready runtime root was marked build-required.'
    Assert-Eq $z.app_root_count 1 'Ready runtime root count drifted.'
    Assert-Eq $z.layout_root '.' 'Ready runtime layout root drifted.'
    Assert-True $z.manifest_valid 'Ready runtime manifest was not valid.'
    Assert-Eq $z.manifest_name 'Fixture App' 'Manifest name drifted.'
    Assert-Eq $z.package_repository_identity 'example/app' 'Package repository identity drifted.'
    Assert-True (Test-CustomAppObserverSha256 $z.tree_sha256) 'Runtime tree hash invalid.'

    # 3. Tree hash is independent of ZIP entry order.
    $zip2=Join-Path $root 'root-reordered.zip'
    New-TestZip $zip2 @(
        (E 'assets/a.txt' 'a'),(E 'package.json' '{"repository":"https://github.com/example/app.git"}'),(E 'index.js' 'console.log("fixture");'),(E 'manifest.json' '{"name":"Fixture App"}')
    )
    $z2=Get-CustomAppObserverZipEvidence -ZipPath $zip2 -WrapperMode none
    Assert-Eq $z2.tree_sha256 $z.tree_sha256 'Tree hash changed with ZIP entry order.'

    # 4. GitHub zipball required wrapper is stripped exactly once.
    $wrapped=Join-Path $root 'wrapped.zip'
    New-TestZip $wrapped @(
        (E 'example-app-abc123/manifest.json' '{"name":"Fixture App"}'),
        (E 'example-app-abc123/index.js' 'console.log("fixture");'),
        (E 'example-app-abc123/assets/a.txt' 'a')
    )
    $w=Get-CustomAppObserverZipEvidence -ZipPath $wrapped -WrapperMode required
    Assert-True $w.wrapper_stripped 'Required GitHub wrapper was not stripped.'
    Assert-Eq $w.wrapper_name 'example-app-abc123' 'Required wrapper name drifted.'
    Assert-Eq $w.layout_root '.' 'Required wrapper did not normalize runtime root.'

    # 5. Release auto-wrapper strips a unique packaging directory only when it exposes a ready runtime root.
    $auto=Get-CustomAppObserverZipEvidence -ZipPath $wrapped -WrapperMode auto
    Assert-True $auto.wrapper_stripped 'Automatic release wrapper was not recognized.'
    Assert-False $auto.build_required 'Automatic wrapper runtime remained build-required.'

    # 6. Source-style nested runtime on repo surface remains build-required after only the GitHub wrapper is stripped.
    $sourceZip=Join-Path $root 'source.zip'
    New-TestZip $sourceZip @(
        (E 'repo-sha/package.json' '{"name":"source"}'),
        (E 'repo-sha/src/app.tsx' 'source'),
        (E 'repo-sha/dist/manifest.json' '{"name":"Fixture App"}'),
        (E 'repo-sha/dist/index.js' 'built')
    )
    $s=Get-CustomAppObserverZipEvidence -ZipPath $sourceZip -WrapperMode required
    Assert-True $s.build_required 'Nested repo runtime was incorrectly treated as ready root.'
    Assert-Eq $s.layout_root 'dist' 'Nested repo app root was not detected.'

    # 7. Multiple runtime roots remain ambiguous.
    $multi=Join-Path $root 'multi.zip'
    New-TestZip $multi @(
        (E 'a/index.js' 'a'),(E 'a/manifest.json' '{"name":"A"}'),(E 'b/index.js' 'b'),(E 'b/manifest.json' '{"name":"B"}')
    )
    $m=Get-CustomAppObserverZipEvidence -ZipPath $multi -WrapperMode none
    Assert-Eq $m.app_root_count 2 'Multiple runtime roots were not detected.'
    Assert-True $m.build_required 'Ambiguous multiple roots were treated as ready.'

    # 8. Invalid package repository metadata is surfaced rather than silently ignored.
    $badPkg=Join-Path $root 'bad-package.zip'
    New-TestZip $badPkg @((E 'index.js' 'x'),(E 'manifest.json' '{"name":"Fixture App"}'),(E 'package.json' '{"repository":"https://gitlab.com/example/app"}'))
    $bp=Get-CustomAppObserverZipEvidence -ZipPath $badPkg -WrapperMode none
    Assert-Eq $bp.package_repository_identity 'invalid-package-repository' 'Invalid package repository was hidden.'

    # 9-12. Traversal, backslash, ADS, and case-collision hazards fail before extraction (there is no extraction path).
    $unsafe=Join-Path $root 'unsafe.zip'
    New-TestZip $unsafe @((E '../evil.js' 'x'),(E 'index.js' 'x'),(E 'manifest.json' '{"name":"Fixture"}'))
    Assert-Throws {Get-CustomAppObserverZipEvidence $unsafe none} 'unsafe path' 'Traversal ZIP'
    New-TestZip $unsafe @((E 'a\evil.js' 'x'),(E 'index.js' 'x'),(E 'manifest.json' '{"name":"Fixture"}'))
    Assert-Throws {Get-CustomAppObserverZipEvidence $unsafe none} 'unsafe path' 'Backslash ZIP'
    New-TestZip $unsafe @((E 'index.js:ads' 'x'),(E 'manifest.json' '{"name":"Fixture"}'))
    Assert-Throws {Get-CustomAppObserverZipEvidence $unsafe none} 'unsafe path' 'ADS ZIP'
    New-TestZip $unsafe @((E 'Index.js' 'a'),(E 'index.js' 'b'),(E 'manifest.json' '{"name":"Fixture"}'))
    Assert-Throws {Get-CustomAppObserverZipEvidence $unsafe none} 'case-colliding' 'Case-collision ZIP'

    # 13. Symlink mode is rejected from ExternalAttributes.
    $symlink=Join-Path $root 'symlink.zip'
    $link=[pscustomobject]@{path='link';content='target';external_attributes=(SymlinkAttributes)}
    New-TestZip $symlink @((E 'index.js' 'x'),(E 'manifest.json' '{"name":"Fixture"}'),$link)
    Assert-Throws {Get-CustomAppObserverZipEvidence $symlink none} 'symlink' 'Symlink ZIP'

    # 14. Metadata parser bounds manifest/package JSON and never needs extraction.
    $large=Join-Path $root 'large-manifest.zip'
    New-TestZip $large @((E 'index.js' 'x'),(E 'manifest.json' ('{"name":"'+('x'*1048576)+'"}')))
    $lm=Get-CustomAppObserverZipEvidence -ZipPath $large -WrapperMode none
    Assert-False $lm.manifest_valid 'Oversized manifest was parsed as valid.'

    # 15. Temp cleanup guard refuses paths outside the dedicated observer temp root.
    Assert-Throws {Remove-CustomAppObserverTempDirectory $PSScriptRoot} 'Refusing to clean' 'Temp cleanup boundary'

    # 16. Minimal observation factory remains authority-denied.
    $repo=[pscustomobject]@{source_identity='example/app';github_repo_id=123;default_branch='main';api_base='https://api.github.com/repos/example/app'}
    $obs=New-CustomAppObserverObservation -Repo $repo -CommitSha ('a'*40) -SurfaceKind 'repo-commit-root' -ZipEvidence $z -Release $null -Asset $null -ReleaseZipAssetCount 0 -HasSubmodule $false
    Assert-False $obs.mutation_authorized 'Collector observation granted mutation authority.'
    Assert-False $obs.auto_update_authorized 'Collector observation granted auto-update authority.'
    Assert-False $obs.auto_install_authorized 'Collector observation granted auto-install authority.'
    Assert-Eq $obs.tree_sha256 $z.tree_sha256 'Observation factory changed tree identity.'

    Write-Host 'CUSTOM_APP_REMOTE_OBSERVER_OFFLINE_ACCEPTANCE_PASS cases=16'
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
