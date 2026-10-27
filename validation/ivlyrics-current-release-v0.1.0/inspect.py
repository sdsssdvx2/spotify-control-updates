from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE='d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
ADDON=ROOT/'validation/v0.6.28/out/bin/addon-manager.ps1'
EXPECTED_ADDON=(323385,'5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285')
EXPECTED_VERSION='7.0.16'
EXPECTED_TAG='v7.0.16'
EXPECTED_ZIP_SIZE=10337565
EXPECTED_ZIP_SHA='a58098f29ca69dc4e56b96b1eb635699d14fc80c19cd2c3710cc42f5312f1509'
EXPECTED_SIDECAR_SIZE=79
EXPECTED_SIDECAR_ASSET_SHA='d9b44b900e9e15b59b06044f9e025a53194f36bfe386d836f6245e9479077ca7'
OUT_DIR=ROOT/'validation/ivlyrics-current-release-v0.1.0'
HARNESS=OUT_DIR/'exact-r17-acceptance.ps1'
HARNESS_RESULT=OUT_DIR/'harness-result.json'
FINAL_RESULT=OUT_DIR/'audit-result.json'
ENTRYPOINTS=[
 'Get-IvLyricsReleaseInfo','Download-IvLyricsReleaseStage','Get-IvLyricsInstalledBaselineProof',
 'Get-IvLyricsOfficialTagTree','Test-IvLyricsTreeAgainstOfficialTag','Test-IvLyricsStageRoot',
 'Test-IvLyricsOfficialTagFallbackEligible','Get-AddonPolicyRegistry'
]

def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def git(*a:str)->str:return subprocess.check_output(['git',*a],cwd=ROOT,text=True).strip()
def blocks(text:str)->dict[str,str]:
    hits=list(re.finditer(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text))
    out={}
    for i,h in enumerate(hits):
        end=hits[i+1].start() if i+1<len(hits) else len(text)
        out[h.group(1)]=text[h.start():end].rstrip()
    return out

def closure(fs:dict[str,str],roots:list[str])->list[str]:
    names=set(fs); need=set(roots); changed=True
    while changed:
        changed=False
        for name in list(need):
            body=fs[name]
            for cand in names:
                if cand not in need and re.search(r'(?i)(?<![A-Za-z0-9_-])'+re.escape(cand)+r'(?![A-Za-z0-9_-])',body):
                    need.add(cand);changed=True
    return [n for n in fs if n in need]

def api(url:str):
    headers={'User-Agent':'spotify-control-ivlyrics-current-release-v010','Accept':'application/vnd.github+json'}
    token=os.environ.get('GH_TOKEN','').strip()
    if token:
        headers['Authorization']=f'Bearer {token}';headers['X-GitHub-Api-Version']='2022-11-28'
    with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=30) as r:return json.load(r)
def download(url:str)->bytes:
    headers={'User-Agent':'spotify-control-ivlyrics-current-release-v010'}
    with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=60) as r:return r.read()

def main():
    if git('merge-base',BASE,'HEAD')!=BASE:raise SystemExit('wrong exact production base')
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.28/build_v0628.py'),'--build'],cwd=ROOT)
    raw=ADDON.read_bytes()
    if (len(raw),sha(raw))!=EXPECTED_ADDON:raise SystemExit(f'exact r17 identity drift: {len(raw)} {sha(raw)}')
    text=raw.decode('utf-8-sig'); fs=blocks(text)
    missing=[n for n in ENTRYPOINTS if n not in fs]
    if missing:raise SystemExit(f'missing exact r17 entrypoints: {missing}')

    rel=api('https://api.github.com/repos/ivLis-Studio/ivLyrics/releases/latest')
    if rel.get('tag_name')!=EXPECTED_TAG or rel.get('draft') or rel.get('prerelease'):
        raise SystemExit(f'latest release moved/status changed: {rel.get("tag_name")} draft={rel.get("draft")} prerelease={rel.get("prerelease")}')
    z=[a for a in rel.get('assets',[]) if a.get('name')=='ivLyrics.zip']
    s=[a for a in rel.get('assets',[]) if a.get('name')=='ivLyrics.zip.sha256']
    if len(z)!=1 or len(s)!=1:raise SystemExit('latest release exact archive/sidecar cardinality changed')
    za,sa=z[0],s[0]
    if int(za.get('size',-1))!=EXPECTED_ZIP_SIZE or za.get('digest')!=f'sha256:{EXPECTED_ZIP_SHA}':raise SystemExit('latest zip identity drifted')
    if int(sa.get('size',-1))!=EXPECTED_SIDECAR_SIZE or sa.get('digest')!=f'sha256:{EXPECTED_SIDECAR_ASSET_SHA}':raise SystemExit('latest sidecar asset identity drifted')
    sidecar=download(sa['browser_download_url'])
    if len(sidecar)!=EXPECTED_SIDECAR_SIZE or sha(sidecar)!=EXPECTED_SIDECAR_ASSET_SHA:raise SystemExit('downloaded sidecar identity drifted')
    m=re.search(rb'(?i)\b([0-9a-f]{64})\b',sidecar)
    if not m or m.group(1).decode().lower()!=EXPECTED_ZIP_SHA:raise SystemExit('sidecar does not bind expected zip SHA-256')

    required=closure(fs,ENTRYPOINTS)
    fn_text='\n\n'.join(fs[n] for n in required)
    harness=f'''$ErrorActionPreference='Stop'\nSet-StrictMode -Version 2.0\n$Version='0.6.5-r17'\n$script:IvLyricsOfficialTagCache=@{{}}\n{fn_text}\n\n'''+r'''
$stage=$null;$drift=$null
try {
  $latest=Get-IvLyricsReleaseInfo -Latest
  if([string]$latest.version -cne '7.0.16' -or [string]$latest.revision -cne 'v7.0.16'){throw 'Exact r17 latest ivLyrics identity mismatch.'}
  if([int64]$latest.size -ne 10337565 -or [string]$latest.digest -cne 'sha256:a58098f29ca69dc4e56b96b1eb635699d14fc80c19cd2c3710cc42f5312f1509'){throw 'Exact r17 latest ivLyrics archive pin mismatch.'}
  $explicit=Get-IvLyricsReleaseInfo -Version '7.0.16'
  if([string]$explicit.url -cne [string]$latest.url -or [string]$explicit.checksum_url -cne [string]$latest.checksum_url -or [string]$explicit.digest -cne [string]$latest.digest){throw 'Latest and explicit v7.0.16 release metadata differ.'}

  $stage=Download-IvLyricsReleaseStage -Remote $latest
  if(-not $stage.Validation.Valid){throw "Exact r17 latest stage invalid: $($stage.Validation.Error)"}
  if([string]$stage.Validation.Version -cne '7.0.16'){throw 'Exact r17 stage version mismatch.'}
  if([string]$stage.ArchiveSha256 -cne 'a58098f29ca69dc4e56b96b1eb635699d14fc80c19cd2c3710cc42f5312f1509'){throw 'Exact r17 downloaded archive SHA mismatch.'}

  $proof=Get-IvLyricsInstalledBaselineProof -Dir $stage.Path -Version '7.0.16'
  if([string]$proof.ProofKind -cne 'release-asset'){throw "Expected release-asset baseline proof, got $($proof.ProofKind)"}
  if([string]$proof.Fingerprint -cne [string]$stage.Validation.Fingerprint){throw 'Baseline proof fingerprint differs from validated stage.'}
  if([string]$proof.TreeSha -cne 'release-asset-a58098f29ca69dc4e56b96b1eb635699d14fc80c19cd2c3710cc42f5312f1509'){throw 'Baseline proof release tree anchor mismatch.'}

  $tag=Get-IvLyricsOfficialTagTree -Version '7.0.16'
  if([string]$tag.tag -cne 'v7.0.16' -or [string]$tag.revision -notmatch '^[0-9a-f]{40}$' -or [string]$tag.tree_sha -notmatch '^[0-9a-f]{40}$'){throw 'Official v7.0.16 tag/tree proof identity invalid.'}
  $releaseVsSource=Test-IvLyricsTreeAgainstOfficialTag -Dir $stage.Path -Remote $tag

  $drift=Join-Path $env:TEMP ('SpotifyControl-IvLyricsCurrentDrift-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $drift|Out-Null
  Copy-DirectoryContentsExact -Source $stage.Path -Destination $drift
  $extra=Join-Path $drift '__spotify_control_extra_probe__.txt'
  [System.IO.File]::WriteAllText($extra,'extra',[System.Text.UTF8Encoding]::new($false))
  $stageDrift=Test-IvLyricsStageRoot -Dir $drift -ExpectedVersion '7.0.16' -ExpectedFingerprint ([string]$stage.Validation.Fingerprint)
  if($stageDrift.Valid){throw 'Exact r17 stage fingerprint accepted an injected extra file.'}
  $baselineDriftRejected=$false;$baselineDriftError=$null
  try {[void](Get-IvLyricsInstalledBaselineProof -Dir $drift -Version '7.0.16')}
  catch {$baselineDriftRejected=$true;$baselineDriftError=[string]$_.Exception.Message}
  if(-not $baselineDriftRejected){throw 'Exact r17 installed baseline proof accepted an injected extra file.'}

  foreach($bad in @('GitHub API failed: 404','ivLyrics archive is missing a valid GitHub-published SHA-256 digest.','ivLyrics GitHub-published digest mismatch. expected=x actual=y')){
    if(Test-IvLyricsOfficialTagFallbackEligible -ErrorMessage $bad){throw "Unsafe proof failure enabled tag fallback: $bad"}
  }
  $registry=Get-AddonPolicyRegistry
  $auto=@($registry|Where-Object{$_.mutation_mode -ceq 'auto'}|ForEach-Object{$_.name}|Sort-Object)
  if(($auto -join '|') -cne 'better-local-files|eternal-jukebox|ivLyrics|playlist-maker'){throw "Automatic authority drift: $($auto -join '|')"}
  $iv=@($registry|Where-Object{$_.name -ceq 'ivLyrics'})
  if($iv.Count -ne 1 -or [string]$iv[0].install_mode -cne 'installed-only' -or [string]$iv[0].version_strategy -cne 'semver-release-exact-tree'){throw 'ivLyrics installed-only/exact-tree policy drifted.'}

  $result=[ordered]@{
    success=$true
    latest_version=[string]$latest.version
    latest_revision=[string]$latest.revision
    archive_sha256=[string]$stage.ArchiveSha256
    stage_fingerprint=[string]$stage.Validation.Fingerprint
    stage_file_count=[int]$stage.Validation.FileCount
    stage_expanded_bytes=[int64]$stage.Validation.ExpandedBytes
    baseline_proof_kind=[string]$proof.ProofKind
    official_tag_revision=[string]$tag.revision
    official_tag_tree_sha=[string]$tag.tree_sha
    release_asset_exactly_equals_source_tag_tree=[bool]$releaseVsSource.Valid
    release_asset_vs_source_tag_tree_error=[string]$releaseVsSource.Error
    extra_file_stage_rejected=$true
    extra_file_baseline_rejected=$baselineDriftRejected
    extra_file_baseline_error=$baselineDriftError
    mutation_performed=$false
    authority_expanded=$false
    install_mode='installed-only'
  }
  $result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $env:IVLYRICS_AUDIT_RESULT -Encoding UTF8
  Write-Host ('IVLYRICS_CURRENT_V7016_EXACT_R17_ACCEPTANCE_PASS '+($result|ConvertTo-Json -Compress -Depth 8))
} finally {
  if($stage -and $stage.Path -and (Test-Path -LiteralPath $stage.Path -ErrorAction SilentlyContinue)){Remove-Item -LiteralPath $stage.Path -Recurse -Force -ErrorAction SilentlyContinue}
  if($drift -and (Test-Path -LiteralPath $drift -ErrorAction SilentlyContinue)){Remove-Item -LiteralPath $drift -Recurse -Force -ErrorAction SilentlyContinue}
}
'''
    HARNESS.write_text(harness,encoding='utf-8',newline='\n')
    env=os.environ.copy();env['IVLYRICS_AUDIT_RESULT']=str(HARNESS_RESULT)
    subprocess.check_call(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(HARNESS)],cwd=ROOT,env=env)
    hr=json.loads(HARNESS_RESULT.read_text(encoding='utf-8-sig'))
    if not hr.get('success') or hr.get('latest_version')!=EXPECTED_VERSION or hr.get('archive_sha256')!=EXPECTED_ZIP_SHA:raise SystemExit('exact r17 harness result contract failed')
    if not hr.get('extra_file_stage_rejected') or not hr.get('extra_file_baseline_rejected'):raise SystemExit('negative drift rejection contract failed')
    report={
      'schema':1,'audit':'ivlyrics-current-release-v0.1.0','production_base':BASE,'validation_head':git('rev-parse','HEAD'),
      'read_only':True,'mutation_performed':False,'authority_expanded':False,
      'exact_r17':{'size':len(raw),'sha256':sha(raw)},
      'independent_release_pin':{
        'version':EXPECTED_VERSION,'tag':EXPECTED_TAG,'published_at':rel.get('published_at'),'release_id':rel.get('id'),
        'zip':{'size':EXPECTED_ZIP_SIZE,'sha256':EXPECTED_ZIP_SHA,'github_digest':za.get('digest')},
        'sidecar':{'size':EXPECTED_SIDECAR_SIZE,'sha256':EXPECTED_SIDECAR_ASSET_SHA,'github_digest':sa.get('digest'),'declared_zip_sha256':m.group(1).decode().lower()},
      },
      'exact_handler_function_count':len(required),'exact_handler_functions':required,
      'acceptance':hr,
      'decision':{
        'latest_release_accepted_by_exact_r17':True,'installed_only_preserved':True,'unproven_drift_rejected':True,
        'production_change_justified':False,'r18_release_justified':False,
        'reason':'exact production r17 accepts the current official v7.0.16 release through GitHub asset digest + sidecar + archive safety + stage fingerprint, proves an exact release-asset baseline, and rejects injected local drift; no handler change is justified',
      },
    }
    FINAL_RESULT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print(json.dumps(report,indent=2,sort_keys=True));print('IVLYRICS_CURRENT_RELEASE_AUDIT_PASS')
if __name__=='__main__':main()
