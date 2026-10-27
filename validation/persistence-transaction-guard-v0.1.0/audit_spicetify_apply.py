from __future__ import annotations

from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "validation/persistence-transaction-guard-v0.1.0/spicetify-apply-scope-report.json"
REPO = "https://github.com/spicetify/cli.git"
TAG = "v2.46.4"
COMMIT = "c3fd98f6fbf922ae944d1ecd64f97c380d04368e"

GUARDED_LITERALS = [
    '"IndexedDB"',
    '"Local Storage"',
    '"Session Storage"',
    '"WebStorage"',
    '"Local State"',
    '"Preferences"',
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def run(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.STDOUT).strip()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def extract_apply_function(text: str) -> str:
    text = text.replace("\r\n", "\n")
    start = text.find("func Apply(spicetifyVersion string) {")
    require(start >= 0, "Spicetify Apply function anchor missing")
    end = text.find("\n}\n\n// RefreshTheme", start)
    require(end > start, "Spicetify Apply function end anchor missing")
    return text[start : end + 2]


def main() -> None:
    temp = Path(tempfile.mkdtemp(prefix="spicetify-apply-scope-"))
    try:
        clone = temp / "cli"
        subprocess.check_call(["git", "clone", "--filter=blob:none", "--no-checkout", REPO, str(clone)])
        subprocess.check_call(["git", "checkout", "--detach", COMMIT], cwd=clone)
        head = run("git", "rev-parse", "HEAD", cwd=clone)
        require(head == COMMIT, f"Spicetify pinned checkout drifted: {head}")
        tag_commit = run("git", "rev-list", "-n", "1", TAG, cwd=clone)
        require(tag_commit == COMMIT, f"Spicetify {TAG} does not resolve to the pinned commit: {tag_commit}")

        apply_path = clone / "src/cmd/apply.go"
        apply_bytes = apply_path.read_bytes()
        apply_text = apply_bytes.decode("utf-8")
        apply_func = extract_apply_function(apply_text)

        # The apply operation must stay scoped to Spotify app/xpui assets plus configured extensions/apps.
        for literal in GUARDED_LITERALS:
            require(literal not in apply_func, f"Spicetify Apply gained direct guarded persistence access: {literal}")
        require("prefsPath" not in apply_func, "Spicetify Apply gained prefsPath access")
        for required in ("appDestPath", "RefreshTheme()", "apply.AdditionalOptions", "RefreshExtensions", "RefreshApps"):
            require(required in apply_func, f"Expected Spicetify Apply scope marker missing: {required}")

        # Search all Go production source for direct fixed-path access to the exact WebView persistence names.
        go_files = sorted((clone / "src").rglob("*.go"))
        literal_hits: dict[str, list[str]] = {literal: [] for literal in GUARDED_LITERALS}
        prefs_hits: list[str] = []
        dangerous_prefs_hits: list[str] = []
        mutator_patterns = [
            re.compile(r"os\.(?:WriteFile|Remove|RemoveAll|Rename|Create|CreateTemp)\s*\([^\n;]*prefsPath", re.I),
            re.compile(r"utils\.(?:Copy|CopyFile|ModifyFile|CheckExistAndDelete)\s*\([^\n;]*prefsPath", re.I),
        ]
        for path in go_files:
            rel = path.relative_to(clone).as_posix()
            text = path.read_text(encoding="utf-8")
            for literal in GUARDED_LITERALS:
                if literal in text:
                    literal_hits[literal].append(rel)
            for lineno, line in enumerate(text.splitlines(), 1):
                if "prefsPath" in line:
                    prefs_hits.append(f"{rel}:{lineno}:{line.strip()}")
            for pattern in mutator_patterns:
                for match in pattern.finditer(text):
                    dangerous_prefs_hits.append(f"{rel}:{match.group(0)}")

        # Exact fixed WebView directory/file names are not part of the CLI's Go mutation surface.
        for literal, hits in literal_hits.items():
            require(not hits, f"Spicetify Go source gained guarded fixed-path literal {literal}: {hits}")
        require(not dangerous_prefs_hits, f"Spicetify Go source gained a prefsPath mutation: {dangerous_prefs_hits}")

        # prefsPath is allowed for read-only Spotify-version/status discovery. Pin every current occurrence for review evidence.
        allowed_pref_files = {
            "src/cmd/apply.go",
            "src/cmd/auto.go",
            "src/cmd/backup.go",
            "src/cmd/cmd.go",
            "src/status/backup/backup.go",
            "src/utils/utils.go",
        }
        actual_pref_files = {row.split(":", 1)[0] for row in prefs_hits}
        require(actual_pref_files.issubset(allowed_pref_files), f"prefsPath appeared in a new production source file: {sorted(actual_pref_files - allowed_pref_files)}")

        report = {
            "schema": 1,
            "repository": "spicetify/cli",
            "release_tag": TAG,
            "release_commit": COMMIT,
            "apply_path": "src/cmd/apply.go",
            "apply_sha256": sha256(apply_bytes),
            "apply_guarded_literal_hits": {k: [] for k in GUARDED_LITERALS},
            "apply_prefs_path_access": False,
            "source_guarded_literal_hits": literal_hits,
            "prefs_path_occurrences": prefs_hits,
            "dangerous_prefs_path_mutations": dangerous_prefs_hits,
            "conclusion": "Spicetify v2.46.4 Apply is scoped to app/xpui assets, extensions and CustomApps; no direct access to the persistence-guard fixed WebView paths was found.",
        }
        REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
        print("SPICETIFY_V2464_APPLY_PERSISTENCE_SCOPE_PASS", COMMIT, sha256(apply_bytes), len(prefs_hits))
    finally:
        shutil.rmtree(temp, ignore_errors=True)


if __name__ == "__main__":
    main()
