from pathlib import Path
import base64, hashlib, io, shutil, zipfile

SOURCE_ZIP_SHA256 = '7c6bf4685a4abc681be93d2406a1505d6de67dea5cf3866ae356f414aa68a350'
SOURCE_FILE_SHA256 = {
    'track-transition-isolation.ps1': 'aa1039bc74e336e9278b4a9f03496a95057688ae6d87679d17e349286759367c',
    'RUN_TRACK_TRANSITION_ISOLATION.cmd': '3c9619b85eaf1ab1ac5383b7d23631395bdc047ac361f36b7eb87bb85ed80bda',
    'SELFTEST.cmd': 'fe6a127f79ae4aab2e475c1598ae97cb9e6feb63b1ad4ffbe0ea4f0fcf211700',
    'README.md': '59e28a604e269b9a85578ec93adb829fa863ca90a5ce4e9a55297f164714175c',
}

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

chunk_dir = Path('validation/performance-phase2-v0.3.0/payload')
chunks = sorted(chunk_dir.glob('chunk-*.txt'))
assert [p.name for p in chunks] == [f'chunk-{i:03d}.txt' for i in range(6)], [p.name for p in chunks]
encoded = ''.join(p.read_text(encoding='ascii') for p in chunks)
raw = base64.b64decode(encoded, validate=True)
assert sha(raw) == SOURCE_ZIP_SHA256, (sha(raw), SOURCE_ZIP_SHA256)

out = Path('phase2-package')
shutil.rmtree(out, ignore_errors=True)
out.mkdir()
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    assert sorted(z.namelist()) == sorted(SOURCE_FILE_SHA256)
    for name, expected in SOURCE_FILE_SHA256.items():
        data = z.read(name)
        assert sha(data) == expected, (name, sha(data), expected)
        (out / name).write_bytes(data)

sums = [f'{sha((out/name).read_bytes())}  {name}' for name in sorted(SOURCE_FILE_SHA256)]
(out / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n', encoding='ascii', newline='\n')

final = Path('SpotifyControl-Track-Transition-Isolation-v0.3.0.zip')
if final.exists():
    final.unlink()
with zipfile.ZipFile(final, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for name in sorted([*SOURCE_FILE_SHA256, 'SHA256SUMS.txt']):
        data = (out / name).read_bytes()
        zi = zipfile.ZipInfo(name, date_time=(2026, 10, 25, 0, 3, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = 0o644 << 16
        z.writestr(zi, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
with zipfile.ZipFile(final) as z:
    assert z.testzip() is None
    for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
        h, name = line.split('  ', 1)
        assert sha(z.read(name)) == h
print('PHASE2_PACKAGE_BUILD_PASS', len(final.read_bytes()), sha(final.read_bytes()))
for name, expected in SOURCE_FILE_SHA256.items():
    print('SOURCE', name, expected)
