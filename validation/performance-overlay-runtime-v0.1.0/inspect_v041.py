from pathlib import Path
import subprocess, tempfile, zipfile, re

SRC_COMMIT='4d9eb71d1fa97b70d839dc887cdc8f5531d2ff8b'
BUILDER='validation/performance-phase2-v0.4.1/build_and_validate.py'

with tempfile.TemporaryDirectory() as td:
    td=Path(td)
    subprocess.run(['git','worktree','add','--detach',str(td/'src'),SRC_COMMIT],check=True)
    src=td/'src'
    subprocess.run(['python',BUILDER],cwd=src,check=True)
    z=src/'SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.1.zip'
    with zipfile.ZipFile(z) as zz:
        s=zz.read('track-transition-isolation.ps1').decode('utf-8-sig')

    def function_block(name):
        pat=re.compile(r'(?m)^function\s+'+re.escape(name)+r'\s*\{')
        m=pat.search(s)
        if not m:return None
        start=m.start(); depth=0; in_s=False; in_d=False; i=m.end()-1
        while i<len(s):
            ch=s[i]
            if ch=='`': i+=2; continue
            if not in_d and ch=="'": in_s=not in_s
            elif not in_s and ch=='"': in_d=not in_d
            elif not in_s and not in_d:
                if ch=='{': depth+=1
                elif ch=='}':
                    depth-=1
                    if depth==0:return s[start:i+1]
            i+=1
        return None

    wanted=[
        'Write-LabLog','Test-SafePath','Get-Sha256Lower','ConvertTo-NativeQuotedArgument','Invoke-Native','Get-SpicetifyExe','Get-IniValue','Get-IniList','Get-TreeFingerprint',
        'Get-ResidentProcesses','Wait-ControlWorkersIdle','Suspend-Resident','Restore-Resident',
        'Stop-SpotifyForVariant','Prepare-Variant','Wait-SpotifyReady','Wait-SpotifyRestartStable',
        'Assert-AcceptedRuntimeBaseline','Measure-TransitionCondition','Get-RoleSnapshot',
        'Get-SpotifyPidSet','Update-RoleCache','Get-ProcessRoleFromCommandLine',
        'Get-LogicalCpuCount','Add-MediaKeyType','Send-MediaKey','Copy-Tree','Backup-ProtectedPersistence',
        'Test-IsElevated','Get-Median','Get-Percentile','Get-MetricSummary','Analyze-Transitions','Get-WorkloadPolicy','Average-TwoMetricSummaries','Build-Comparison'
    ]
    print('SCRIPT_LENGTH',len(s.encode('utf-8-sig')))
    for n in wanted:
        b=function_block(n)
        print('\n=== BLOCK',n,'FOUND' if b else 'MISSING','===')
        if b: print(b)
