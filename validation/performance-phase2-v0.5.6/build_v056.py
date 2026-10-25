from pathlib import Path
import base64

root = Path(__file__).parent
parts = sorted(root.glob('build_v056.part*.b64'))
if len(parts) != 6:
    raise RuntimeError(f'expected 6 embedded builder chunks, found {len(parts)}')
payload = ''.join(p.read_text(encoding='ascii').strip() for p in parts)
code = base64.b64decode(payload)
exec(compile(code, 'build_v056.selfcontained.py', 'exec'), globals(), globals())
