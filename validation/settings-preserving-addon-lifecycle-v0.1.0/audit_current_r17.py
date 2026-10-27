from __future__ import annotations

from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'validation/settings-preserving-addon-lifecycle-v0.1.0/out'
R17_OUT = ROOT / 'validation/v0.6.28/out/bin'

EXPECTED_ADDON_SIZE = 323385
EXPECTED_ADDON_SHA = '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
EXPECTED_AUTO = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']
PROTECTED_ROOT_MARKERS = [
    'Browser', 'Users', 'IndexedDB', 'Local Storage', 'localStorage', 'Default'
]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def functions(text: str) -> dict[str, str]:
    matches = list(re.finditer(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{', text))
    out: dict[str, str] = {}
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        out[m.group(1)] = text[m.start():end].rstrip()
    return out


def compact(body: str) -> dict:
    lines = body.splitlines()
    risky = []
    patterns = {
        'remove_item': r'\bRemove-Item\b',
        'spicetify_apply': r'(?i)spicetify(?:\.exe)?[^\n]{0,80}\bapply\b',
        'browser_root': r'(?i)[\\/]Browser(?:[\\/]|\b)',
        'users_root': r'(?i)[\\/]Users(?:[\\/]|\b)',
        'indexeddb': r'(?i)IndexedDB',
        'local_storage': r'(?i)Local Storage|localStorage',
        'marketplace': r'(?i)Marketplace',
    }
    for key, pat in patterns.items():
        hits = [idx + 1 for idx, line in enumerate(lines) if re.search(pat, line)]
        if hits:
            risky.append({'kind': key, 'lines': hits})
    return {'line_count': len(lines), 'risk_hits': risky, 'body': body}


def main() -> None:
    subprocess.check_call([sys.executable, str(ROOT / 'validation/v0.6.28/build_v0628.py'), '--build'], cwd=ROOT)
    addon_path = R17_OUT / 'addon-manager.ps1'
    addon = addon_path.read_bytes()
    if (len(addon), sha256(addon)) != (EXPECTED_ADDON_SIZE, EXPECTED_ADDON_SHA):
        raise RuntimeError(f'r17 addon identity drift: {len(addon)} {sha256(addon)}')
    text = addon.decode('utf-8-sig').replace('\r\n', '\n')
    fmap = functions(text)

    selected_names = sorted(
        name for name in fmap
        if any(token.lower() in name.lower() for token in (
            'Addon', 'AutoApps', 'IvLyrics', 'Pithaya', 'Transaction', 'Inventory',
            'Spicetify', 'Marketplace', 'Rollback', 'Commit'
        ))
    )

    registry = fmap.get('Get-AddonPolicyRegistry', '')
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in EXPECTED_AUTO):
        raise RuntimeError(f'current mutation authority drift: {auto}')

    whole_hits = {}
    for marker in PROTECTED_ROOT_MARKERS:
        whole_hits[marker] = [i + 1 for i, line in enumerate(text.splitlines()) if marker.lower() in line.lower()]

    selected = {name: compact(fmap[name]) for name in selected_names}
    report = {
        'schema': 1,
        'addon_size': len(addon),
        'addon_sha256': sha256(addon),
        'function_count': len(fmap),
        'selected_function_count': len(selected_names),
        'selected_function_names': selected_names,
        'automatic_mutation_authority': auto,
        'protected_root_marker_lines': whole_hits,
        'selected_functions': selected,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'addon-manager-r17.ps1').write_bytes(addon)
    (OUT / 'audit.json').write_text(json.dumps(report, indent=2, sort_keys=True), encoding='utf-8')

    print('SETTINGS_PRESERVATION_R17_AUDIT_PASS')
    print('ADDON_SHA256=' + sha256(addon))
    print('FUNCTION_COUNT=' + str(len(fmap)))
    print('AUTO=' + '|'.join(auto))
    print('SELECTED=' + '|'.join(selected_names))
    for marker, lines in whole_hits.items():
        print('MARKER_' + re.sub(r'[^A-Za-z0-9]+', '_', marker).upper() + '=' + ','.join(map(str, lines)))


if __name__ == '__main__':
    main()
