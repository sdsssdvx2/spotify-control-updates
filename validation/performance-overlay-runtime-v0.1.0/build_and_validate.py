from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "SpotifyControl-Performance-Overlay-Runtime-Validator-v0.1.0.zip"
SOURCE_COMMIT = "4d9eb71d1fa97b70d839dc887cdc8f5531d2ff8b"
SOURCE_BUILDER = "validation/performance-phase2-v0.4.1/build_and_validate.py"
SOURCE_ZIP_SHA256 = "2c857fa0988cb73d3930c599c30655b8315f53ebb2b425e67fb79b2e0244d5b1"
SOURCE_SCRIPT_SHA256 = "c345e5fbd346b817ad434d1396aa52a84898494eacea53ad47f4d4614ab6ab87"
SOURCE_SCRIPT_SIZE = 64005

OVERLAY_FILES = [
    "performance/overlay/apply-overlay.ps1",
    "performance/overlay/collect-active-provenance.ps1",
    "performance/overlay/lazy-custom-app-loader.js",
    "performance/overlay/targets/pithaya-optional-custom-apps.json",
]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def extract_function_blocks(script: str) -> list[tuple[str, str]]:
    starts = list(re.finditer(r"(?m)^function\s+([A-Za-z0-9_-]+)\s*\{", script))
    blocks: list[tuple[str, str]] = []
    for match in starts:
        name = match.group(1)
        i = match.end() - 1
        depth = 0
        in_single = False
        in_double = False
        while i < len(script):
            ch = script[i]
            if ch == "`":
                i += 2
                continue
            if not in_double and ch == "'":
                in_single = not in_single
            elif not in_single and ch == '"':
                in_double = not in_double
            elif not in_single and not in_double:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        blocks.append((name, script[match.start() : i + 1]))
                        break
            i += 1
        else:
            raise RuntimeError(f"Could not extract function block: {name}")
    return blocks


def get_validated_v041_script() -> str:
    with tempfile.TemporaryDirectory() as td_raw:
        td = Path(td_raw)
        worktree = td / "v041"
        subprocess.run(
            ["git", "worktree", "add", "--detach", str(worktree), SOURCE_COMMIT],
            cwd=ROOT,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            subprocess.run(["python", SOURCE_BUILDER], cwd=worktree, check=True)
            package = worktree / "SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.1.zip"
            package_bytes = package.read_bytes()
            if sha256(package_bytes) != SOURCE_ZIP_SHA256:
                raise RuntimeError("Validated v0.4.1 package provenance mismatch")
            with zipfile.ZipFile(package) as zf:
                script_bytes = zf.read("track-transition-isolation.ps1")
            if len(script_bytes) != SOURCE_SCRIPT_SIZE or sha256(script_bytes) != SOURCE_SCRIPT_SHA256:
                raise RuntimeError("Validated v0.4.1 script provenance mismatch")
            return script_bytes.decode("utf-8-sig")
        finally:
            subprocess.run(
                ["git", "worktree", "remove", "--force", str(worktree)],
                cwd=ROOT,
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )


HEADER = r'''param(
    [ValidateSet("Run","SelfTest")]
    [string]$Action = "Run"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$Version = "0.1.0"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$OverlayRoot = Join-Path $Root "overlay"
$OverlayApply = Join-Path $OverlayRoot "apply-overlay.ps1"
$OverlayCollector = Join-Path $OverlayRoot "collect-active-provenance.ps1"
$OverlayTargets = Join-Path $OverlayRoot "targets\pithaya-optional-custom-apps.json"
$LocalRoot = Join-Path $env:LOCALAPPDATA "SpotifyControl"
$ReportDir = Join-Path $LocalRoot "reports"
$BackupBase = Join-Path $LocalRoot "backups\performance-overlay-runtime-v010"
$LogDir = Join-Path $LocalRoot "logs"
$ReportJson = Join-Path $ReportDir "performance-overlay-runtime-v010-latest.json"
$ReportTxt = Join-Path $ReportDir "performance-overlay-runtime-v010-latest.txt"
$RawCsv = Join-Path $ReportDir "performance-overlay-runtime-v010-raw-latest.csv"
$Log = Join-Path $LogDir "performance-overlay-runtime-v010-error.log"
$ConfigPath = Join-Path $env:APPDATA "spicetify\config-xpui.ini"
$MainPath = Join-Path $LocalRoot "bin\spotify-control.ps1"
$AddonPath = Join-Path $LocalRoot "bin\addon-manager.ps1"
$AgentPath = Join-Path $LocalRoot "bin\spotify-control-agent.vbs"
$BootstrapPath = Join-Path $LocalRoot "bootstrap.ps1"
$ResidentTaskName = "Spotify Control Resident"
$LocalSpotify = Join-Path $env:LOCALAPPDATA "Spotify"
$SpotifyExe = Join-Path $env:APPDATA "Spotify\Spotify.exe"
$AppsPath = Join-Path $env:APPDATA "Spotify\Apps"
$XpuiPath = Join-Path $AppsPath "xpui"
$IndexPath = Join-Path $XpuiPath "index.html"

$AcceptedMainShas = @(
    "503a65bca9e6019a9ba60c17b4695b48802cf5566f23d740118bd98d276fba9a",
    "27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f"
)
$ExpectedAddonSha = "b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977"
$ExpectedAgentSha = "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278"
$ExpectedBootstrapSha = "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6"
$ExpectedSpotifyVersion = "1.3.6.1921"
$ExpectedSpicetifyVersion = "2.46.2"
$AcceptedXpuiMinFiles = 60
$SampleIntervalMs = 250
$TransitionSeconds = 50
$TransitionWindowSeconds = 6.0
$PlaybackWarmupSeconds = 15
$NextOffsets = @(12,25,38)
$StabilizeSeconds = 4
$MaxRestartAttempts = 1

$script:ResidentWasRunning = $false
$script:ResidentSuspended = $false
$script:XpuiMutationStarted = $false
$script:OriginalIndexBackup = $null
$script:OriginalIndexHash = $null
$script:OriginalTree = $null
$script:OriginalConfigHash = $null
$script:RoleCacheSignature = ""
$script:RoleCache = @{}
$script:OverlayStateRoot = $null
$script:OverlayApplied = $false
$script:SessionDir = $null
'''

CUSTOM = r'''
function Write-JsonUtf8NoBom {
    param([string]$Path,$Value)
    $json=$Value|ConvertTo-Json -Depth 24
    [IO.File]::WriteAllBytes($Path,([Text.UTF8Encoding]::new($false)).GetBytes($json))
}

function Invoke-OverlayToolJson {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("Collect","Audit","Apply","Restore")][string]$Operation,
        [string]$ProvenancePath
    )
    $ps=(Get-Command powershell.exe -ErrorAction Stop).Source
    if($Operation -eq "Collect"){
        $r=Invoke-Native -FilePath $ps -Arguments @("-NoProfile","-ExecutionPolicy","Bypass","-File",$OverlayCollector,"-XpuiRoot",$XpuiPath,"-OutputPath",$ProvenancePath,"-TargetMetadataPath",$OverlayTargets) -TimeoutSeconds 60
    }elseif($Operation -eq "Restore"){
        $r=Invoke-Native -FilePath $ps -Arguments @("-NoProfile","-ExecutionPolicy","Bypass","-File",$OverlayApply,"-Mode","Restore","-StateRoot",$script:OverlayStateRoot,"-TargetMetadataPath",$OverlayTargets) -TimeoutSeconds 60
    }else{
        $r=Invoke-Native -FilePath $ps -Arguments @("-NoProfile","-ExecutionPolicy","Bypass","-File",$OverlayApply,"-Mode",$Operation,"-XpuiRoot",$XpuiPath,"-ProvenancePath",$ProvenancePath,"-StateRoot",$script:OverlayStateRoot,"-TargetMetadataPath",$OverlayTargets) -TimeoutSeconds 60
    }
    if($r.ExitCode -ne 0){throw "Overlay $Operation failed: $($r.Output)"}
    try{return ([string]$r.Output|ConvertFrom-Json)}catch{throw "Overlay $Operation returned invalid JSON: $($r.Output)"}
}

function Start-SpotifyAndWarmup {
    param([string]$Label)
    if(-not(Test-SafePath $SpotifyExe "Leaf")){throw "Spotify executable disappeared before $Label launch."}
    Start-Process -FilePath $SpotifyExe
    if(-not(Wait-SpotifyReady 45)){throw "Spotify did not become healthy for $Label"}
    $script:RoleCacheSignature='';$script:RoleCache=@{}
    Start-Sleep -Seconds 3
    Send-MediaKey 'PlayPause'
    Write-LabLog ("Playback start key sent for {0}; warmup={1} sec." -f $Label,$PlaybackWarmupSeconds)
    Start-Sleep -Seconds $PlaybackWarmupSeconds
}

function Analyze-ShortTransitions {
    param([string]$Label,[object[]]$Rows,[object[]]$Events)
    $windowRows=New-Object System.Collections.Generic.List[object]
    $peaks=New-Object System.Collections.Generic.List[object]
    foreach($ev in $Events){
        $s=[double]$ev.actual_seconds
        $subset=@($Rows|Where-Object{[double]$_.elapsed_seconds -ge $s -and [double]$_.elapsed_seconds -le ($s+$TransitionWindowSeconds)})
        foreach($r in $subset){$windowRows.Add($r)}
        if($subset.Count -eq 0){throw "No transition samples found for $Label event $($ev.index)."}
        $peaks.Add([pscustomobject]@{
            index=$ev.index;event_seconds=$s
            cpu_peak=[Math]::Round((($subset.cpu_percent|Measure-Object -Maximum).Maximum),2)
            main_peak=[Math]::Round((($subset.main_cpu_percent|Measure-Object -Maximum).Maximum),2)
            renderer_peak=[Math]::Round((($subset.renderer_cpu_percent|Measure-Object -Maximum).Maximum),2)
            gpu_peak=[Math]::Round((($subset.gpu_cpu_percent|Measure-Object -Maximum).Maximum),2)
            ws_peak_mb=[Math]::Round((($subset.working_set_mb|Measure-Object -Maximum).Maximum),1)
        })
    }
    $active=@($peaks.ToArray()|Where-Object{[double]$_.cpu_peak -ge 1.5}).Count
    return [pscustomobject]@{
        label=$Label
        transition_sample_count=$windowRows.Count
        metrics=(Get-MetricSummary $windowRows.ToArray())
        transitions=$peaks.ToArray()
        active_transition_windows=$active
        short_baseline_canary_pass=($active -ge 2)
    }
}

function New-ConditionResult {
    param([string]$Label,$Measured)
    $analysis=Analyze-ShortTransitions -Label $Label -Rows $Measured.rows -Events $Measured.events
    $isBaseline=$Label -like 'BASELINE_*'
    $status=if($analysis.short_baseline_canary_pass){'active-response'}elseif($isBaseline){'baseline-invalid'}else{'low-response-accepted'}
    if($isBaseline -and -not $analysis.short_baseline_canary_pass){throw "$Label short workload canary failed: only $($analysis.active_transition_windows)/3 transition windows reached 1.5% CPU."}
    return [pscustomobject]@{
        label=$Label
        metrics=$analysis.metrics
        transitions=$analysis.transitions
        active_transition_windows=$analysis.active_transition_windows
        workload_policy_status=$status
        min_spotify_process_count=$Measured.min_spotify_process_count
        end_spotify_process_count=$Measured.end_spotify_process_count
        rows=$Measured.rows
        events=$Measured.events
    }
}

function Get-OverlayComparison {
    param($BaselineMetrics,$OverlayCondition)
    return [pscustomobject]@{
        cpu_p95_saved=[Math]::Round([double]$BaselineMetrics.cpu_percent.p95-[double]$OverlayCondition.metrics.cpu_percent.p95,2)
        cpu_p99_saved=[Math]::Round([double]$BaselineMetrics.cpu_percent.p99-[double]$OverlayCondition.metrics.cpu_percent.p99,2)
        cpu_max_saved=[Math]::Round([double]$BaselineMetrics.cpu_percent.max-[double]$OverlayCondition.metrics.cpu_percent.max,2)
        renderer_p95_saved=[Math]::Round([double]$BaselineMetrics.renderer_cpu_percent.p95-[double]$OverlayCondition.metrics.renderer_cpu_percent.p95,2)
        renderer_max_saved=[Math]::Round([double]$BaselineMetrics.renderer_cpu_percent.max-[double]$OverlayCondition.metrics.renderer_cpu_percent.max,2)
        gpu_p95_saved=[Math]::Round([double]$BaselineMetrics.gpu_cpu_percent.p95-[double]$OverlayCondition.metrics.gpu_cpu_percent.p95,2)
        working_set_p95_saved_mb=[Math]::Round([double]$BaselineMetrics.working_set_mb.p95-[double]$OverlayCondition.metrics.working_set_mb.p95,1)
    }
}

function Assert-FinalSafetyState {
    param([string]$OriginalIndexHash,$OriginalTree,[string]$OriginalConfigHash,[hashtable]$OriginalPayloadHashes)
    if((Get-Sha256Lower $IndexPath) -ne $OriginalIndexHash){throw 'Final index.html SHA-256 differs from the original.'}
    if((Get-Sha256Lower $ConfigPath) -ne $OriginalConfigHash){throw 'config-xpui.ini changed during runtime validation.'}
    $tree=Get-TreeFingerprint $XpuiPath
    if($tree.sha256 -ne $OriginalTree.sha256 -or $tree.file_count -ne $OriginalTree.file_count -or $tree.total_bytes -ne $OriginalTree.total_bytes){throw 'Final xpui tree fingerprint differs from the original.'}
    foreach($path in @($OriginalPayloadHashes.Keys)){
        if(-not(Test-SafePath $path 'Leaf')){throw "Protected app payload disappeared: $path"}
        if((Get-Sha256Lower $path) -ne [string]$OriginalPayloadHashes[$path]){throw "Protected app payload changed: $path"}
    }
}

function Write-RuntimeTextReport {
    param($Report)
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add('Spotify Control Performance Overlay Runtime Validator v0.1.0')
    $lines.Add(('Generated: '+$Report.generated_at))
    $lines.Add('')
    $lines.Add(('Runtime: Spotify Control '+$Report.runtime.spotify_control_version+' | Spotify '+$Report.runtime.spotify_version+' | Spicetify '+$Report.runtime.spicetify_version))
    $lines.Add(('Optimized targets: '+(@($Report.optimized_targets)-join ', ')))
    $lines.Add(('Baseline A/B p95 drift: CPU='+$Report.baseline_drift.cpu_p95_points+' pts | renderer='+$Report.baseline_drift.renderer_p95_points+' pts'))
    $lines.Add('')
    foreach($c in @($Report.conditions)){
        $lines.Add($c.label)
        $lines.Add(('  CPU p95='+$c.metrics.cpu_percent.p95+'% p99='+$c.metrics.cpu_percent.p99+'% max='+$c.metrics.cpu_percent.max+'%'))
        $lines.Add(('  Renderer p95='+$c.metrics.renderer_cpu_percent.p95+'% max='+$c.metrics.renderer_cpu_percent.max+'% | GPU p95='+$c.metrics.gpu_cpu_percent.p95+'% | WS p95='+$c.metrics.working_set_mb.p95+' MB'))
        $lines.Add(('  evidence='+$c.workload_policy_status+' active_windows='+$c.active_transition_windows+'/3'))
        $lines.Add('')
    }
    $lines.Add(('Overlay savings vs averaged baselines: CPU p95 '+$Report.overlay_savings.cpu_p95_saved+' pts | p99 '+$Report.overlay_savings.cpu_p99_saved+' | renderer p95 '+$Report.overlay_savings.renderer_p95_saved+' pts'))
    $lines.Add('')
    $lines.Add('Safety:')
    $lines.Add('- Original index.html restored byte-for-byte.')
    $lines.Add('- Full xpui tree fingerprint restored exactly.')
    $lines.Add('- config-xpui.ini remained byte-for-byte unchanged.')
    $lines.Add('- Better Local Files and Playlist Maker payload files remained byte-for-byte unchanged.')
    $lines.Add('- Browser/Default persistence was safety-backed up and never edited.')
    $lines.Add('- ivLyrics/Tagify/Splitify/Marketplace/user.css/SC Cover Ambience were outside the optimization mutation scope.')
    $lines.Add('- Resident production code/task definition was unchanged; only the running resident process was temporarily suspended.')
    [IO.File]::WriteAllLines($ReportTxt,$lines.ToArray(),[Text.UTF8Encoding]::new($true))
}
'''

MAIN = r'''
if($Action -eq 'SelfTest'){
    $required=@($OverlayApply,$OverlayCollector,$OverlayTargets,(Join-Path $OverlayRoot 'lazy-custom-app-loader.js'))
    foreach($p in $required){if(-not(Test-SafePath $p 'Leaf')){throw "SELFTEST missing packaged overlay file: $p"}}
    if($NextOffsets.Count -ne 3 -or $TransitionSeconds -ne 50 -or $PlaybackWarmupSeconds -ne 15){throw 'SELFTEST short-runtime timing contract drifted.'}
    if($AcceptedMainShas.Count -ne 2){throw 'SELFTEST accepted Spotify Control hash set drifted.'}
    Write-Host 'PERFORMANCE OVERLAY RUNTIME VALIDATOR SELFTEST PASS'
    exit 0
}

New-Item -ItemType Directory -Force -Path $ReportDir,$BackupBase,$LogDir | Out-Null
if(Test-Path -LiteralPath $Log){Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue}
$sessionName=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N')
$script:SessionDir=Join-Path $BackupBase $sessionName
New-Item -ItemType Directory -Force -Path $script:SessionDir | Out-Null
$script:OverlayStateRoot=Join-Path $script:SessionDir 'overlay-state'
$provenancePath=Join-Path $script:SessionDir 'active-extension-provenance.json'
$protectedBackup=Join-Path $script:SessionDir 'protected-persistence'
$originalIndexBackup=Join-Path $script:SessionDir 'index.original.bin'
$success=$false
$primaryError=$null
$runtime=$null
$originalTree=$null
$originalIndexHash=$null
$originalConfigHash=$null
$originalPayloadHashes=@{}
$conditions=New-Object System.Collections.Generic.List[object]
$allRows=New-Object System.Collections.Generic.List[object]
$optimizedTargets=@()

try{
    $runtime=Assert-AcceptedRuntimeBaseline
    Suspend-Resident
    Stop-SpotifyForVariant
    Backup-ProtectedPersistence $protectedBackup | Out-Null

    $originalIndexHash=Get-Sha256Lower $IndexPath
    [IO.File]::WriteAllBytes($originalIndexBackup,[IO.File]::ReadAllBytes($IndexPath))
    if((Get-Sha256Lower $originalIndexBackup)-ne $originalIndexHash){throw 'Original index backup verification failed.'}
    $originalConfigHash=Get-Sha256Lower $ConfigPath
    $originalTree=Get-TreeFingerprint $XpuiPath
    if($originalTree.file_count -lt $AcceptedXpuiMinFiles){throw "Active xpui tree is unexpectedly small: $($originalTree.file_count) files."}

    $provenance=Invoke-OverlayToolJson -Operation Collect -ProvenancePath $provenancePath
    foreach($name in @('better-local-files','playlist-maker')){
        $p=$provenance.targets.PSObject.Properties[$name]
        if($null -ne $p){
            $activePath=[string]$p.Value.active_extension_path
            if(Test-SafePath $activePath 'Leaf'){$originalPayloadHashes[$activePath]=Get-Sha256Lower $activePath}
        }
    }
    $audit=Invoke-OverlayToolJson -Operation Audit -ProvenancePath $provenancePath
    $exact=@($audit.targets|Where-Object{$_.eligible})
    if($exact.Count -eq 0){
        $report=[ordered]@{
            schema=1;version=$Version;generated_at=(Get-Date).ToString('o');status='skipped-no-exact-targets';runtime=$runtime
            provenance=$provenance;overlay_audit=$audit;optimized_targets=@();conditions=@();safety=[ordered]@{mutation_started=$false;resident_restored=$false}
        }
        Write-JsonUtf8NoBom $ReportJson $report
        throw 'No exact active Better Local Files/Playlist Maker target matched the pinned overlay provenance. Optimization was skipped without mutating xpui.'
    }

    Start-SpotifyAndWarmup 'BASELINE_A'
    $mA=Measure-TransitionCondition 'BASELINE_A'
    $cA=New-ConditionResult 'BASELINE_A' $mA
    $conditions.Add($cA);foreach($r in $mA.rows){$allRows.Add($r)}
    Write-LabLog ("Completed BASELINE_A: CPU p95={0}% renderer p95={1}%" -f $cA.metrics.cpu_percent.p95,$cA.metrics.renderer_cpu_percent.p95) 'OK'

    Stop-SpotifyForVariant
    $apply=Invoke-OverlayToolJson -Operation Apply -ProvenancePath $provenancePath
    if($apply.status -ne 'applied'){throw "Overlay was not applied after exact audit: status=$($apply.status) reason=$($apply.reason)"}
    $script:OverlayApplied=$true
    $optimizedTargets=@($apply.optimized_targets)

    Start-SpotifyAndWarmup 'OVERLAY'
    $mO=Measure-TransitionCondition 'OVERLAY'
    $cO=New-ConditionResult 'OVERLAY' $mO
    $conditions.Add($cO);foreach($r in $mO.rows){$allRows.Add($r)}
    Write-LabLog ("Completed OVERLAY: CPU p95={0}% renderer p95={1}% evidence={2}" -f $cO.metrics.cpu_percent.p95,$cO.metrics.renderer_cpu_percent.p95,$cO.workload_policy_status) 'OK'

    Stop-SpotifyForVariant
    $restore=Invoke-OverlayToolJson -Operation Restore
    if($restore.status -ne 'restored'){throw "Overlay restore did not report restored: $($restore.status)"}
    $script:OverlayApplied=$false
    Assert-FinalSafetyState $originalIndexHash $originalTree $originalConfigHash $originalPayloadHashes

    Start-SpotifyAndWarmup 'BASELINE_B'
    $mB=Measure-TransitionCondition 'BASELINE_B'
    $cB=New-ConditionResult 'BASELINE_B' $mB
    $conditions.Add($cB);foreach($r in $mB.rows){$allRows.Add($r)}
    Write-LabLog ("Completed BASELINE_B: CPU p95={0}% renderer p95={1}%" -f $cB.metrics.cpu_percent.p95,$cB.metrics.renderer_cpu_percent.p95) 'OK'

    Stop-SpotifyForVariant
    Assert-FinalSafetyState $originalIndexHash $originalTree $originalConfigHash $originalPayloadHashes

    $baselineAverage=Average-TwoMetricSummaries $cA.metrics $cB.metrics
    $comparison=Get-OverlayComparison $baselineAverage $cO
    $baselineDrift=[pscustomobject]@{
        cpu_p95_points=[Math]::Round([Math]::Abs([double]$cA.metrics.cpu_percent.p95-[double]$cB.metrics.cpu_percent.p95),2)
        renderer_p95_points=[Math]::Round([Math]::Abs([double]$cA.metrics.renderer_cpu_percent.p95-[double]$cB.metrics.renderer_cpu_percent.p95),2)
        working_set_p95_mb=[Math]::Round([Math]::Abs([double]$cA.metrics.working_set_mb.p95-[double]$cB.metrics.working_set_mb.p95),1)
    }

    $report=[ordered]@{
        schema=1
        version=$Version
        generated_at=(Get-Date).ToString('o')
        status='verified'
        runtime=$runtime
        optimized_targets=$optimizedTargets
        provenance=$provenance
        overlay_audit=$audit
        baseline_drift=$baselineDrift
        conditions=@($conditions.ToArray()|ForEach-Object{[pscustomobject]@{
            label=$_.label;metrics=$_.metrics;transitions=$_.transitions;active_transition_windows=$_.active_transition_windows
            workload_policy_status=$_.workload_policy_status;min_spotify_process_count=$_.min_spotify_process_count;end_spotify_process_count=$_.end_spotify_process_count
        }})
        overlay_savings=$comparison
        safety=[ordered]@{
            original_index_sha256=$originalIndexHash
            original_tree=$originalTree
            original_config_sha256=$originalConfigHash
            protected_payload_sha256=$originalPayloadHashes
            exact_index_restore=$true
            exact_tree_restore=$true
            config_unchanged=$true
            payloads_unchanged=$true
            persistence_backup_only=$true
        }
    }
    Write-JsonUtf8NoBom $ReportJson $report
    Write-RuntimeTextReport ([pscustomobject]$report)
    if($allRows.Count -gt 0){$allRows.ToArray()|Export-Csv -LiteralPath $RawCsv -NoTypeInformation -Encoding UTF8}
    $success=$true
    Write-LabLog 'PERFORMANCE OVERLAY RUNTIME VALIDATION VERIFIED' 'OK'
} catch {
    $primaryError=$_.Exception.Message
    Write-LabLog $primaryError 'ERROR'
} finally {
    try{Stop-SpotifyForVariant}catch{Write-LabLog ("Final Spotify stop warning: "+$_.Exception.Message) 'WARN'}
    if($script:OverlayApplied -or (Test-Path -LiteralPath (Join-Path $script:OverlayStateRoot 'active-state.json'))){
        try{
            $rest=Invoke-OverlayToolJson -Operation Restore
            if($rest.status -eq 'restored'){$script:OverlayApplied=$false;Write-LabLog 'Overlay restored during final cleanup.' 'OK'}
        }catch{Write-LabLog ("Final overlay restore failed without forcing an overwrite: "+$_.Exception.Message) 'ERROR'}
    }
    if($null -ne $originalTree -and $originalIndexHash -and $originalConfigHash){
        try{Assert-FinalSafetyState $originalIndexHash $originalTree $originalConfigHash $originalPayloadHashes;Write-LabLog 'Final xpui/config/payload safety verification passed.' 'OK'}catch{Write-LabLog ("Final safety verification failed: "+$_.Exception.Message) 'ERROR';$success=$false}
    }
    try{Restore-Resident}catch{Write-LabLog ("Resident restore failure: "+$_.Exception.Message) 'ERROR';$success=$false}
}

if(-not $success){throw $(if($primaryError){$primaryError}else{'Runtime validation failed; see the error log.'})}
Write-Host ''
Write-Host 'PERFORMANCE OVERLAY RUNTIME VALIDATION VERIFIED' -ForegroundColor Green
Write-Host ("Report: {0}" -f $ReportTxt)
Write-Host ("JSON:   {0}" -f $ReportJson)
Write-Host ("CSV:    {0}" -f $RawCsv)
'''

README = r'''# Spotify Control Performance Overlay Runtime Validator v0.1.0

This is a one-shot validation package. It does **not** install a replacement player and does not modify the production Spotify Control updater.

It validates a guarded lazy-loading overlay for the currently pinned Better Local Files and Playlist Maker background extensions.

## Before running

1. In Spotify, choose a playlist or album with at least 6 playable tracks.
2. Pause playback on a normal track and exit Spotify normally.
3. Extract this ZIP to a normal folder.
4. Run `RUN_PERFORMANCE_OVERLAY_RUNTIME.cmd` normally, **not as Administrator**.
5. Do not interact with Spotify until the validator finishes.

Residual Spotify tray/helper processes are closed safely by the validator after accepted-runtime checks. You do not need to use Task Manager.

## What it changes temporarily

Only active `xpui/index.html` plus one owned loader file under active xpui are changed during the OVERLAY condition. The original Better Local Files and Playlist Maker `extension.js` files are never patched, deleted, renamed, or replaced.

The validator automatically restores the exact original index and removes its owned loader before BASELINE_B. It then verifies the complete xpui tree fingerprint, config hash, and protected app payload hashes.

## What it never mutates

- Spotify login/settings and Browser/Default persistence
- IndexedDB/localStorage/session storage (a safety copy is created only)
- Spicetify config or `spicetify apply/backup/restore`
- Marketplace data
- ivLyrics, Tagify, Splitify
- Star Ratings playlists/data
- user.css / colors.css
- SC Cover Ambience
- Better Local Files / Playlist Maker payload files

If active extension bytes do not exactly match the pinned upstream SHA-256, that target is skipped rather than patched. Unknown/new upstream versions remain intact.

Reports are written under `%LOCALAPPDATA%\SpotifyControl\reports` and the error log under `%LOCALAPPDATA%\SpotifyControl\logs`.
'''

RUN_CMD = r'''@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime-validator.ps1" -Action Run
set EC=%ERRORLEVEL%
echo.
if not "%EC%"=="0" echo Runtime validation exited with code %EC%.
pause
exit /b %EC%
'''

SELFTEST_CMD = r'''@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime-validator.ps1" -Action SelfTest
exit /b %ERRORLEVEL%
'''


def build() -> dict[str, bytes]:
    source = get_validated_v041_script()
    blocks = extract_function_blocks(source)
    names = [name for name, _ in blocks]
    required = {
        "Write-LabLog",
        "Test-SafePath",
        "Get-Sha256Lower",
        "Invoke-Native",
        "Get-TreeFingerprint",
        "Suspend-Resident",
        "Restore-Resident",
        "Stop-SpotifyForVariant",
        "Wait-SpotifyReady",
        "Assert-AcceptedRuntimeBaseline",
        "Measure-TransitionCondition",
        "Get-RoleSnapshot",
        "Send-MediaKey",
        "Backup-ProtectedPersistence",
        "Get-MetricSummary",
        "Average-TwoMetricSummaries",
    }
    missing = sorted(required.difference(names))
    if missing:
        raise RuntimeError(f"Validated v0.4.1 helper extraction missing: {missing}")
    if len(names) != len(set(names)):
        raise RuntimeError("Validated v0.4.1 unexpectedly contains duplicate function names")

    inherited = "\n\n".join(block for _, block in blocks)
    runtime = (HEADER + "\n" + inherited + "\n" + CUSTOM + "\n" + MAIN).replace("\r\n", "\n").encode("utf-8-sig")

    files: dict[str, bytes] = {
        "runtime-validator.ps1": runtime,
        "RUN_PERFORMANCE_OVERLAY_RUNTIME.cmd": RUN_CMD.replace("\n", "\r\n").encode("utf-8"),
        "SELFTEST.cmd": SELFTEST_CMD.replace("\n", "\r\n").encode("utf-8"),
        "README.md": README.replace("\r\n", "\n").encode("utf-8"),
    }
    for rel in OVERLAY_FILES:
        src = ROOT / rel
        if not src.is_file():
            raise RuntimeError(f"Missing overlay source: {rel}")
        dest = "overlay/" + rel.split("performance/overlay/", 1)[1]
        files[dest] = src.read_bytes()

    sums = []
    for name in sorted(files):
        sums.append(f"{sha256(files[name])} *{name}")
    files["SHA256SUMS.txt"] = ("\n".join(sums) + "\n").encode("ascii")
    return files


def validate(files: dict[str, bytes]) -> None:
    script = files["runtime-validator.ps1"].decode("utf-8-sig")
    required_fragments = [
        '$TransitionSeconds = 50',
        '$NextOffsets = @(12,25,38)',
        "BASELINE_A",
        "OVERLAY",
        "BASELINE_B",
        "Invoke-OverlayToolJson -Operation Collect",
        "Invoke-OverlayToolJson -Operation Apply",
        "Invoke-OverlayToolJson -Operation Restore",
        "Assert-FinalSafetyState",
        "Backup-ProtectedPersistence",
        "Suspend-Resident",
        "Restore-Resident",
        "No exact active Better Local Files/Playlist Maker target",
    ]
    for fragment in required_fragments:
        if fragment not in script:
            raise RuntimeError(f"Runtime package invariant missing: {fragment}")
    forbidden = [
        "spicetify apply",
        "spicetify backup",
        "spicetify restore",
        "Remove-Item -LiteralPath $ConfigPath",
        "Set-Content -LiteralPath $ConfigPath",
    ]
    lowered = script.lower()
    for fragment in forbidden:
        if fragment.lower() in lowered:
            raise RuntimeError(f"Forbidden runtime mutation phrase: {fragment}")

    target = json.loads(files["overlay/targets/pithaya-optional-custom-apps.json"].decode("utf-8"))
    ids = {item["id"] for item in target["targets"]}
    if ids != {"better-local-files", "playlist-maker"}:
        raise RuntimeError(f"Unexpected overlay target set: {ids}")
    if "sc-cover-ambience" in json.dumps(target):
        raise RuntimeError("SC Cover Ambience must not be an overlay target")

    sums = files["SHA256SUMS.txt"].decode("ascii").splitlines()
    expected_names = sorted(name for name in files if name != "SHA256SUMS.txt")
    actual_names = sorted(line.split(" *", 1)[1] for line in sums)
    if actual_names != expected_names:
        raise RuntimeError("SHA256SUMS inventory mismatch")
    for line in sums:
        digest, name = line.split(" *", 1)
        if sha256(files[name]) != digest:
            raise RuntimeError(f"SHA256SUMS mismatch for {name}")


def write_zip(files: dict[str, bytes]) -> None:
    if OUT.exists():
        OUT.unlink()
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_STORED) as zf:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, (2026, 10, 25, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o100644 << 16
            zf.writestr(info, files[name])


if __name__ == "__main__":
    files = build()
    validate(files)
    write_zip(files)
    with zipfile.ZipFile(OUT) as zf:
        bad = zf.testzip()
        if bad:
            raise RuntimeError(f"ZIP CRC failure: {bad}")
        if sorted(zf.namelist()) != sorted(files):
            raise RuntimeError("ZIP inventory mismatch")
        for name, data in files.items():
            if zf.read(name) != data:
                raise RuntimeError(f"ZIP byte mismatch: {name}")
    print("PERFORMANCE_OVERLAY_RUNTIME_PACKAGE_PASS", OUT.stat().st_size, sha256(OUT.read_bytes()))
    print("RUNTIME_SCRIPT_PASS", len(files["runtime-validator.ps1"]), sha256(files["runtime-validator.ps1"]))
