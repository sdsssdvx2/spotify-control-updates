from pathlib import Path
import base64, hashlib, io, shutil, zipfile

ROOT = Path('validation/performance-phase2-v0.3.1')
PAYLOAD = ROOT / 'payload'
PARTS = [
    ('chunk-000.txt', 4096, 'eb116d7a05dc2a2378db9fc3529311e942846c663d0e4623ab67f4ef8f4cdbb3'),
    ('chunk-001.txt', 4096, '9d51df08ca410ef2ff93c836be05a87b822020d3692debb9029824bf50abfe1a'),
    ('rest.txt', 15744, 'fd9b81b929eb6321b109c8d27223490abea0d9acfdd31666d33d72d335a910aa'),
]
EXPECTED_ZIP_SIZE = 17950
EXPECTED_ZIP_SHA256 = 'a7956053f0bf8e8d6b20558894873e9a9a6d31e4131ce8a1c6a7226ea7eb127c'
EXPECTED_ENTRIES = {
    'README.md': (3997, '009cda12bcfdbd2e743efc2d6391d9c76297d995f402f7ecfd9e39859c6e17c7'),
    'RUN_TRACK_TRANSITION_ISOLATION.cmd': (785, '5aff48af4bf526c8d2233be81b1c119805de4aa95aa1b75e15c0365ab91d2e6c'),
    'SELFTEST.cmd': (201, '150b228128e92926be6aaf622cbee87b2f18faf3a5d2e7f22710d817d0e5be37'),
    'SHA256SUMS.txt': (353, 'e85a50b0af4287e3c5b7b835ce0ef10c7b43705bcf4e7df30c8fda49287c2fd1'),
    'track-transition-isolation.ps1': (52154, '5bf5e9ea10795f106c004f0ef578c111d2506a8f380456d34de06215eb41101b'),
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
assert sha(encoded) == '2906ae40553434283c7574b2bc35c1a7e1b8e03c4c455d6f1c9bbdbec390fad1'
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
