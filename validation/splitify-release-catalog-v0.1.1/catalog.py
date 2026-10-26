from pathlib import Path
import hashlib, json, re, stat, urllib.request, zipfile

API = 'https://api.github.com/repos/alexander-rebello/splitify/releases?per_page=100'
UA = 'SpotifyControl-Splitify-Release-Catalog/0.1.1'
OUT = Path('splitify-release-catalog-evidence')
OUT.mkdir(exist_ok=True)


def get_json(url):
    req = urllib.request.Request(url, headers={
        'User-Agent': UA,
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def download(url, path):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=60) as r, open(path, 'wb') as f:
        while True:
            b = r.read(1024 * 1024)
            if not b:
                break
            f.write(b)


def semver(tag):
    return tuple(map(int, tag[1:].split('.')))


def ordinal_ignore_case_ascii_key(path):
    if any(ord(c) > 127 for c in path):
        raise ValueError(f'non-ASCII path requires explicit OrdinalIgnoreCase parity review: {path!r}')
    return (path.lower(), path)


def decode_manifest(raw):
    value = json.loads(raw)
    if isinstance(value, str):
        value = json.loads(value)
    if not isinstance(value, dict):
        raise ValueError(f'manifest-json-type:{type(value).__name__}')
    return value


def inspect_release(release):
    tag = release['tag_name']
    version = tag[1:]
    assets = [a for a in release.get('assets', []) if a.get('name') == 'splitify.zip']
    if len(assets) != 1:
        return None, {'version': version, 'tag': tag, 'reason': 'no-splitify-zip' if not assets else f'ambiguous-splitify-zip-assets:{len(assets)}'}
    asset = assets[0]
    digest = str(asset.get('digest') or '').lower()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        return None, {'version': version, 'tag': tag, 'reason': 'no-github-sha256-digest'}
    try:
        zip_path = OUT / f'{tag}.zip'
        download(asset['browser_download_url'], zip_path)
        raw = zip_path.read_bytes()
        actual = hashlib.sha256(raw).hexdigest()
        if len(raw) != int(asset['size']) or actual != digest[7:]:
            raise ValueError('asset-authentication-mismatch')
        seen = set()
        top = set()
        files = []
        expanded = 0
        manifest_bytes = None
        with zipfile.ZipFile(zip_path) as z:
            infos = z.infolist()
            if len(infos) > 100:
                raise ValueError('too-many-entries')
            for info in infos:
                name = info.filename.replace('\\', '/')
                if not name or name.startswith('/') or re.match(r'^[A-Za-z]:', name) or ':' in name:
                    raise ValueError(f'unsafe-path:{name}')
                trimmed = name.rstrip('/')
                parts = trimmed.split('/') if trimmed else []
                if not parts or any(p in ('', '.', '..') for p in parts):
                    raise ValueError(f'unsafe-component:{name}')
                key = trimmed.lower()
                if key in seen:
                    raise ValueError(f'duplicate-case-collision:{trimmed}')
                seen.add(key)
                top.add(parts[0])
                mode = (info.external_attr >> 16) & 0o170000
                if mode == stat.S_IFLNK:
                    raise ValueError(f'symlink:{name}')
                if info.is_dir():
                    continue
                if info.file_size < 0 or info.file_size > 16 * 1024 * 1024:
                    raise ValueError(f'oversized-entry:{name}')
                expanded += info.file_size
                if expanded > 32 * 1024 * 1024:
                    raise ValueError('expanded-cap-exceeded')
            if len(top) != 1:
                raise ValueError('ambiguous-top-level:' + ','.join(sorted(top)))
            root = next(iter(top))
            for info in infos:
                if info.is_dir():
                    continue
                parts = info.filename.replace('\\', '/').rstrip('/').split('/')
                if parts[0] != root:
                    raise ValueError('root-drift')
                relpath = '/'.join(parts[1:])
                if not relpath:
                    raise ValueError('file-at-top-level-root')
                data = z.read(info)
                if len(data) != info.file_size:
                    raise ValueError(f'size-mismatch:{info.filename}')
                file_row = {'path': relpath, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                files.append(file_row)
                if relpath == 'manifest.json':
                    manifest_bytes = data
        if not files:
            raise ValueError('no-files')
        if manifest_bytes is None:
            raise ValueError('manifest-missing')
        manifest = decode_manifest(manifest_bytes)
        if str(manifest.get('name') or '').lower() != 'splitify':
            raise ValueError('manifest-identity-mismatch')
        files.sort(key=lambda x: ordinal_ignore_case_ascii_key(x['path']))
        payload = ''.join(f"{x['path']}|{x['size']}|{x['sha256']}\n" for x in files).encode('utf-8')
        tree = hashlib.sha256(payload).hexdigest()
        return {
            'version': version,
            'tag': tag,
            'published_at': release.get('published_at'),
            'asset_size': len(raw),
            'asset_sha256': actual,
            'asset_digest': digest,
            'root_name': root,
            'tree_sha256': tree,
            'file_count': len(files),
            'expanded_bytes': sum(x['size'] for x in files),
            'manifest_name': manifest.get('name'),
            'manifest_version': manifest.get('version'),
            'files': files,
        }, None
    except Exception as exc:
        return None, {'version': version, 'tag': tag, 'reason': 'asset-unprovable:' + str(exc)}


releases = get_json(API)
stable = [r for r in releases if not r.get('draft') and not r.get('prerelease') and re.fullmatch(r'v\d+\.\d+\.\d+', str(r.get('tag_name') or ''))]
stable.sort(key=lambda r: semver(r['tag_name']))
if not stable:
    raise SystemExit('No stable Splitify releases found')

catalog = []
unsupported = []
for release in stable:
    release_row, bad = inspect_release(release)
    if release_row:
        catalog.append(release_row)
        print('SPLITIFY_RELEASE', release_row['tag'], release_row['asset_size'], release_row['asset_sha256'], release_row['tree_sha256'], release_row['file_count'])
    else:
        unsupported.append(bad)
        print('SPLITIFY_UNPROVABLE', bad['tag'], bad['reason'])
if not catalog:
    raise SystemExit('No cryptographically provable release assets')

by_tree = {}
for release_row in catalog:
    by_tree.setdefault(release_row['tree_sha256'], []).append(release_row['version'])
duplicates = {k: v for k, v in by_tree.items() if len(v) > 1}
result = {
    'schema': 2,
    'canonical_order': 'OrdinalIgnoreCase-ASCII-path, Ordinal tie-break',
    'repository': 'alexander-rebello/splitify',
    'stable_release_count': len(stable),
    'provable_release_count': len(catalog),
    'latest_stable_version': stable[-1]['tag_name'][1:],
    'latest_provable_version': catalog[-1]['version'],
    'catalog': catalog,
    'unsupported_stable_releases': unsupported,
    'duplicate_tree_versions': duplicates,
}
(OUT / 'catalog.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n', encoding='utf-8')
print('SPLITIFY_RELEASE_CATALOG_PASS', len(stable), len(catalog), stable[-1]['tag_name'], json.dumps(unsupported, sort_keys=True), json.dumps(duplicates, sort_keys=True))
