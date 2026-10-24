from pathlib import Path
import base64, hashlib, io, shutil, zipfile

ROOT = Path('validation/performance-phase2-v0.3.1')
PAYLOAD = ROOT / 'payload'
PARTS = [
    ('chunk-000.txt', 4096, 'eb116d7a05dc2a2378db9fc3529311e942846c663d0e4623ab67f4ef8f4cdbb3'),
    ('chunk-001.txt', 4096, '9d51df08ca410ef2ff93c836be05a87b822020d3692debb9029824bf50abfe1a'),
    ('chunk-002.txt', 4096, '1d39088ff7cb5e0e55ac733f1bb65f07c77dc3e0f5ea796a8d2fa56320f95f7c'),
    ('chunk-003.txt', 4096, 'f4444c70fa758b3038e471d8bf9f678115ec9f8defc9f0b6409c7d926f83c5dc'),
    ('chunk-004.txt', 4096, '4bf4434e2f21ded2b53f04e9c6a4b8f4aa0922a2b3a43d939f7e9b212d5198b3'),
    ('chunk-005.txt', 3456, '9763ff54b6da8d970ec900595ac08c3de5fe719db53bdf5276da735e1699ad13'),
]
SOURCE_ZIP_SIZE = 17950
SOURCE_ZIP_SHA256 = 'a7956053f0bf8e8d6b20558894873e9a9a6d31e4131ce8a1c6a7226ea7eb127c'
SOURCE_ENTRIES = {
    'README.md': (3997, '009cda12bcfdbd2e743efc2d6391d9c76297d995f402f7ecfd9e39859c6e17c7'),
    'RUN_TRACK_TRANSITION_ISOLATION.cmd': (785, '5aff48af4bf526c8d2233be81b1c119805de4aa95aa1b75e15c0365ab91d2e6c'),
    'SELFTEST.cmd': (201, '150b228128e92926be6aaf622cbee87b2f18faf3a5d2e7f22710d817d0e5be37'),
    'SHA256SUMS.txt': (353, 'e85a50b0af4287e3c5b7b835ce0ef10c7b43705bcf4e7df30c8fda49287c2fd1'),
    'track-transition-isolation.ps1': (52154, '5bf5e9ea10795f106c004f0ef578c111d2506a8f380456d34de06215eb41101b'),
}
FINAL_ZIP_SIZE = 17946
FINAL_ZIP_SHA256 = 'a0502408df6ff313f434943671db2d00a147f812b18562f5e346f292412921f8'
FINAL_ENTRIES = {
    'README.md': (4004, '7aab62038eca83eb10b213891c35e1f71861ceac6228256761231314f945506b'),
    'RUN_TRACK_TRANSITION_ISOLATION.cmd': (785, '5aff48af4bf526c8d2233be81b1c119805de4aa95aa1b75e15c0365ab91d2e6c'),
    'SELFTEST.cmd': (201, '150b228128e92926be6aaf622cbee87b2f18faf3a5d2e7f22710d817d0e5be37'),
    'SHA256SUMS.txt': (353, '342861b74aab6f3412113c2568720988420fba4855b741f207b08e5b48a86499'),
    'track-transition-isolation.ps1': (52154, '5bf5e9ea10795f106c004f0ef578c111d2506a8f380456d34de06215eb41101b'),
}

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def validate_entries(raw: bytes, expected: dict) -> None:
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        assert z.testzip() is None
        assert sorted(z.namelist()) == sorted(expected), z.namelist()
        for name, (size, digest) in expected.items():
            data = z.read(name)
            assert len(data) == size, (name, len(data), size)
            assert sha(data) == digest, (name, sha(data), digest)
        sums = z.read('SHA256SUMS.txt').decode('ascii').splitlines()
        assert len(sums) == 4, sums
        for line in sums:
            digest, name = line.split('  ', 1)
            assert name != 'SHA256SUMS.txt'
            assert sha(z.read(name)) == digest, (name, digest, sha(z.read(name)))

encoded_parts = []
for i, (name, size, expected) in enumerate(PARTS):
    expected_name = f'chunk-{i:03d}.txt'
    assert name == expected_name, (name, expected_name)
    data = (PAYLOAD / name).read_bytes()
    assert len(data) == size, (name, len(data), size)
    assert sha(data) == expected, (name, sha(data), expected)
    data.decode('ascii')
    encoded_parts.append(data)

assert not (PAYLOAD / 'rest.txt').exists(), 'Legacy rest.txt must not be present in the canonical six-chunk transport.'
encoded = b''.join(encoded_parts)
assert len(encoded) == 23936
assert sha(encoded) == '2906ae40553434283c7574b2bc35c1a7e1b8e03c4c455d6f1c9bbdbec390fad1'
source_raw = base64.b64decode(encoded, validate=True)
assert len(source_raw) == SOURCE_ZIP_SIZE, len(source_raw)
assert sha(source_raw) == SOURCE_ZIP_SHA256, sha(source_raw)
validate_entries(source_raw, SOURCE_ENTRIES)

# The runtime package above already passed Windows PS5.1 CI. Independent artifact
# inspection found only README path rendering damage caused by raw \r/\t bytes.
# Correct those seven documentation bytes deterministically; runtime code is unchanged.
with zipfile.ZipFile(io.BytesIO(source_raw)) as z:
    infos = {zi.filename: zi for zi in z.infolist()}
    files = {name: z.read(name) for name in z.namelist()}

readme = files['README.md']
raw_cr = sum(1 for i, x in enumerate(readme) if x == 13 and (i + 1 >= len(readme) or readme[i + 1] != 10))
raw_tab = readme.count(b'\t')
assert (raw_cr, raw_tab) == (3, 4), (raw_cr, raw_tab)
readme = readme.replace(b'\r', b'\\r').replace(b'\t', b'\\t')
assert b'%LOCALAPPDATA%\\SpotifyControl\\reports\\track-transition-isolation-latest.json' in readme
assert b'%LOCALAPPDATA%\\SpotifyControl\\reports\\track-transition-isolation-latest.txt' in readme
assert b'%LOCALAPPDATA%\\SpotifyControl\\reports\\track-transition-isolation-raw-latest.csv' in readme
assert b'%LOCALAPPDATA%\\SpotifyControl\\logs\\track-transition-isolation-error.log' in readme
files['README.md'] = readme

sum_names = ['README.md', 'RUN_TRACK_TRANSITION_ISOLATION.cmd', 'SELFTEST.cmd', 'track-transition-isolation.ps1']
files['SHA256SUMS.txt'] = ''.join(f'{sha(files[name])}  {name}\n' for name in sum_names).encode('ascii')

buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w') as z:
    for name in infos:
        old = infos[name]
        zi = zipfile.ZipInfo(name, date_time=old.date_time)
        zi.compress_type = old.compress_type
        zi.comment = old.comment
        zi.extra = old.extra
        zi.internal_attr = old.internal_attr
        zi.external_attr = old.external_attr
        zi.create_system = old.create_system
        zi.create_version = old.create_version
        zi.extract_version = old.extract_version
        zi.flag_bits = old.flag_bits
        z.writestr(zi, files[name], compress_type=old.compress_type, compresslevel=9)
final_raw = buf.getvalue()
assert len(final_raw) == FINAL_ZIP_SIZE, len(final_raw)
assert sha(final_raw) == FINAL_ZIP_SHA256, sha(final_raw)
validate_entries(final_raw, FINAL_ENTRIES)

# Reject accidental raw control characters in every user-visible text entry.
with zipfile.ZipFile(io.BytesIO(final_raw)) as z:
    for name in z.namelist():
        if not name.lower().endswith(('.md', '.cmd', '.ps1', '.txt')):
            continue
        data = z.read(name)
        bad_cr = [i for i, x in enumerate(data) if x == 13 and (i + 1 >= len(data) or data[i + 1] != 10)]
        bad_tab = [i for i, x in enumerate(data) if x == 9]
        assert not bad_cr and not bad_tab, (name, bad_cr, bad_tab)

outzip = Path('SpotifyControl-Track-Transition-Isolation-v0.3.1.zip')
outzip.write_bytes(final_raw)
outdir = Path('phase2-v031')
shutil.rmtree(outdir, ignore_errors=True)
outdir.mkdir()
with zipfile.ZipFile(io.BytesIO(final_raw)) as z:
    z.extractall(outdir)

print('PHASE2_V031_SOURCE_RECONSTRUCTION_PASS', SOURCE_ZIP_SIZE, SOURCE_ZIP_SHA256)
print('PHASE2_V031_TRANSPORT_PASS', len(PARTS), len(encoded), sha(encoded))
print('PHASE2_V031_README_CONTROL_REPAIR_PASS', raw_cr, raw_tab, FINAL_ENTRIES['README.md'][1])
print('PHASE2_V031_TEXT_CONTROL_SCAN_PASS')
print('PHASE2_V031_FINAL_PACKAGE_PASS', FINAL_ZIP_SIZE, FINAL_ZIP_SHA256)
print('PHASE2_V031_SCRIPT', FINAL_ENTRIES['track-transition-isolation.ps1'][0], FINAL_ENTRIES['track-transition-isolation.ps1'][1])
