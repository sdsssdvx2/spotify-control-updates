param([Parameter(Mandatory=$true)][string]$Candidate)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Candidate,[ref]$tokens,[ref]$errors)
if($errors.Count){$errors|%{Write-Error $_.Message};throw 'candidate parse failed'}
function Import-Fn([string]$Name){
  $fn=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true))
  if($fn.Count -ne 1){throw "function $Name count=$($fn.Count)"};Invoke-Expression $fn[0].Extent.Text
}
foreach($n in @('Get-VersionBase4','Test-ProvenStaleSpicetifyBackup','Get-Utf8TextSnapshot','Write-Utf8TextLikeSnapshot','Restore-Utf8TextSnapshot','Get-IniSectionKeyValueFromText','Set-IniSectionKeyValueInText','Invoke-SpicetifyBackupApplyForVerifiedSpotifyUpdate')){Import-Fn $n}
function Get-ExactFileSha256([string]$Path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
$base=Join-Path $env:RUNNER_TEMP ('v0618-prov-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $base|Out-Null
try{
  $b=Join-Path $base 'Backup';New-Item -ItemType Directory -Force -Path $b|Out-Null
  $a=Join-Path $b 'xpui.spa';$c=Join-Path $b 'login.spa';[IO.File]::WriteAllText($a,'a');[IO.File]::WriteAllText($c,'b')
  $now=[DateTimeOffset]::UtcNow;$script:MockTxn=[pscustomobject]@{id='stage10';status='committed';before_version='1.3.3.264';after_version='1.3.6.1921';after_fullversion='1.3.6.1921.g7086c071a617';apply_started_at=$now.AddSeconds(-2).ToString('o');apply_finished_at=$now.AddSeconds(2).ToString('o')}
  (Get-Item $a).LastWriteTimeUtc=$now.UtcDateTime;(Get-Item $c).LastWriteTimeUtc=$now.UtcDateTime
  function Get-SpotifyTransaction{return $script:MockTxn}
  $status=[pscustomobject]@{SpotifyVersion='1.3.6.1921';PrefsVersion='1.3.6.1921.g7086c071a617';BackupVersion='1.3.3.264.gdaf3b824';SpaFiles=@(Get-Item $a, $c)}
  $ok=Test-ProvenStaleSpicetifyBackup $status;if(-not $ok.Proven){throw ('positive provenance rejected: '+($ok.Reasons -join ';'))}
  (Get-Item $a).LastWriteTimeUtc=$now.AddMinutes(-10).UtcDateTime;$bad=Test-ProvenStaleSpicetifyBackup $status;if($bad.Proven){throw 'out-of-window SPA timestamp was accepted'}
  (Get-Item $a).LastWriteTimeUtc=$now.UtcDateTime;$script:MockTxn.before_version='1.3.2.1';$bad=Test-ProvenStaleSpicetifyBackup $status;if($bad.Proven){throw 'wrong source version was accepted'}
  $script:MockTxn.before_version='1.3.3.264'

  $env:APPDATA=Join-Path $base 'Roaming';$prefsDir=Join-Path $env:APPDATA 'Spotify';New-Item -ItemType Directory -Force -Path $prefsDir|Out-Null
  $prefs=Join-Path $prefsDir 'prefs';$orig=[Text.UTF8Encoding]::new($false).GetBytes("app.last-launched-version = 1.3.3.264.gdaf3b824`r`nother = keep`r`n");[IO.File]::WriteAllBytes($prefs,$orig);$origHash=Get-ExactFileSha256 $prefs
  $script:Cfg=Join-Path $base 'config-xpui.ini';[IO.File]::WriteAllText($script:Cfg,"[Backup]`r`nversion = 1.3.3.264.gdaf3b824`r`nwith = 2.46.2`r`n",[Text.UTF8Encoding]::new($false))
  function Get-ConfigPath{return $script:Cfg}
  function Invoke-SpiceCapture { param([string[]]$Arguments)
    if(($Arguments -join ' ') -cne 'backup apply --no-restart'){throw 'unexpected mocked spicetify args'}
    $snap=Get-Utf8TextSnapshot $prefs;$v=Get-IniSectionKeyValueFromText $snap.Text '' 'app.last-launched-version'
    if($v -cne '1.3.6.1921.g7086c071a617'){throw "prefs not temporarily pinned: $v"}
    [IO.File]::WriteAllText($script:Cfg,"[Backup]`r`nversion = $v`r`nwith = 2.46.2`r`n",[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ExitCode=0;Output='mock-pass'}
  }
  $r=Invoke-SpicetifyBackupApplyForVerifiedSpotifyUpdate -ExpectedShortVersion '1.3.6.1921' -ExpectedFullVersion '1.3.6.1921.g7086c071a617'
  if($r.ExitCode -ne 0){throw 'mock backup apply did not pass'}
  if((Get-ExactFileSha256 $prefs) -cne $origHash){throw 'prefs exact bytes were not restored after target-version backup apply'}
  $cfgSnap=Get-Utf8TextSnapshot $script:Cfg;if((Get-IniSectionKeyValueFromText $cfgSnap.Text 'Backup' 'version') -cne '1.3.6.1921.g7086c071a617'){throw 'mock Backup version not target fullversion'}
  Write-Host 'V0618_PROVENANCE_AND_PREFS_PIN_PASS'
}finally{Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue}
