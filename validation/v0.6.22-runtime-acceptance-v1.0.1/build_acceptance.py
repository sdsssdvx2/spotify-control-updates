from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from io import BytesIO

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
GEN = HERE / 'generated'
OUT = HERE / 'out'
PKG = OUT / 'SpotifyControl-v0.6.22-r11-Runtime-Acceptance-v1.0.1'
ZIP = OUT / 'SpotifyControl-v0.6.22-r11-Runtime-Acceptance-v1.0.1.zip'

BASE_VALIDATION_HEAD = '5e38454eab01af94ae40980a5ff3d927997fccfc'
BASE_BUILDER_PATH = 'validation/v0.6.22-runtime-acceptance-v1.0.0/build_acceptance.py'
BASE_BUILDER_BLOB = '2c8f0605dcb6b62e730256e49ed875ea4f3c1465'
BASE_ZIP_NAME = 'SpotifyControl-v0.6.22-r11-Runtime-Acceptance-v1.0.0.zip'
BASE_ZIP_SIZE = 56228
BASE_ZIP_SHA256 = '04b555a3e68a7baf72b9fabdf2f15419cf7c1bf70fb5915d936165cd74e3bd14'

PRODUCTION_BASE = 'dacd4faf6a632b6b33571acf16ed4b6e73a865d7'
RELEASE_HEAD = '9c1cabcaaed6c7a1465f5baea12d046a5d51c8dc'
RELEASE_MANIFEST_SHA256 = '9eea792cf0f81c09d3527f879b98c44dbbcbce1209c7dbc651d4298453f28e32'
TRANSPORT_SOURCE = 'db4dd0e4357cbf03ea95dd8773c0be173b2c91fc'
PAYLOAD_SET = 'cb396442ac874504a04d4acb0034d3cb9fa11acce290da18e639c2dbe8e5a091'

BASE_MAIN_SHA = 'f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'
BASE_ADDON_SHA = '7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
TARGET_MAIN_SHA = 'b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe'
TARGET_ADDON_SHA = '0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc'
AGENT_SHA = '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP_SHA = 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'

BASE_MAIN_SIZE = 281579
BASE_ADDON_SIZE = 250616
TARGET_MAIN_SIZE = 281586
TARGET_ADDON_SIZE = 268670
AGENT_SIZE = 4855
BOOTSTRAP_SIZE = 42963

SOURCE_FILES = [
    'RUN_RUNTIME_ACCEPTANCE.ps1',
    'RUN_RUNTIME_ACCEPTANCE.cmd',
    'PRECHECK_RUNTIME_ACCEPTANCE.ps1',
    'BOOTSTRAP_RUNNER.ps1',
]

README_TEXT = f'''Spotify Control v0.6.22 / Addon Manager r11 Runtime Acceptance v1.0.1

Purpose
-------
This is the one-shot real-PC acceptance for the already CI-validated v0.6.22/r11 release candidate.
It does not permanently install the candidate. On success or failure it restores exact v0.6.21/r10 production state.

Why v1.0.1 exists
-----------------
v1.0.0 was retired before user execution after a post-validation static audit found stale inherited size assertions and target labels in the outer acceptance script. The v0.6.22/r11 candidate and Bootstrap transport were not implicated. v1.0.1 corrects those assertions and adds explicit manifest-derived baseline/target size-contract validation so this generation error cannot pass CI again.

Transport design
----------------
1. Before resident/mutation state is touched, the acceptance fetches the manifest from the exact immutable release-head GitHub raw HTTPS URL.
2. It validates release head data: v0.6.22, source commit, payload-set hash, exact Bootstrap 1.0.6 identity, exact latest payload identities, and the exact v0.6.21 -> v0.6.22 two-patch edge.
3. The exact installed Bootstrap 1.0.6 file is executed byte-for-byte unchanged.
4. In that temporary runner process only, the single Invoke-RestMethod call for Bootstrap's production manifest URL is shimmed to return the already validated local release-head manifest object.
5. Every Bootstrap action must produce evidence that this shim was used exactly once.
6. Patch chunks are NOT shimmed. Bootstrap continues to download them itself from raw.githubusercontent.com at manifest source_commit {TRANSPORT_SOURCE} and verifies their size/SHA/compressed payload contracts normally.

Exact identities
----------------
Baseline v0.6.21/r10:
- Spotify Control: {BASE_MAIN_SIZE} bytes / {BASE_MAIN_SHA}
- Addon Manager: {BASE_ADDON_SIZE} bytes / {BASE_ADDON_SHA}

Candidate v0.6.22/r11:
- Spotify Control: {TARGET_MAIN_SIZE} bytes / {TARGET_MAIN_SHA}
- Addon Manager: {TARGET_ADDON_SIZE} bytes / {TARGET_ADDON_SHA}

Unchanged:
- resident agent: {AGENT_SIZE} bytes / {AGENT_SHA}
- Bootstrap 1.0.6: {BOOTSTRAP_SIZE} bytes / {BOOTSTRAP_SHA}

Safety
------
- Spotify must be fully closed.
- Run as a normal user, NOT Administrator.
- No Spotify launch is performed.
- Addon Manager Update is not called.
- Tagify, Splitify, Star Ratings, SC Cover Ambience and Spicetify config surfaces are fingerprinted and must stay unchanged.
- Exact v0.6.21/r10/agent/Bootstrap identities are required before test.
- The HTTPS manifest preflight happens before the resident is stopped or agent_mutation_enabled is changed.
- Child PowerShell executions are bounded by explicit process timeouts.
- On any later failure, the original production code/state and resident agent are restored.

Run
---
1. Fully close Spotify.
2. Extract this ZIP into a NEW folder. Do not overwrite older acceptance files.
3. Run RUN_RUNTIME_ACCEPTANCE.cmd normally, NOT as Administrator.
4. Do not edit Spotify/Spicetify files while it runs.

Retired builds
--------------
v1.0.0 must not be run. Historical localhost acceptance builds also remain retired.

Evidence
--------
Success:
%LOCALAPPDATA%\\SpotifyControl\\reports\\v0622-r11-runtime-acceptance-latest.json

Failure:
%LOCALAPPDATA%\\SpotifyControl\\reports\\v0622-r11-runtime-acceptance-failure-latest.txt
'''


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_path(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def manifest_at(commit: str) -> dict:
    return json.loads(git_bytes(commit, 'manifest.json').decode('utf-8-sig'))


def latest_row(manifest: dict, path: str) -> dict:
    rows = [x for x in manifest.get('latest_files', []) if x.get('path') == path]
    if len(rows) != 1:
        raise RuntimeError(f'manifest latest_files row missing/duplicate: {path}')
    return rows[0]


def validate_manifest_contracts() -> None:
    base = manifest_at(PRODUCTION_BASE)
    rel_bytes = git_bytes(RELEASE_HEAD, 'manifest.json')
    if sha_bytes(rel_bytes) != RELEASE_MANIFEST_SHA256:
        raise RuntimeError('release manifest byte identity drift')
    rel = json.loads(rel_bytes.decode('utf-8-sig'))
    if base.get('latest_version') != '0.6.21' or rel.get('latest_version') != '0.6.22':
        raise RuntimeError('baseline/release manifest version drift')
    if rel.get('source_commit') != TRANSPORT_SOURCE or rel.get('payload_set_sha256') != PAYLOAD_SET:
        raise RuntimeError('release manifest transport identity drift')
    expected = [
        (base, 'bin/spotify-control.ps1', BASE_MAIN_SIZE, BASE_MAIN_SHA),
        (base, 'bin/addon-manager.ps1', BASE_ADDON_SIZE, BASE_ADDON_SHA),
        (base, 'bin/spotify-control-agent.vbs', AGENT_SIZE, AGENT_SHA),
        (rel, 'bin/spotify-control.ps1', TARGET_MAIN_SIZE, TARGET_MAIN_SHA),
        (rel, 'bin/addon-manager.ps1', TARGET_ADDON_SIZE, TARGET_ADDON_SHA),
        (rel, 'bin/spotify-control-agent.vbs', AGENT_SIZE, AGENT_SHA),
    ]
    for manifest, path, size, sha in expected:
        row = latest_row(manifest, path)
        if int(row.get('size', -1)) != size or row.get('sha256') != sha:
            raise RuntimeError(f'manifest identity mismatch for {path}: {row}')
    boot = rel.get('bootstrap') or {}
    if boot.get('version') != '1.0.6' or int(boot.get('size', -1)) != BOOTSTRAP_SIZE or boot.get('sha256') != BOOTSTRAP_SHA:
        raise RuntimeError('release Bootstrap identity drift')
    edges = [e for e in rel.get('updates', []) if e.get('from_version') == '0.6.21' and e.get('to_version') == '0.6.22']
    if len(edges) != 1 or sorted(p.get('path') for p in edges[0].get('patches', [])) != ['bin/addon-manager.ps1', 'bin/spotify-control.ps1']:
        raise RuntimeError('release exact v0.6.21 -> v0.6.22 edge drift')


def rebuild_base_v100() -> tuple[bytes, dict]:
    blob = subprocess.check_output(['git', 'rev-parse', f'{BASE_VALIDATION_HEAD}:{BASE_BUILDER_PATH}'], cwd=ROOT, text=True).strip()
    if blob != BASE_BUILDER_BLOB:
        raise RuntimeError(f'v1.0.0 builder blob drift: {blob}')
    source = git_bytes(BASE_VALIDATION_HEAD, BASE_BUILDER_PATH)
    temp = ROOT / 'validation' / 'v0.6.22-runtime-acceptance-v1.0.0'
    shutil.rmtree(temp, ignore_errors=True)
    temp.mkdir(parents=True)
    try:
        (temp / 'build_acceptance.py').write_bytes(source)
        subprocess.check_call([sys.executable, str(temp / 'build_acceptance.py')], cwd=ROOT)
        base_zip = temp / 'out' / BASE_ZIP_NAME
        raw = base_zip.read_bytes()
        if len(raw) != BASE_ZIP_SIZE or sha_bytes(raw) != BASE_ZIP_SHA256:
            raise RuntimeError(f'v1.0.0 base package identity drift: {len(raw)} {sha_bytes(raw)}')
        with zipfile.ZipFile(base_zip) as z:
            if z.testzip() is not None:
                raise RuntimeError('v1.0.0 base package CRC failure')
            report = json.loads(z.read('evidence/SELF_VALIDATION_REPORT.json').decode('utf-8'))
            if int(report.get('passed', -1)) != 73 or int(report.get('total', -1)) != 73:
                raise RuntimeError('v1.0.0 base source contract is not 73/73')
        return raw, report
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def replace_one(data: bytes, old: bytes, new: bytes, label: str) -> bytes:
    count = data.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one old token, found {count}')
    return data.replace(old, new)


def patch_runtime(data: bytes) -> bytes:
    replacements = [
        (b"$AcceptanceVersion='1.0.0'", b"$AcceptanceVersion='1.0.1'", 'acceptance-version'),
        (b'v0622-r10-runtime-acceptance-latest.json', b'v0622-r11-runtime-acceptance-latest.json', 'verification-report-name'),
        (b'v0622-r10-runtime-acceptance-failure-latest.txt', b'v0622-r11-runtime-acceptance-failure-latest.txt', 'failure-report-name'),
        (b'backups\\v0622-r10-runtime-acceptance', b'backups\\v0622-r11-runtime-acceptance', 'backup-root-name'),
        (b"Assert-Identity $Main $BaselineMainSha 281585 'Spotify Control v0.6.21 main'", b"Assert-Identity $Main $BaselineMainSha 281579 'Spotify Control v0.6.21 main'", 'baseline-main-size'),
        (b"Assert-Identity $Addon $BaselineAddonSha 225044 'Addon Manager r9'", b"Assert-Identity $Addon $BaselineAddonSha 250616 'Addon Manager r10'", 'baseline-addon-size-label'),
        (b"Assert-Identity $Main $TargetMainSha 281579 'Spotify Control v0.6.22 main'", b"Assert-Identity $Main $TargetMainSha 281586 'Spotify Control v0.6.22 main'", 'target-main-size'),
        (b"Assert-Identity $Addon $TargetAddonSha 250616 'Addon Manager r10'", b"Assert-Identity $Addon $TargetAddonSha 268670 'Addon Manager r11'", 'target-addon-size-label'),
        (b'[int64]$mainRows[0].size -ne 281579', b'[int64]$mainRows[0].size -ne 281586', 'manifest-main-size'),
        (b'[int64]$addonRows[0].size -ne 250616', b'[int64]$addonRows[0].size -ne 268670', 'manifest-addon-size'),
        (b"'r10 registry/inventory report missing.'", b"'r11 registry/inventory report missing.'", 'registry-missing-label'),
        (b"'r10 registry report identity invalid.'", b"'r11 registry report identity invalid.'", 'registry-invalid-label'),
        (b'Running v0.6.22 main + Addon Manager r10 self-tests', b'Running v0.6.22 main + Addon Manager r11 self-tests', 'candidate-stage-label'),
        (b'Addon Manager r10 SelfTest failed', b'Addon Manager r11 SelfTest failed', 'candidate-selftest-label'),
        (b'Addon Manager r10 real inventory Check failed', b'Addon Manager r11 real inventory Check failed', 'candidate-check-label'),
        (b'Addon Manager r10 registry:', b'Addon Manager r11 registry:', 'candidate-summary-label'),
    ]
    for old, new, label in replacements:
        data = replace_one(data, old, new, label)
    return data


def extract_and_patch(base_zip_raw: bytes) -> None:
    shutil.rmtree(GEN, ignore_errors=True)
    GEN.mkdir(parents=True)
    with zipfile.ZipFile(BytesIO(base_zip_raw)) as z:
        if z.testzip() is not None:
            raise RuntimeError('base package CRC failure during extraction')
        for name in SOURCE_FILES:
            (GEN / name).write_bytes(z.read(name))
    (GEN / 'RUN_RUNTIME_ACCEPTANCE.ps1').write_bytes(patch_runtime((GEN / 'RUN_RUNTIME_ACCEPTANCE.ps1').read_bytes()))
    (GEN / 'README.txt').write_bytes(README_TEXT.replace('\n', '\r\n').encode('utf-8'))


def validate_sources(base_report: dict) -> dict:
    run = (GEN / 'RUN_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig')
    readme = (GEN / 'README.txt').read_text(encoding='utf-8')
    runner = (GEN / 'BOOTSTRAP_RUNNER.ps1').read_text(encoding='utf-8-sig')
    checks = []

    def ck(name: str, ok: bool) -> None:
        checks.append((name, bool(ok)))

    ck('base-v100-package-source-contract-73-of-73', int(base_report.get('passed', -1)) == 73 and int(base_report.get('total', -1)) == 73)
    for key, token in {
        'acceptance-version': "$AcceptanceVersion='1.0.1'",
        'baseline-main-version': "$BaselineMainVersion='0.6.21'",
        'baseline-addon-version': "$BaselineAddonVersion='0.6.5-r10'",
        'target-main-version': "$TargetMainVersion='0.6.22'",
        'target-addon-version': "$TargetAddonVersion='0.6.5-r11'",
        'baseline-main-sha': BASE_MAIN_SHA,
        'baseline-addon-sha': BASE_ADDON_SHA,
        'target-main-sha': TARGET_MAIN_SHA,
        'target-addon-sha': TARGET_ADDON_SHA,
        'release-head': RELEASE_HEAD,
        'transport-source': TRANSPORT_SOURCE,
        'payload-set': PAYLOAD_SET,
    }.items():
        ck('run-pin:' + key, token in run)

    ck('baseline-main-assert-exact', f"Assert-Identity $Main $BaselineMainSha {BASE_MAIN_SIZE} 'Spotify Control v0.6.21 main'" in run)
    ck('baseline-addon-assert-exact', f"Assert-Identity $Addon $BaselineAddonSha {BASE_ADDON_SIZE} 'Addon Manager r10'" in run)
    ck('target-main-assert-exact', f"Assert-Identity $Main $TargetMainSha {TARGET_MAIN_SIZE} 'Spotify Control v0.6.22 main'" in run)
    ck('target-addon-assert-exact', f"Assert-Identity $Addon $TargetAddonSha {TARGET_ADDON_SIZE} 'Addon Manager r11'" in run)
    ck('manifest-main-size-exact', f'[int64]$mainRows[0].size -ne {TARGET_MAIN_SIZE}' in run)
    ck('manifest-addon-size-exact', f'[int64]$addonRows[0].size -ne {TARGET_ADDON_SIZE}' in run)
    ck('report-name-r11', 'v0622-r11-runtime-acceptance-latest.json' in run)
    ck('failure-name-r11', 'v0622-r11-runtime-acceptance-failure-latest.txt' in run)
    ck('backup-name-r11', 'backups\\v0622-r11-runtime-acceptance' in run)
    ck('candidate-r11-selftest-label', 'Addon Manager r11 SelfTest failed' in run)
    ck('candidate-r11-check-label', 'Addon Manager r11 real inventory Check failed' in run)
    ck('candidate-r11-registry-label', 'Addon Manager r11 registry:' in run)
    ck('old-baseline-main-size-absent', '281585' not in run)
    ck('old-baseline-addon-size-absent', '225044' not in run)
    for bad in ['Addon Manager r10 SelfTest', 'Addon Manager r10 real inventory Check', 'Addon Manager r10 registry:', 'r10 registry/inventory report', 'r10 registry report identity']:
        ck('stale-target-label-absent:' + bad, bad not in run)
    ck('old-acceptance-version-absent', "$AcceptanceVersion='1.0.0'" not in run)
    ck('runner-still-exact-bootstrap', f"$ExpectedBootstrapSha='{BOOTSTRAP_SHA}'" in runner and '$ExpectedBootstrapSize=42963' in runner)
    ck('readme-v101-r11', 'Addon Manager r11 Runtime Acceptance v1.0.1' in readme)
    ck('readme-retire-v100', 'v1.0.0 must not be run' in readme)
    ck('readme-exact-transport-source', TRANSPORT_SOURCE in readme)
    ck('readme-old-transport-source-absent', '9a90d5f' not in readme)
    ck('readme-baseline-main-identity', f'{BASE_MAIN_SIZE} bytes / {BASE_MAIN_SHA}' in readme)
    ck('readme-baseline-addon-identity', f'{BASE_ADDON_SIZE} bytes / {BASE_ADDON_SHA}' in readme)
    ck('readme-target-main-identity', f'{TARGET_MAIN_SIZE} bytes / {TARGET_MAIN_SHA}' in readme)
    ck('readme-target-addon-identity', f'{TARGET_ADDON_SIZE} bytes / {TARGET_ADDON_SHA}' in readme)

    passed = sum(ok for _, ok in checks)
    report = {
        'schema': 2,
        'acceptance': 'v0.6.22-r11-runtime-v1.0.1',
        'supersedes': {
            'acceptance': 'v0.6.22-r11-runtime-v1.0.0',
            'package_size': BASE_ZIP_SIZE,
            'package_sha256': BASE_ZIP_SHA256,
            'reason': 'retired before user execution: stale inherited baseline/target size assertions and target presentation labels',
        },
        'release': {
            'production_base': PRODUCTION_BASE,
            'head': RELEASE_HEAD,
            'manifest_sha256': RELEASE_MANIFEST_SHA256,
            'transport_source': TRANSPORT_SOURCE,
            'payload_set_sha256': PAYLOAD_SET,
        },
        'identities': {
            'baseline': {'main': {'size': BASE_MAIN_SIZE, 'sha256': BASE_MAIN_SHA}, 'addon': {'size': BASE_ADDON_SIZE, 'sha256': BASE_ADDON_SHA}},
            'target': {'main': {'size': TARGET_MAIN_SIZE, 'sha256': TARGET_MAIN_SHA}, 'addon': {'size': TARGET_ADDON_SIZE, 'sha256': TARGET_ADDON_SHA}},
            'agent': {'size': AGENT_SIZE, 'sha256': AGENT_SHA},
            'bootstrap': {'size': BOOTSTRAP_SIZE, 'sha256': BOOTSTRAP_SHA},
        },
        'passed': passed,
        'total': len(checks),
        'checks': checks,
        'files': {name: {'size': (GEN / name).stat().st_size, 'sha256': sha_path(GEN / name)} for name in SOURCE_FILES + ['README.txt']},
    }
    if passed != len(checks):
        for name, ok in checks:
            if not ok:
                print('FAIL', name)
        raise RuntimeError(f'v1.0.1 corrected source contract failed {passed}/{len(checks)}')
    return report


def build() -> dict:
    validate_manifest_contracts()
    base_zip_raw, base_report = rebuild_base_v100()
    extract_and_patch(base_zip_raw)
    report = validate_sources(base_report)

    shutil.rmtree(OUT, ignore_errors=True)
    PKG.mkdir(parents=True)
    for name in SOURCE_FILES + ['README.txt']:
        shutil.copy2(GEN / name, PKG / name)
    evidence = PKG / 'evidence'
    evidence.mkdir()
    (evidence / 'SELF_VALIDATION_REPORT.json').write_text(json.dumps(report, indent=2, ensure_ascii=True) + '\n', encoding='utf-8', newline='\n')
    (evidence / 'SELF_VALIDATION_REPORT.txt').write_text(
        f"V0.6.22/R11 RUNTIME ACCEPTANCE v1.0.1 SELF VALIDATION: {report['passed']}/{report['total']} PASS\n" + ''.join(f'PASS: {name}\n' for name, ok in report['checks']),
        encoding='utf-8', newline='\n')
    rels = SOURCE_FILES + ['README.txt', 'evidence/SELF_VALIDATION_REPORT.json', 'evidence/SELF_VALIDATION_REPORT.txt']
    (PKG / 'SHA256SUMS.txt').write_text(''.join(f'{sha_path(PKG / rel)}  {rel}\n' for rel in rels), encoding='ascii', newline='\n')

    if ZIP.exists():
        ZIP.unlink()
    with zipfile.ZipFile(ZIP, 'w', compression=zipfile.ZIP_STORED) as z:
        for path in sorted(PKG.rglob('*')):
            if not path.is_file():
                continue
            rel = path.relative_to(PKG).as_posix()
            info = zipfile.ZipInfo(rel, (2026, 10, 27, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = (0o100644 << 16)
            z.writestr(info, path.read_bytes())
    with zipfile.ZipFile(ZIP) as z:
        if z.testzip() is not None:
            raise RuntimeError('final package CRC failure')
        for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
            expected, rel = line.split('  ', 1)
            if sha_bytes(z.read(rel)) != expected:
                raise RuntimeError('internal checksum mismatch: ' + rel)

    print('V0622_R11_RUNTIME_ACCEPTANCE_V101_BUILD_PASS', ZIP.stat().st_size, sha_path(ZIP), report['passed'], report['total'], report['files']['RUN_RUNTIME_ACCEPTANCE.ps1']['sha256'], report['files']['BOOTSTRAP_RUNNER.ps1']['sha256'])
    return report


if __name__ == '__main__':
    build()
