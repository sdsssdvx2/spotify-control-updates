from pathlib import Path
import base64
import hashlib
import io
import json
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
GEN = HERE / 'generated'
OUT = HERE / 'out'
PKG = OUT / 'SpotifyControl-v0.6.22-r11-Runtime-Acceptance-v1.0.0'
ZIP = OUT / 'SpotifyControl-v0.6.22-r11-Runtime-Acceptance-v1.0.0.zip'

HIST_COMMIT = 'abb41059469334e71ce07b72add19c4c1a0e39ed'
HIST_DIR = 'validation/v0.6.21-runtime-acceptance-v2.0.3/source-b64'
HIST_BUNDLE_SHA256 = 'f1b61478f076a91ae69279e6f804adb8457ab0a8545e9393487ba85bc6375fa7'
HIST_CHUNKS = [f'chunk-{i:03d}.txt' for i in range(5)]
SOURCE_FILES = [
    'RUN_RUNTIME_ACCEPTANCE.ps1',
    'RUN_RUNTIME_ACCEPTANCE.cmd',
    'PRECHECK_RUNTIME_ACCEPTANCE.ps1',
    'BOOTSTRAP_RUNNER.ps1',
    'README.txt',
]

BASE_MAIN_SHA = 'f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'
BASE_ADDON_SHA = '7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
TARGET_MAIN_SHA = 'b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe'
TARGET_ADDON_SHA = '0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc'
AGENT_SHA = '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP_SHA = 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
RELEASE_HEAD = '9c1cabcaaed6c7a1465f5baea12d046a5d51c8dc'
TRANSPORT_SOURCE = 'db4dd0e4357cbf03ea95dd8773c0be173b2c91fc'
PAYLOAD_SET = 'cb396442ac874504a04d4acb0034d3cb9fa11acce290da18e639c2dbe8e5a091'

OLD_BASE_MAIN_SHA = 'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'
OLD_BASE_ADDON_SHA = '3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'
OLD_TARGET_MAIN_SHA = BASE_MAIN_SHA
OLD_TARGET_ADDON_SHA = BASE_ADDON_SHA
OLD_RELEASE_HEAD = '5eac4f39920b84f22e2a5ee07422f6080bfc7ef7'
OLD_TRANSPORT_SOURCE = '9a90d5f13eb63023d8f965a004be14d309d99429'
OLD_PAYLOAD_SET = '7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55'


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_path(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def git_show(path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{HIST_COMMIT}:{path}'], cwd=ROOT)


def get_historic_bundle() -> bytes:
    text = ''
    for name in HIST_CHUNKS:
        raw = git_show(f'{HIST_DIR}/{name}').decode('ascii')
        text += ''.join(raw.split())
    bundle = base64.b64decode(text, validate=True)
    if sha_bytes(bundle) != HIST_BUNDLE_SHA256:
        raise RuntimeError('historic v2.0.3 source bundle SHA drift')
    with zipfile.ZipFile(io.BytesIO(bundle)) as z:
        if z.testzip() is not None:
            raise RuntimeError('historic v2.0.3 source bundle CRC failure')
        if sorted(z.namelist()) != sorted(SOURCE_FILES):
            raise RuntimeError(f'historic source entries drift: {z.namelist()}')
    return bundle


def shift_pair(data: bytes, old_target: bytes, old_base: bytes, new_base: bytes, new_target: bytes, label: str) -> bytes:
    marker = (b'__SPOTIFY_CONTROL_SHIFT_' + label.encode('ascii') + b'__')
    if marker in data:
        raise RuntimeError(f'placeholder collision: {label}')
    if old_target not in data:
        return data
    data = data.replace(old_target, marker)
    data = data.replace(old_base, new_base)
    data = data.replace(marker, new_target)
    return data


def transform(name: str, data: bytes) -> bytes:
    # Exact one-generation version shift: v0.6.20/r9 -> v0.6.21/r10 baseline,
    # and v0.6.21/r10 -> v0.6.22/r11 target. Byte replacement preserves BOM/CRLF.
    data = shift_pair(data, b'0.6.21', b'0.6.20', b'0.6.21', b'0.6.22', 'VER')
    data = shift_pair(data, b'0.6.5-r10', b'0.6.5-r9', b'0.6.5-r10', b'0.6.5-r11', 'ADDONVER')
    data = shift_pair(data, b'v0621', b'v0620', b'v0621', b'v0622', 'LOWERNUM')
    data = shift_pair(data, b'V0621', b'V0620', b'V0621', b'V0622', 'UPPERNUM')

    data = data.replace(b'2.0.3', b'1.0.0')
    data = data.replace(b'v203', b'v100')
    data = data.replace(b'V203', b'V100')

    # Hashes must be shifted target-first because the previous target is the new baseline.
    data = data.replace(OLD_TARGET_MAIN_SHA.encode(), TARGET_MAIN_SHA.encode())
    data = data.replace(OLD_BASE_MAIN_SHA.encode(), BASE_MAIN_SHA.encode())
    data = data.replace(OLD_TARGET_ADDON_SHA.encode(), TARGET_ADDON_SHA.encode())
    data = data.replace(OLD_BASE_ADDON_SHA.encode(), BASE_ADDON_SHA.encode())
    data = data.replace(OLD_RELEASE_HEAD.encode(), RELEASE_HEAD.encode())
    data = data.replace(OLD_TRANSPORT_SOURCE.encode(), TRANSPORT_SOURCE.encode())
    data = data.replace(OLD_PAYLOAD_SET.encode(), PAYLOAD_SET.encode())

    return data


def unpack_and_transform() -> dict:
    bundle = get_historic_bundle()
    shutil.rmtree(GEN, ignore_errors=True)
    GEN.mkdir(parents=True)
    with zipfile.ZipFile(io.BytesIO(bundle)) as z:
        for name in SOURCE_FILES:
            (GEN / name).write_bytes(transform(name, z.read(name)))
    return {name: {'size': (GEN / name).stat().st_size, 'sha256': sha_path(GEN / name)} for name in SOURCE_FILES}


def validate_sources(files: dict) -> dict:
    run = (GEN / 'RUN_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig')
    runner = (GEN / 'BOOTSTRAP_RUNNER.ps1').read_text(encoding='utf-8-sig')
    pre = (GEN / 'PRECHECK_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig')
    readme = (GEN / 'README.txt').read_text(encoding='utf-8')
    cmd = (GEN / 'RUN_RUNTIME_ACCEPTANCE.cmd').read_text(encoding='utf-8-sig')
    checks = []

    def ck(name, ok):
        checks.append((name, bool(ok)))

    pins = {
        'acceptance': "$AcceptanceVersion='1.0.0'",
        'baseline_main': "$BaselineMainVersion='0.6.21'",
        'baseline_addon': "$BaselineAddonVersion='0.6.5-r10'",
        'target_main': "$TargetMainVersion='0.6.22'",
        'target_addon': "$TargetAddonVersion='0.6.5-r11'",
        'baseline_main_sha': BASE_MAIN_SHA,
        'baseline_addon_sha': BASE_ADDON_SHA,
        'target_main_sha': TARGET_MAIN_SHA,
        'target_addon_sha': TARGET_ADDON_SHA,
        'agent_sha': AGENT_SHA,
        'bootstrap_sha': BOOTSTRAP_SHA,
        'release_head': RELEASE_HEAD,
        'transport_source': TRANSPORT_SOURCE,
        'payload_set': PAYLOAD_SET,
    }
    for key, value in pins.items():
        ck('run-pin:' + key, value in run)

    required_run = [
        'Assert-BaselineComponents', 'Assert-TargetComponents', 'Assert-TransactionsTerminal',
        'Assert-PinnedReleaseManifest', 'Fetch-PinnedReleaseManifest',
        "Invoke-BootstrapRun -Action 'RollbackTest'", "Invoke-BootstrapRun -Action 'Update'",
        "Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','SelfTest')",
        "Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','Check','-Force')",
        'Assert-RegistryEvidence', 'protect-ratings-tags-notes', 'never-disable-or-optimize',
        'playlist-backed-ratings-preserve', 'preserve-unknown-source', 'Restore-ResidentSafely',
        'Timed out after $TimeoutSeconds seconds.', 'manifest-shim evidence invalid',
        'V0.6.22/R11 WINDOWS RUNTIME ACCEPTANCE VERIFIED',
    ]
    for token in required_run:
        ck('run-required:' + token, token in run)

    forbidden_run = [
        'LOCAL_MANIFEST_SERVER', 'Start-LocalManifestServer', 'Get-FreeTcpPort',
        'New-BootstrapExecutionCopy', '127.0.0.1', 'SpotifyControlLoopbackBypassProxy',
        "Invoke-PowerShellScript -Path $Addon -Arguments @('-Action','Update'",
        'Start-Spotify', 'Get-Process Spotify | Stop-Process',
        'Remove-Item -LiteralPath $env:APPDATA', 'Remove-Item -LiteralPath $env:LOCALAPPDATA',
        OLD_RELEASE_HEAD, OLD_TRANSPORT_SOURCE, OLD_PAYLOAD_SET, OLD_BASE_MAIN_SHA, OLD_BASE_ADDON_SHA,
    ]
    for token in forbidden_run:
        ck('run-forbidden-absent:' + token, token not in run)

    ck('preflight-before-quiesce', run.index("$Phase='transport-preflight'") < run.index("$Phase='quiesce'"))
    ck('manifest-fetch-before-restore-needed', run.index('$ManifestPreflight=Fetch-PinnedReleaseManifest') < run.index('$RestoreNeeded=$true'))
    ck('single-bootstrap-update', run.count("-Action 'Update'") == 1)
    ck('no-addon-update-action', "@('-Action','Update')" not in '\n'.join(line for line in run.splitlines() if '$Addon' in line))
    ck('release-manifest-exact-head-url', f'https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/{RELEASE_HEAD}/manifest.json' in run)
    ck('main-manifest-report-url', 'https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json' in run)

    runner_required = [
        f"$ExpectedBootstrapSha='{BOOTSTRAP_SHA}'", '$ExpectedBootstrapSize=42963',
        'Microsoft.PowerShell.Utility\\Invoke-WebRequest', 'BOOTSTRAP_MANIFEST_FETCH_PASS',
        'function Invoke-RestMethod', 'Manifest shim refused unexpected Invoke-RestMethod URI',
        '$global:SpotifyControlManifestShimState', '& $BootstrapPath -Action $Action -Json',
        'BOOTSTRAP_MANIFEST_SHIM_SELFTEST_PASS',
    ]
    for token in runner_required:
        ck('runner-required:' + token, token in runner)
    for token in ('127.0.0.1', 'LOCAL_MANIFEST_SERVER', 'function Invoke-WebRequest', '$script:Shim'):
        ck('runner-forbidden-absent:' + token, token not in runner)
    ck('runner-exact-bootstrap-no-copy', 'ExecutionCopy' not in runner and 'Replace($MainManifestUrl' not in runner)
    ck('precheck-includes-runner', 'BOOTSTRAP_RUNNER.ps1' in pre and 'LOCAL_MANIFEST_SERVER' not in pre)
    ck('cmd-launches-precheck', 'PRECHECK_RUNTIME_ACCEPTANCE.ps1' in cmd and 'powershell' in cmd.lower())
    ck('readme-target', 'v0.6.22' in readme and 'r11' in readme)
    ck('readme-no-localhost', 'removes localhost HTTP entirely' in readme)
    ck('readme-exact-bootstrap', 'exact installed Bootstrap 1.0.6 file is executed byte-for-byte unchanged' in readme)

    passed = sum(ok for _, ok in checks)
    report = {
        'schema': 1,
        'acceptance': 'v0.6.22-r11-runtime-v1.0.0',
        'derived_from': {'commit': HIST_COMMIT, 'bundle_sha256': HIST_BUNDLE_SHA256},
        'release': {'head': RELEASE_HEAD, 'transport_source': TRANSPORT_SOURCE, 'payload_set_sha256': PAYLOAD_SET},
        'baseline': {'main_sha256': BASE_MAIN_SHA, 'addon_sha256': BASE_ADDON_SHA},
        'target': {'main_sha256': TARGET_MAIN_SHA, 'addon_sha256': TARGET_ADDON_SHA},
        'passed': passed,
        'total': len(checks),
        'checks': checks,
        'files': files,
    }
    if passed != len(checks):
        for name, ok in checks:
            if not ok:
                print('FAIL', name)
        raise RuntimeError(f'v0.6.22 acceptance source contract failed {passed}/{len(checks)}')
    return report


def build() -> dict:
    files = unpack_and_transform()
    report = validate_sources(files)
    shutil.rmtree(OUT, ignore_errors=True)
    PKG.mkdir(parents=True)
    for name in SOURCE_FILES:
        shutil.copy2(GEN / name, PKG / name)
    evidence = PKG / 'evidence'
    evidence.mkdir()
    (evidence / 'SELF_VALIDATION_REPORT.json').write_text(json.dumps(report, indent=2, ensure_ascii=True) + '\n', encoding='utf-8', newline='\n')
    (evidence / 'SELF_VALIDATION_REPORT.txt').write_text(
        f"V0.6.22/R11 RUNTIME ACCEPTANCE v1.0.0 SELF VALIDATION: {report['passed']}/{report['total']} PASS\n" +
        ''.join(f'PASS: {name}\n' for name, ok in report['checks']),
        encoding='utf-8', newline='\n')
    rels = SOURCE_FILES + ['evidence/SELF_VALIDATION_REPORT.json', 'evidence/SELF_VALIDATION_REPORT.txt']
    (PKG / 'SHA256SUMS.txt').write_text(
        ''.join(f'{sha_path(PKG / rel)}  {rel}\n' for rel in rels), encoding='ascii', newline='\n')

    if ZIP.exists():
        ZIP.unlink()
    with zipfile.ZipFile(ZIP, 'w', compression=zipfile.ZIP_STORED) as z:
        for path in sorted(PKG.rglob('*')):
            if not path.is_file():
                continue
            rel = path.relative_to(PKG).as_posix()
            info = zipfile.ZipInfo(rel, (2026, 10, 26, 0, 0, 0))
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

    print(
        'V0622_R11_RUNTIME_ACCEPTANCE_V100_BUILD_PASS',
        ZIP.stat().st_size, sha_path(ZIP), report['passed'], report['total'],
        report['files']['RUN_RUNTIME_ACCEPTANCE.ps1']['sha256'],
        report['files']['BOOTSTRAP_RUNNER.ps1']['sha256'],
    )
    return report


if __name__ == '__main__':
    build()
