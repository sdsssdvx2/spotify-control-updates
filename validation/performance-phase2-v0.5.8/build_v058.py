from pathlib import Path
import base64, lzma, zipfile, shutil, hashlib, re

root = Path(__file__).parent
payload = (root / 'build_v058.payload.b64').read_text(encoding='ascii').strip()
code = lzma.decompress(base64.b64decode(payload))
exec(compile(code, 'build_v058.selfcontained.py', 'exec'), globals(), globals())

# Harden the residual-process shutdown edge without changing the media-command-free
# measurement surface. If force termination fails after exact audio restoration,
# Spotify is re-armed to verified mute + volume 0 before any resume is allowed.
repo = root.parents[1]
out = repo / 'SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.8.zip'
work = repo / 'phase2-v058-wrapper-hardening'
shutil.rmtree(work, ignore_errors=True)
work.mkdir(parents=True)
with zipfile.ZipFile(out) as z:
    if z.testzip() is not None:
        raise RuntimeError('v0.5.8 pre-hardening ZIP CRC failure')
    z.extractall(work)

ps1 = work / 'idle-overlay-media-command-free-revalidation.ps1'
raw = ps1.read_bytes()
bom = b'\xef\xbb\xbf'
if not raw.startswith(bom):
    raise RuntimeError('Expected UTF-8 BOM on v0.5.8 PowerShell script')
text = raw[len(bom):].decode('utf-8')
start = text.index('function Stop-SpotifyForVariant {')
match = re.search(r'\r\nfunction |\r\ntry\s*\{', text[start + 20:])
if match is None:
    raise RuntimeError('Could not bound Stop-SpotifyForVariant')
end = start + 20 + match.start()

new_stop_lf = r'''function Stop-SpotifyForVariant {
    $procs=@(Get-Process Spotify -ErrorAction SilentlyContinue)
    if($procs.Count -eq 0){[void](Restore-SpotifyAudioForTest -BestEffort);return}
    [void](Hide-SpotifyWindowsForSetup)

    # First request normal hidden-window shutdown while the mute+volume-zero guard remains armed.
    try{[void](Close-SpotifyWindowsHidden)}catch{}
    for($i=0;$i -lt 12;$i++){
        if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -eq 0){[void](Restore-SpotifyAudioForTest -BestEffort);Write-LabLog 'Spotify exited while the audio guard remained armed.' 'OK';return}
        Start-Sleep -Milliseconds 250
    }

    # If Spotify stays resident, suspend all Spotify processes BEFORE restoring exact audio state,
    # then terminate them while still suspended. If termination itself fails, re-arm and verify
    # mute + volume 0 BEFORE resuming so there is still no audible live-process window.
    $frozen=[SpotifyControlProcessFreeze]::SuspendAll();$terminated=$false;$resilencedBeforeResume=$false
    try{
        if($script:SpotifyAudioGuardArmed){[void](Restore-SpotifyAudioForTest)}
        @(Get-Process Spotify -ErrorAction SilentlyContinue)|Stop-Process -Force -ErrorAction SilentlyContinue
        for($i=0;$i -lt 40;$i++){
            if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -eq 0){$terminated=$true;break}
            Start-Sleep -Milliseconds 100
        }
        if(-not $terminated){
            [void](Arm-SpotifySilentGuard)
            [void](Refresh-SpotifySilentForTest)
            $resilencedBeforeResume=$true
        }
    }finally{
        if(-not $terminated){
            if(-not $resilencedBeforeResume){throw 'Refusing to resume residual Spotify processes because verified mute + volume 0 could not be re-armed.'}
            try{[void][SpotifyControlProcessFreeze]::ResumeAll()}catch{throw ('Spotify remained suspended after failed termination because safe resume failed: '+$_.Exception.Message)}
        }
    }
    if(-not $terminated){throw 'Spotify did not terminate while suspended; it was resumed only after verified mute + volume 0 was re-armed.'}
    Write-LabLog ("Spotify audio state restored only while Spotify processes were suspended, then processes were terminated without resume; suspended process(es)={0}." -f $frozen) 'OK'
}'''
new_stop = new_stop_lf.replace('\n', '\r\n')
text = text[:start] + new_stop + text[end:]
ps1.write_bytes(bom + text.encode('utf-8'))

# Rebuild the checksum manifest after the hardening patch with fixed LF bytes.
entries = []
for path in sorted(work.rglob('*')):
    if path.is_file() and path.name != 'SHA256SUMS.txt':
        rel = path.relative_to(work).as_posix()
        entries.append((rel, hashlib.sha256(path.read_bytes()).hexdigest()))
(work / 'SHA256SUMS.txt').write_bytes(''.join(f'{sha}  {rel}\n' for rel, sha in entries).encode('ascii'))

# Repack using stable metadata. Windows CI is the canonical artifact platform.
if out.exists():
    out.unlink()
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_STORED) as z:
    for path in sorted(work.rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(work).as_posix()
        zi = zipfile.ZipInfo(rel, (2026, 10, 26, 5, 55, 0))
        zi.compress_type = zipfile.ZIP_STORED
        zi.create_system = 0
        zi.external_attr = 0
        z.writestr(zi, path.read_bytes(), compress_type=zipfile.ZIP_STORED)

shutil.rmtree(work, ignore_errors=True)
print('V058_WRAPPER_HARDENED_PS1', ps1 if ps1.exists() else 'repacked')
print('V058_WRAPPER_HARDENED_ZIP', out.stat().st_size, hashlib.sha256(out.read_bytes()).hexdigest())
