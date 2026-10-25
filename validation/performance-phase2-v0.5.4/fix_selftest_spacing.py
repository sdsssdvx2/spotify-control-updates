from pathlib import Path

p = Path('validation/performance-phase2-v0.5.4/runtime_overlay_v054.ps1.inc')
s = p.read_text(encoding='utf-8')
marker = 'function Invoke-SelfTest {'
if marker not in s:
    raise SystemExit('Invoke-SelfTest not found')
head, selftest = s.split(marker, 1)
before = selftest

# Normalize only known glued PowerShell operators inside Invoke-SelfTest.
repls = [
    (')-ne95', ') -ne 95'),
    (')-ne2.5', ') -ne 2.5'),
    (")-ne'", ") -ne '"),
    ('$matrix.Count-ne5', '$matrix.Count -ne 5'),
    (').Count-ne2', ').Count -ne 2'),
    (').Count-ne1', ').Count -ne 1'),
    ("status-ne'", "status -ne '"),
    ("reason-ne'", "reason -ne '"),
    (')-eq$origSha', ') -eq $origSha'),
    (')-ne$origSha', ') -ne $origSha'),
    ("$txt-notmatch'", "$txt -notmatch '"),
    ("$txt-match'", "$txt -match '"),
]
for old, new in repls:
    selftest = selftest.replace(old, new)

if selftest == before:
    raise SystemExit('spacing fixer made no changes')

for bad in [
    '-ne95', '-ne2.5', ")-ne'", 'Count-ne', 'status-ne', 'reason-ne',
    '$txt-notmatch', '$txt-match', '-eq$origSha', '-ne$origSha',
]:
    if bad in selftest:
        raise SystemExit(f'glued operator survived: {bad}')

p.write_text(head + marker + selftest, encoding='utf-8', newline='\n')
print('PHASE2_V054_SELFTEST_SPACING_FIXED')
