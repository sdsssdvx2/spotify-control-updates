$CustomAppLocalRuntimeBaselineSchema = 1

function Get-CustomAppLocalRuntimeRelativePath {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$FullPath)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $prefix=$rootFull+[IO.Path]::DirectorySeparatorChar
    $child=[IO.Path]::GetFullPath($FullPath)
    if(-not $child.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Local runtime entry escaped the Custom App root.'}
    $relative=$child.Substring($prefix.Length).Replace('\','/')
    $check=Test-CustomAppRemoteRelativePath -Path $relative
    if(-not [bool]$check.safe){throw "Local runtime relative path is unsafe ($([string]$check.reason)): $relative"}
    return [string]$check.canonical
}

function Get-CustomAppLocalRuntimeEntrySnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$AppPath,
        [int]$MaxFiles=20000,
        [int64]$MaxFileBytes=67108864,
        [int64]$MaxTotalBytes=268435456
    )
    if($MaxFiles -lt 1 -or $MaxFileBytes -lt 1 -or $MaxTotalBytes -lt 1){throw 'Local runtime baseline safety limits are invalid.'}
    if(-not (Test-Path -LiteralPath $AppPath -PathType Container)){throw 'Local runtime Custom App root is missing.'}
    $root=Get-Item -LiteralPath $AppPath -Force -ErrorAction Stop
    if(($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Local runtime Custom App root is a reparse point.'}
    $rootFull=[IO.Path]::GetFullPath($root.FullName).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $stack=New-Object System.Collections.Generic.Stack[string]
    $stack.Push($rootFull)
    $entries=New-Object System.Collections.Generic.List[object]
    $seen=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    [int64]$total=0
    while($stack.Count -gt 0){
        $dir=$stack.Pop()
        foreach($item in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)){
            $relative=Get-CustomAppLocalRuntimeRelativePath -Root $rootFull -FullPath $item.FullName
            if($relative.Equals('.git',[StringComparison]::OrdinalIgnoreCase) -or $relative.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase)){continue}
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Local runtime contains a reparse point: $relative"}
            if($item.PSIsContainer){$stack.Push([string]$item.FullName);continue}
            if(-not $seen.Add($relative)){throw "Local runtime contains a case-colliding path: $relative"}
            [int64]$size=$item.Length
            if($size -lt 0 -or $size -gt $MaxFileBytes){throw "Local runtime file exceeds the per-file safety limit: $relative"}
            $total += $size
            if($total -gt $MaxTotalBytes){throw 'Local runtime expanded-byte total exceeds the safety limit.'}
            $entries.Add([pscustomobject]@{path=$relative;full_path=[string]$item.FullName;size=$size;last_write_utc_ticks=[int64]$item.LastWriteTimeUtc.Ticks})
            if($entries.Count -gt $MaxFiles){throw 'Local runtime file count exceeds the safety limit.'}
        }
    }
    $array=@($entries.ToArray()|Sort-Object -Property @{Expression={$_.path.ToLowerInvariant()};Ascending=$true})
    return [pscustomobject]@{root=$rootFull;entries=$array;file_count=$array.Count;total_bytes=$total}
}

function Get-CustomAppLocalRuntimeFileSha256 {
    param([Parameter(Mandatory=$true)]$Entry)
    $stream=$null;$sha=$null
    try{
        $stream=[IO.File]::Open([string]$Entry.full_path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if([int64]$stream.Length -ne [int64]$Entry.size){throw "Local runtime file size changed during observation: $([string]$Entry.path)"}
        $sha=[Security.Cryptography.SHA256]::Create()
        $hash=([BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant())
        if([int64]$stream.Length -ne [int64]$Entry.size){throw "Local runtime file size changed while hashing: $([string]$Entry.path)"}
        return $hash
    } finally {
        if($null -ne $sha){$sha.Dispose()}
        if($null -ne $stream){$stream.Dispose()}
    }
}

function Test-CustomAppLocalRuntimeSnapshotStable {
    param([Parameter(Mandatory=$true)]$Before,[Parameter(Mandatory=$true)]$After)
    if([int]$Before.file_count -ne [int]$After.file_count -or [int64]$Before.total_bytes -ne [int64]$After.total_bytes){return $false}
    $a=@($Before.entries);$b=@($After.entries)
    for($i=0;$i -lt $a.Count;$i++){
        if([string]$a[$i].path -cne [string]$b[$i].path -or [int64]$a[$i].size -ne [int64]$b[$i].size -or [int64]$a[$i].last_write_utc_ticks -ne [int64]$b[$i].last_write_utc_ticks){return $false}
    }
    return $true
}

function Get-CustomAppLocalRuntimeBaseline {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$AppPath,
        [int]$MaxFiles=20000,
        [int64]$MaxFileBytes=67108864,
        [int64]$MaxTotalBytes=268435456,
        [int64]$MaxManifestBytes=1048576
    )
    if([string]::IsNullOrWhiteSpace($Name)){throw 'Local runtime baseline name is empty.'}
    if($MaxManifestBytes -lt 1){throw 'Local runtime manifest safety limit is invalid.'}
    $before=Get-CustomAppLocalRuntimeEntrySnapshot -AppPath $AppPath -MaxFiles $MaxFiles -MaxFileBytes $MaxFileBytes -MaxTotalBytes $MaxTotalBytes
    if([int]$before.file_count -lt 1){throw 'Local runtime contains no runtime files after VCS metadata exclusion.'}
    $files=New-Object System.Collections.Generic.List[object]
    $rows=New-Object System.Collections.Generic.List[string]
    foreach($entry in @($before.entries)){
        $hash=Get-CustomAppLocalRuntimeFileSha256 -Entry $entry
        $logical=[string]$entry.path
        $files.Add([pscustomobject]@{path=$logical;type='file';size=[int64]$entry.size;sha256=$hash})
        $rows.Add(('f|'+$logical.ToLowerInvariant()+'|'+[int64]$entry.size+'|'+$hash))
    }
    $after=Get-CustomAppLocalRuntimeEntrySnapshot -AppPath $AppPath -MaxFiles $MaxFiles -MaxFileBytes $MaxFileBytes -MaxTotalBytes $MaxTotalBytes
    if(-not (Test-CustomAppLocalRuntimeSnapshotStable -Before $before -After $after)){throw 'Local runtime changed during baseline observation.'}
    $rowArray=[string[]]$rows.ToArray();[Array]::Sort($rowArray,[StringComparer]::Ordinal)
    $tree=Get-CustomAppRemoteStringSha256 (($rowArray -join "`n")+"`n")

    $index=@($files.ToArray()|Where-Object{[string]$_.path -ceq 'index.js'})
    $manifestFiles=@($files.ToArray()|Where-Object{[string]$_.path -ceq 'manifest.json'})
    $manifestValid=$false;$manifestName=$null
    if($manifestFiles.Count -eq 1){
        $manifestEntry=@($before.entries|Where-Object{[string]$_.path -ceq 'manifest.json'})[0]
        if([int64]$manifestEntry.size -le $MaxManifestBytes){
            try{
                $json=[IO.File]::ReadAllText([string]$manifestEntry.full_path,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
                $manifestName=([string]$json.name).Trim()
                $manifestValid=(-not [string]::IsNullOrWhiteSpace($manifestName) -and $manifestName.Length -le 256)
            }catch{$manifestValid=$false;$manifestName=$null}
        }
    }
    $final=Get-CustomAppLocalRuntimeEntrySnapshot -AppPath $AppPath -MaxFiles $MaxFiles -MaxFileBytes $MaxFileBytes -MaxTotalBytes $MaxTotalBytes
    if(-not (Test-CustomAppLocalRuntimeSnapshotStable -Before $after -After $final)){throw 'Local runtime changed while reading manifest metadata.'}
    $ready=($index.Count -eq 1 -and $manifestFiles.Count -eq 1 -and $manifestValid)
    $reason=$(if($index.Count -ne 1){'root-index-js-missing-or-duplicate'}elseif($manifestFiles.Count -ne 1){'root-manifest-json-missing-or-duplicate'}elseif(-not $manifestValid){'root-manifest-invalid'}else{'safe-ready-local-runtime-root'})
    return [pscustomobject]@{
        schema=$CustomAppLocalRuntimeBaselineSchema;name=$Name;path=[string]$before.root;safe=$true;installable=$ready;reason=$reason
        file_count=[int]$before.file_count;total_bytes=[int64]$before.total_bytes;tree_sha256=$tree;files=$files.ToArray()
        manifest_valid=$manifestValid;manifest_name=$manifestName;layout_root='.';app_root_count=$(if($ready){1}else{0})
        vcs_metadata_excluded=$true;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false
    }
}

function Test-CustomAppLocalRuntimeBaselineMutationAuthority {
    param([Parameter(Mandatory=$true)]$Baseline)
    return ([bool]$Baseline.mutation_authorized -or [bool]$Baseline.auto_update_authorized -or [bool]$Baseline.auto_install_authorized)
}
