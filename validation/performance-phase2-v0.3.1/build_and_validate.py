from pathlib import Path
import base64, hashlib, io, shutil, zipfile

ROOT = Path('validation/performance-phase2-v0.3.1')
PAYLOAD = ROOT / 'payload'
PARTS = [
    ('chunk-000.txt', 4096, '0ca8ef5f7b34c876c1355bb1203b1f61487b68e206d6befc71960e9c3e86cd8f'),
    ('chunk-001.txt', 4096, '9d51df08ca410ef2ff93c836be05a87b822020d3692debb9029824bf50abfe1a'),
    ('rest.txt', 15744, 'e17945a47744814f0a60b21bfd2b7b81604f4a515cf6c28b88b86910ed82d362'),
]
EXPECTED_ZIP_SIZE = 17950
EXPECTED_ZIP_SHA256 = '6bdd9d81c327471b6cf27be877c587e4b67d34456823fd5d722d1e854dd99bb9'
EXPECTED_ENTRIES = {
    'README.md': (3997, '009cda12bcfdbd2e743efc2d6391d9c76297d995f402f7ecfd9e39859c6e17c7'),
    'RUN_TRACK_TRANSITION_ISOLATION.cmd': (785, '5aff48af4bf526c8d2233be81b1c119805de4aa95aa1b75e15c0365ab91d2e6c'),
    'SELFTEST.cmd': (201, '150b228128e92926be6aaf622cbee87b2f18faf3a5d2e7f22710d817d0e5be37'),
    'SHA256SUMS.txt': (353, '0044bb92f640891fefb760bf0c379dad7e6ce895b4d56eefe61605ceb1bbc4a2'),
    'track-transition-isolation.ps1': (52154, '4ca577fc4e3b125ad8d13e4b86f089afc87168c761aab1d1a58302a6332bf007'),
}

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

encoded_parts = []
for name, size, expected in PARTS:
    data = (PAYLOAD / name).read_bytes()
    assert len(data) == size, (name, len(data), size)
    assert sha(data) == expected, (name, sha(data), expected)
    data.decode('ascii')
    encoded_parts.append(data)

encoded = b''.join(encoded_parts)
assert len(encoded) == 23936
assert sha(encoded) == '08719dc52b0986013a628e6d5f922cceee2d3dea300ae82aca5d9740d3c3f1ff'
raw = base64.b64decode(encoded, validate=True)
assert len(raw) == EXPECTED_ZIP_SIZE, len(raw)
assert sha(raw) == EXPECTED_ZIP_SHA256, sha(raw)

with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    assert sorted(z.namelist()) == sorted(EXPECTED_ENTRIES), z.namelist()
    for name, (size, expected) in EXPECTED_ENTRIES.items():
        data = z.read(name)
        assert len(data) == size, (name, len(data), size)
        assert sha(data) == expected, (name, sha(data), expected)
    sums = z.read('SHA256SUMS.txt').decode('ascii').splitlines()
    assert len(sums) == 4, sums
    for line in sums:
        h, name = line.split('  ', 1)
        assert name != 'SHA256SUMS.txt'
        assert sha(z.read(name)) == h, (name, h, sha(z.read(name)))

outdir = Path('phase2-v031')
shutil.rmtree(outdir, ignore_errors=True)
outdir.mkdir()
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    z.extractall(outdir)

outzip = Path('SpotifyControl-Track-Transition-Isolation-v0.3.1.zip')
outzip.write_bytes(raw)
assert len(outzip.read_bytes()) == EXPECTED_ZIP_SIZE
assert sha(outzip.read_bytes()) == EXPECTED_ZIP_SHA256
print('PHASE2_V031_RECONSTRUCTION_PASS', EXPECTED_ZIP_SIZE, EXPECTED_ZIP_SHA256)
print('PHASE2_V031_SCRIPT', EXPECTED_ENTRIES['track-transition-isolation.ps1'][0], EXPECTED_ENTRIES['track-transition-isolation.ps1'][1])
