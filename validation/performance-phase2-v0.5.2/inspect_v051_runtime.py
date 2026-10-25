from pathlib import Path
import runpy, zipfile
R=Path.cwd()
runpy.run_path('validation/performance-phase2-v0.5.1/build_v051.py', run_name='__main__')
z=R/'SpotifyControl-Track-Transition-Direct-Patch-Acceptance-v0.5.1.zip'
with zipfile.ZipFile(z) as a:
    s=a.read('track-transition-direct-patch-acceptance.ps1').decode('utf-8-sig').replace('\r\n','\n')

def body(name):
    marker='function '+name+' {'
    a=s.index(marker)
    b=s.find('\nfunction ',a+1)
    if b<0:b=s.find('\ntry{',a+1)
    print('\n===== '+name+' =====\n'+s[a:b].strip()+'\n')
for n in ['Send-MediaKey','Wait-SpotifyReady','Start-SpotifyForCondition','Stop-SpotifyForCondition','Measure-TransitionCondition','Analyze-Transitions','Get-WorkloadPolicy']:
    body(n)
