from pathlib import Path

p = Path('validation/performance-phase2-v0.5.4/runtime_overlay_v054.ps1.inc')
s = p.read_text(encoding='utf-8')
marker = 'function Invoke-SelfTest {'
if marker not in s:
    raise SystemExit('Invoke-SelfTest not found')
head, selftest = s.split(marker, 1)
before = selftest

# Normalize only the known glued comparison/match tokens inside Invoke-SelfTest.
# Keep this deliberately scoped so no production/runtime orchestration outside SelfTest changes.
repls = {
    ')-ne95': ') -ne 95',
    ')-ne2.5': ') -ne 2.5',
    ")-ne'current-v0620-r9'": ") -ne 'current-v0620-r9'",
    ")-ne'previous-v0619-r8'": ") -ne 'previous-v0619-r8'",
    ")-ne'previous-v0618-r7'": ") -ne 'previous-v0618-r7'",
    ")-ne'unknown-or-partial'": ") -ne 'unknown-or-partial'",
    '$matrix.Count-ne5': '$matrix.Count -ne 5',
    ")-ne'BASELINE_A,BLF_ORIGINAL,PLAYLIST_MAKER_ORIGINAL,BOTH_ORIGINAL,BASELINE_B'": ") -ne 'BASELINE_A,BLF_ORIGINAL,PLAYLIST_MAKER_ORIGINAL,BOTH_ORIGINAL,BASELINE_B'",
    ').Count-ne2': ').Count -ne 2',
    ').Count-ne1': ').Count -ne 1',
    "status-ne'applied'": "status -ne 'applied'",
    ')-eq$origSha': ') -eq $origSha',
    "$txt-notmatch'spotify-control-performance-overlay:lazy:better-local-files'": "$txt -notmatch 'spotify-control-performance-overlay:lazy:better-local-files'",
    "$txt-notmatch'spotify-control-performance-overlay:lazy:playlist-maker'": "$txt -notmatch 'spotify-control-performance-overlay:lazy:playlist-maker'",
    ')-ne$origSha': ') -ne $origSha',
    "$txt-match'spotify-control-performance-overlay:lazy:better-local-files'": "$txt -match 'spotify-control-performance-overlay:lazy:better-local-files'",
    "$txt-notmatch'extensions/better-local-files/extension.js'": "$txt -notmatch 'extensions/better-local-files/extension.js'",
    "reason-ne'no-exactly-proven-targets'": "reason -ne 'no-exactly-proven-targets'",
}
for old, new in repls.items():
    selftest = selftest.replace(old, new)

if selftest == before:
    raise SystemExit('spacing fixer made no changes')

for bad in [
    '-ne95', '-ne2.5', 'Count-ne', 'status-ne', 'reason-ne',
    '$txt-notmatch', '$txt-match', '-eq$origSha', '-ne$origSha',
    ")-ne'current-v0620-r9'", ")-ne'previous-v0619-r8'",
    ")-ne'previous-v0618-r7'", ")-ne'unknown-or-partial'",
]:
    if bad in selftest:
        raise SystemExit(f'glued operator survived: {bad}')

p.write_text(head + marker + selftest, encoding='utf-8', newline='\n')
print('PHASE2_V054_SELFTEST_SPACING_FIXED')
