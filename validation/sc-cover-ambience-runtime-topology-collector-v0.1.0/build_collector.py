from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

OLD_HEAD = "14a2f9bfacc54e617aec024b44b7f367dec28bbe"
OLD_ROOT = "validation/star-ratings-runtime-topology-collector-v0.1.0"
OLD_BLOBS = {
    "Collect-StarRatings-Topology.ps1": "d654f1ebf1aa37e8650534ae62b9f5bc3a57d2ed",
    "LevelDbReadOnly.cs": "66de32a1dafcb4fbca9ebe0509cf326fd8a65a5e",
    "fixture_builder.py": "0edaad18329fb2bec41d576285a88fcbbc0cd4f9",
}
CATALOG_FINGERPRINT = "c12391e57a393d37d70ffd7a984bdbb6af9f4a83cf3c2b0a8c9bf040247c731f"
CURRENT_SHA = "0aea69246e14156b22a10261af07b84f3abc58bed4368e03f740ed76db329738"
CURRENT_SIZE = 10267
COVER_RECORD = "marketplace:installed:Theblockbuster1/spicetify-extensions/CoverAmbience/CoverAmbience.js"


def show(name: str) -> str:
    path = f"{OLD_ROOT}/{name}"
    blob = subprocess.check_output(["git", "rev-parse", f"{OLD_HEAD}:{path}"], text=True).strip()
    if blob != OLD_BLOBS[name]:
        raise RuntimeError(f"pinned source blob drifted for {name}: {blob}")
    return subprocess.check_output(["git", "show", f"{OLD_HEAD}:{path}"], text=True)


def show_bytes(name: str) -> bytes:
    path = f"{OLD_ROOT}/{name}"
    blob = subprocess.check_output(["git", "rev-parse", f"{OLD_HEAD}:{path}"], text=True).strip()
    if blob != OLD_BLOBS[name]:
        raise RuntimeError(f"pinned source blob drifted for {name}: {blob}")
    return subprocess.check_output(["git", "show", f"{OLD_HEAD}:{path}"])


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def build_collector() -> str:
    text = show("Collect-StarRatings-Topology.ps1")
    text = once(text, "'star-ratings-topology-latest.json'", "'sc-cover-ambience-topology-latest.json'", "output name")
    text = once(text, "$StarRecordKey = 'marketplace:installed:brimell/spicetify-star-ratings/dist/star-ratings.js'", f"$CoverRecordKey = '{COVER_RECORD}'", "record key")
    text = once(text, "$KnownOriginalSha = '198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1'\n$KnownTransformedSha = '6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3'\n$PerformanceId = 'star-ratings-observer-debounce-v1'\n", f"$CatalogPath = Join-Path $PSScriptRoot 'official-snapshots.json'\n$ExpectedCatalogFingerprint = '{CATALOG_FINGERPRINT}'\n$ExpectedCurrentSha = '{CURRENT_SHA}'\n$ExpectedCurrentSize = {CURRENT_SIZE}\n", "performance constants")

    text = text.replace("$StarRecordKey", "$CoverRecordKey")
    text = text.replace("star_record_present", "cover_record_present")
    text = text.replace("list_contains_star", "list_contains_cover")
    text = text.replace("$starEntry", "$coverEntry")
    text = text.replace("$starPresent", "$coverPresent")
    text = text.replace("$anyStar", "$anyCover")
    text = text.replace("$starMatches", "$coverMatches")
    text = text.replace("star_configured", "cover_configured")
    text = text.replace("$stars", "$covers")
    text = once(text, "$_ -ieq 'sc-star-ratings.js' -or $_ -ieq 'star-ratings.js'", "$_ -ieq 'sc-cover-ambience.js' -or $_ -ieq 'CoverAmbience.js'", "config tokens")
    text = text.replace("sc-star-ratings.js", "sc-cover-ambience.js")
    text = text.replace("star-ratings.js", "CoverAmbience.js")

    start = text.index("function Test-ChildPath")
    end = text.index("function Get-LevelDbFileFingerprint")
    provenance = r'''function Get-OfficialCatalog {
    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) { throw "Official snapshot catalog missing: $CatalogPath" }
    $doc = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
    if ([int]$doc.schema -ne 1) { throw 'Unsupported Cover Ambience catalog schema.' }
    if ([string]$doc.source_repository -cne 'Theblockbuster1/spicetify-extensions') { throw 'Cover Ambience catalog repository mismatch.' }
    if ([string]$doc.source_path -cne 'CoverAmbience/CoverAmbience.js') { throw 'Cover Ambience catalog path mismatch.' }
    if ([string]$doc.audit_catalog_payload_sha256 -cne $ExpectedCatalogFingerprint) { throw 'Cover Ambience audit catalog fingerprint mismatch.' }
    if ([string]$doc.current_sha256 -cne $ExpectedCurrentSha -or [int64]$doc.current_size -ne [int64]$ExpectedCurrentSize) { throw 'Cover Ambience current snapshot contract mismatch.' }
    $snapshots = @($doc.snapshots)
    if ($snapshots.Count -ne 35) { throw "Unexpected Cover Ambience snapshot count: $($snapshots.Count)" }
    $map = @{}
    foreach ($snapshot in $snapshots) {
        $key = ('{0}|{1}' -f [int64]$snapshot.size,([string]$snapshot.sha256).ToLowerInvariant())
        if ($map.ContainsKey($key)) { throw "Duplicate Cover Ambience size/hash snapshot: $key" }
        $map[$key] = $snapshot
    }
    return [pscustomobject]@{ document=$doc; by_key=$map }
}

function Resolve-OfficialSnapshot([object]$Identity, [object]$Catalog) {
    if (-not $Identity.exists) { return [pscustomobject]@{ label=$Identity.label; official=$false; reason='file-absent'; commit=$null; date=$null; current=$false } }
    if ($Identity.reparse) { return [pscustomobject]@{ label=$Identity.label; official=$false; reason='reparse-point-refused'; commit=$null; date=$null; current=$false } }
    if ([string]::IsNullOrWhiteSpace([string]$Identity.sha256)) { return [pscustomobject]@{ label=$Identity.label; official=$false; reason='sha-unavailable'; commit=$null; date=$null; current=$false } }
    $key = ('{0}|{1}' -f [int64]$Identity.size,([string]$Identity.sha256).ToLowerInvariant())
    if (-not $Catalog.by_key.ContainsKey($key)) { return [pscustomobject]@{ label=$Identity.label; official=$false; reason='bytes-not-in-official-snapshot-catalog'; commit=$null; date=$null; current=$false } }
    $snapshot = $Catalog.by_key[$key]
    return [pscustomobject]@{ label=$Identity.label; official=$true; reason='exact-official-snapshot'; commit=[string]$snapshot.commit; date=[string]$snapshot.date; current=[bool]$snapshot.current; size=[int64]$snapshot.size; sha256=[string]$snapshot.sha256 }
}

'''
    text = text[:start] + provenance + text[end:]

    text = once(text, "$performance = Get-PerformanceEvidence\n$marketplace = Get-MarketplaceEvidence", "$catalog = Get-OfficialCatalog\n$marketplace = Get-MarketplaceEvidence", "runtime evidence")
    old = "$activeExisting = @($activeFiles | Where-Object { $_.exists -and -not $_.reparse })\n$activeKnown = @($activeExisting | Where-Object { $_.sha256 -ceq $KnownOriginalSha -or $_.sha256 -ceq $KnownTransformedSha })\n$sourceExisting = @($sourceFiles | Where-Object { $_.exists -and -not $_.reparse })\n$localConfiguredActive = [bool]($config.configured -and $activeExisting.Count -gt 0)\n$localResidual = [bool]((-not $config.configured) -and ($sourceExisting.Count -gt 0 -or $activeExisting.Count -gt 0))\n$localDrift = [bool]($config.configured -and $activeExisting.Count -eq 0)"
    new = "$activeExisting = @($activeFiles | Where-Object { $_.exists -and -not $_.reparse })\n$sourceExisting = @($sourceFiles | Where-Object { $_.exists -and -not $_.reparse })\n$sourceProvenance = @($sourceFiles | ForEach-Object { Resolve-OfficialSnapshot $_ $catalog })\n$activeProvenance = @($activeFiles | ForEach-Object { Resolve-OfficialSnapshot $_ $catalog })\n$sourceOfficial = @($sourceProvenance | Where-Object { $_.official -eq $true })\n$activeOfficial = @($activeProvenance | Where-Object { $_.official -eq $true })\n$localConfiguredOwned = [bool]($config.configured -and ($sourceExisting.Count -gt 0 -or $activeExisting.Count -gt 0))\n$localResidual = [bool]((-not $config.configured) -and ($sourceExisting.Count -gt 0 -or $activeExisting.Count -gt 0))\n$localDrift = [bool]($config.configured -and $sourceExisting.Count -eq 0 -and $activeExisting.Count -eq 0)"
    text = once(text, old, new, "local ownership derivation")
    text = text.replace("$localConfiguredActive", "$localConfiguredOwned")
    text = text.replace("local_configured_active = $localConfiguredOwned", "local_configured_owned = $localConfiguredOwned")

    text = once(text, "star_ratings_record = $CoverRecordKey", "cover_ambience_record = $CoverRecordKey", "exact key field")
    text = once(text, "    local_source_files = $sourceFiles\n    active_xpui_files = $activeFiles\n    performance_state = $performance\n    derived = [ordered]@{", "    local_source_files = $sourceFiles\n    active_xpui_files = $activeFiles\n    provenance_catalog = [ordered]@{ source_repository=[string]$catalog.document.source_repository; source_path=[string]$catalog.document.source_path; audit_catalog_payload_sha256=[string]$catalog.document.audit_catalog_payload_sha256; snapshot_count=@($catalog.document.snapshots).Count; current_size=[int64]$catalog.document.current_size; current_sha256=[string]$catalog.document.current_sha256 }\n    local_source_provenance = $sourceProvenance\n    active_xpui_provenance = $activeProvenance\n    derived = [ordered]@{", "report provenance")
    text = once(text, "        active_known_release_or_transform_count = $activeKnown.Count", "        local_source_official_snapshot_count = $sourceOfficial.Count\n        active_official_snapshot_count = $activeOfficial.Count", "derived official count")
    text = once(text, "        safe_to_expand_mutation_authority = $false\n        next_decision = 'review-topology-evidence-only'", "        safe_to_expand_mutation_authority = $false\n        safe_to_auto_remove_direct_copy = $false\n        disable_or_optimize = $false\n        next_decision = 'review-topology-and-provenance-only'", "derived safety")
    text = text.replace("Star Ratings ownership topology", "SC Cover Ambience ownership topology")
    text = text.replace("No Spotify/Spicetify/Marketplace data was modified.", "No Spotify/Spicetify/Marketplace data was modified. SC Cover Ambience was not disabled, optimized, updated, installed, or removed.")
    if "Get-PerformanceEvidence" in text or "KnownOriginalSha" in text or "PerformanceId" in text:
        raise RuntimeError("Star Ratings performance surface leaked into Cover Ambience collector")
    return text


def build_fixture() -> str:
    text = show("fixture_builder.py")
    text = text.replace("STAR_RECORD", "COVER_RECORD")
    text = text.replace("marketplace:installed:brimell/spicetify-star-ratings/dist/star-ratings.js", COVER_RECORD)
    text = text.replace("sc-star-ratings.js", "sc-cover-ambience.js")
    text = text.replace("Star Ratings", "Cover Ambience")
    text = text.replace("synthetic-active-star-ratings-fixture", "synthetic-active-cover-ambience-fixture")
    text = text.replace("STAR_RATINGS_TOPOLOGY_FIXTURES_BUILT", "SC_COVER_AMBIENCE_TOPOLOGY_FIXTURES_BUILT")
    if "star-ratings" in text.lower() or "STAR_RECORD" in text:
        raise RuntimeError("Star Ratings fixture token leaked into Cover Ambience fixture builder")
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--catalog", required=True, type=Path)
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    if catalog.get("schema") != 1 or catalog.get("audit_catalog_payload_sha256") != CATALOG_FINGERPRINT:
        raise RuntimeError("pinned official snapshot catalog contract mismatch")
    if len(catalog.get("snapshots", [])) != 35 or catalog.get("current_sha256") != CURRENT_SHA or catalog.get("current_size") != CURRENT_SIZE:
        raise RuntimeError("pinned official snapshot catalog identity mismatch")

    args.out.mkdir(parents=True, exist_ok=True)
    collector = build_collector()
    fixture = build_fixture()
    reader = show_bytes("LevelDbReadOnly.cs")
    (args.out / "Collect-SCCoverAmbience-Topology.ps1").write_text(collector, encoding="utf-8", newline="\n")
    (args.out / "LevelDbReadOnly.cs").write_bytes(reader)
    (args.out / "fixture_builder.py").write_text(fixture, encoding="utf-8", newline="\n")
    (args.out / "official-snapshots.json").write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    cmd = '@echo off\r\nsetlocal\r\ncd /d "%~dp0"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-SCCoverAmbience-Topology.ps1"\r\nset "rc=%ERRORLEVEL%"\r\necho.\r\nif not "%rc%"=="0" echo Collector failed with exit code %rc%.\r\npause\r\nexit /b %rc%\r\n'
    (args.out / "Run-SCCoverAmbience-Topology.cmd").write_bytes(cmd.encode("ascii"))
    for name in ("Collect-SCCoverAmbience-Topology.ps1", "LevelDbReadOnly.cs", "fixture_builder.py", "official-snapshots.json", "Run-SCCoverAmbience-Topology.cmd"):
        data = (args.out / name).read_bytes()
        print(f"GENERATED {name} size={len(data)} sha256={hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    main()
