from pathlib import Path
import argparse
import base64
import gzip
import hashlib
import io
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASE_COMMIT = 'dacd4faf6a632b6b33571acf16ed4b6e73a865d7'
BASE_VERSION = '0.6.21'
NEW_VERSION = '0.6.22'
BASE_MAIN_SHA = 'f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'
BASE_MAIN_SIZE = 281579
BASE_ADDON_SHA = '7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
BASE_ADDON_SIZE = 250616
TARGET_MAIN_SHA = 'b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe'
TARGET_MAIN_SIZE = 281586
TARGET_ADDON_SHA = '0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc'
TARGET_ADDON_SIZE = 268670
AGENT_SHA = '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE = 4855
BOOTSTRAP = {
    'version': '1.0.6',
    'sha256': 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6',
    'size': 42963,
}
VALIDATION_HEAD = 'ff3eff5eaf660d021b306ea8a25f4d3d0151ab0b'
VALIDATION_PUSH_RUN = '40334742776'
VALIDATION_PR_RUN = '40334963589'
VALIDATION_ARTIFACT_ID = '12655932754'
VALIDATION_ARTIFACT_DIGEST = 'sha256:42865e648bdbfe95d5d120d3b1b64a59e3ff7b095dc8c14144ff71b89ff63252'
VALIDATION_REPORT_SHA = 'ffa767a7bedbe097c314a5cae1b362f8e31cf866e60167d925760bd502606297'
ADAPTER_FINGERPRINT = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
REGISTRY_FINGERPRINT = '05c40a5339fe59b001ca0f4c4929643fd59e33a3002bae7067425845c85e2f6e'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']
BASE_OUT = ROOT / 'validation/v0.6.21/out/bin'
TARGET_OUT = ROOT / 'validation/v0.6.22/out/bin'
META = ROOT / 'validation/v0.6.22/release-metadata.json'
MAIN_DIR = ROOT / 'packages/v0.6.22/main-v0621-to-v0622'
ADDON_DIR = ROOT / 'packages/v0.6.22/addon-v065r10-to-v065r11'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def deterministic_gzip(data: bytes) -> bytes:
    buf = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', fileobj=buf, compresslevel=9, mtime=0) as g:
        g.write(data)
    return buf.getvalue()


def clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def write_chunks(encoded: bytes, folder: Path, chunk_size: int = 4096):
    clean_dir(folder)
    chunks = []
    for offset in range(0, len(encoded), chunk_size):
        data = encoded[offset:offset + chunk_size]
        path = folder / f'chunk-{offset // chunk_size:03d}.txt'
        path.write_bytes(data)
        chunks.append({
            'path': str(path.relative_to(ROOT)).replace('\\', '/'),
            'sha256': sha(data),
            'size': len(data),
        })
    if not chunks:
        raise RuntimeError('transport produced no chunks')
    return chunks


def build_full_file_patch(path: str, before: bytes, after: bytes, folder: Path):
    compressed = deterministic_gzip(after)
    encoded = base64.b64encode(compressed)
    chunks = write_chunks(encoded, folder)
    return {
        'path': path,
        'from_sha256': sha(before),
        'to_sha256': sha(after),
        'encoding': 'gzip-base64-full-file',
        'encoded_sha256': sha(encoded),
        'encoded_size': len(encoded),
        'compressed_sha256': sha(compressed),
        'compressed_size': len(compressed),
        'target_size': len(after),
        'chunks': chunks,
    }


def read_chunks(patch, reader):
    parts = []
    for chunk in patch['chunks']:
        data = reader(chunk['path'])
        if len(data) != int(chunk['size']) or sha(data) != chunk['sha256']:
            raise RuntimeError(f"chunk mismatch: {chunk['path']}")
        parts.append(data)
    encoded = b''.join(parts)
    if len(encoded) != int(patch['encoded_size']) or sha(encoded) != patch['encoded_sha256']:
        raise RuntimeError(f"encoded transport mismatch: {patch['path']}")
    compressed = base64.b64decode(encoded, validate=True)
    if len(compressed) != int(patch['compressed_size']) or sha(compressed) != patch['compressed_sha256']:
        raise RuntimeError(f"gzip transport mismatch: {patch['path']}")
    target = gzip.decompress(compressed)
    if len(target) != int(patch['target_size']) or sha(target) != patch['to_sha256']:
        raise RuntimeError(f"target transport mismatch: {patch['path']}")
    return target


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def canonical_payload(latest_files) -> str:
    rows = [f"{row['path']}|{int(row['size'])}|{row['sha256']}" for row in sorted(latest_files, key=lambda x: x['path'])]
    return sha(('\n'.join(rows) + '\n').encode('ascii'))


def build_candidate():
    subprocess.check_call([sys.executable, str(ROOT / 'validation/v0.6.22/build_v0622.py'), '--build'], cwd=ROOT)
    main = (TARGET_OUT / 'spotify-control.ps1').read_bytes()
    addon = (TARGET_OUT / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (TARGET_MAIN_SIZE, TARGET_MAIN_SHA):
        raise RuntimeError(f'validated v0.6.22 main identity mismatch: {len(main)} {sha(main)}')
    if (len(addon), sha(addon)) != (TARGET_ADDON_SIZE, TARGET_ADDON_SHA):
        raise RuntimeError(f'validated r11 identity mismatch: {len(addon)} {sha(addon)}')
    return main, addon


def base_payloads():
    main = (BASE_OUT / 'spotify-control.ps1').read_bytes()
    addon = (BASE_OUT / 'addon-manager.ps1').read_bytes()
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError('v0.6.21 main base identity mismatch')
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError('r10 addon base identity mismatch')
    return main, addon


def build_packages():
    target_main, target_addon = build_candidate()
    base_main, base_addon = base_payloads()
    main_patch = build_full_file_patch('bin/spotify-control.ps1', base_main, target_main, MAIN_DIR)
    addon_patch = build_full_file_patch('bin/addon-manager.ps1', base_addon, target_addon, ADDON_DIR)
    metadata = {
        'schema': 1,
        'base_commit': BASE_COMMIT,
        'base_version': BASE_VERSION,
        'version': NEW_VERSION,
        'addon_version': '0.6.5-r11',
        'candidate_main': {'size': TARGET_MAIN_SIZE, 'sha256': TARGET_MAIN_SHA},
        'candidate_addon': {'size': TARGET_ADDON_SIZE, 'sha256': TARGET_ADDON_SHA},
        'resident_agent': {'size': AGENT_SIZE, 'sha256': AGENT_SHA},
        'bootstrap': BOOTSTRAP,
        'authority_expanded': False,
        'new_auto_install_authority': False,
        'auto_authority': AUTHORIZED_NAMES,
        'adapter_fingerprint': ADAPTER_FINGERPRINT,
        'registry_fingerprint': REGISTRY_FINGERPRINT,
        'validation': {
            'head': VALIDATION_HEAD,
            'push_run': VALIDATION_PUSH_RUN,
            'pr_run': VALIDATION_PR_RUN,
            'artifact_id': VALIDATION_ARTIFACT_ID,
            'artifact_digest': VALIDATION_ARTIFACT_DIGEST,
            'deterministic_report_sha256': VALIDATION_REPORT_SHA,
        },
        'transport': {'main': main_patch, 'addon': addon_patch},
    }
    META.write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    print('V0622_RELEASE_PACKAGES_PASS', TARGET_MAIN_SIZE, TARGET_MAIN_SHA, TARGET_ADDON_SIZE, TARGET_ADDON_SHA)
    return metadata


def assert_base_manifest(manifest):
    if manifest.get('schema') != 1 or manifest.get('channel') != 'stable':
        raise RuntimeError('unexpected manifest schema/channel')
    if manifest.get('latest_version') != BASE_VERSION:
        raise RuntimeError(f"expected stable {BASE_VERSION}, got {manifest.get('latest_version')}")
    if manifest.get('min_bootstrap_version') != '1.0.6' or manifest.get('bootstrap') != BOOTSTRAP:
        raise RuntimeError('Bootstrap contract drift')
    latest = {row['path']: row for row in manifest.get('latest_files', [])}
    expected = {
        'bin/spotify-control.ps1': (BASE_MAIN_SIZE, BASE_MAIN_SHA),
        'bin/addon-manager.ps1': (BASE_ADDON_SIZE, BASE_ADDON_SHA),
        'bin/spotify-control-agent.vbs': (AGENT_SIZE, AGENT_SHA),
    }
    if set(latest) != set(expected):
        raise RuntimeError('unexpected stable latest_files set')
    for path, (size, digest) in expected.items():
        if (int(latest[path]['size']), latest[path]['sha256']) != (size, digest):
            raise RuntimeError(f'base latest_files mismatch: {path}')


def write_manifest(source_commit: str):
    if not re.fullmatch(r'[0-9a-f]{40}', source_commit):
        raise RuntimeError('source commit is not a full lowercase SHA')
    subprocess.check_call(['git', 'cat-file', '-e', f'{source_commit}^{{commit}}'], cwd=ROOT)
    metadata = build_packages()
    manifest_path = ROOT / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    assert_base_manifest(manifest)
    if any(edge.get('from_version') == BASE_VERSION and edge.get('to_version') == NEW_VERSION for edge in manifest['updates']):
        raise RuntimeError('v0.6.21 -> v0.6.22 edge already exists')
    latest_files = [
        {'path': 'bin/spotify-control.ps1', 'sha256': TARGET_MAIN_SHA, 'size': TARGET_MAIN_SIZE},
        {'path': 'bin/addon-manager.ps1', 'sha256': TARGET_ADDON_SHA, 'size': TARGET_ADDON_SIZE},
        {'path': 'bin/spotify-control-agent.vbs', 'sha256': AGENT_SHA, 'size': AGENT_SIZE},
    ]
    edge = {
        'from_version': BASE_VERSION,
        'to_version': NEW_VERSION,
        'patches': [metadata['transport']['main'], metadata['transport']['addon']],
    }
    manifest['latest_version'] = NEW_VERSION
    manifest['source_commit'] = source_commit
    manifest['latest_files'] = latest_files
    manifest['payload_set_sha256'] = canonical_payload(latest_files)
    manifest['updates'].append(edge)
    manifest_path.write_text(json.dumps(manifest, separators=(',', ':')) + '\n', encoding='utf-8', newline='\n')
    print('V0622_MANIFEST_WRITE_PASS', source_commit, manifest['payload_set_sha256'])


def validate_published():
    build_packages()
    manifest = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8-sig'))
    if manifest.get('latest_version') != NEW_VERSION:
        raise RuntimeError(f"expected published {NEW_VERSION}, got {manifest.get('latest_version')}")
    if manifest.get('bootstrap') != BOOTSTRAP or manifest.get('min_bootstrap_version') != '1.0.6':
        raise RuntimeError('published Bootstrap contract drift')
    source = manifest.get('source_commit', '')
    if not re.fullmatch(r'[0-9a-f]{40}', source):
        raise RuntimeError('published source_commit invalid')
    subprocess.check_call(['git', 'cat-file', '-e', f'{source}^{{commit}}'], cwd=ROOT)
    base_manifest = json.loads(git_bytes(BASE_COMMIT, 'manifest.json').decode('utf-8-sig'))
    assert_base_manifest(base_manifest)
    if manifest['updates'][:-1] != base_manifest['updates']:
        raise RuntimeError('historical update edges changed')
    edge = manifest['updates'][-1]
    if edge.get('from_version') != BASE_VERSION or edge.get('to_version') != NEW_VERSION:
        raise RuntimeError('published v0.6.21 -> v0.6.22 edge missing at tail')
    patches = {p['path']: p for p in edge.get('patches', [])}
    if set(patches) != {'bin/spotify-control.ps1', 'bin/addon-manager.ps1'}:
        raise RuntimeError('published edge patch set mismatch')
    target_main = read_chunks(patches['bin/spotify-control.ps1'], lambda p: git_bytes(source, p))
    target_addon = read_chunks(patches['bin/addon-manager.ps1'], lambda p: git_bytes(source, p))
    if (len(target_main), sha(target_main)) != (TARGET_MAIN_SIZE, TARGET_MAIN_SHA):
        raise RuntimeError('immutable source main reconstruction mismatch')
    if (len(target_addon), sha(target_addon)) != (TARGET_ADDON_SIZE, TARGET_ADDON_SHA):
        raise RuntimeError('immutable source addon reconstruction mismatch')
    latest = manifest['latest_files']
    expected_latest = [
        {'path': 'bin/spotify-control.ps1', 'sha256': TARGET_MAIN_SHA, 'size': TARGET_MAIN_SIZE},
        {'path': 'bin/addon-manager.ps1', 'sha256': TARGET_ADDON_SHA, 'size': TARGET_ADDON_SIZE},
        {'path': 'bin/spotify-control-agent.vbs', 'sha256': AGENT_SHA, 'size': AGENT_SIZE},
    ]
    if latest != expected_latest:
        raise RuntimeError('published latest_files mismatch')
    if manifest.get('payload_set_sha256') != canonical_payload(latest):
        raise RuntimeError('published payload set mismatch')
    metadata = json.loads(META.read_text(encoding='utf-8'))
    for patch_name, package_path in [('main', MAIN_DIR), ('addon', ADDON_DIR)]:
        expected = metadata['transport'][patch_name]
        actual = patches['bin/spotify-control.ps1' if patch_name == 'main' else 'bin/addon-manager.ps1']
        if expected != actual:
            raise RuntimeError(f'published {patch_name} transport metadata differs from deterministic rebuild')
        for chunk in expected['chunks']:
            working = (ROOT / chunk['path']).read_bytes()
            pinned = git_bytes(source, chunk['path'])
            if working != pinned:
                raise RuntimeError(f"working transport differs from source commit: {chunk['path']}")
    print('V0622_PUBLISHED_TRANSPORT_PASS', source, manifest['payload_set_sha256'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-packages', action='store_true')
    parser.add_argument('--write-manifest', action='store_true')
    parser.add_argument('--validate-published', action='store_true')
    parser.add_argument('--source-commit')
    args = parser.parse_args()
    modes = sum(bool(x) for x in (args.build_packages, args.write_manifest, args.validate_published))
    if modes != 1:
        parser.error('choose exactly one mode')
    if args.build_packages:
        build_packages()
    elif args.write_manifest:
        if not args.source_commit:
            parser.error('--write-manifest requires --source-commit')
        write_manifest(args.source_commit)
    else:
        validate_published()


if __name__ == '__main__':
    main()
