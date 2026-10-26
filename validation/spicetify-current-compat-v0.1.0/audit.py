from pathlib import Path
import hashlib, json, re, subprocess, sys, urllib.request

ROOT = Path(__file__).resolve().parents[2]
BASE_MAIN = '29d6c52c6a79559e513b367ec57edcccebae5fd0'
PROD_MAIN = (281585, 'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18')
PROD_ADDON = (225044, '3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86')
SPICETIFY = {
    '2.46.2': 'dc00e57f2fa8d4502a8efe8633bfaace953f3b09',
    '2.46.3': 'c2ea16caa724464249a78d8e7cedf2aefe5a40b5',
    '2.46.4': 'c3fd98f6fbf922ae944d1ecd64f97c380d04368e',
}
REQUIRED_TAG_TEMPLATES = [
    "<script defer src='extensions/%s'></script>\\n",
    "<script defer type='module' src='extensions/%s'></script>\\n",
    "<script defer src='extensions/%s/%s'></script>\\n",
    "<script defer type='module' src='extensions/%s/%s'></script>\\n",
]


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def ident(path: Path, expected, label: str):
    b = path.read_bytes()
    actual = (len(b), sha(b))
    if actual != expected:
        raise RuntimeError(f'{label} identity drift: {actual} != {expected}')
    return b


def fetch_text(url: str) -> str:
    req = urllib.request.Request(url, headers={'User-Agent': 'spotify-control-spicetify-compat-audit/0.1.0'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode('utf-8')


def main():
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    base = subprocess.check_output(['git', 'merge-base', BASE_MAIN, 'HEAD'], text=True).strip()
    if base != BASE_MAIN:
        raise RuntimeError(f'validation branch is not based on exact production main: merge-base={base}')

    subprocess.check_call([sys.executable, str(ROOT / 'validation/v0.6.20/build_v0620.py'), '--build'], cwd=ROOT)
    out = ROOT / 'validation/v0.6.20/out/bin'
    ident(out / 'spotify-control.ps1', PROD_MAIN, 'production Spotify Control')
    addon_bytes = ident(out / 'addon-manager.ps1', PROD_ADDON, 'production Addon Manager')
    addon = addon_bytes.decode('utf-8-sig')

    if addon.count('$Version = "0.6.5-r9"') != 1:
        raise RuntimeError('generated production Addon Manager version marker mismatch')

    # Known current Spicetify releases must never be hard-pinned in production Addon Manager.
    direct_pins = sorted(set(re.findall(r'(?<![0-9])2\\.46\\.[0-9]+(?![0-9])', addon)))
    if direct_pins:
        raise RuntimeError('production Addon Manager contains Spicetify 2.46.x literal pin(s): ' + ', '.join(direct_pins))

    # Record all Spicetify/version/comparison lines for human evidence. A literal semver near
    # Spicetify is treated as a compatibility-gate candidate and fails the audit.
    lines = addon.splitlines()
    spicetify_lines = []
    gate_candidates = []
    semver = re.compile(r'(?<![0-9])([0-9]+\\.[0-9]+\\.[0-9]+)(?![0-9])')
    for i, line in enumerate(lines, 1):
        lower = line.lower()
        if 'spicetify' in lower:
            spicetify_lines.append({'line': i, 'text': line[:500]})
            nearby = '\n'.join(lines[max(0, i-3):min(len(lines), i+2)])
            versions = semver.findall(nearby)
            if versions:
                gate_candidates.append({'line': i, 'versions': versions, 'context': nearby[:1500]})
    if gate_candidates:
        raise RuntimeError('found semantic-version literal(s) adjacent to Spicetify production logic: ' + json.dumps(gate_candidates, ensure_ascii=False))

    required_contracts = [
        'Invoke-PerformanceOverlayBestEffort',
        'Invoke-StarRatingsPerformanceBestEffort',
        'upstream/original hooks remain authoritative',
        'active upstream bytes remain authoritative',
        'Performance overlay safe no-op',
    ]
    for marker in required_contracts:
        if marker not in addon:
            raise RuntimeError(f'missing fail-open production contract marker: {marker}')

    check_start = addon.index('"Check" {')
    update_start = addon.index('"Update" {')
    check_block = addon[check_start:update_start]
    if 'Invoke-PerformanceOverlayBestEffort' in check_block or 'Invoke-StarRatingsPerformanceBestEffort' in check_block:
        raise RuntimeError('Check action unexpectedly mutates performance optimization state')

    upstream = {}
    normalized_templates = None
    for version, commit in SPICETIFY.items():
        url = f'https://raw.githubusercontent.com/spicetify/cli/{commit}/src/apply/apply.go'
        source = fetch_text(url)
        missing = [x for x in REQUIRED_TAG_TEMPLATES if x not in source]
        if missing:
            raise RuntimeError(f'Spicetify {version} extension/custom-app tag contract changed: missing {missing}')
        template_lines = sorted(
            line.strip() for line in source.splitlines()
            if 'extensionsHTML' in line and '<script defer' in line and "src='extensions/" in line
        )
        if normalized_templates is None:
            normalized_templates = template_lines
        elif template_lines != normalized_templates:
            raise RuntimeError(f'Spicetify {version} extension tag template set differs from 2.46.2')
        upstream[version] = {
            'commit': commit,
            'required_templates_present': True,
            'template_lines': template_lines,
        }

    overlay = (ROOT / 'performance/overlay/apply-overlay.ps1').read_text(encoding='utf-8-sig')
    if '(?:\\./)?' not in overlay or '["'']' not in overlay:
        raise RuntimeError('overlay hook matcher lost optional ./ or quote-tolerant source matching')

    report = {
        'schema': 1,
        'audit': 'spicetify-current-compat-v0.1.0',
        'production_base': BASE_MAIN,
        'validation_head': head,
        'production_main': {'size': PROD_MAIN[0], 'sha256': PROD_MAIN[1]},
        'production_addon': {'size': PROD_ADDON[0], 'sha256': PROD_ADDON[1]},
        'spicetify_literal_pins': direct_pins,
        'spicetify_logic_line_count': len(spicetify_lines),
        'spicetify_logic_lines': spicetify_lines,
        'spicetify_semver_gate_candidates': gate_candidates,
        'upstream_apply_contracts': upstream,
        'result': 'PASS',
        'conclusion': 'Production logic is not pinned to Spicetify 2.46.x; exact-file provenance remains the optimization gate and upstream extension tag generation is compatible across 2.46.2/2.46.3/2.46.4.',
    }
    path = ROOT / 'spicetify-current-compat-audit.json'
    path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')
    print('SPICETIFY_CURRENT_COMPAT_AUDIT_PASS')
    print('production_addon', PROD_ADDON[0], PROD_ADDON[1])
    print('spicetify_logic_line_count', len(spicetify_lines))
    print('upstream_versions', ','.join(SPICETIFY))


if __name__ == '__main__':
    main()
