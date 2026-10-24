from pathlib import Path
import hashlib, shutil, subprocess, zipfile

base=Path('base-v121.zip')
raw=base.read_bytes()
assert len(raw)==34841, len(raw)
assert hashlib.sha256(raw).hexdigest()=='962a09cd5adbcb4dd49046dd672b44252238f43859f5b97a4ce70f8492068fd8'

# Derive the already-reviewed v1.3 intermediate from the exact final v1.2.1 artifact,
# bypassing the obsolete v1.2.1 workflow-reconstruction code that is sensitive to runner paths.
subprocess.check_call(['git','fetch','origin','refs/heads/validate/stage14-v1.3.0:refs/remotes/origin/validate/stage14-v1.3.0'])
v130=subprocess.check_output(['git','show','origin/validate/stage14-v1.3.0:validation/stage14-v1.3.0/build_stage14_v130.py']).decode('utf-8')
start=v130.index('# Rebuild the exact previously Windows-validated v1.2.1 package')
end=v130.index('for old,new in [',start)
replacement="""# Exact v1.2.1 artifact supplied by this validation run.\nbase_zip=Path('base-v121.zip')\nbase_raw=base_zip.read_bytes()\nassert len(base_raw)==34841\nassert hashlib.sha256(base_raw).hexdigest()=='962a09cd5adbcb4dd49046dd672b44252238f43859f5b97a4ce70f8492068fd8'\nout=Path('stage14-v120-unpacked')\nshutil.rmtree(out,ignore_errors=True)\nout.mkdir(parents=True)\nwith zipfile.ZipFile(base_zip) as z:\n    assert z.testzip() is None\n    z.extractall(out)\nrunp=out/'RUN_RUNTIME_ACCEPTANCE.ps1'\nrun=runp.read_text(encoding='utf-8-sig')\n"""
v130=v130[:start]+replacement+v130[end:]
exec(compile(v130,'artifact-based-stage14-v130.py','exec'),{'__name__':'__main__'})
assert Path('SpotifyControl-Windows-Runtime-Acceptance-v1.3.0.zip').is_file()
assert Path('stage14-v120-unpacked').is_dir()

# Execute the v1.4 delta builder from that exact v1.3 intermediate.
# Two v1.3 lineage quirks need explicit handling rather than the single-occurrence table:
# 1) the self-update function token appears twice (definition + call);
# 2) the v1.3 success display string still says v0.6.15/r5 although its logic targets r6.
v140=Path('validation/stage14-v1.4.0/build_stage14_v140.py').read_text(encoding='utf-8')
for pair in [
    '("Invoke-TrustedV0616SelfUpdateAcceptance","Invoke-TrustedV0617SelfUpdateAcceptance"),\n',
    '("Self-update v0.6.16/r6:","Self-update v0.6.17/r7:"),\n',
]:
    assert v140.count(pair)==1,pair
    v140=v140.replace(pair,'',1)
marker="]: run=one(run,a,b)\n"
assert v140.count(marker)==1
v140=v140.replace(marker,"]: run=one(run,a,b)\nassert run.count('Invoke-TrustedV0616SelfUpdateAcceptance')==2,run.count('Invoke-TrustedV0616SelfUpdateAcceptance')\nrun=run.replace('Invoke-TrustedV0616SelfUpdateAcceptance','Invoke-TrustedV0617SelfUpdateAcceptance')\nstale=\"Self-update v0.6.15/r5:     VERIFIED / rollback + fresh commit\"\nassert run.count(stale)==1,run.count(stale)\nrun=run.replace(stale,\"Self-update v0.6.17/r7:     VERIFIED / 2-edge rollback + fresh commit\",1)\n",1)
start=v140.index('# Reuse v1.3 builder only as a deterministic bridge')
end=v140.index('for a,b in [',start)
replacement="""# Exact v1.3 intermediate was produced immediately above.\nbase=Path('SpotifyControl-Windows-Runtime-Acceptance-v1.3.0.zip')\nassert base.is_file()\nout=Path('stage14-v120-unpacked')\nassert out.is_dir()\nrunp=out/'RUN_RUNTIME_ACCEPTANCE.ps1'\nrun=runp.read_text(encoding='utf-8-sig')\n"""
v140=v140[:start]+replacement+v140[end:]
exec(compile(v140,'artifact-based-stage14-v140.py','exec'),{'__name__':'__main__'})
final=Path('SpotifyControl-Windows-Runtime-Acceptance-v1.4.0.zip')
assert final.is_file()
print('ARTIFACT_BASED_V140',final.stat().st_size,hashlib.sha256(final.read_bytes()).hexdigest())
