from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from io import BytesIO

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
GEN = HERE / 'generated'
OUT = HERE / 'out'
PKG = OUT / 'SpotifyControl-v0.6.22-r11-Runtime-Acceptance-v1.0.2'
ZIP = OUT / 'SpotifyControl-v0.6.22-r11-Runtime-Acceptance-v1.0.2.zip'

BASE_VALIDATION_HEAD = '14862b19faa486cc9582fac51d8ce0394e7cd02d'
BASE_BUILDER_PATH = 'validation/v0.6.22-runtime-acceptance-v1.0.1/build_acceptance.py'
BASE_BUILDER_BLOB = '2f65d2d4ba815b40bd0d7fafd8431e28bcda431a'
BASE_ZIP_NAME = 'SpotifyControl-v0.6.22-r11-Runtime-Acceptance-v1.0.1.zip'
BASE_ZIP_SIZE = 52871
BASE_ZIP_SHA256 = '0ce86460a356a5408b2c1bc89a7af13ec5576bd4b357744861adbb5e349f45b7'
BASE_RUNTIME_SHA256 = 'd3884e7abec8fc1c5f6c4c6af0f4bf5921dffab038a7608e7cd73c6468d749d2'
BASE_RUNNER_SHA256 = 'ea09f1f4d545973a3b34c360bb97882a32faa934f772079cfb9241c85abfcf6a'

RELEASE_HEAD = '9c1cabcaaed6c7a1465f5baea12d046a5d51c8dc'
RELEASE_MANIFEST_SHA256 = '9eea792cf0f81c09d3527f879b98c44dbbcbce1209c7dbc651d4298453f28e32'
TRANSPORT_SOURCE = 'db4dd0e4357cbf03ea95dd8773c0be173b2c91fc'
PAYLOAD_SET = 'cb396442ac874504a04d4acb0034d3cb9fa11acce290da18e639c2dbe8e5a091'

V0620_MAIN_SHA = 'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'
V0620_ADDON_SHA = '3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'
V0620_MAIN_SIZE = 281585
V0620_ADDON_SIZE = 225044

V0621_MAIN_SHA = 'f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'
V0621_ADDON_SHA = '7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
V0621_MAIN_SIZE = 281579
V0621_ADDON_SIZE = 250616

TARGET_MAIN_SHA = 'b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe'
TARGET_ADDON_SHA = '0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc'
TARGET_MAIN_SIZE = 281586
TARGET_ADDON_SIZE = 268670
AGENT_SHA = '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE = 4855
BOOTSTRAP_SHA = 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
BOOTSTRAP_SIZE = 42963

SOURCE_FILES = [
    'RUN_RUNTIME_ACCEPTANCE.ps1',
    'RUN_RUNTIME_ACCEPTANCE.cmd',
    'PRECHECK_RUNTIME_ACCEPTANCE.ps1',
    'BOOTSTRAP_RUNNER.ps1',
]

README_TEXT = f"""Spotify Control v0.6.22 / Addon Manager r11 Runtime Acceptance v1.0.2

Purpose
-------
This is the one-shot real-PC acceptance for the already CI-validated v0.6.22/r11 release candidate.
It supports either of the two exact known starting production baselines and restores the exact baseline it found:
- v0.6.20 / Addon Manager r9 (two update edges)
- v0.6.21 / Addon Manager r10 (one update edge)

Why v1.0.2 exists
-----------------
v1.0.1 was retired after a real-PC preflight, before any candidate mutation, proved that the machine still had the exact v0.6.20/r9 production payload rather than v0.6.21/r10. The observed v0.6.20/r9 hashes exactly match the historical validated release identities. This was an acceptance-baseline assumption failure, not a v0.6.22/r11 candidate failure.

v1.0.2 removes that assumption. It accepts only the two exact pinned baseline pairs above, detects which pair is actually installed before mutation, verifies the corresponding one-edge or two-edge Bootstrap path, and restores that same exact starting pair afterward. Any unknown or mixed baseline fails closed before mutation.

Transport design
----------------
1. Before resident/mutation state is touched, the acceptance selects an exact supported baseline by size + SHA-256 for both Spotify Control and Addon Manager, while also pinning the resident agent and Bootstrap 1.0.6.
2. It fetches the manifest from the exact immutable release-head GitHub raw HTTPS URL.
3. It validates v0.6.22, source commit, payload-set hash, exact Bootstrap identity, exact latest payload identities, and both sequential edges v0.6.20 -> v0.6.21 and v0.6.21 -> v0.6.22 including SHA linkage for both managed files.
4. The exact installed Bootstrap 1.0.6 file is executed byte-for-byte unchanged.
5. In that temporary runner process only, Bootstrap's single production-manifest Invoke-RestMethod call is shimmed to return the already validated pinned manifest object.
6. Patch chunks are not shimmed. Bootstrap downloads them from raw.githubusercontent.com at source commit {TRANSPORT_SOURCE} and verifies their size/SHA/compressed payload contracts normally.
7. Check must report exactly 2 edges from v0.6.20 or exactly 1 edge from v0.6.21. RollbackTest must restore the exact selected baseline; Update must commit exact v0.6.22/r11; post-Check must report already-current with zero edges.

Exact identities
----------------
Supported baseline A - v0.6.20/r9:
- Spotify Control: {V0620_MAIN_SIZE} bytes / {V0620_MAIN_SHA}
- Addon Manager: {V0620_ADDON_SIZE} bytes / {V0620_ADDON_SHA}

Supported baseline B - v0.6.21/r10:
- Spotify Control: {V0621_MAIN_SIZE} bytes / {V0621_MAIN_SHA}
- Addon Manager: {V0621_ADDON_SIZE} bytes / {V0621_ADDON_SHA}

Candidate v0.6.22/r11:
- Spotify Control: {TARGET_MAIN_SIZE} bytes / {TARGET_MAIN_SHA}
- Addon Manager: {TARGET_ADDON_SIZE} bytes / {TARGET_ADDON_SHA}

Unchanged:
- resident agent: {AGENT_SIZE} bytes / {AGENT_SHA}
- Bootstrap 1.0.6: {BOOTSTRAP_SIZE} bytes / {BOOTSTRAP_SHA}

Safety
------
- Spotify must be fully closed.
- Run as a normal user, NOT Administrator.
- No Spotify launch is performed.
- Addon Manager Update is not called.
- Tagify, Splitify, Star Ratings, SC Cover Ambience and Spicetify config surfaces are fingerprinted and must stay unchanged.
- Unknown or mixed main/addon baseline identities fail closed before mutation.
- HTTPS manifest preflight happens before the resident is stopped or agent_mutation_enabled is changed.
- Child PowerShell executions are bounded by explicit process timeouts.
- On any later failure, the exact starting code/state and resident agent are restored.

Run
---
1. Fully close Spotify.
2. Extract this ZIP into a NEW folder. Do not overwrite older acceptance files.
3. Run RUN_RUNTIME_ACCEPTANCE.cmd normally, NOT as Administrator.
4. Do not edit Spotify/Spicetify files while it runs.

Retired builds
--------------
v1.0.0 and v1.0.1 must not be run. Historical localhost acceptance builds also remain retired.

Evidence
--------
Success:
%LOCALAPPDATA%\\SpotifyControl\\reports\\v0622-r11-runtime-acceptance-latest.json

Failure:
%LOCALAPPDATA%\\SpotifyControl\\reports\\v0622-r11-runtime-acceptance-failure-latest.txt
"""


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_path(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


def patch_map(edge: dict) -> dict:
    rows = edge.get('patches', [])
    if len(rows) != 2:
        raise RuntimeError('expected exactly two managed patches per edge')
    out = {p.get('path'): p for p in rows}
    if sorted(out) != ['bin/addon-manager.ps1', 'bin/spotify-control.ps1']:
        raise RuntimeError(f'edge patch path drift: {sorted(out)}')
    return out


def validate_release_manifest_contracts() -> None:
    rel_bytes = git_bytes(RELEASE_HEAD, 'manifest.json')
    if len(rel_bytes) != 38782 or sha_bytes(rel_bytes) != RELEASE_MANIFEST_SHA256:
        raise RuntimeError(f'release manifest byte identity drift: {len(rel_bytes)} {sha_bytes(rel_bytes)}')
    rel = json.loads(rel_bytes.decode('utf-8-sig'))
    if rel.get('latest_version') != '0.6.22':
        raise RuntimeError('release latest_version drift')
    if rel.get('source_commit') != TRANSPORT_SOURCE or rel.get('payload_set_sha256') != PAYLOAD_SET:
        raise RuntimeError('release transport identity drift')
    boot = rel.get('bootstrap') or {}
    if boot != {'version': '1.0.6', 'sha256': BOOTSTRAP_SHA, 'size': BOOTSTRAP_SIZE}:
        raise RuntimeError(f'release Bootstrap identity drift: {boot}')
    latest = {x.get('path'): x for x in rel.get('latest_files', [])}
    expected_latest = {
        'bin/spotify-control.ps1': {'path': 'bin/spotify-control.ps1', 'sha256': TARGET_MAIN_SHA, 'size': TARGET_MAIN_SIZE},
        'bin/addon-manager.ps1': {'path': 'bin/addon-manager.ps1', 'sha256': TARGET_ADDON_SHA, 'size': TARGET_ADDON_SIZE},
        'bin/spotify-control-agent.vbs': {'path': 'bin/spotify-control-agent.vbs', 'sha256': AGENT_SHA, 'size': AGENT_SIZE},
    }
    for path, expected in expected_latest.items():
        if latest.get(path) != expected:
            raise RuntimeError(f'release latest identity drift for {path}: {latest.get(path)}')
    e20 = [e for e in rel.get('updates', []) if e.get('from_version') == '0.6.20' and e.get('to_version') == '0.6.21']
    e21 = [e for e in rel.get('updates', []) if e.get('from_version') == '0.6.21' and e.get('to_version') == '0.6.22']
    if len(e20) != 1 or len(e21) != 1:
        raise RuntimeError('required sequential release edges missing/ambiguous')
    p20, p21 = patch_map(e20[0]), patch_map(e21[0])
    chain = [
        ('bin/spotify-control.ps1', V0620_MAIN_SHA, V0621_MAIN_SHA, TARGET_MAIN_SHA),
        ('bin/addon-manager.ps1', V0620_ADDON_SHA, V0621_ADDON_SHA, TARGET_ADDON_SHA),
    ]
    for path, h20, h21, h22 in chain:
        if p20[path].get('from_sha256') != h20 or p20[path].get('to_sha256') != h21:
            raise RuntimeError(f'v0.6.20 -> v0.6.21 SHA linkage drift for {path}')
        if p21[path].get('from_sha256') != h21 or p21[path].get('to_sha256') != h22:
            raise RuntimeError(f'v0.6.21 -> v0.6.22 SHA linkage drift for {path}')


def rebuild_base_v101() -> tuple[bytes, dict]:
    blob = subprocess.check_output(['git', 'rev-parse', f'{BASE_VALIDATION_HEAD}:{BASE_BUILDER_PATH}'], cwd=ROOT, text=True).strip()
    if blob != BASE_BUILDER_BLOB:
        raise RuntimeError(f'v1.0.1 builder blob drift: {blob}')
    source = git_bytes(BASE_VALIDATION_HEAD, BASE_BUILDER_PATH)
    temp = ROOT / 'validation' / 'v0.6.22-runtime-acceptance-v1.0.1'
    shutil.rmtree(temp, ignore_errors=True)
    temp.mkdir(parents=True)
    try:
        (temp / 'build_acceptance.py').write_bytes(source)
        subprocess.check_call([sys.executable, str(temp / 'build_acceptance.py')], cwd=ROOT)
        base_zip = temp / 'out' / BASE_ZIP_NAME
        raw = base_zip.read_bytes()
        if len(raw) != BASE_ZIP_SIZE or sha_bytes(raw) != BASE_ZIP_SHA256:
            raise RuntimeError(f'v1.0.1 base package identity drift: {len(raw)} {sha_bytes(raw)}')
        with zipfile.ZipFile(base_zip) as z:
            if z.testzip() is not None:
                raise RuntimeError('v1.0.1 base package CRC failure')
            if sha_bytes(z.read('RUN_RUNTIME_ACCEPTANCE.ps1')) != BASE_RUNTIME_SHA256:
                raise RuntimeError('v1.0.1 runtime identity drift')
            if sha_bytes(z.read('BOOTSTRAP_RUNNER.ps1')) != BASE_RUNNER_SHA256:
                raise RuntimeError('v1.0.1 Bootstrap runner identity drift')
            report = json.loads(z.read('evidence/SELF_VALIDATION_REPORT.json').decode('utf-8'))
            if int(report.get('passed', -1)) != 42 or int(report.get('total', -1)) != 42:
                raise RuntimeError('v1.0.1 base source contract is not 42/42')
        return raw, report
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def replace_one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one old token, found {count}')
    return text.replace(old, new, 1)


def replace_line_prefix(text: str, prefix: str, replacement: str, label: str) -> str:
    lines = text.splitlines(keepends=True)
    hits = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(hits) != 1:
        raise RuntimeError(f'{label}: expected exactly one line prefix, found {len(hits)}')
    i = hits[0]
    ending = '\r\n' if lines[i].endswith('\r\n') else '\n'
    lines[i] = replacement + ending
    return ''.join(lines)


def patch_runtime(data: bytes) -> bytes:
    text = data.decode('utf-8-sig')
    text = replace_one(text, "$AcceptanceVersion='1.0.1'", "$AcceptanceVersion='1.0.2'", 'acceptance-version')
    old_baseline = "\n".join([
        "$BaselineMainVersion='0.6.21'",
        "$BaselineAddonVersion='0.6.5-r10'",
        "$BaselineMainSha='f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'",
        "$BaselineAddonSha='7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'",
    ])
    new_baseline = "\n".join([
        "$BaselineMainVersion=$null",
        "$BaselineAddonVersion=$null",
        "$BaselineMainSha=$null",
        "$BaselineAddonSha=$null",
        "$BaselineMainSize=[int64]0",
        "$BaselineAddonSize=[int64]0",
        "$BaselineProfile=$null",
        "$ExpectedEdgeCount=0",
        "$BaselineSelected=$false",
        "$V0620MainSha='e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'",
        "$V0620AddonSha='3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'",
        "$V0621MainSha='f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'",
        "$V0621AddonSha='7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'",
    ])
    text = replace_one(text, old_baseline, new_baseline, 'baseline-constant-block')

    select_and_assert = (
        "function Assert-BaselineComponents{Assert-Identity $Main $BaselineMainSha $BaselineMainSize "
        "('Spotify Control '+$BaselineMainVersion+' main');Assert-Identity $Addon $BaselineAddonSha $BaselineAddonSize "
        "('Addon Manager '+$BaselineAddonVersion);Assert-Identity $Agent $ExpectedAgentSha 4855 'resident agent';"
        "Assert-Identity $Bootstrap $ExpectedBootstrapSha 42963 'Bootstrap 1.0.6'}\n"
        "function Select-ExactBaseline{Assert-Identity $Agent $ExpectedAgentSha 4855 'resident agent';"
        "Assert-Identity $Bootstrap $ExpectedBootstrapSha 42963 'Bootstrap 1.0.6';"
        "if(-not(Test-Path -LiteralPath $Main -PathType Leaf) -or -not(Test-Path -LiteralPath $Addon -PathType Leaf)){throw 'Managed main/addon baseline file missing.'};"
        "$ms=[int64](Get-Item -LiteralPath $Main).Length;$as=[int64](Get-Item -LiteralPath $Addon).Length;"
        "$mh=Get-Sha $Main;$ah=Get-Sha $Addon;"
        "if($ms -eq 281585 -and $mh -ceq $V0620MainSha -and $as -eq 225044 -and $ah -ceq $V0620AddonSha){"
        "$script:BaselineMainVersion='0.6.20';$script:BaselineAddonVersion='0.6.5-r9';$script:BaselineMainSha=$V0620MainSha;$script:BaselineAddonSha=$V0620AddonSha;"
        "$script:BaselineMainSize=[int64]281585;$script:BaselineAddonSize=[int64]225044;$script:BaselineProfile='v0.6.20/r9';$script:ExpectedEdgeCount=2}"
        "elseif($ms -eq 281579 -and $mh -ceq $V0621MainSha -and $as -eq 250616 -and $ah -ceq $V0621AddonSha){"
        "$script:BaselineMainVersion='0.6.21';$script:BaselineAddonVersion='0.6.5-r10';$script:BaselineMainSha=$V0621MainSha;$script:BaselineAddonSha=$V0621AddonSha;"
        "$script:BaselineMainSize=[int64]281579;$script:BaselineAddonSize=[int64]250616;$script:BaselineProfile='v0.6.21/r10';$script:ExpectedEdgeCount=1}"
        "else{throw \"Unsupported or mixed installed baseline. main_size=$ms main_sha=$mh addon_size=$as addon_sha=$ah\"};"
        "$script:BaselineSelected=$true;Write-Host ('Exact starting baseline selected: '+$BaselineProfile+' / expected edges='+$ExpectedEdgeCount)}"
    )
    text = replace_line_prefix(text, 'function Assert-BaselineComponents{', select_and_assert, 'baseline-functions')

    manifest_function = (
        "function Assert-PinnedReleaseManifest{param([string]$ManifestPath);"
        "if(-not(Test-Path -LiteralPath $ManifestPath -PathType Leaf)){throw 'Pinned release manifest file missing.'};"
        "$raw=Get-Content -LiteralPath $ManifestPath -Raw;$m=$raw|ConvertFrom-Json;"
        "if([int]$m.schema -ne 1 -or [string]$m.channel -cne 'stable' -or [string]$m.source_repository -cne 'sdsssdvx2/spotify-control-updates'){throw 'Pinned release manifest root identity mismatch.'};"
        "if([string]$m.latest_version -cne $TargetMainVersion){throw 'Pinned release manifest latest_version mismatch.'};"
        "if([string]$m.source_commit -cne $TransportSourceCommit){throw 'Pinned release manifest source_commit mismatch.'};"
        "if([string]$m.payload_set_sha256 -cne $PayloadSet){throw 'Pinned release manifest payload-set mismatch.'};"
        "if([string]$m.min_bootstrap_version -cne $ExpectedBootstrapVersion){throw 'Pinned release manifest min_bootstrap_version mismatch.'};"
        "if([string]$m.bootstrap.version -cne $ExpectedBootstrapVersion -or [string]$m.bootstrap.sha256 -cne $ExpectedBootstrapSha -or [int64]$m.bootstrap.size -ne 42963){throw 'Pinned release manifest Bootstrap identity mismatch.'};"
        "$latest=@($m.latest_files);$mainRows=@($latest|Where-Object{[string]$_.path -ceq 'bin/spotify-control.ps1'});"
        "$addonRows=@($latest|Where-Object{[string]$_.path -ceq 'bin/addon-manager.ps1'});$agentRows=@($latest|Where-Object{[string]$_.path -ceq 'bin/spotify-control-agent.vbs'});"
        "if($mainRows.Count -ne 1 -or [string]$mainRows[0].sha256 -cne $TargetMainSha -or [int64]$mainRows[0].size -ne 281586){throw 'Pinned release manifest main latest_file mismatch.'};"
        "if($addonRows.Count -ne 1 -or [string]$addonRows[0].sha256 -cne $TargetAddonSha -or [int64]$addonRows[0].size -ne 268670){throw 'Pinned release manifest addon latest_file mismatch.'};"
        "if($agentRows.Count -ne 1 -or [string]$agentRows[0].sha256 -cne $ExpectedAgentSha -or [int64]$agentRows[0].size -ne 4855){throw 'Pinned release manifest agent latest_file mismatch.'};"
        "$e20=@($m.updates|Where-Object{[string]$_.from_version -ceq '0.6.20' -and [string]$_.to_version -ceq '0.6.21'});"
        "$e21=@($m.updates|Where-Object{[string]$_.from_version -ceq '0.6.21' -and [string]$_.to_version -ceq '0.6.22'});"
        "if($e20.Count -ne 1 -or @($e20[0].patches).Count -ne 2){throw 'Pinned release manifest exact v0.6.20 -> v0.6.21 edge missing/ambiguous.'};"
        "if($e21.Count -ne 1 -or @($e21[0].patches).Count -ne 2){throw 'Pinned release manifest exact v0.6.21 -> v0.6.22 edge missing/ambiguous.'};"
        "foreach($edge in @($e20[0],$e21[0])){$paths=@($edge.patches|ForEach-Object{[string]$_.path}|Sort-Object);if(($paths-join ',') -cne 'bin/addon-manager.ps1,bin/spotify-control.ps1'){throw \"Pinned release manifest patch paths changed: $($paths-join ',')\"}};"
        "$m20=@($e20[0].patches|Where-Object{[string]$_.path -ceq 'bin/spotify-control.ps1'});$a20=@($e20[0].patches|Where-Object{[string]$_.path -ceq 'bin/addon-manager.ps1'});"
        "$m21=@($e21[0].patches|Where-Object{[string]$_.path -ceq 'bin/spotify-control.ps1'});$a21=@($e21[0].patches|Where-Object{[string]$_.path -ceq 'bin/addon-manager.ps1'});"
        "if([string]$m20[0].from_sha256 -cne $V0620MainSha -or [string]$m20[0].to_sha256 -cne $V0621MainSha -or [string]$m21[0].from_sha256 -cne $V0621MainSha -or [string]$m21[0].to_sha256 -cne $TargetMainSha){throw 'Pinned main SHA chain linkage mismatch.'};"
        "if([string]$a20[0].from_sha256 -cne $V0620AddonSha -or [string]$a20[0].to_sha256 -cne $V0621AddonSha -or [string]$a21[0].from_sha256 -cne $V0621AddonSha -or [string]$a21[0].to_sha256 -cne $TargetAddonSha){throw 'Pinned addon SHA chain linkage mismatch.'};"
        "return [pscustomobject]@{sha256=(Get-Sha $ManifestPath);size=[int64](Get-Item $ManifestPath).Length;source_commit=[string]$m.source_commit;payload_set_sha256=[string]$m.payload_set_sha256;"
        "supported_baseline=[string]$BaselineProfile;expected_edge_count=[int]$ExpectedEdgeCount}}"
    )
    text = replace_line_prefix(text, 'function Assert-PinnedReleaseManifest{', manifest_function, 'manifest-function')
    text = replace_one(text, '    Assert-BaselineComponents;Assert-TransactionsTerminal',
                       '    Select-ExactBaseline;Assert-BaselineComponents;Assert-TransactionsTerminal', 'preflight-baseline-select')
    text = replace_one(
        text,
        "    if([string]$CheckEvidence.installed_version -cne $BaselineMainVersion -or [int]$CheckEvidence.result.edge_count -ne 1 -or [bool]$CheckEvidence.result.already_current){throw 'Pinned Check did not resolve exact one-edge v0.6.21 -> v0.6.22 update.'}",
        "    if([string]$CheckEvidence.installed_version -cne $BaselineMainVersion -or [int]$CheckEvidence.result.edge_count -ne $ExpectedEdgeCount -or [bool]$CheckEvidence.result.already_current){throw ('Pinned Check did not resolve the exact expected '+$ExpectedEdgeCount+'-edge path from '+$BaselineMainVersion+' to v0.6.22.')}",
        'dynamic-edge-check')
    text = replace_one(text,
        "    Write-Host '[7/7] Restoring exact v0.6.21/r10 production state and resident agent...'",
        "    Write-Host ('[7/7] Restoring exact starting production state '+$BaselineProfile+' and resident agent...')",
        'restore-label')
    old_no_restore = "\n".join([
        "        }else{",
        "            Assert-BaselineComponents",
        "            $untouched=Get-Json $StatePath;if($null -eq $untouched -or [bool]$untouched.agent_mutation_enabled -ne [bool]$OriginalMutation){throw 'Preflight failure changed mutation state unexpectedly.'}",
        "            if(@(Get-AgentProcesses).Count -ne 1){throw 'Preflight failure changed resident process count unexpectedly.'}",
        "            if($null -ne $ProtectedBefore -and -not(Snapshot-Equal $ProtectedBefore (Get-ProtectedSnapshot))){throw 'Preflight failure changed protected surfaces unexpectedly.'}",
        "        }",
    ])
    new_no_restore = "\n".join([
        "        }else{",
        "            if($BaselineSelected){",
        "                Assert-BaselineComponents",
        "                $untouched=Get-Json $StatePath;if($null -eq $untouched -or [bool]$untouched.agent_mutation_enabled -ne [bool]$OriginalMutation){throw 'Preflight failure changed mutation state unexpectedly.'}",
        "            }",
        "            if(@(Get-AgentProcesses).Count -ne 1){throw 'Preflight failure changed resident process count unexpectedly.'}",
        "            if($null -ne $ProtectedBefore -and -not(Snapshot-Equal $ProtectedBefore (Get-ProtectedSnapshot))){throw 'Preflight failure changed protected surfaces unexpectedly.'}",
        "        }",
    ])
    text = replace_one(text, old_no_restore, new_no_restore, 'preflight-no-restore-safeguard')
    text = replace_one(text,
        "baseline=[ordered]@{main_version=$BaselineMainVersion;addon_version=$BaselineAddonVersion;main_sha256=(Get-Sha $Main);addon_sha256=(Get-Sha $Addon);agent_sha256=(Get-Sha $Agent);bootstrap_sha256=(Get-Sha $Bootstrap)}",
        "baseline=[ordered]@{profile=$BaselineProfile;expected_edge_count=$ExpectedEdgeCount;main_version=$BaselineMainVersion;addon_version=$BaselineAddonVersion;main_sha256=(Get-Sha $Main);addon_sha256=(Get-Sha $Addon);agent_sha256=(Get-Sha $Agent);bootstrap_sha256=(Get-Sha $Bootstrap)}",
        'final-baseline-evidence')
    text = replace_one(text, "Write-Host 'Bootstrap one-edge rollback/update: VERIFIED'",
                       "Write-Host ('Bootstrap update path:             VERIFIED / '+$ExpectedEdgeCount+' edge(s)')", 'summary-edge')
    text = replace_one(text, "Write-Host 'Installed code after test:         RESTORED TO v0.6.21/r10'",
                       "Write-Host ('Installed code after test:         RESTORED TO '+$BaselineProfile)", 'summary-restore')
    return b'\xef\xbb\xbf' + text.encode('utf-8')


def extract_and_patch(base_zip_raw: bytes) -> None:
    shutil.rmtree(GEN, ignore_errors=True)
    GEN.mkdir(parents=True)
    with zipfile.ZipFile(BytesIO(base_zip_raw)) as z:
        if z.testzip() is not None:
            raise RuntimeError('base package CRC failure during extraction')
        for name in SOURCE_FILES:
            (GEN / name).write_bytes(z.read(name))
    (GEN / 'RUN_RUNTIME_ACCEPTANCE.ps1').write_bytes(patch_runtime((GEN / 'RUN_RUNTIME_ACCEPTANCE.ps1').read_bytes()))
    (GEN / 'README.txt').write_bytes(README_TEXT.replace('\n', '\r\n').encode('utf-8'))


def validate_sources(base_report: dict) -> dict:
    run = (GEN / 'RUN_RUNTIME_ACCEPTANCE.ps1').read_text(encoding='utf-8-sig')
    readme = (GEN / 'README.txt').read_text(encoding='utf-8')
    runner = (GEN / 'BOOTSTRAP_RUNNER.ps1').read_text(encoding='utf-8-sig')
    checks = []

    def ck(name: str, ok: bool) -> None:
        checks.append((name, bool(ok)))

    ck('base-v101-package-source-contract-42-of-42', int(base_report.get('passed', -1)) == 42 and int(base_report.get('total', -1)) == 42)
    for key, token in {
        'acceptance-version': "$AcceptanceVersion='1.0.2'",
        'release-head': RELEASE_HEAD,
        'transport-source': TRANSPORT_SOURCE,
        'payload-set': PAYLOAD_SET,
        'v0620-main-sha': V0620_MAIN_SHA,
        'v0620-addon-sha': V0620_ADDON_SHA,
        'v0621-main-sha': V0621_MAIN_SHA,
        'v0621-addon-sha': V0621_ADDON_SHA,
        'target-main-sha': TARGET_MAIN_SHA,
        'target-addon-sha': TARGET_ADDON_SHA,
    }.items():
        ck('run-pin:' + key, token in run)
    ck('adaptive-baseline-selector-present', 'function Select-ExactBaseline{' in run)
    ck('v0620-exact-baseline-profile', "$script:BaselineProfile='v0.6.20/r9';$script:ExpectedEdgeCount=2" in run)
    ck('v0621-exact-baseline-profile', "$script:BaselineProfile='v0.6.21/r10';$script:ExpectedEdgeCount=1" in run)
    ck('mixed-unknown-baseline-fail-closed', 'Unsupported or mixed installed baseline.' in run)
    ck('baseline-selected-before-transaction-check', 'Select-ExactBaseline;Assert-BaselineComponents;Assert-TransactionsTerminal' in run)
    ck('dynamic-baseline-main-size', "Assert-Identity $Main $BaselineMainSha $BaselineMainSize" in run)
    ck('dynamic-baseline-addon-size', "Assert-Identity $Addon $BaselineAddonSha $BaselineAddonSize" in run)
    ck('both-release-edges-required', "v0.6.20 -> v0.6.21 edge missing/ambiguous." in run and "v0.6.21 -> v0.6.22 edge missing/ambiguous." in run)
    ck('main-sha-chain-linkage-enforced', 'Pinned main SHA chain linkage mismatch.' in run)
    ck('addon-sha-chain-linkage-enforced', 'Pinned addon SHA chain linkage mismatch.' in run)
    ck('dynamic-check-edge-count', 'edge_count -ne $ExpectedEdgeCount' in run)
    ck('dynamic-check-start-version', 'installed_version -cne $BaselineMainVersion' in run)
    ck('rollback-reasserts-selected-baseline', "transaction_status -cne 'rolled-back'" in run and 'Assert-BaselineComponents' in run)
    ck('target-exact-main', f"Assert-Identity $Main $TargetMainSha {TARGET_MAIN_SIZE} 'Spotify Control v0.6.22 main'" in run)
    ck('target-exact-addon', f"Assert-Identity $Addon $TargetAddonSha {TARGET_ADDON_SIZE} 'Addon Manager r11'" in run)
    ck('preflight-unknown-baseline-does-not-force-restore-assert', 'if($BaselineSelected){' in run)
    ck('restore-label-dynamic', "Restoring exact starting production state '+$BaselineProfile" in run)
    ck('final-baseline-profile-recorded', 'profile=$BaselineProfile;expected_edge_count=$ExpectedEdgeCount' in run)
    ck('summary-edge-dynamic', "VERIFIED / '+$ExpectedEdgeCount+' edge(s)'" in run)
    ck('summary-restore-dynamic', "RESTORED TO '+$BaselineProfile" in run)
    ck('addon-update-action-absent', "@('-Action','Update')" not in '\n'.join(line for line in run.splitlines() if '$Addon' in line))
    ck('spotify-launch-absent', 'Start-Spotify' not in run)
    for policy in ['protect-ratings-tags-notes', 'preserve-unknown-source', 'playlist-backed-ratings-preserve', 'never-disable-or-optimize']:
        ck('protected-policy:' + policy, policy in run)
    ck('runner-identity-unchanged', sha_path(GEN / 'BOOTSTRAP_RUNNER.ps1') == BASE_RUNNER_SHA256)
    ck('runner-exact-bootstrap-pin', f"$ExpectedBootstrapSha='{BOOTSTRAP_SHA}'" in runner and '$ExpectedBootstrapSize=42963' in runner)
    ck('readme-v102', 'Runtime Acceptance v1.0.2' in readme)
    ck('readme-dual-baseline', 'v0.6.20 / Addon Manager r9' in readme and 'v0.6.21 / Addon Manager r10' in readme)
    ck('readme-retire-v101', 'v1.0.0 and v1.0.1 must not be run' in readme)
    ck('readme-candidate-not-implicated', 'not a v0.6.22/r11 candidate failure' in readme)
    ck('readme-transport-source', TRANSPORT_SOURCE in readme)
    ck('readme-v0620-identities', f'{V0620_MAIN_SIZE} bytes / {V0620_MAIN_SHA}' in readme and f'{V0620_ADDON_SIZE} bytes / {V0620_ADDON_SHA}' in readme)
    ck('readme-v0621-identities', f'{V0621_MAIN_SIZE} bytes / {V0621_MAIN_SHA}' in readme and f'{V0621_ADDON_SIZE} bytes / {V0621_ADDON_SHA}' in readme)
    ck('readme-target-identities', f'{TARGET_MAIN_SIZE} bytes / {TARGET_MAIN_SHA}' in readme and f'{TARGET_ADDON_SIZE} bytes / {TARGET_ADDON_SHA}' in readme)

    passed = sum(ok for _, ok in checks)
    report = {
        'schema': 3,
        'acceptance': 'v0.6.22-r11-runtime-v1.0.2',
        'supersedes': {
            'acceptance': 'v0.6.22-r11-runtime-v1.0.1',
            'package_size': BASE_ZIP_SIZE,
            'package_sha256': BASE_ZIP_SHA256,
            'reason': 'real-PC preflight proved exact v0.6.20/r9 starting payload; v1.0.2 supports both exact known baselines and fails closed on any other/mixed pair',
        },
        'release': {
            'head': RELEASE_HEAD,
            'manifest_sha256': RELEASE_MANIFEST_SHA256,
            'transport_source': TRANSPORT_SOURCE,
            'payload_set_sha256': PAYLOAD_SET,
        },
        'supported_baselines': [
            {'profile': 'v0.6.20/r9', 'expected_edge_count': 2, 'main': {'size': V0620_MAIN_SIZE, 'sha256': V0620_MAIN_SHA}, 'addon': {'size': V0620_ADDON_SIZE, 'sha256': V0620_ADDON_SHA}},
            {'profile': 'v0.6.21/r10', 'expected_edge_count': 1, 'main': {'size': V0621_MAIN_SIZE, 'sha256': V0621_MAIN_SHA}, 'addon': {'size': V0621_ADDON_SIZE, 'sha256': V0621_ADDON_SHA}},
        ],
        'target': {
            'main': {'size': TARGET_MAIN_SIZE, 'sha256': TARGET_MAIN_SHA},
            'addon': {'size': TARGET_ADDON_SIZE, 'sha256': TARGET_ADDON_SHA},
            'agent': {'size': AGENT_SIZE, 'sha256': AGENT_SHA},
            'bootstrap': {'size': BOOTSTRAP_SIZE, 'sha256': BOOTSTRAP_SHA},
        },
        'passed': passed,
        'total': len(checks),
        'checks': checks,
        'files': {name: {'size': (GEN / name).stat().st_size, 'sha256': sha_path(GEN / name)} for name in SOURCE_FILES + ['README.txt']},
    }
    if passed != len(checks):
        for name, ok in checks:
            if not ok:
                print('FAIL', name)
        raise RuntimeError(f'v1.0.2 adaptive source contract failed {passed}/{len(checks)}')
    return report


def build() -> dict:
    validate_release_manifest_contracts()
    base_zip_raw, base_report = rebuild_base_v101()
    extract_and_patch(base_zip_raw)
    report = validate_sources(base_report)

    shutil.rmtree(OUT, ignore_errors=True)
    PKG.mkdir(parents=True)
    for name in SOURCE_FILES + ['README.txt']:
        shutil.copy2(GEN / name, PKG / name)
    evidence = PKG / 'evidence'
    evidence.mkdir()
    (evidence / 'SELF_VALIDATION_REPORT.json').write_text(json.dumps(report, indent=2, ensure_ascii=True) + '\n', encoding='utf-8', newline='\n')
    (evidence / 'SELF_VALIDATION_REPORT.txt').write_text(
        f"V0.6.22/R11 RUNTIME ACCEPTANCE v1.0.2 SELF VALIDATION: {report['passed']}/{report['total']} PASS\n"
        + ''.join(f'PASS: {name}\n' for name, ok in report['checks']),
        encoding='utf-8', newline='\n')
    rels = SOURCE_FILES + ['README.txt', 'evidence/SELF_VALIDATION_REPORT.json', 'evidence/SELF_VALIDATION_REPORT.txt']
    (PKG / 'SHA256SUMS.txt').write_text(''.join(f'{sha_path(PKG / rel)}  {rel}\n' for rel in rels), encoding='ascii', newline='\n')

    if ZIP.exists():
        ZIP.unlink()
    with zipfile.ZipFile(ZIP, 'w', compression=zipfile.ZIP_STORED) as z:
        for path in sorted(PKG.rglob('*')):
            if not path.is_file():
                continue
            rel = path.relative_to(PKG).as_posix()
            info = zipfile.ZipInfo(rel, (2026, 10, 27, 0, 0, 0))
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

    print('V0622_R11_RUNTIME_ACCEPTANCE_V102_BUILD_PASS', ZIP.stat().st_size, sha_path(ZIP), report['passed'], report['total'], report['files']['RUN_RUNTIME_ACCEPTANCE.ps1']['sha256'], report['files']['BOOTSTRAP_RUNNER.ps1']['sha256'])
    return report


if __name__ == '__main__':
    build()
