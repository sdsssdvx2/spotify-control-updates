from pathlib import Path
p=Path('validation/performance-phase2-v0.5.4/runtime_overlay_v054.ps1.inc')
s=p.read_text(encoding='utf-8')
repls={
    ')-ne95':') -ne 95',
    ')-ne2.5':') -ne 2.5',
    ')-ne\'current-v0620-r9\'':') -ne \'current-v0620-r9\'',
    ')-ne\'previous-v0619-r8\'':') -ne \'previous-v0619-r8\'',
    ')-ne\'previous-v0618-r7\'':') -ne \'previous-v0618-r7\'',
    ')-ne\'unknown-or-partial\'':') -ne \'unknown-or-partial\'',
    '$matrix.Count-ne5':'$matrix.Count -ne 5',
    ")-ne'BASELINE_A,BLF_ORIGINAL,PLAYLIST_MAKER_ORIGINAL,BOTH_ORIGINAL,BASELINE_B'":") -ne 'BASELINE_A,BLF_ORIGINAL,PLAYLIST_MAKER_ORIGINAL,BOTH_ORIGINAL,BASELINE_B'",
    ').Count-ne2':').Count -ne 2',
    ').Count-ne1':').Count -ne 1',
    ").status-ne'applied'":").status -ne 'applied'",
    ")-eq$origSha":") -eq $origSha",
    "$txt-notmatch'spotify-control-performance-overlay:lazy:better-local-files'":"$txt -notmatch 'spotify-control-performance-overlay:lazy:better-local-files'",
    "$txt-notmatch'spotify-control-performance-overlay:lazy:playlist-maker'":"$txt -notmatch 'spotify-control-performance-overlay:lazy:playlist-maker'",
    ")-ne$origSha":") -ne $origSha",
    "$txt-match'spotify-control-performance-overlay:lazy:better-local-files'":"$txt -match 'spotify-control-performance-overlay:lazy:better-local-files'",
    "$txt-notmatch'extensions/better-local-files/extension.js'":"$txt -notmatch 'extensions/better-local-files/extension.js'",
    ").reason-ne'no-exactly-proven-targets'":").reason -ne 'no-exactly-proven-targets'",
}
for old,new in repls.items():
    if old not in s:
        raise SystemExit(f'missing expected token: {old}')
    s=s.replace(old,new)
# Fail if known glued comparison/match operators remain in the SelfTest block.
selftest=s[s.index('function Invoke-SelfTest {'):]
for bad in ['-ne95','-ne2.5','Count-ne','status-ne','reason-ne','$txt-notmatch','$txt-match','-eq$origSha','-ne$origSha']:
    if bad in selftest:
        raise SystemExit(f'glued operator survived: {bad}')
p.write_text(s,encoding='utf-8',newline='\n')
print('PHASE2_V054_SELFTEST_SPACING_FIXED')
